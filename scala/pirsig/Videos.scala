package piabrota.pirsig

import java.nio.charset.StandardCharsets.UTF_8

import scala.collection.immutable.VectorMap
import scala.util.matching.Regex

import VideoFiles.*

/** Videos into the pirsig brain, as a pull request: the tools `pirsig_video_fetch`,
  * `pirsig_video_check` and `pirsig_video_submit`.
  *
  * The method is pirsig's own: `.claude/agents/video-indexer.md` and `scripts/videos.mjs` in
  * piabrota/pirsig. `fetch` and `check` are ports of that script's two commands, so a folder made
  * here passes `just video-check` there. Two steps stay on the owner's computer, because this box
  * has no browser and no `psg`: `just video-figures` (Archify draws the PNGs in Chrome) and
  * `just video-notes` (psg files the notes). The pull request says so.
  */
object Videos:
  private val Name = "\\d{4}-\\d\\d-\\d\\d-[a-z0-9-]+".r
  private val NoteLine = "(?s)### \\[k=([a-z0-9-]+) t=([\\d:]+)-([\\d:]+)\\] (.+)".r
  private val FigureLine = "(?s)!\\[fig\\]\\((.*)\\)".r
  val YtdlpTimeout = 300
  /** The length of `<yyyy-mm-dd>-` at the start of a folder's name. */
  private val DatePrefix = 11

  /** gramatico, the mechanical part (PTW-1, PTW-4, CIE-11), as in videos.mjs. Python's `\b` knows
    * Unicode letters and RE2's does not, so with `wordBefore` (and `wordAfter`) a hit counts only
    * where the character before (after) it is no word character. `hit` is the group the problem quotes; the
    * rest of the match is what Python's look-ahead checked.
    */
  private final case class Banned(pattern: Regex, why: String, wordBefore: Boolean = true,
      wordAfter: Boolean = false, hit: Int = 0)
  private val W = "[\\p{L}\\p{N}_]"
  private val BannedRules = List(
    Banned(" — ".r, "travessão em prosa", wordBefore = false),
    Banned("(?i)vale ressaltar|cabe destacar|no âmbito de".r, "enchimento", wordAfter = true),
    Banned(s"(?i)utiliz$W+".r, "`usar`, não `utilizar`"),
    Banned(s"(?i)(realizar|efetuar) (a|o) $W+".r, "verbo pleno (PTW-4)"),
    Banned("(?i)(o mesmo) [a-z]+ (é|foi|está)".r, "`o mesmo` como pronome (PTW-1)", hit = 1),
  )

  private val FolderName = "The folder's name, <date>-<slug>"

  val fetch = Tool(
    ToolName.VideoFetch,
    "Fetch a YouTube video's metadata and captions (no video, no audio) into a work folder, " +
      "as the first step of indexing it into the owner's pirsig brain. Use only when the owner " +
      "asks to index, save or study a video in pirsig. Load the skill " +
      "pirsig-video-indexer first. Returns the folder's name and path, the transcript's " +
      "path and the path of pirsig's video-indexer policy.",
    Schema.Record(List(Property("url", Schema.Text(Some("The video's YouTube URL")), required = true))),
    fetchVideo,
  )

  val check = Tool(
    ToolName.VideoCheck,
    "Check a video's work folder as pirsig's `just video-check` does: every second covered " +
      "by a note, unique keys, links with reasons, figure entries, gramatico's mechanical " +
      "rules, and the reading time. Run it after each change to leitura.markdown.",
    Schema.Record(List(Property("name", Schema.Text(Some(FolderName)), required = true))),
    checkVideo,
  )

  val submit = Tool(
    ToolName.VideoSubmit,
    "Open a pull request to the owner's pirsig brain with a video's reading: video.json, " +
      "leitura.markdown, figuras.json and figuras/*.json (never the transcript). Use only " +
      s"when ${ToolName.VideoCheck.mcp} passes and the owner asked to send it. Returns the URL.",
    Schema.Record(List(
      Property("name", Schema.Text(Some(FolderName)), required = true),
      Property("request", Schema.Text(Some("One English sentence: what the owner asked for")), required = true),
    )),
    submitVideo,
  )

  /** `h:mm:ss`, `m:ss` or `s`: the form of the `t=` ranges in the reading. */
  def seconds(s: String): Int =
    s.split(":", -1).foldLeft(0): (total, part) =>
      part.toIntOption.map(total * 60 + _)
        .getOrElse(throw BadData(s"invalid literal for int() with base 10: ${Py.repr(part)}"))

  def clock(t: Double): String =
    val s = t.toLong
    f"${s / 3600}%02d:${s / 60 % 60}%02d:${s % 60}%02d"

  /** `name` comes from the model: the pattern keeps it from leaving `videos/` (no `..`, no `/`). */
  def workDir(home: os.Path, name: String): os.Path =
    if !Name.matches(name) then throw BrainError(s"not a video folder name: ${Py.repr(name)}")
    Brain.dataDir(home, ToolFamily.Videos) / WorkDir / name

  /** videos.mjs: lower case, NFD, runs of [^a-z0-9] to one space, the first five words. A letter
    * with a mark splits the word, as there.
    */
  def videoSlug(title: String): String =
    val parts = Py.nfd(title.toLowerCase).replaceAll("[^a-z0-9]+", " ").split(' ').filter(_.nonEmpty).take(5)
    if parts.isEmpty then "video" else parts.mkString("-")

  /** `pt-BR` and `pt-orig` are both the spoken `pt`; with no known language nothing is. */
  private def inLanguage(lang: String, spoken: String): Boolean =
    spoken.nonEmpty && lang.split("-", -1).head == spoken

  /** A person's captions in the spoken language, then any person's, then the automatic `-orig`
    * track of the spoken language (videos.mjs, fetchVideo).
    */
  def pickCaptions(tracks: CaptionTracks): Option[Track] =
    val spoken = tracks.language.split("-", -1).head
    val manual = tracks.subtitles.filter(_ != "live_chat")
    // Only the `-orig` track is what the speaker said; the others are machine translations.
    val original = tracks.automatic.filter(_.endsWith("-orig"))
    manual.find(inLanguage(_, spoken)).orElse(manual.headOption).map(Track(_, CaptionsKind.Manual))
      .orElse(original.find(inLanguage(_, spoken)).map(Track(_, CaptionsKind.Automatic)))

  /** The captions in blocks of 30 s: `[00:01:30] text...`. */
  def transcript(captions: Seq[Caption]): String =
    val blocks = captions.filter(_.text.nonEmpty).foldLeft(VectorMap.empty[Long, Vector[String]]): (blocks, c) =>
      val block = math.floor(c.startMs / 30000).toLong * 30
      blocks.updated(block, blocks.getOrElse(block, Vector.empty) :+ c.text)
    blocks.map((t, lines) => s"[${clock(t.toDouble)}] ${lines.mkString(" ")}\n").mkString



  // `--skip-download`: only the info and the captions, never the video file.
  private def ytdlp(out: os.Path, url: String, extra: String*): Unit =
    Brain.run(Seq("yt-dlp", "--skip-download", "--no-playlist", "--quiet", "-o", out.toString) ++ extra :+ url,
      timeout = YtdlpTimeout)

  private def readJson(file: os.Path): ujson.Value = Json.read(os.read(file)).fold(m => throw BadData(m), identity)

  /** Runs yt-dlp twice: first for the info, which decides the captions, then for the captions.
    * Returns the info and the track.
    */
  private def downloadCaptions(tmp: os.Path, url: String): (ujson.Obj, Track) =
    val out = tmp / YtdlpFiles.Template
    ytdlp(out, url, "--write-info-json")
    val info = readJson(tmp / YtdlpFiles.Info).objOpt.map(ujson.Obj(_)).getOrElse(throw BadData("not an object"))
    pickCaptions(CaptionTracks.parse(info)) match
      case None =>
        throw BrainError(s"no captions in the spoken language (${Py.str(Json.get(info, "language"))}): " +
          "stop and tell the owner; never transcribe from memory")
      case Some(track) =>
        ytdlp(out, url, track.kind.ytdlpFlag, "--sub-langs", track.name, "--sub-format", "json3")
        info -> track

  /** Writes video.json and the transcript into the work folder. */
  private def writeFolder(home: os.Path, b: Brain, tmp: os.Path, info: ujson.Obj, track: Track): Fetched =
    val date = VideoRecord.date(info)
    val name = s"$date-${videoSlug(VideoRecord.title(info))}"
    // From the merge on the notes belong to the owner; a second fetch must not overwrite them.
    if os.exists(b.path / BrainTree.Root / BrainTree.Videos / name) then
      throw BrainError(s"$name is already in the brain: from then on its notes are the owner's")
    val target = workDir(home, name)
    os.makeDir.all(target / FiguresDir)
    val video = VideoRecord.from(info, date, track)
    os.write.over(target / VideoJson, Py.dumpsIndented(video.json) + "\n")
    val raw = tmp / YtdlpFiles.captions(track.name)
    val text = transcript(Caption.parseAll(Json.list(readJson(raw), "events")))
    os.write.over(target / Transcript, text)
    os.copy.over(raw, target / TranscriptJson)
    Fetched(name, target, video, clock(video.duration), target / Transcript, Py.split(text).size,
      b.path / BrainTree.VideoPolicy)

  private def fetchVideo(config: Config, args: ujson.Obj): Answer =
    FetchInput.parse(args) match
      case Left(message) => Answer.Failed(message)
      case Right(input) =>
        try
          val b = Brain.open(config, ToolFamily.Videos)
          b.sync(maxAge = Brain.RefreshSeconds)
          val tmp = os.temp.dir(Brain.dataDir(config.home, ToolFamily.Videos), deleteOnExit = false)
          val fetched =
            try
              val (info, track) = downloadCaptions(tmp, input.url)
              writeFolder(config.home, b, tmp, info, track)
            finally os.remove.all(tmp)
          Answer.Done(fetched.json)
        catch
          case BrainError(message) => Answer.Failed(message)
          case BadData(message)    => Answer.Failed(s"yt-dlp gave an unexpected answer: $message")

  /** A part or a note while `parse` reads it. */
  private final case class OpenNote(title: String, key: String, from: Int, to: Int,
      lines: Vector[String] = Vector.empty, links: Vector[Link] = Vector.empty):
    def note: VideoNote = VideoNote(title, key, from, to, Py.strip(lines.mkString("\n")), links.toList)

  private final case class OpenPart(title: String, lines: Vector[String] = Vector.empty,
      notes: Vector[OpenNote] = Vector.empty):
    def part: Part = Part(title, Py.strip(lines.mkString("\n")), notes.map(_.note).toList)

  /** Where the next line of text goes: always the last part, or the last note of the last part. */
  private enum At:
    case Nowhere, LastPart, LastNote

  private final case class Reader(title: String = "", parts: Vector[OpenPart] = Vector.empty, at: At = At.Nowhere,
      problems: Vector[String] = Vector.empty):
    def problem(p: String): Reader = copy(problems = problems :+ p)
    def part(f: OpenPart => OpenPart): Reader = copy(parts = parts.updated(parts.size - 1, f(parts.last)))
    def note(f: OpenNote => OpenNote): Reader = part(p => p.copy(notes = p.notes.updated(p.notes.size - 1, f(p.notes.last))))

    // The first matching case wins: `### [k= t=]` is tested before the plain `### ` error, and both
    // before body text.
    def read(line: String): Reader = line match
      case l if l.startsWith("# ")  => copy(title = l.drop(2))
      case l if l.startsWith("## ") => copy(parts = parts :+ OpenPart(l.drop(3)), at = At.LastPart)
      case l @ NoteLine(key, from, to, noteTitle) =>
        val placed = if parts.isEmpty then problem(s"note before the first part: $l").copy(parts = Vector(OpenPart(""))) else this
        val note = OpenNote(noteTitle, key, seconds(from), seconds(to))
        placed.part(p => p.copy(notes = p.notes :+ note)).copy(at = At.LastNote)
      case l if l.startsWith("-> ") =>
        val rest = l.drop(3)
        val link = rest.indexOf(": ") match
          case -1 => Link(rest, "")
          case i  => Link(rest.take(i), rest.drop(i + 2))
        if at == At.LastNote then note(n => n.copy(links = n.links :+ link)) else problem(s"link outside a note: $l")
      case l if l.startsWith("### ") => problem(s"note without [k= t=]: $l")
      case l => at match
        case At.Nowhere  => this
        case At.LastPart => part(p => p.copy(lines = p.lines :+ l))
        case At.LastNote => note(n => n.copy(lines = n.lines :+ l))

  /** Parts (`## `) hold notes (`### [k=key t=a-b] Title`); `-> key: why` is a link. Returns the
    * reading and the lines out of place.
    */
  def parse(text: String): (Doc, List[String]) =
    val r = text.split("\n", -1).foldLeft(Reader())(_.read(_))
    (Doc(r.title, r.parts.map(_.part).toList), r.problems.toList)

  /** 238 words a minute, rounded up; long sentences and many long words each add 15 %. */
  def readingMinutes(count: Int, mean: Double, share: Double): Int =
    val minutes = count / 238.0 * (if mean > 20 then 1.15 else 1) * (if share > 0.25 then 1.15 else 1)
    math.ceil(minutes).toInt

  /** What a reader reads: titles and bodies, without figures and Markdown marks. */
  private def readingText(doc: Doc): String =
    val chunks = doc.parts.flatMap(p => p.title :: p.body :: p.notes.flatMap(n => List(n.title, n.body)))
    withoutFigures(chunks.mkString("\n")).replaceAll("[*`#]", " ")

  private def withoutFigures(text: String): String =
    text.split("\n", -1).map(line => if FigureLine.matches(line) then "" else line).mkString("\n")

  /** Words and the reading time, by the formula in gramatico's SKILL.md (videos.mjs). */
  def reading(doc: Doc): Reading =
    val text = readingText(doc)
    val words = Py.split(text).filter(_.exists(c => Py.isWord(c) && c != '_'))
    val sentences = text.split(s"[.!?:]${Py.spaceClass}|\n+").count(s => Py.strip(s).nonEmpty)
    val long = words.count(_.count(Py.isLetterLike) >= 10)
    val count = words.size.max(1)
    val mean = count.toDouble / sentences.max(1)
    val share = long.toDouble / count
    Reading(words.size, round(mean, 1), round(share, 2), readingMinutes(count, mean, share))

  /** Python's `round(x, n)`: half to even, on the exact value of the double. */
  private def round(x: Double, n: Int): Double =
    java.math.BigDecimal(x).setScale(n, java.math.RoundingMode.HALF_EVEN).doubleValue

  private def missingFiles(path: os.Path): List[String] =
    List(VideoJson, ReadingMd, FiguresJson).filterNot(f => os.isFile(path / f)).map(f => s"no $f")

  /** The notes must cover the video from 0 to its end with no gap. Returns the problems and the
    * second where the coverage stops.
    */
  def coverage(notes: List[VideoNote], duration: Double): (List[String], Int) =
    val (problems, covered) = notes.sortBy(n => (n.from, n.to, n.key)).foldLeft((List.empty[String], 0)):
      case ((problems, covered), n) =>
        val gap = Option.when(n.from > covered)(s"gap ${clock(covered.toDouble)}-${clock(n.from.toDouble)} before ${n.key}")
        val backwards = Option.when(n.to <= n.from)(s"${n.key}: ends before it starts")
        (problems ++ gap ++ backwards, covered.max(n.to))
    val short = Option.when(covered < duration - 1)(s"stops at ${clock(covered.toDouble)} of ${clock(duration)}")
    (problems ++ short, covered)

  private def keyAndLinkProblems(notes: List[VideoNote]): List[String] =
    val keys = notes.map(_.key).toSet
    val repeated = if keys.size != notes.size then List("repeated note keys") else Nil
    repeated ++ notes.flatMap: n =>
      n.links.flatMap: link =>
        // `#10` points at a note of the brain by its zid, outside this reading.
        val unknown = Option.when(!keys.contains(link.target) && !link.target.matches("(?s)#\\d.*"))(
          s"${n.key}: unknown link ${link.target}")
        val reason = Option.when(link.why.isEmpty)(s"${n.key}: link to ${link.target} has no reason")
        unknown ++ reason

  private def loadFigures(path: os.Path): (Figures, List[String]) =
    Json.read(os.read(path / FiguresJson)) match
      case Right(o: ujson.Obj) => (Figures.parse(o), Nil)
      case Right(_)            => (Figures.Empty, List(s"$FiguresJson is not JSON: not an object"))
      case Left(message)       => (Figures.Empty, List(s"$FiguresJson is not JSON: $message"))

  private def oneFigureProblems(path: os.Path, fid: String, entry: FigureEntry): List[String] =
    if !entry.present then List(s"figure $fid has no entry in $FiguresJson")
    else
      val fields = entry.missing.map(f => s"figure $fid: no ${f.key}")
      // The id is a file name: only these characters keep it inside figuras/.
      val source = Option.when(!fid.matches("[a-z0-9-]+") || !os.isFile(path / FiguresDir / s"$fid.json"))(
        s"figure $fid: no $FiguresDir/$fid.json (Archify's source)")
      fields ++ source

  /** Every figure of the text has an entry and a source; every entry is used. */
  private def figureProblems(path: os.Path, body: String, figures: Figures): List[String] =
    val used = body.split("\n", -1).toList.collect { case FigureLine(fid) => fid }.distinct
    used.flatMap(fid => oneFigureProblems(path, fid, figures.entries.getOrElse(fid, FigureEntry.Absent))) ++
      figures.entries.keys.filterNot(used.contains).map(fid => s"figure $fid is not in the text")

  def bannedProblems(body: String): List[String] =
    def wordAt(i: Int) = i >= 0 && i < body.length && Py.isWord(body(i))
    BannedRules.flatMap: rule =>
      val m = rule.pattern.pattern.matcher(body)
      val hits = List.newBuilder[String]
      var from = 0
      while from <= body.length && m.find(from) do
        val (start, end) = (m.start(rule.hit), m.end(rule.hit))
        val bounded = !(rule.wordBefore && wordAt(start - 1)) && !(rule.wordAfter && wordAt(end))
        if bounded then hits += s"${rule.why}: ${body.substring(start, end)}"
        from = if bounded && end > start then end else m.start() + 1
      hits.result()

  /** The checks of a work folder, as the tool answers them. */
  def checkDir(path: os.Path): CheckResult =
    val missing = missingFiles(path)
    if missing.nonEmpty then CheckResult.Incomplete(missing)
    else
      val video = readJson(path / VideoJson)
      val (doc, parseProblems) = parse(os.read(path / ReadingMd))
      val duration = VideoSummary.duration(video)
      val (gaps, covered) = coverage(doc.notes, duration)
      val (figures, figuresFile) = loadFigures(path)
      val body = doc.body
      val problems = parseProblems ++ gaps ++ keyAndLinkProblems(doc.notes) ++ figuresFile ++
        figureProblems(path, body, figures) ++ bannedProblems(body)
      CheckResult.Checked(doc.notes.size, figures.entries.size, s"${clock(covered.toDouble)} of ${clock(duration)}",
        reading(doc), problems)

  private def checkVideo(config: Config, args: ujson.Obj): Answer =
    try
      val result = checkDir(workDir(config.home, CheckInput.parse(args).name))
      Answer.Done(ujson.Obj.from(("passed" -> ujson.Bool(result.problems.isEmpty)) +: result.json.value.toSeq))
    catch
      case BrainError(message) => Answer.Failed(message)
      case BadData(message)    => Answer.Failed(s"cannot read the folder: $message")

  private def prBody(request: String, name: String, video: VideoSummary, result: CheckResult.Checked,
      files: Seq[String]): String =
    val folder = s"${BrainTree.Root}/${BrainTree.Videos}/$name"
    (Seq(
      s"**Summary**: $request This PR adds the reading of one video to `$folder`: " +
        s"${result.notes} literature notes and ${result.figures} figure sources.",
      "",
      s"**Tested**: The ${ToolFamily.Videos.dataDir} plugin ran the checks of `just video-check`, except the PNG " +
        s"check. Coverage: ${result.covers}. Reading time: about ${result.reading.minutes} min.",
      "",
      "**What changed**",
    ) ++ files.map(f => s"- `$f`") ++ Seq(
      "",
      "**Video**",
      s"- ${video.url}, ${clock(video.duration)}, ${video.captionsKind} captions (`${video.captions}`).",
      "",
      "**To finish this PR on your computer** (the VPS has no browser and no `psg`)",
      s"1. Check out this branch. Run `just video-fetch ${video.url}` to get the transcript again. " +
        "The transcript is not in git.",
      s"2. Run `just video-figures $folder`. Look at each PNG at 800 px wide.",
      s"3. Run `just video-check $folder`. It must pass.",
      s"4. Run `just video-notes $folder`. Psg files the notes and copies them into brain/.",
      "5. Commit the PNGs and the notes on this branch. Then merge.",
      "",
      "**Not checked**",
      "- The text against the transcript: a reader must do this once.",
      "- The figures as pictures: Archify did not draw them yet.",
      "",
    )).mkString("\n")

  /** The files of the pull request: the reading and the figure sources, never the transcript. */
  private def sources(path: os.Path): List[String] =
    val figures = if os.isDir(path / FiguresDir) then os.list(path / FiguresDir).map(_.last).filter(_.endsWith(".json")).sorted else Nil
    List(VideoJson, ReadingMd, FiguresJson) ++ figures.map(f => s"$FiguresDir/$f")

  private def submitVideo(config: Config, args: ujson.Obj): Answer =
    VideoSubmitInput.parse(args) match
      case Left(message) => Answer.Failed(message)
      case Right(input) =>
        try
          val path = workDir(config.home, input.name)
          checkDir(path) match
            case result: CheckResult.Checked if result.problems.isEmpty =>
              val video = readJson(path / VideoJson)
              // The PR body says how to fetch the transcript again.
              val files = sources(path).map: rel =>
                NewFile(s"${BrainTree.Root}/${BrainTree.Videos}/${input.name}/$rel",
                  new String(os.read.bytes(path / os.RelPath(rel)), UTF_8))
              val b = Brain.open(config, ToolFamily.Videos)
              val title = "videos: add the reading of one video"
              val slug = s"video-${input.name.drop(DatePrefix)}".take(60).reverse.dropWhile(_ == '-').reverse
              val pr = b.openPr(files, slug, title,
                prBody(input.request, input.name, VideoSummary.parse(video), result, files.map(_.path)))
              Answer.Done(Submitted(files.map(_.path), pr).json)
            case result =>
              Answer.Failed(s"${ToolName.VideoCheck.mcp} does not pass; fix the folder first", Some(result.problems))
        catch
          case BrainError(message) => Answer.Failed(message)
          case BadData(message)    => Answer.Failed(s"cannot read the folder: $message")
