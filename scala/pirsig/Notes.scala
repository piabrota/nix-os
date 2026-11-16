package piabrota.pirsig

import java.time.{ZoneOffset, ZonedDateTime}
import java.time.format.DateTimeFormatter

import FrontMatter.yamlStr
import NoteDraft.{MaxNotes, MaxWords}

/** Smart notes into the pirsig brain, as a pull request: the tools `pirsig_note_search` and
  * `pirsig_notes_submit`.
  *
  * The rules are gramatico's smart-note level (piabrota/gramatico, SKILL.md, "Smart note"), in
  * pirsig's fields: a note is a file of brain/Inbox/ with no `pirsig:` key and no zid, so
  * `psg fork import brain` gives it a zid and files it, and `psg fork export` never rewrites it.
  */
object Notes:
  private val TagPattern = "[a-z0-9][a-z0-9-]*(?:/[a-z0-9][a-z0-9-]*)*".r
  private val W = "\\p{L}\\p{N}_" // Python's \w, in a character class
  private val Email = s"[$W.+-]+@[$W-]+\\.[$W.-]+".r.unanchored
  val InboxDir = s"${BrainTree.Root}/${Folder.Inbox.dir}"
  val RulesBroken = "the notes break the smart-note rules; fix them and call again"

  val search = Tool(
    ToolName.NoteSearch,
    "Search the notes of the owner's pirsig brain (piabrota/pirsig, brain/Zettelkasten and " +
      s"brain/Inbox) by words of a title or body. Use it before ${ToolName.NotesSubmit.mcp}, to find " +
      "existing notes that a new note can link to. Returns each match's stem (the link " +
      "target), title, zid and kind.",
    Schema.Record(List(
      Property("query", Schema.Text(Some("Words to look for, in any order")), required = true),
      Property("limit", Schema.Integer(Some(
        s"At most this many matches (1-${SearchInput.MaxLimit}, default ${SearchInput.DefaultLimit})"))),
    )),
    searchNotes,
  )

  private val link = Schema.Record(List(
    Property("target", Schema.Text(Some("A title in this call, or an existing note's stem")), required = true),
    Property("why", Schema.Text(Some("Why the two notes belong together")), required = true),
  ))

  private val note = Schema.Record(List(
    Property("title", Schema.Text(Some("The idea as a claim, in one sentence")), required = true),
    Property("type", Schema.Text(oneOf = NoteType.values.toList.map(_.label)), required = true),
    Property("status", Schema.Text(oneOf = NoteStatus.values.toList.map(_.label)), required = true),
    Property("source", Schema.Text(Some("URL, DOI or citekey; required for literature"))),
    Property("tags", Schema.ListOf(Schema.Text())),
    Property("body", Schema.Text(Some(s"The note in the writer's own words, at most $MaxWords words")), required = true),
    Property("links", Schema.ListOf(link)),
    Property("proposed_link", Schema.Text(Some("With no known neighbour: the note that should exist, and why (marked ⚠)"))),
  ))

  val submit = Tool(
    ToolName.NotesSubmit,
    "Open one pull request to the owner's pirsig brain with smart notes, one idea per note, " +
      "following gramatico's smart-note rules. Use only when the owner asks to save, index or " +
      "send notes to pirsig. Load the skill pirsig-smart-notes first. Every note needs " +
      "at least one link with a reason: to another note in the same call (by its title) or " +
      s"to an existing note (a stem from ${ToolName.NoteSearch.mcp}); with no known neighbour, give " +
      "proposed_link instead. Returns the pull request URL.",
    Schema.Record(List(
      Property("request", Schema.Text(Some("One English sentence: what the owner asked for. It opens the PR body.")),
        required = true),
      Property("notes", Schema.ListOf(note, Some(s"1 to $MaxNotes notes")), required = true),
    )),
    submitNotes,
  )

  /** `slugify` of brain.py: lower case, marks dropped, runs of [^a-z0-9] as one `-`. */
  def slugify(text: String, words: Int = 6): String =
    val plain = Py.nfd(text.toLowerCase).filterNot(Py.isMark)
    val parts = plain.replaceAll("[^a-z0-9]+", " ").split(' ').filter(_.nonEmpty).take(words)
    if parts.isEmpty then "untitled" else parts.mkString("-")

  /** The notes with a word of `query` (lower case), best first: a hit in the title counts three
    * times a hit in the body.
    */
  def rank(notes: List[BrainNote], query: String): List[BrainNote] =
    val words = Py.split(query)
    def score(n: BrainNote) =
      val (title, body) = (n.title.toLowerCase, n.body.toLowerCase)
      words.map(w => (if title.contains(w) then 3 else 0) + (if body.contains(w) then 1 else 0)).sum
    notes.map(n => score(n) -> n).filter(_._1 > 0).sortBy(-_._1).map(_._2)

  private def searchNotes(config: Config, args: ujson.Obj): Answer =
    SearchInput.parse(args) match
      case Left(message) => Answer.Failed(message)
      case Right(input) =>
        try
          val b = Brain.open(config, ToolFamily.Notes)
          b.sync(maxAge = Brain.RefreshSeconds)
          val found = rank(b.notes(), input.query)
          Answer.Done(SearchResult(b.repo, found.take(input.limit), found.size).json)
        catch case BrainError(message) => Answer.Failed(message)

  def words(text: String): Int = Py.split(text).count(_.exists(Py.isWord))

  // The rules below each take one note, the titles of the whole call and the stems of the brain,
  // and return the problems of that rule, without the "note N:" prefix that `accept` adds.
  private type Rule = (NoteDraft, Seq[String], Set[String]) => Seq[String]

  private val ruleTitle: Rule = (n, _, _) =>
    val title = n.title
    if title.isEmpty || title.contains('\n') || title.codePointCount(0, title.length) > 160 then
      Seq("the title is one line of at most 160 characters")
    else Nil

  private val ruleType: Rule = (n, _, _) =>
    if n.kind.isDefined then Nil else Seq(s"type is one of ${NoteType.values.map(_.label).mkString(", ")}")

  private val ruleStatus: Rule = (n, _, _) =>
    if n.status.isDefined then Nil
    else Seq(s"status is one of ${NoteStatus.values.map(_.label).mkString(", ")} (approved is the owner's word)")

  private val ruleSource: Rule = (n, _, _) =>
    if n.kind.contains(NoteType.Literature) && n.source.isEmpty then Seq("a literature note needs its source")
    else Nil

  private val ruleBody: Rule = (n, _, _) =>
    val count = words(n.body)
    if n.body.isEmpty then Seq("no body")
    else if count > MaxWords then Seq(s"$count words; more than $MaxWords is more than one idea")
    else Nil

  private val ruleEmail: Rule = (n, _, _) =>
    Seq(n.title, n.body, n.source).collect:
      case t if Email.findFirstIn(t).isDefined => "an email address; people appear by nickname only"

  private val ruleTags: Rule = (n, _, _) =>
    n.tags.collect:
      case tag if !TagPattern.matches(tag.text) => s"tag ${tag.repr} is not lowercase-with-hyphens"

  private def linkProblems(link: Link, title: String, titles: Seq[String], existing: Set[String]): Seq[String] =
    val reason = if link.why.isEmpty then Seq(s"the link to ${Py.repr(link.target)} has no reason") else Nil
    val known =
      if link.target.toLowerCase == title.toLowerCase then Seq("links to itself")
      else if !titles.exists(_.toLowerCase == link.target.toLowerCase) && !existing.contains(link.target) then
        Seq(s"${Py.repr(link.target)} is no title in this call and no note in the brain")
      else Nil
    reason ++ known

  private val ruleLinks: Rule = (n, titles, existing) =>
    val problems = n.links.flatMap(linkProblems(_, n.title, titles, existing))
    // A note with no neighbour is allowed only if it says so in `proposed_link`.
    if n.links.isEmpty && n.proposedLink.isEmpty then
      problems :+ "no link; link a neighbour or give proposed_link"
    else problems

  // The order is the order of the messages in the tool's answer.
  private val NoteRules = Seq(ruleTitle, ruleType, ruleStatus, ruleSource, ruleBody, ruleEmail, ruleTags, ruleLinks)

  /** The notes of a call if they keep every rule, or the problems. */
  def accept(batch: Either[String, Seq[NoteDraft]], existing: Set[String]): Either[Seq[String], Seq[NoteDraft]] =
    batch.left.map(Seq(_)).flatMap: notes =>
      val titles = notes.map(_.title)
      val same =
        if titles.map(_.toLowerCase).distinct.size != titles.size then
          Seq("two notes have the same title: one idea, one note")
        else Nil
      val problems = same ++ notes.zipWithIndex.flatMap: (n, i) =>
        NoteRules.flatMap(rule => rule(n, titles, existing).map(p => s"note ${i + 1}: $p"))
      if problems.isEmpty then Right(notes) else Left(problems)

  def validate(notes: ujson.Value, existing: Set[String]): Seq[String] =
    accept(NoteDraft.batch(notes), existing).fold(identity, _ => Nil)

  private val Minute = DateTimeFormatter.ofPattern("yyyyMMddHHmm")
  private val Created = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm':00+00:00'")

  private def render(n: NoteDraft, stemOf: Map[String, String], titles: Map[String, String],
      created: ZonedDateTime): String =
    val tags = (n.tags ++ Tag.of(n.statusLabel)).distinct
    val frontMatter = Seq(
      "---",
      s"${Key.Id}: \"${created.format(Minute)}\"",
      s"${Key.Title}: ${yamlStr(n.title)}",
      s"${Key.Kind}: ${n.kindLabel}",
    ) ++ Option.when(n.source.nonEmpty)(s"${Key.Source}: ${yamlStr(n.source)}") ++ Seq(
      s"${Key.Tags}: [${tags.map(_.yaml).mkString(", ")}]",
      s"${Key.Created}: ${created.format(Created)}",
      "---",
      "",
    )
    val text = frontMatter.mkString("\n") + s"\n# ${n.title}\n\n${n.body}\n"
    // Tells the reader of the file that no neighbour is known, so a person links it by hand.
    val flagged = if n.proposedLink.nonEmpty then s"\n⚠ ${n.proposedLink}\n" else ""
    val lines = n.links.map: link =>
      val stem = stemOf.getOrElse(link.target.toLowerCase, link.target)
      s"- [[$stem]] ${titles.getOrElse(stem, link.target)}: ${link.why}"
    text + flagged + (if lines.nonEmpty then "\n## Links\n\n" + lines.mkString("\n") + "\n" else "")

  /** The files of a submission: brain/Inbox/<id>-<slug>.md, one minute apart so each id is unique
    * (gramatico's id is the UTC minute of creation).
    */
  def build(notes: Seq[NoteDraft], existing: Map[String, String], now: ZonedDateTime): Seq[NewFile] =
    val created = notes.indices.map(i => now.plusMinutes(i.toLong))
    val stems = notes.zip(created).map((n, at) => s"${at.format(Minute)}-${slugify(n.title)}")
    val stemOf = notes.map(_.title.toLowerCase).zip(stems).toMap
    val titles = existing ++ stems.zip(notes.map(_.title))
    notes.zip(created).zip(stems).map:
      case ((n, at), stem) => NewFile(s"$InboxDir/$stem${BrainNote.Extension}", render(n, stemOf, titles, at))

  private def prBody(request: String, notes: Seq[NoteDraft], files: Seq[String]): String =
    val rows = files.zip(notes).map((path, n) => s"- `$path`: ${n.kindLabel}, ${n.statusLabel}. ${n.title}")
    val flagged = notes.filter(_.proposedLink.nonEmpty).map(n => s"- ⚠ No known neighbour: ${n.title}")
    (Seq(
      s"**Summary**: $request This PR adds ${notes.size} smart notes to $InboxDir/.",
      "",
      s"**Tested**: The ${ToolFamily.Notes.dataDir} plugin checked the mechanical smart-note rules. " +
        "A person must read each note against its source.",
      "",
      "**What changed**",
      rows.mkString("\n"),
      "",
      "**After the merge**",
      "1. Run `psg fork import brain`. Pirsig gives each note a zid and imports its links.",
      "2. Read each note. Change `status` only when you checked the source.",
      "",
      "**Not checked**",
      "- Own words, one idea per note, and names of people: these need a reader.",
    ) ++ flagged :+ "").mkString("\n")

  private def submitNotes(config: Config, args: ujson.Obj): Answer =
    NotesSubmitInput.parse(args) match
      case Left(message) => Answer.Failed(message)
      case Right(input) =>
        try
          val b = Brain.open(config, ToolFamily.Notes)
          // `sync()` with no age always fetches: the rules must see the notes of the brain now.
          b.sync()
          val existing = b.notes().map(n => n.stem -> n.title).toMap
          accept(input.notes, existing.keySet) match
            case Left(problems) => Answer.Failed(RulesBroken, Some(problems))
            case Right(batch) =>
              // The id is the UTC minute; `build` adds one minute for each next note.
              val now = ZonedDateTime.now(ZoneOffset.UTC).withSecond(0).withNano(0)
              val files = build(batch, existing, now)
              val count = batch.size
              val title = s"notes: add $count smart note${if count > 1 then "s" else ""} to the inbox"
              val pr = b.openPr(files, s"notes-${slugify(batch.head.title, 5)}", title,
                prBody(input.request, batch, files.map(_.path)))
              Answer.Done(Submitted(files.map(_.path), pr).json)
        catch case BrainError(message) => Answer.Failed(message)
