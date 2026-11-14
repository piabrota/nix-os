package piabrota.reels

import scala.scalanative.posix.{signal, unistd}
import Json.*

/** The clips, the sound and the assembly into out/<slug>/reel.mp4. */
object Render:
  /** Seconds and peak memory of the timed runs so far, from the toolkit's `times`. */
  def stats(times: Seq[String]): Option[ujson.Obj] =
    val runs = times.filter(_.nonEmpty).map(_.split(' ').toSeq.map(_.toDoubleOption))
    if runs.exists(r => r.length < 2 || r.take(2).exists(_.isEmpty)) then None
    else
      val rows = runs.map(r => (r(0).get, jqRound(r(1).get / 1024 * 10) / 10.0))
      Some(ujson.Obj(
        "ffmpeg_wall_s" -> rows.map(_._1).sum,
        "peak_rss_mib" -> rows.map(_._2).maxOption.getOrElse(0.0),
        "runs" -> rows.length,
        "per_run" -> ujson.Arr.from(rows.map((s, m) => ujson.Arr(s, m)))))

  /** The filter graph of one xfade chain over `cuts`, after the stream of the stages before it when
    * `hasAcc`. Returns the graph and the index of the next input (the sound, on the last stage).
    */
  def chain(cuts: Seq[(Cut, Int)], hasAcc: Boolean, fps: Int): (String, Int) =
    val first = if hasAcc then 1 else 0
    val start = if hasAcc then ("[0:v]settb=AVTB,setpts=PTS-STARTPTS[acc];", "acc") else ("", "")
    val (graph, prev) = cuts.zipWithIndex.foldLeft(start) { case ((g, prev), ((c, i), j)) =>
      val clip = s"[${first + j}:v]settb=AVTB,setpts=PTS-STARTPTS[c$i];"
      if prev.isEmpty then (g + clip, s"c$i")
      else
        // The offset is 5 ms before the frame it names. ffmpeg 8.1's xfade `slideup` reads stray
        // memory in the one frame where progress is exactly 0 (the first of the transition, when the
        // offset falls on a frame), so two renders of one screenplay differed in that frame. The
        // `fps` filter below puts every frame back on the grid, and the frames after the transition
        // are unchanged (tested).
        val kind = if c.tr == Cut.Hard then Cut.HardAs else c.tr
        (g + clip + s"[$prev][c$i]xfade=transition=$kind:duration=${Json.num(c.dq / fps)}:offset=${Json.num(c.offset - 0.005)}[x$i];", s"x$i")
    }
    (graph + s"[$prev]fps=$fps,format=yuv420p[v]", first + cuts.length)

  /** One xfade chain over the clips of a stage, starting from the stream of the stages before it
    * (acc), when there is one. The offsets of the frame plan are on the chain's own timeline, so a
    * chain can be cut anywhere. ffmpeg reads every input at once, and each open input costs memory
    * (docs/REELS.md, "Limits"), so a long reel is built in stages of at most video.max_inputs inputs.
    * A stage that is not the last writes the video again at the quality of the scene clips, no sound.
    */
  private def assembleStage(tk: Toolkit, p: Project, acc: Option[os.Path], stage: Stage, out: os.Path): Unit =
    val cuts = (stage.from until stage.to).map(i => (p.timeline(i), i))
    val inputs = acc.toSeq.flatMap(a => Seq("-threads", "1", "-i", a.toString)) ++
      cuts.flatMap((c, _) => Seq("-threads", "1", "-i", p.dir.clip(c.id).toString))
    val (graph, k) = chain(cuts, acc.isDefined, tk.FPS)
    val color = Seq("-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709", "-color_range", "tv")
    val args =
      if stage.last then
        inputs ++ Seq("-i", (p.dir.audio / Name.Mix).toString, "-filter_complex", graph,
          "-map", "[v]", "-map", s"$k:a", "-c:v", "libx264", "-preset", tk.p("video", "preset"), "-crf", tk.p("video", "crf"),
          "-profile:v", "high", "-level", "4.0", "-pix_fmt", "yuv420p") ++ color ++
          Seq("-g", (tk.FPS * 2).toString, "-x264-params", tk.p("video", "x264_params"), "-threads", tk.p("video", "threads"),
            "-c:a", tk.p("audio", "codec"), "-b:a", tk.p("audio", "bitrate"), "-ar", tk.p("audio", "rate"), "-ac", tk.p("audio", "channels"),
            "-t", p.screenplay.format, "-map_metadata", "-1", "-metadata", s"title=${p.screenplay.title}", "-movflags", "+faststart",
            "-fflags", "+bitexact", "-flags:v", "+bitexact", "-flags:a", "+bitexact", "-f", "mp4", out.toString)
      else
        inputs ++ Seq("-filter_complex", graph, "-map", "[v]", "-an", "-c:v", "libx264", "-preset", "veryfast",
          "-crf", tk.p("video", "scene_crf"), "-pix_fmt", "yuv420p") ++ color ++
          Seq("-r", tk.FPS.toString, "-threads", "2", "-fflags", "+bitexact", "-flags:v", "+bitexact", "-f", "mp4", out.toString)
    if !tk.ffp(args*) then fail("assembly failed")

  /** One render at a time in a project. A lock left by a render that died (a killed seat, a
    * restart) names a process that is gone, and is taken over. Returns the lock, which the caller
    * removes.
    */
  def lock(dir: ProjectDir): os.Path =
    val lk = dir.lock
    if !tryMakeDir(lk) then
      val pid = try os.read(lk / Name.Pid).strip() catch case _: java.io.IOException => "0"
      if pid.toIntOption.exists(n => n > 0 && signal.kill(n, 0) == 0) then
        fail(s"another render of this project is running (process $pid). Wait for it, or remove $lk if it is not")
      os.remove.all(lk)
      if !tryMakeDir(lk) then fail(s"cannot take the render lock $lk")
    os.write.over(lk / Name.Pid, s"${unistd.getpid()}\n")
    lk

  def render(tk: Toolkit, args: List[String]): Int =
    if args.length != 1 then fail("usage: reel render <slug>")
    val slug = args.head
    val p = Gate.load(tk, slug)
    Gate.requireShotlist(tk, p)
    val rd = tk.out(slug)
    os.makeDir.all(rd.root)
    val lk = lock(p.dir)
    try build(tk, p, rd)
    finally os.remove.all(lk)

  private def build(tk: Toolkit, p: Project, rd: OutDir): Int =
    // What an earlier run left is of no use now, and a file of an old screenplay must not be taken
    // for this one's: the finished files go first, then the half-written ones of a run that died.
    Seq(rd.reel, rd.renderReport, rd.qaReport).foreach(os.remove(_))
    glob(rd.root, "", Name.Part).foreach(os.remove(_))
    val build = p.dir.build
    (glob(build, "stage", ".mp4") ++ glob(p.dir.scenes, "", Name.Part) ++ glob(p.dir.audio, "", Name.Part))
      .foreach(os.remove(_))
    val t0 = System.currentTimeMillis() / 1000
    note("sound")
    Audio.mixRun(tk, p, quiet = true)
    for c <- p.timeline do
      note(s"scene ${c.id}")
      Scene.buildClip(tk, p, c.id)
    val n = p.timeline.length
    note(s"assemble $n clips")

    val part = Name.part(rd.reel)
    Stage.plan(n, tk.pInt("video", "max_inputs")).foldLeft(Option.empty[os.Path]) { (acc, stage) =>
      val out = if stage.last then part else build / s"stage${stage.n}.mp4"
      note(s"assemble: stage ${stage.n}, clips ${stage.from + 1} to ${stage.to} of $n")
      assembleStage(tk, p, acc, stage, out)
      Some(out)
    }
    glob(build, "stage", ".mp4").foreach(os.remove(_))
    os.move(part, rd.reel, replaceExisting = true)
    val wall = System.currentTimeMillis() / 1000 - t0
    val bytes = os.size(rd.reel)
    val report = stats(os.read.lines(tk.times)).getOrElse(fail("cannot write render.json"))
    report("slug") = p.slug
    report("wall_s") = wall.toDouble
    report("bytes") = bytes.toDouble
    report(RenderClaim.ReelSha) = tk.sha(rd.reel)
    report(RenderClaim.ScreenplaySha) = p.hash
    os.write.over(Name.part(rd.renderReport), Json.compact(report) + "\n")
    os.move(Name.part(rd.renderReport), rd.renderReport, replaceExisting = true)
    say(s"render: ${rd.reel} ($bytes bytes, $wall s wall, ${report("peak_rss_mib").text} MiB peak in one ffmpeg)")
    0
