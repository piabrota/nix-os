package piabrota.pirsig

import scala.collection.immutable.VectorMap

/** The files of a video's work folder; all but the transcripts go to the pull request. */
object VideoFiles:
  val VideoJson = "video.json"
  val ReadingMd = "leitura.markdown"
  val FiguresJson = "figuras.json"
  val FiguresDir = "figuras"
  val Transcript = "transcript.txt"
  val TranscriptJson = "transcript.json3"
  /** The work folders, under the data directory of the videos. */
  val WorkDir = "videos"

/** The files yt-dlp writes for `-o v.%(ext)s`. */
object YtdlpFiles:
  val Template = "v.%(ext)s"
  val Info = "v.info.json"
  def captions(track: String): String = s"v.$track.json3"

enum CaptionsKind(val label: String, val ytdlpFlag: String):
  case Manual extends CaptionsKind("manual", "--write-subs")
  case Automatic extends CaptionsKind("automatic", "--write-auto-subs")

/** A caption track of yt-dlp, by its language code. */
final case class Track(name: String, kind: CaptionsKind)

/** The caption tracks of a video's info, and the spoken language ("" when unknown). */
final case class CaptionTracks(language: String, subtitles: List[String], automatic: List[String])

object CaptionTracks:
  def parse(info: ujson.Value): CaptionTracks =
    CaptionTracks(Json.string(info, "language").getOrElse(""), Json.keys(info, "subtitles"),
      Json.keys(info, "automatic_captions"))

/** One json3 event of the captions: when it starts and its text, whitespace runs as one space. */
final case class Caption(startMs: Double, text: String)

object Caption:
  def parse(event: ujson.Value): Option[Caption] = event.objOpt.map: e =>
    val segs = e.get("segs").flatMap(_.arrOpt).getOrElse(Nil)
    val joined = segs.flatMap(_.objOpt).map(_.get("utf8").flatMap(_.strOpt).getOrElse("")).mkString
    Caption(e.get("tStartMs").flatMap(_.numOpt).getOrElse(0.0), Py.strip(joined.replaceAll(s"${Py.spaceClass}+", " ")))

  def parseAll(events: Seq[ujson.Value]): List[Caption] = events.toList.flatMap(parse)

/** video.json, as `pirsig_video_fetch` writes it from yt-dlp's info. */
final case class VideoRecord(id: String, url: String, title: String, channel: Option[String], date: String,
    duration: Double, language: Option[String], track: Track, description: Option[String]):
  def json: ujson.Obj =
    def opt(v: Option[String]): ujson.Value = v.fold(ujson.Null)(ujson.Str(_))
    ujson.Obj(
      "id" -> id, "url" -> url, "title" -> title, "channel" -> opt(channel), "date" -> date,
      "duration" -> duration, "language" -> opt(language), "captions" -> track.name,
      "captions_kind" -> track.kind.label, "description" -> opt(description),
      "hub" -> ujson.Null, "resource" -> ujson.Null,
    )

object VideoRecord:
  /** yt-dlp's `upload_date`, `yyyyMMdd`, as `yyyy-MM-dd`. */
  def date(info: ujson.Value): String =
    val d = Py.str(Json.field(info, "upload_date"))
    s"${d.take(4)}-${d.slice(4, 6)}-${d.drop(6)}"

  def title(info: ujson.Value): String = Py.str(Json.field(info, "title"))

  def from(info: ujson.Value, date: String, track: Track): VideoRecord =
    VideoRecord(
      id = Py.str(Json.field(info, "id")),
      url = Py.str(Json.field(info, "webpage_url")),
      title = title(info),
      channel = Json.string(info, "channel"),
      date = date,
      duration = Json.number(Json.field(info, "duration")),
      language = Json.string(info, "language"),
      track = track,
      description = Json.string(info, "description"),
    )

/** What the pull request says of a video, read back from video.json. */
final case class VideoSummary(url: String, duration: Double, captionsKind: String, captions: String)

object VideoSummary:
  def duration(video: ujson.Value): Double = Json.number(Json.field(video, "duration"))

  def parse(video: ujson.Value): VideoSummary =
    val url = Py.str(Json.field(video, "url"))
    val seconds = duration(video)
    val kind = Py.str(Json.field(video, "captions_kind"))
    VideoSummary(url, seconds, kind, Py.str(Json.field(video, "captions")))

/** A note of the reading: `### [k=key t=from-to] Title`, its text and its links (`-> key: why`). */
final case class VideoNote(title: String, key: String, from: Int, to: Int, body: String, links: List[Link])

/** A part of the reading (`## Title`): its own text, then its notes. */
final case class Part(title: String, body: String = "", notes: List[VideoNote] = Nil)

final case class Doc(title: String, parts: List[Part]):
  def notes: List[VideoNote] = parts.flatMap(_.notes)
  /** The bodies of every part and note, in order. */
  def body: String = parts.flatMap(p => p.body :: p.notes.map(_.body)).mkString("\n")

final case class Reading(words: Int, mean: Double, longShare: Double, minutes: Int):
  def render: String =
    s"Leitura estimada: ~$minutes min ($words palavras; frase média $mean; " +
      s"${math.rint(longShare * 100).toLong}% palavras longas)"

enum FigureField(val key: String):
  case Title extends FigureField("title")
  case Alt extends FigureField("alt")
  case Takeaway extends FigureField("takeaway")
  case Read extends FigureField("read")
  case Missing extends FigureField("missing")
  case Evidence extends FigureField("evidence")

/** An entry of figuras.json: whether it is there (Python-truthy) and the fields it lacks. */
final case class FigureEntry(present: Boolean, missing: List[FigureField])

object FigureEntry:
  val Absent: FigureEntry = FigureEntry(present = false, FigureField.values.toList)

  def parse(v: ujson.Value): FigureEntry =
    FigureEntry(Json.truthy(v), FigureField.values.toList.filterNot(f => Json.truthy(Json.get(v, f.key))))

/** figuras.json: the figures by id, in the file's order. */
final case class Figures(entries: VectorMap[String, FigureEntry])

object Figures:
  val Empty: Figures = Figures(VectorMap.empty)

  def parse(o: ujson.Obj): Figures = Figures(VectorMap.from(o.value.iterator.map((k, v) => k -> FigureEntry.parse(v))))

/** The result of `pirsig_video_check`. */
enum CheckResult:
  /** A file of the folder is not there: nothing else is checked. */
  case Incomplete(missing: List[String])
  case Checked(notes: Int, figures: Int, covers: String, reading: Reading, found: List[String])

  def problems: List[String] = this match
    case Incomplete(missing)        => missing
    case Checked(_, _, _, _, found)    => found

  def json: ujson.Obj = this match
    case Incomplete(missing) => ujson.Obj("problems" -> Json.strings(missing))
    case Checked(notes, figures, covers, reading, found) =>
      ujson.Obj(
        "notes" -> notes, "figures" -> figures, "covers" -> covers, "reading" -> reading.render,
        "minutes" -> reading.minutes, "problems" -> Json.strings(found),
        "pending" -> "figuras/*.png: `just video-figures` on the owner's computer (this box has no browser)",
      )

/** What `pirsig_video_fetch` answers. */
final case class Fetched(name: String, path: os.Path, video: VideoRecord, duration: String, transcript: os.Path,
    words: Int, policy: os.Path):
  def json: ujson.Obj =
    ujson.Obj(
      "name" -> name, "path" -> path.toString, "title" -> video.title,
      "channel" -> video.channel.fold(ujson.Null)(ujson.Str(_)), "duration" -> duration,
      "captions" -> video.track.name, "captions_kind" -> video.track.kind.label,
      "transcript" -> transcript.toString, "transcript_words" -> words, "policy" -> policy.toString,
      "next" -> ("Read the whole transcript, then write leitura.markdown, figuras.json and " +
        s"figuras/<id>.json in this folder, and run ${ToolName.VideoCheck.mcp}."),
    )

final case class FetchInput(url: String)
final case class CheckInput(name: String)
final case class VideoSubmitInput(name: String, request: String)

object FetchInput:
  val Hosts = Set("youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be", "music.youtube.com")

  def parse(args: ujson.Obj): Either[String, FetchInput] =
    val url = Py.strip(Json.text(args, "url"))
    if isYoutubeUrl(url) then Right(FetchInput(url)) else Left("give an https YouTube URL")

  /** urlparse: the scheme is https and the host is YouTube's. */
  def isYoutubeUrl(url: String): Boolean =
    val Url = "(?s)([A-Za-z][A-Za-z0-9+.-]*):(.*)".r
    url match
      case Url(scheme, rest) if scheme.toLowerCase == "https" && rest.startsWith("//") =>
        val netloc = rest.drop(2).takeWhile(c => !"/?#".contains(c))
        val host = netloc.split("@", -1).last
        val hostname = if host.startsWith("[") then host.takeWhile(_ != ']').drop(1) else host.takeWhile(_ != ':')
        Hosts.contains(hostname.toLowerCase)
      case _ => false

object CheckInput:
  def parse(args: ujson.Obj): CheckInput = CheckInput(Json.text(args, "name"))

object VideoSubmitInput:
  def parse(args: ujson.Obj): Either[String, VideoSubmitInput] =
    val request = Py.strip(Json.text(args, "request"))
    if request.isEmpty then Left(Messages.NoRequest)
    else Right(VideoSubmitInput(Json.text(args, "name"), request))
