package piabrota.reels

import piabrota.lib.{Exit, Sh, warn}

/** `reel: <message>` on stderr, then exit 1. */
def fail(message: String): Nothing = throw Exit(1, s"reel: $message")

/** `reel: <message>` on stderr; the command goes on. */
def note(message: String): Unit = warn(s"reel: $message")

def say(message: String): Unit = println(message)

def needTools(tools: Seq[Tool]): Unit =
  tools.foreach(t => if Sh.which(t.bin).isEmpty then fail(s"missing tool: ${t.bin}"))

/** What every command shares: the configuration, the profile and a temporary folder of this run,
  * `tmp`, which `Toolkit.close` removes. Made once for each run of `reel`, by `Toolkit.open`.
  */
final case class Toolkit(cfg: Config, profile: Profile, tmp: os.Path, gnuTime: Boolean):
  export cfg.{share, fonts, home, outbox}
  export profile.{p, pInt, W, H, FPS}

  def profileText: String = profile.text
  def project(slug: String): ProjectDir = cfg.project(slug)
  def out(slug: String): OutDir = cfg.out(slug)

  /** The seconds and peak KiB of each timed run, one "seconds KiB" line each. */
  def times: os.Path = tmp / "times"

  private def ffTimeout = p("limits", "ffmpeg_timeout_s")
  private def resvgTimeout = p("limits", "resvg_timeout_s")

  /** Where fontconfig reads its configuration: the user's cache, or the temporary folder. */
  def fontCache: String = s"${cfg.cacheBase.getOrElse(tmp.toString)}/reels"

  /** The environment of every ffmpeg. Every command that runs ffmpeg loads its project first, and
    * `Gate.load` writes this file (`setupFonts`).
    */
  lazy val ffEnv: Map[String, String] = Map(EnvVar.FontConfig -> (os.Path(fontCache, os.pwd) / Name.FontsConf).toString)

  /** Runs the command; returns its exit code. */
  def exec(cmd: Seq[String], extraEnv: Map[String, String] = Map.empty,
      stdout: os.ProcessOutput = os.Inherit, stderr: os.ProcessOutput = os.Inherit,
      mergeErr: Boolean = false): Int =
    os.proc(cmd).call(env = extraEnv, stdin = os.Inherit, stdout = stdout, stderr = stderr,
      mergeErrIntoOut = mergeErr, check = false).exitCode

  /** Runs the command and appends "seconds peak-KiB" to `times` (GNU time, when there is one). */
  def timed(cmd: Seq[String], extraEnv: Map[String, String] = Map.empty,
      stdout: os.ProcessOutput = os.Inherit, mergeErr: Boolean = false): Int =
    if gnuTime then
      exec(Seq(Tool.Time.bin, "-f", "%e %M", "-a", "-o", times.toString) ++ cmd, extraEnv, stdout, mergeErr = mergeErr)
    else
      val start = System.currentTimeMillis() / 1000
      val code = exec(cmd, extraEnv, stdout, mergeErr = mergeErr)
      os.write.append(times, s"${System.currentTimeMillis() / 1000 - start} 0\n")
      code

  private def stopped(code: Int, name: String, seconds: String): Int =
    if code == 124 then note(s"$name stopped: no result after $seconds s")
    code

  private def ffmpeg(loglevel: Seq[String], args: Seq[String]): Seq[String] =
    limited(ffTimeout, Seq(Tool.Ffmpeg.bin, "-nostdin", "-hide_banner") ++ loglevel ++
      Seq("-y", "-filter_threads", "2", "-filter_complex_threads", "2") ++ args)

  /** ffmpeg, quiet. */
  def ff(args: String*): Boolean =
    stopped(exec(ffmpeg(Seq("-loglevel", "error"), args), ffEnv), Tool.Ffmpeg.bin, ffTimeout) == 0

  /** ffmpeg, quiet and timed. */
  def ffp(args: String*): Boolean =
    stopped(timed(ffmpeg(Seq("-loglevel", "error"), args), ffEnv), Tool.Ffmpeg.bin, ffTimeout) == 0

  /** ffmpeg whose log is the result (loudnorm prints its measurement): the log, or None. */
  def ffl(args: String*): Option[String] =
    val r = os.proc(ffmpeg(Seq("-nostats", "-loglevel", "info"), args))
      .call(env = ffEnv, stdin = os.Inherit, stdout = os.Inherit, stderr = os.Pipe, check = false)
    Option.when(stopped(r.exitCode, Tool.Ffmpeg.bin, ffTimeout) == 0)(r.err.text())

  /** resvg, with its own time limit; it reads our two fonts only. */
  def svgToPng(args: String*): Boolean =
    val cmd = limited(resvgTimeout,
      Seq(Tool.Resvg.bin, "--skip-system-fonts", "--use-fonts-dir", fonts.toString) ++ args)
    stopped(exec(cmd), Tool.Resvg.bin, resvgTimeout) == 0

  /** fontconfig reads only our two fonts, from a cache the user can write. */
  def setupFonts(): Unit =
    if !os.isDir(fonts) then fail(s"no fonts folder: $fonts")
    val cache = checkedPath(fontCache, "the cache folder")
    os.makeDir.all(cache)
    os.write.over(cache / Name.FontsConf, fontsConf(fonts, cache))

  /** SHA-256 of a file, in lower-case hex. */
  def sha(file: os.Path): String = shaOf(Seq(file))

  /** The names of the style files. */
  def styles: Seq[String] =
    os.list(cfg.styles).map(_.last).filter(_.endsWith(".json")).map(_.stripSuffix(".json")).sorted

  def styleFile(name: String): os.Path = cfg.styles / s"$name.json"

end Toolkit

object Toolkit:
  /** The edge of every run: the temporary folder, the profile, and whether `time` is GNU time. */
  def open(cfg: Config): Toolkit =
    val tmp =
      try os.temp.dir(cfg.tmpRoot, prefix = Defaults.TmpPrefix, deleteOnExit = false)
      catch case _: Exception => fail("cannot make a temporary folder")
    checkedPath(tmp.toString, EnvVar.TmpDir)
    val tk = Toolkit(cfg, readProfile(cfg.profileFile), tmp, gnuTime)
    os.write.over(tk.times, "")
    tk

  def close(tk: Toolkit): Unit = os.remove.all(tk.tmp)

  private def readProfile(file: os.Path): Profile =
    val json = Json.readFile(file).getOrElse(fail(s"cannot read $file"))
    Profile(Json.compact(json), json)

  private def gnuTime: Boolean =
    try Sh.ok(Tool.Time.bin, "-f", "%e %M", "true")
    catch case _: Exception => false

/** Low priority and a time limit: a stuck program ends with a clear line instead of holding the
  * seat. The unit has one memory budget for the daemon and all seats (docs/REELS.md, "Limits").
  */
def limited(seconds: String, cmd: Seq[String]): Seq[String] =
  Seq(Tool.Timeout.bin, "-k", "5", seconds, Tool.Nice.bin, "-n", "10") ++ cmd

def fontsConf(fonts: os.Path, cache: os.Path): String =
  s"""<?xml version="1.0"?>
     |<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
     |<fontconfig>
     |  <dir>$fonts</dir>
     |  <cachedir>$cache/fontconfig</cachedir>
     |</fontconfig>
     |""".stripMargin

/** SHA-256 of the files one after the other (`cat files | sha256sum`). */
def shaOf(files: Seq[os.Path], prefix: String = ""): String =
  val material = new geny.Writable:
    def writeBytesTo(out: java.io.OutputStream): Unit =
      out.write(prefix.getBytes("UTF-8"))
      files.foreach(f => os.read.stream(f).writeBytesTo(out))
  val r = os.proc(Tool.Sha256sum.bin).call(stdin = os.Source.WritableSource(material), check = false)
  if r.exitCode != 0 then throw Exit(r.exitCode, r.err.text().strip())
  r.out.text().takeWhile(_ != ' ')

/** A regular file that is not a link: the gate reads the screenplay and its approval as they are,
  * never through a link that someone can move.
  */
def plainFile(p: os.Path): Boolean = os.isFile(p) && !os.isLink(p)

def present(p: os.Path): Boolean = os.exists(p, followLinks = false)

/** `mkdir` without -p: false when the folder exists or cannot be made. */
def tryMakeDir(dir: os.Path): Boolean =
  try { os.makeDir(dir); true }
  catch case _: java.io.IOException => false

/** The names in `dir` that a shell glob `prefix*suffix` matches (no dot files), sorted. */
def glob(dir: os.Path, prefix: String, suffix: String): Seq[os.Path] =
  if !os.isDir(dir) then Nil
  else os.list(dir).filter { p =>
    val n = p.last
    !n.startsWith(".") && n.startsWith(prefix) && n.endsWith(suffix) && n.length >= prefix.length + suffix.length
  }.sortBy(_.last)

/** Succeeds when nothing in the folder tree is a symbolic link. */
def noLinks(dir: os.Path): Boolean =
  os.list(dir).forall(p => !os.isLink(p) && (!os.isDir(p) || noLinks(p)))

/** What a screenplay says reaches a terminal only after the control characters are gone. */
def printable(s: String): String =
  s.filterNot(c => (c <= '\u0008') || (c >= '\u000b' && c <= '\u001f') || c == '\u007f')

/** `x1 y1 x2 y2` of what a `bbox` filter printed to `file`, or "none". */
def bboxOf(file: os.Path): String =
  val kv = metadata(file)
  (for x1 <- kv.get("lavfi.bbox.x1"); y1 <- kv.get("lavfi.bbox.y1"); x2 <- kv.get("lavfi.bbox.x2"); y2 <- kv.get("lavfi.bbox.y2")
  yield s"$x1 $y1 $x2 $y2").getOrElse(Box.Empty)

/** The words for a box that is not there: nothing drawn, or no frame at all. */
object Box:
  val Empty = "none"
  val Missing = "missing"

/** The `key=value` lines of a `metadata=mode=print` file; the last one of a key wins. */
def metadata(file: os.Path): Map[String, String] =
  if !os.exists(file) then Map.empty
  else os.read.lines(file).flatMap(l => l.split("=", 2) match
    case Array(k, v) => Some(k -> v)
    case _           => None
  ).toMap

/** jq's `round`: half away from zero. */
def jqRound(d: Double): Long = if d < 0 then -math.round(-d) else math.round(d)
