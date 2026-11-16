package piabrota.pirsig

enum NoteType(val label: String):
  case Fleeting extends NoteType("fleeting")
  case Literature extends NoteType("literature")
  case Permanent extends NoteType("permanent")

object NoteType:
  def parse(label: String): Option[NoteType] = values.find(_.label == label)

// `approved` is the owner's word, never the machine's (gramatico, smart note rule 6).
enum NoteStatus(val label: String):
  case Unverified extends NoteStatus("unverified")
  case Partial extends NoteStatus("partial")
  case Verified extends NoteStatus("verified")
  case OpenQuestion extends NoteStatus("open-question")

object NoteStatus:
  def parse(label: String): Option[NoteStatus] = values.find(_.label == label)

/** A link of a note, or of a video's note, and why the two belong together. */
final case class Link(target: String, why: String)

object Link:
  /** `{"target": ..., "why": ...}` as the model sent it, both stripped. */
  def parse(v: ujson.Value): Link = Link(Py.strip(Json.text(v, "target")), Py.strip(Json.text(v, "why")))

/** A tag as the model sent it: its `str()`, and whether it was a JSON string (a number is a tag too,
  * and its YAML has no quotes).
  */
final case class Tag(text: String, quoted: Boolean):
  def repr: String = if quoted then Py.repr(text) else text
  def yaml: String = if quoted then FrontMatter.yamlStr(text) else text

object Tag:
  def parse(v: ujson.Value): Tag = v match
    case ujson.Str(s) => Tag(s, quoted = true)
    case other        => Tag(Py.str(other), quoted = false)

  /** The tags that record who wrote a note. */
  def of(status: String): Seq[Tag] = Seq(Tag(s"status/$status", quoted = true), Tag("hermes", quoted = true))

/** A note as the model sent it to `pirsig_notes_submit`. A missing field reads as Python's
  * `str(n.get(key, ""))`; a type or a status that is no known one is None.
  */
final case class NoteDraft(title: String, kind: Option[NoteType], status: Option[NoteStatus], source: String,
    tags: Seq[Tag], body: String, links: Seq[Link], proposedLink: String):
  def kindLabel: String = kind.fold("")(_.label)
  def statusLabel: String = status.fold("")(_.label)

object NoteDraft:
  val MaxNotes = 20
  val MaxWords = 500

  def parse(v: ujson.Value): NoteDraft =
    def stripped(key: String) = Py.strip(Json.text(v, key))
    NoteDraft(
      title = stripped("title"),
      kind = Json.string(v, "type").flatMap(NoteType.parse),
      status = Json.string(v, "status").flatMap(NoteStatus.parse),
      source = stripped("source"),
      tags = Json.list(v, "tags").map(Tag.parse),
      body = stripped("body"),
      links = Json.list(v, "links").map(Link.parse),
      proposedLink = stripped("proposed_link"),
    )

  /** The notes of one call, or why they are no batch. */
  def batch(v: ujson.Value): Either[String, Seq[NoteDraft]] = v match
    case ujson.Arr(xs) if xs.nonEmpty && xs.size <= MaxNotes => Right(xs.toSeq.map(parse))
    case _                                                   => Left(s"give 1 to $MaxNotes notes")

final case class SearchInput(query: String, limit: Int)

object SearchInput:
  val DefaultLimit = 10
  val MaxLimit = 20

  def parse(args: ujson.Obj): Either[String, SearchInput] =
    val query = Py.strip(Json.text(args, "query")).toLowerCase
    val limit = (args.value.get("limit") match
      case Some(ujson.Num(n)) if n != 0     => n.toInt
      case Some(ujson.Str(s)) if s.nonEmpty => Py.strip(s).toIntOption.getOrElse(DefaultLimit)
      case _                                => DefaultLimit
    ).max(1).min(MaxLimit)
    if query.isEmpty then Left("no query") else Right(SearchInput(query, limit))

final case class SearchResult(repo: String, matches: Seq[BrainNote], count: Int):
  def json: ujson.Obj =
    ujson.Obj("repo" -> repo, "matches" -> ujson.Arr.from(matches.map(_.json)), "count" -> count)

final case class NotesSubmitInput(request: String, notes: Either[String, Seq[NoteDraft]])

object NotesSubmitInput:
  def parse(args: ujson.Obj): Either[String, NotesSubmitInput] =
    val request = Py.strip(Json.text(args, "request"))
    if request.isEmpty then Left(Messages.NoRequest)
    else Right(NotesSubmitInput(request, NoteDraft.batch(args.value.getOrElse("notes", ujson.Null))))
