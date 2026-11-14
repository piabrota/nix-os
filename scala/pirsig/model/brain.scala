package piabrota.pirsig

/** A failure to report to the model as the tool's `error`. */
final case class BrainError(message: String) extends Exception(message, null, false, false)

/** A file or an answer of yt-dlp without what the tool needs: Python's KeyError and ValueError.
  * Each tool says where it came from ("cannot read the folder: ...").
  */
final case class BadData(message: String) extends Exception(message, null, false, false)

/** A tool family, and the data directory its Python plugin kept, so its checkout and work folders
  * stay in use.
  */
enum ToolFamily(val dataDir: String):
  case Notes extends ToolFamily("pirsig-notes")
  case Videos extends ToolFamily("pirsig-videos")

/** The paths of the pirsig brain's tree that the tools read and write. */
object BrainTree:
  val Root = "brain"
  val Videos = "Videos"
  /** The video policy of pirsig, which the model reads before it writes a reading. */
  val VideoPolicy: os.RelPath = os.rel / ".claude" / "agents" / "video-indexer.md"
  /** What the checkout holds: the brain and the video policy. The rest (Rust, the apps) stays out. */
  val Sparse = Seq(Root, ".claude/agents")

/** The folders of the brain with notes. */
enum Folder:
  case Zettelkasten, Inbox

  def dir: String = toString

/** The front matter keys the tools read and write. */
object Key:
  val Id = "id"
  val Title = "title"
  val Zid = "zid"
  val Kind = "kind"
  val Type = "type"
  val Source = "source"
  val Tags = "tags"
  val Created = "created"

/** The flat `key: value` lines of `---` front matter, as strings (no YAML library here), and the
  * text after it.
  */
final case class FrontMatter(fields: Map[String, String], body: String)

object FrontMatter:
  def parse(text: String): FrontMatter =
    val end = text.indexOf("\n---", 4)
    if !text.startsWith("---\n") || end < 0 then FrontMatter(Map.empty, text)
    else
      val fields = Py.splitlines(text.substring(4, end)).flatMap: line =>
        line.indexOf(':') match
          case i if i > 0 && !line.startsWith(" ") && !line.startsWith("-") =>
            Some(Py.strip(line.take(i)) -> unquote(Py.strip(line.drop(i + 1))))
          case _ => None
      FrontMatter(fields.toMap, text.drop(end + 4).dropWhile(_ == '\n'))

  private def unquote(value: String): String =
    if value.length >= 2 && value.head == '"' && value.last == '"' then
      Json.read(value).toOption.flatMap(_.strOpt).getOrElse(value.substring(1, value.length - 1))
    else value

  /** A YAML scalar that is also JSON: safe for any title. */
  def yamlStr(value: String): String = Py.dumps(ujson.Str(value))

/** A Markdown note of the brain's slip-box or inbox. */
final case class BrainNote(stem: String, title: String, zid: String, kind: String, folder: Folder, body: String):
  def json: ujson.Obj =
    ujson.Obj("stem" -> stem, "title" -> title, "zid" -> zid, "kind" -> kind, "folder" -> folder.dir)

object BrainNote:
  val Extension = ".md"

  def parse(folder: Folder, fileName: String, text: String): BrainNote =
    val fm = FrontMatter.parse(text)
    val stem = fileName.stripSuffix(Extension)
    BrainNote(
      stem = stem,
      title = fm.fields.get(Key.Title).filter(_.nonEmpty).getOrElse(stem),
      zid = fm.fields.getOrElse(Key.Zid, ""),
      kind = fm.fields.get(Key.Kind).filter(_.nonEmpty).orElse(fm.fields.get(Key.Type)).getOrElse(""),
      folder = folder,
      body = fm.body,
    )

/** A file a pull request adds: its path relative to the repository, and its text. */
final case class NewFile(path: String, content: String)

final case class PullRequest(branch: String, url: String)

/** The answer of a tool that opened a pull request. */
final case class Submitted(files: Seq[String], pr: PullRequest):
  def json: ujson.Obj = ujson.Obj("files" -> Json.strings(files), "branch" -> pr.branch, "pr" -> pr.url)
