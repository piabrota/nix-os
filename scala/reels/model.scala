package piabrota.reels

import Json.*

/** The domain of the toolkit: what a command reads, decides on and writes. The commands work on
  * these values; JSON and file names stay at the edges, here.
  */

/** The programs the toolkit runs, by the name it looks up on the PATH. */
enum Tool(val bin: String):
  case Jq extends Tool("jq")
  case Ffmpeg extends Tool("ffmpeg")
  case Ffprobe extends Tool("ffprobe")
  case Resvg extends Tool("resvg")
  case Sha256sum extends Tool("sha256sum")
  case Timeout extends Tool("timeout")
  case Nice extends Tool("nice")
  case Time extends Tool("time")
  case Cp extends Tool("cp")
  case Chmod extends Tool("chmod")
  case Blender extends Tool("blender")

/** The subcommands of `reel`, and the tools each one needs on the PATH. */
enum Cmd(val key: String, val tools: Seq[Tool]):
  case New extends Cmd("new", Seq(Tool.Jq))
  case Lint extends Cmd("lint", Nil)
  case View extends Cmd("screenplay-view", Seq(Tool.Jq))
  case Timing extends Cmd("timing-report", Seq(Tool.Jq))
  case Approve extends Cmd("approve", Seq(Tool.Jq, Tool.Sha256sum))
  case Shotlist extends Cmd("shotlist", Seq(Tool.Jq, Tool.Sha256sum))
  case Still extends Cmd("still", Seq(Tool.Jq, Tool.Ffmpeg, Tool.Resvg))
  case Scene extends Cmd("scene", Seq(Tool.Jq, Tool.Ffmpeg, Tool.Resvg))
  case Music extends Cmd("music", Seq(Tool.Jq, Tool.Ffmpeg))
  case Blender extends Cmd("blender", Seq(Tool.Jq, Tool.Sha256sum))
  case Mix extends Cmd("mix", Seq(Tool.Jq, Tool.Ffmpeg))
  case Render extends Cmd("render", Seq(Tool.Jq, Tool.Ffmpeg, Tool.Ffprobe, Tool.Resvg))
  case Qa extends Cmd("qa", Seq(Tool.Jq, Tool.Ffmpeg, Tool.Ffprobe))
  case ContactSheet extends Cmd("contact-sheet", Seq(Tool.Jq, Tool.Ffmpeg))
  case Publish extends Cmd("publish", Seq(Tool.Jq, Tool.Sha256sum))

object Cmd:
  def parse(key: String): Option[Cmd] = values.find(_.key == key)

/** The tools that every command needs: the wrapper's PATH has no more than these and each
  * command's own.
  */
val baseTools: Seq[Tool] = Seq(Tool.Jq, Tool.Timeout, Tool.Nice, Tool.Sha256sum)

/** The environment variables the toolkit reads, once, in `Config.read`. */
object EnvVar:
  val Share = "REELS_SHARE"
  val Fonts = "REELS_FONTS"
  val Home = "REELS_HOME"
  val Outbox = "REELS_OUTBOX"
  val Blender = "REELS_BLENDER"
  val TmpDir = "TMPDIR"
  val XdgCache = "XDG_CACHE_HOME"
  val UserHome = "HOME"
  val XdgConfig = "XDG_CONFIG_HOME"
  val FontConfig = "FONTCONFIG_FILE"

object Defaults:
  val Home = "/var/lib/openrig/work/reels-fabric"
  val Outbox = "/var/lib/rig-outbox/reels-fabric"
  val TmpDir = "/tmp"
  val TmpPrefix = "reel."

/** The names of the files and folders the toolkit reads and writes. */
object Name:
  val Screenplay = "screenplay.json"
  val Approval = "screenplay.approved"
  val Shotlist = "shotlist.json"
  val Brief = "brief.md"
  val Reel = "reel.mp4"
  val RenderReport = "render.json"
  val QaReport = "qa.json"
  val Profile = "profile.json"
  val Lock = "render.lock"
  val Pid = "pid"
  val Music = "music.wav"
  val Premix = "premix.wav"
  val Mix = "mix.wav"
  val Hook = "hook.png"
  val ContactSheet = "contact-sheet.png"
  val Fonts = "fonts"
  val Lib = "lib"
  val Styles = "styles"
  val Examples = "examples"
  val Projects = "projects"
  val Out = "out"
  val Part = ".part"
  val FontsConf = "fonts.conf"

  /** `file.part`, the name a file is written under before its rename. */
  def part(file: os.Path): os.Path = file / os.up / s"${file.last}$Part"

  /** `file.part.png`: ffmpeg and resvg pick the format from the extension. */
  def partPng(file: os.Path): os.Path = file / os.up / s"${file.last}$Part.png"

/** The jq rule programs of share/reels/lib. */
enum Rule(val file: String):
  case Lint extends Rule("lint.jq")
  case ShotLint extends Rule("shotlint.jq")
  case Timeline extends Rule("timeline.jq")
  case Scene extends Rule("scene.jq")
  case Shotlist extends Rule("shotlist.jq")
  case Skeleton extends Rule("skeleton.jq")
  case Timing extends Rule("timing.jq")
  case View extends Rule("view.jq")
  case Background extends Rule("bg.jq")
  case QaPlan extends Rule("qaplan.jq")
  case QaReport extends Rule("qareport.jq")

/** The folders of one project, projects/<slug>/. */
final case class ProjectDir(root: os.Path):
  def screenplay: os.Path = root / Name.Screenplay
  def approval: os.Path = root / Name.Approval
  def brief: os.Path = root / Name.Brief
  def review: os.Path = root / "review"
  def direction: os.Path = root / "direction"
  def shotlist: os.Path = direction / Name.Shotlist
  def storyboard: os.Path = direction / "storyboard"
  def svg: os.Path = direction / "svg"
  def build: os.Path = root / "build"
  def scenes: os.Path = build / "scenes"
  def cache: os.Path = build / "cache"
  def layers: os.Path = build / "layers"
  def audio: os.Path = build / "audio"
  def lock: os.Path = build / Name.Lock
  def blenderHome: os.Path = build / "blender-home"
  def blenderScene(id: String): os.Path = root / "blender" / s"$id.py"
  def frames(id: String): os.Path = root / "frames" / id
  def clip(id: String): os.Path = scenes / s"$id.mp4"
  def ass(id: String): os.Path = scenes / s"$id.ass"

  /** The folders `reel new` makes, and those every loaded project has. */
  def newDirs: Seq[os.Path] = Seq(review, storyboard, svg, build)
  def workDirs: Seq[os.Path] = Seq(scenes, cache, layers, audio, storyboard)

/** The finished files of one project, out/<slug>/. */
final case class OutDir(root: os.Path):
  def reel: os.Path = root / Name.Reel
  def renderReport: os.Path = root / Name.RenderReport
  def qaReport: os.Path = root / Name.QaReport
  def qa: os.Path = root / "qa"
  def frame(id: String): os.Path = qa / s"$id.png"
  def startFrame(id: String): os.Path = qa / s"$id-start.png"
  def hook: os.Path = qa / Name.Hook
  def contactSheet: os.Path = qa / Name.ContactSheet

/** Where everything is, read once from the environment at the edge (`Config.read`). */
final case class Config(share: os.Path, fonts: os.Path, home: os.Path, outbox: os.Path, tmpRoot: os.Path,
    cacheBase: Option[String], blender: Option[String]):
  def lib: os.Path = share / Name.Lib
  def profileFile: os.Path = share / Name.Profile
  def styles: os.Path = share / Name.Styles
  def example(format: String): os.Path = share / Name.Examples / format
  def projects: os.Path = home / Name.Projects
  def project(slug: String): ProjectDir = ProjectDir(projects / slug)
  def out(slug: String): OutDir = OutDir(home / Name.Out / slug)

object Config:
  /** The configuration from an environment (`lookup` gives a set, non-empty variable). It refuses
    * the same paths, in the same order, as the shell toolkit did.
    */
  def read(share: os.Path, lookup: String => Option[String]): Config =
    checkedPath(share.toString, EnvVar.Share)
    val fonts = checkedPath(lookup(EnvVar.Fonts).getOrElse((share / Name.Fonts).toString), EnvVar.Fonts)
    val home = checkedPath(lookup(EnvVar.Home).getOrElse(Defaults.Home), EnvVar.Home)
    val outbox = os.Path(lookup(EnvVar.Outbox).getOrElse(Defaults.Outbox), os.pwd)
    val tmpRoot = os.Path(lookup(EnvVar.TmpDir).getOrElse(Defaults.TmpDir), os.pwd)
    val cache = lookup(EnvVar.XdgCache).orElse(lookup(EnvVar.UserHome).map(_ + "/.cache"))
    Config(share, fonts, home, outbox, tmpRoot, cache, lookup(EnvVar.Blender))

/** A path that reaches an ffmpeg filter graph, a fontconfig file or a Dialogue line is written into
  * a syntax with its own special characters (: , ; ' [ ] \ < &). One rule keeps them out, here,
  * instead of an escape at each place: these paths hold letters, digits and / . _ - only.
  */
def checkedPath(path: String, what: String): os.Path =
  if !path.matches("[A-Za-z0-9/._-]+") then
    fail(s"$what: unsupported character in the path $path (letters, digits and / . _ - only)")
  os.Path(path, os.pwd)

/** profile.json: every number of the toolkit. `text` is the file as `jq -c` writes it, which the
  * jq programs get and which is in the key of every cached clip.
  */
final case class Profile(text: String, json: ujson.Value):
  /** A number or a word, as `jq -r` prints it: `p("video", "crf")`. */
  def p(path: String*): String = path.foldLeft(json)(_.at(_)).text
  def pInt(path: String*): Int = path.foldLeft(json)(_.at(_)).num.toInt
  def W: Int = pInt("video", "width")
  def H: Int = pInt("video", "height")
  def FPS: Int = pInt("video", "fps")

/** The level of a lint finding. */
enum Level(val key: String):
  case Error extends Level("error")
  case Warn extends Level("warn")
  case Other extends Level("")

object Level:
  def parse(key: String): Level = values.find(l => l != Other && l.key == key).getOrElse(Other)

/** One finding of a jq rule program. */
final case class Finding(level: Level, beat: String, rule: String, msg: String)

object Finding:
  val NoBeat = "--"

  def from(v: ujson.Value): Finding =
    val level = v.at("level") match
      case ujson.Str(s) => Level.parse(s)
      case _            => Level.Other
    Finding(level, v.at("beat").or(ujson.Str(NoBeat)).text, v.at("rule").text, v.at("msg").text)

  def all(v: ujson.Value): Seq[Finding] = v.items.map(from)

  /** The one finding of a rule program that could not read its input: an error, never a pass. */
  def unreadable(rule: String, why: String): Seq[Finding] = Seq(Finding(Level.Error, NoBeat, rule, why))

/** A music preset of the screenplay (music.preset). */
enum MusicPreset(val key: String):
  case Pulse extends MusicPreset("pulse")
  case Ambient extends MusicPreset("ambient")
  case Tension extends MusicPreset("tension")
  case Upbeat extends MusicPreset("upbeat")

object MusicPreset:
  /** The word for "no music". */
  val NoMusic = "none"
  def parse(key: String): Option[MusicPreset] = values.find(_.key == key)

/** The level of the music under a beat (sound.music), as a gain. */
enum MusicLevel(val key: String, val gain: Double):
  case On extends MusicLevel("on", 0.55)
  case Low extends MusicLevel("low", 0.22)
  case Off extends MusicLevel("off", 0.0)

object MusicLevel:
  def parse(key: String): Option[MusicLevel] = values.find(_.key == key)

/** One sound effect: its name in the screenplay, its length, its ffmpeg source and its filters. */
enum Sfx(val key: String, val seconds: String, val source: String, val filters: String):
  case Hit extends Sfx("hit", "0.9", "aevalsrc=exprs='0.9*sin(2*PI*(42*t+110*(1-exp(-28*t))/28))*exp(-5*t)+0.3*(random(0)*2-1)*exp(-60*t)':s=48000:d=0.9", "alimiter=limit=0.9:level=disabled")
  case Tick extends Sfx("tick", "0.1", "aevalsrc=exprs='0.7*sin(2*PI*2300*t)*exp(-85*t)':s=48000:d=0.1", "volume=0.8")
  case Pop extends Sfx("pop", "0.25", "aevalsrc=exprs='0.8*sin(2*PI*(320*t+650*(1-exp(-38*t))/38))*exp(-22*t)':s=48000:d=0.25", "volume=0.9")
  case Whoosh extends Sfx("whoosh", "0.8", "anoisesrc=d=0.8:c=pink:a=0.9:r=48000:seed=7", "highpass=f=350,lowpass=f=7500,volume='pow(sin(PI*t/0.8),2)*0.8':eval=frame")
  case Riser extends Sfx("riser", "2.2", "aevalsrc=exprs='((random(0)*2-1)*0.5+0.6*sin(2*PI*(180*t+200*t*t)))*pow(t/2.2,2.2)':s=48000:d=2.2", "highpass=f=200,volume=0.7")

object Sfx:
  def parse(key: String): Option[Sfx] = values.find(_.key == key)

/** One sound effect a beat asks for, `at` seconds into the beat. */
final case class SfxCue(name: String, at: Option[Double])

/** What the sound of a beat says. */
final case class Sound(silence: Boolean, music: String, sfx: Seq[SfxCue])

final case class Beat(tIn: Option[Double], sound: Sound)

/** The music bed: its preset word and its tempo (`bpmText` as the screenplay writes it). */
final case class Music(preset: String, bpm: Option[Double], bpmText: String):
  def isOn: Boolean = preset != MusicPreset.NoMusic

/** What the toolkit's Scala code reads of a screenplay; the jq programs read the whole text. Each
  * text field is as `jq -r` prints it.
  */
final case class Screenplay(slug: String, format: String, title: String, loop: Boolean, style: String,
    music: Music, beats: Seq[Beat])

object Screenplay:
  def from(v: ujson.Value): Screenplay =
    def number(x: ujson.Value) = x match
      case ujson.Num(d) => Some(d)
      case _            => None
    val music = v.at("music")
    val beats = v.at("beats").items.map { b =>
      val s = b.at("sound")
      val cues = s.at("sfx").items.map(e => SfxCue(e.at("name").text, number(e.at("at"))))
      Beat(number(b.at("t_in")), Sound(s.at("silence") == ujson.True, s.at("music").or(ujson.Str(MusicLevel.On.key)).text, cues))
    }
    Screenplay(v.at("slug").text, v.at("format").text, v.at("title").text, v.at("loop").text == "true",
      v.at("look").at("style").text,
      Music(music.at("preset").or(ujson.Str(MusicPreset.NoMusic)).text, number(music.at("bpm")).filter(_ != 0), music.at("bpm").text),
      beats)

/** The kind of a shot in the shotlist. */
enum ShotKind(val key: String):
  case Flat extends ShotKind("flat")
  case ThreeD extends ShotKind("3d")

object ShotKind:
  def parse(key: String): ShotKind = if key == ThreeD.key then ThreeD else Flat

/** The shot of a beat: `text` is its JSON for the jq programs, `{}` when the shotlist has none. */
final case class Shot(text: String, listed: Boolean, kind: ShotKind)

object Shot:
  val Empty = "{}"
  def from(text: String): Shot =
    val v = Json.read(text).getOrElse(ujson.Obj())
    Shot(text, v.at("beat").truthy, ShotKind.parse(v.at("kind").or(ujson.Str(ShotKind.Flat.key)).text))

/** A screenplay that passed the gate: `sp` is a private copy of the file that was hashed, so the
  * file cannot change under a render.
  */
final case class Approved(slug: String, dir: ProjectDir, sp: os.Path, hash: String)

/** One beat in the frame plan (timeline.jq): frames S to E, the handles, the clip length, the
  * transition into it and where its xfade starts.
  */
final case class Cut(id: String, tr: String, s: Double, e: Double, hin: Double, hout: Double,
    frames: Double, dq: Double, offset: Double)

object Cut:
  /** The transition word for a hard cut: ffmpeg's xfade has no "cut", so it is a fade of 0 frames. */
  val Hard = "cut"
  val HardAs = "fade"

  def from(c: ujson.Value): Cut =
    def n(k: String) = c.at(k) match
      case ujson.Num(d) => d
      case _            => 0.0
    Cut(c.at("id").text, c.at("tr").text, n("S"), n("E"), n("hin"), n("hout"), n("frames"), n("dq"), n("offset"))

/** An approved project with what a render reads: the screenplay, its style, its frame plan and its
  * shotlist, each read once, so a render uses one version from its first beat to its last.
  */
final case class Project(approved: Approved, spText: String, screenplay: Screenplay, style: String,
    timeline: Vector[Cut], shots: os.Path, shotsSha: String):
  export approved.{slug, dir, sp, hash}
  def hasShots: Boolean = os.isFile(shots)
  def isLast(id: String): Boolean = timeline.lastOption.exists(_.id == id)
  def cut(id: String): Option[Cut] = timeline.find(_.id == id)

object Project:
  /** The hash of the shotlist when the project has none, in the key of every cached clip. */
  val NoShotlist = "none"

/** What render.json claims about reel.mp4: the hashes of the screenplay and of the file. Empty
  * when render.json is missing or does not say.
  */
final case class RenderClaim(screenplaySha: String, reelSha: String)

object RenderClaim:
  val ScreenplaySha = "screenplay_sha256"
  val ReelSha = "reel_sha256"

  def from(v: Option[ujson.Value]): RenderClaim =
    def claim(k: String) = v.map(_.at(k).or(ujson.Str("")).text).getOrElse("")
    RenderClaim(claim(ScreenplaySha), claim(ReelSha))

/** The QA report that publish reads. */
final case class QaVerdict(passed: Boolean, reelSha: String, screenplaySha: String)

object QaVerdict:
  val Schema = "reels.qa/1"

  /** True when the report passed: every check, every beat, no failure. */
  def passed(report: ujson.Value): Boolean =
    def allPass(k: String) = report.at(k) match
      case a: ujson.Arr => a.value.forall(_.at("pass").truthy)
      case _            => false
    report.at("schema") == ujson.Str(Schema) && report.at("pass") == ujson.True &&
      allPass("checks") && allPass("beats") && (report.at("failures") match
        case a: ujson.Arr => a.value.isEmpty
        case _            => false)

  def from(report: ujson.Value): QaVerdict =
    QaVerdict(passed(report), report.at(RenderClaim.ReelSha).text, report.at(RenderClaim.ScreenplaySha).text)

/** The two modes of a Blender run. */
enum BlenderMode(val key: String):
  case Probe extends BlenderMode("probe")
  case Render extends BlenderMode("render")

object BlenderMode:
  /** The output path of a probe, which writes nothing. */
  val NoOutput = "none"

/** What scene.jq writes for a beat. */
enum SceneMode(val key: String):
  case Ass extends SceneMode("ass")
  case Plan extends SceneMode("plan")

/** The options of `reel still`. */
final case class StillOptions(at: String, out: String)

/** One stage of the assembly: the clips [from, to), and whether it is the last. */
final case class Stage(n: Int, from: Int, to: Int, last: Boolean)

object Stage:
  /** The stages of `clips` clips with at most `max` inputs to one ffmpeg: the first takes `max`
    * clips, each later one `max - 1` and the stream of the stages before it.
    */
  def plan(clips: Int, max: Int): Seq[Stage] =
    Iterator.unfold((0, 1)) { (from, n) =>
      Option.when(from < clips) {
        val to = math.min(from + (if n == 1 then max else max - 1), clips)
        (Stage(n, from, to, to == clips), (to, n + 1))
      }
    }.toSeq

/** The two lengths of a reel, in seconds, as the screenplay and `reel new` write them. */
object Format:
  val Seconds: Seq[String] = Seq("15", "30")

/** An SVG layer of a beat: its file in the project, when it fades in and for how long. */
final case class Layer(svg: String, at: String, fade: String)

/** What scene.jq plans for the picture of a beat, each number as jq prints it. */
final case class ScenePlan(zoom0: String, zoom1: String, grain: String, diagramY0: String, diagramH: String,
    diagramW: String, layers: Seq[Layer])

object ScenePlan:
  def from(v: ujson.Value): ScenePlan =
    val d = v.at("diagram")
    ScenePlan(v.at("zoom").at(0).text, v.at("zoom").at(1).text, v.at("grain").text, d.at("y0").text, d.at("h").text,
      d.at("w").text, v.at("layers").items.map(l => Layer(l.at("svg").text, l.at("at").text, l.at("fade").text)))
