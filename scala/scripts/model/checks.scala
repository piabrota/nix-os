package piabrota.scripts

// The checks of the repository's own files: Hermes's context files, the favicon build and the
// video render path.

/** How close a context file is to Hermes's cut. */
enum ContextLevel(val label: String, val annotation: Option[String]):
  case Ok extends ContextLevel("ok", None)
  case Warn extends ContextLevel("WARN", Some("warning"))
  case Fail extends ContextLevel("FAIL", Some("error"))

/** context-size's settings: the checkout, and whether to write GitHub annotations (GITHUB_ACTIONS). */
final case class ContextConfig(root: os.Path, annotate: Boolean)

object ContextConfig:
  // Hermes cuts a context file at 32000 characters (agent.prompt_builder logs 'Context file X
  // TRUNCATED') and drops the middle. Warn from a margin of 2000.
  val limit = 32000
  val warnFrom = 30000
  val files = List("AGENTS.md", "hermes/AGENTS.md", "hermes/SOUL.md")

/** One expectation of favicon-files-check. */
final case class FileCheck(desc: String, got: Any, want: Any):
  def passed: Boolean = got == want
  def render: String = s"FAIL $desc: got [$got], want [$want]"

/** The files of the favicon build. */
object FaviconOutput:
  val touchIcon = "apple-touch-icon.png"
  val ico = "favicon.ico"
  val svg = "favicon.svg"
  val files = List(touchIcon, ico, svg)
  val icoSizes = List(16, 32, 48)
  val touchPx = 180
  val png: List[Byte] = List(0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n').map(_.toByte)

/** One scene of the dummy video: its name, its tone and its gradient. */
final case class Scene(name: String, freq: Int, from: String, to: String)

object Scene:
  val all: List[Scene] = List(
    Scene("brief", 220, "0x1d3557", "0xa8dadc"),
    Scene("script", 262, "0x6a040f", "0xf48c06"),
    Scene("voice", 330, "0x1b4332", "0x95d5b2"),
    Scene("visuals", 392, "0x3c096c", "0xe0aaff"),
    Scene("render", 440, "0x03045e", "0x90e0ef"),
  )

/** video-dummy's settings: the output folder as given (VIDEO_LAB_OUT). */
final case class VideoConfig(outName: String):
  def out: os.Path = os.Path(outName, os.pwd)

  /** As the report names the file: the folder as given, not made absolute. */
  def shown: String =
    (if outName.startsWith("/") then os.Path(outName) / VideoConfig.file else os.RelPath(outName) / VideoConfig.file).toString

object VideoConfig:
  val defaultOut = "video-lab/out/dummy"
  val file = "dummy.mp4"

/** What ffprobe says of the video, with the time and peak memory of the ffmpeg runs. */
final case class VideoReport(file: String, bytes: Long, duration: Double, width: Int, height: Int,
    videoCodec: String, audioCodec: String, streams: Map[Char, Int], wall: Double, peakMiB: Long):
  /** Python's json.dumps layout, which the report has always had. */
  def render: String =
    List(
      "file" -> ujson.write(file), "bytes" -> bytes.toString, "duration_s" -> f"$duration%.1f",
      "width" -> width.toString, "height" -> height.toString, "video_codec" -> ujson.write(videoCodec),
      "audio_codec" -> ujson.write(audioCodec), "subtitle_tracks" -> streams('s').toString,
      "wall_s" -> f"$wall%.1f", "peak_mib" -> peakMiB.toString,
    ).map((k, v) => s"\"$k\": $v").mkString("{", ", ", "}")

  /** Why the artifact fails, if it does. */
  def problem: Option[String] =
    if bytes <= 102400 then Some(s"file is $bytes bytes, 100 KB or less")
    else if streams('v') != 1 then Some(s"${streams('v')} video streams, expected 1")
    else if streams('a') != 1 then Some(s"${streams('a')} audio streams, expected 1")
    else if duration < 24 || duration > 32 then Some(f"duration $duration%.1f s, expected 24 to 32 s")
    else None

  def summary: String =
    f"ARTIFACT OK: $file ($duration%.1fs, ${width}x$height, $videoCodec+$audioCodec, ${bytes / 1048576.0}%.1f MiB, peak $peakMiB MiB)"
