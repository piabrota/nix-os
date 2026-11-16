package piabrota.scripts

import scala.scalanative.unsafe.*
import piabrota.lib.{Sh, die, warn}

/** `piabrota video-dummy`: a smoke check of the render path (stages 5 to 7 of
  * docs/VIDEO-PIPELINE.md), a 28 s video from ffmpeg and ffprobe alone. It tests nothing else.
  * Run by `just video-dummy`. VIDEO_LAB_OUT names the output folder (default video-lab/out/dummy).
  * Prints `ARTIFACT OK: ...` and writes report.json, or prints `ARTIFACT FAILED: ...` and exits 1.
  */
object VideoDummy:
  private def fail(message: String): Nothing = die(s"ARTIFACT FAILED: $message")

  /** ffmpeg at low priority, two threads; returns its time and the peak memory of the children so
    * far, in KiB.
    */
  private def ff(args: os.Shellable*): (Double, Long) =
    val start = System.nanoTime()
    val code = Sh.run("nice", "-n", "10", "ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
      "-threads", "2", args)
    if code != 0 then die(s"ffmpeg: exit $code")
    ((System.nanoTime() - start) / 1e9, Rusage.childrenMaxRssKiB())

  private def font(): String =
    Sh.outOpt("fc-list").toList.flatMap(_.linesIterator)
      .find(_.toLowerCase.contains(".ttf")).map(_.split(":", 2)(0)).getOrElse("")

  def stamp(ms: Int): String = f"00:00:${ms / 1000}%02d,${ms % 1000}%03d"

  /** The caption of scene `index` (from 0): a scene starts every 5.5 s (6 s minus the 0.5 s fade). */
  def cue(index: Int, text: String): String =
    val start = index * 5500
    s"${index + 1}\n${stamp(start)} --> ${stamp(start + 5000)}\n$text\n"

  /** The join: xfade for video, acrossfade for audio, then loudnorm. */
  def graph(scenes: Int): String =
    val joins = (1 until scenes).map { n =>
      val (prev, aprev) = if n == 1 then ("[0:v]", s"[$scenes:a]") else (s"[v${n - 1}]", s"[a${n - 1}]")
      f"$prev[$n:v]xfade=transition=fade:duration=0.5:offset=${n * 5.5}%.1f[v$n];" +
        s"$aprev[${n + scenes}:a]acrossfade=d=0.5[a$n];"
    }
    joins.mkString + s"[a${scenes - 1}]loudnorm=I=-16:TP=-1.5:LRA=11,aresample=48000[aout]"

  private def probe(file: os.Path, args: String*): String =
    Sh.call("ffprobe", "-v", "error", args, "-of", "csv=p=0", file.toString).out.text().strip()

  def run(args: List[String]): Int =
    val config = VideoConfig(sys.env.getOrElse("VIDEO_LAB_OUT", VideoConfig.defaultOut))
    val out = config.out
    val (file, captions, tmp) = (out / VideoConfig.file, out / "captions.srt", out / "tmp")
    os.makeDir.all(out)
    List(file, captions, out / "report.json").foreach(os.remove(_))
    os.remove.all(tmp)
    os.makeDir(tmp)

    val ttf = font()
    if ttf.isEmpty then warn("No .ttf font found: the clips have no text.")
    val times = List.newBuilder[(Double, Long)]
    val cues = Scene.all.zipWithIndex.map { (scene, index) =>
      val i = index + 1
      val text = s"Scene $i: ${scene.name}"
      os.write(tmp / s"text$i.txt", text)
      val vf =
        if ttf.isEmpty then "null"
        else s"drawtext=fontfile=$ttf:textfile=$tmp/text$i.txt:fontsize=64:fontcolor=white:borderw=3:" +
          "bordercolor=black:x=(w-text_w)/2+120*sin(t):y=(h-text_h)/2+30*cos(t)"
      // 1. Visuals: a moving gradient with a moving text.
      times += ff("-f", "lavfi", "-i", s"gradients=s=1280x720:r=25:d=6:c0=${scene.from}:c1=${scene.to}:speed=0.05",
        "-vf", s"$vf,format=yuv420p", "-c:v", "libx264", "-preset", "veryfast", "-crf", "23", tmp / s"v$i.mp4")
      // 2. Voice: a tone. This stands in for the TTS stage (stage 3) of the spec.
      times += ff("-f", "lavfi", "-i", s"sine=f=${scene.freq}:r=44100:d=6", "-af", "afade=t=in:d=0.3,afade=t=out:st=5.7:d=0.3",
        "-ac", "2", tmp / s"a$i.wav")
      // 4. Captions: one cue for each scene.
      cue(index, text)
    }
    os.write(captions, cues.mkString("\n") + "\n")

    // 3. Join.
    val n = Scene.all.size
    val inputs = (1 to n).flatMap(i => List("-i", (tmp / s"v$i.mp4").toString)) ++
      (1 to n).flatMap(i => List("-i", (tmp / s"a$i.wav").toString))
    times += ff(inputs, "-i", captions, "-filter_complex", graph(n), "-map", s"[v${n - 1}]", "-map", "[aout]",
      "-map", s"${2 * n}:0", "-c:v", "libx264", "-preset", "veryfast", "-crf", "23", "-pix_fmt", "yuv420p", "-r", "25",
      "-c:a", "aac", "-b:a", "128k", "-c:s", "mov_text", "-movflags", "+faststart", file)

    // 5. Report.
    if !os.isFile(file) then fail("no output file")
    val Array(width, height) =
      probe(file, "-select_streams", "v:0", "-show_entries", "stream=width,height").split(",").map(_.trim.toInt): @unchecked
    val all = times.result()
    val report = VideoReport(
      file = config.shown,
      bytes = os.size(file),
      duration = probe(file, "-show_entries", "format=duration").toDoubleOption.getOrElse(0.0),
      width = width, height = height,
      videoCodec = probe(file, "-select_streams", "v:0", "-show_entries", "stream=codec_name"),
      audioCodec = probe(file, "-select_streams", "a:0", "-show_entries", "stream=codec_name"),
      streams = "vas".map(k => k -> probe(file, "-select_streams", k.toString, "-show_entries", "stream=index")
        .split("\\s+").count(_.nonEmpty)).toMap,
      wall = all.map(_._1).sum,
      peakMiB = all.map(_._2).max / 1024)
    os.write(out / "report.json", report.render + "\n")
    os.remove.all(tmp)

    // 6. Verdict.
    report.problem.foreach(fail)
    println(report.summary)
    0

/** getrusage(2) with the whole struct: Scala Native's binding has only the two times. */
private object Rusage:
  @extern private object libc:
    def getrusage(who: CInt, usage: Ptr[Byte]): CInt = extern

  private val childrenWho = -1 // RUSAGE_CHILDREN on Linux
  private val maxRssOffset = 32 // after ru_utime and ru_stime, two 16-byte timevals on 64-bit Linux

  def childrenMaxRssKiB(): Long =
    val usage = stackalloc[Byte](144)
    if libc.getrusage(childrenWho, usage) != 0 then 0L else !(usage + maxRssOffset).asInstanceOf[Ptr[Long]]
