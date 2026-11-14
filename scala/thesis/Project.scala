package piabrota.thesis

import scala.collection.mutable.ArrayBuffer
import piabrota.lib.{Exit, Sh, warn}
import Text.{fixed, padBytes}

/** The template of a project: share/thesis/templates/<name> with its template.json. A field is
  * read as `jq -r` prints it, "null" when it is missing.
  */
final case class Template(name: String, dir: os.Path, json: ujson.Value):
  private def field(path: String): String = J.raw(J.path(json, path))
  def csl: String = field("bibliography.csl")
  def documentclassFrom: String = field("documentclass_from")
  def preamble: List[String] = field("overlay.preamble").split("\\s+").filter(_.nonEmpty).toList
  def pinnedDirs: List[String] = J.get(json, "pinned_dirs").flatMap(_.arrOpt).toList.flatten.map(J.rawValue)
  def defaultSections: ujson.Value = J.get(json, "default_sections").getOrElse(ujson.Null)

object Template:
  val NameMax = 48

  /** `need_template`: the name, or the profile's default when it is empty. */
  def load(k: Kit, name: String): Template =
    val n = if name.isEmpty then k.profile.defaultTemplate else name
    Kit.checkName("template", n, NameMax)
    val dir = k.share / "templates" / n
    if !os.isFile(dir / Names.TemplateJson) then fail(s"no template $n (looked in $dir)")
    Template(n, dir, ujson.read(os.read(dir / Names.TemplateJson)))

  def of(k: Kit, p: Project): Template = load(k, p.templateName)

/** Where a section stands; who holds its claim, and whether that claim is stale. */
final case class Status(state: SectionState, by: String = "", stale: Boolean = false)

/** The editor's and the writers' commands: new, sections, status, fetch, release, submit, and the
  * reviewer's review-report and verdict. A verdict is by hash: a section accepted and then edited
  * shows as changed.
  */
object ProjectCommands:
  import SectionState.{Accepted, Changed, Claimed, Drafted, Linted, Omit, Other, Revise, Todo}

  /** `claim_info`. */
  def claim(p: Project, id: String): Option[Claim] =
    val f = p.claimFile(id)
    if !Kit.plainFile(f) then None else Claim.parse(os.read(f))

  def isStale(k: Kit, c: Claim): Boolean = Kit.nowS() - c.epoch > k.profile.limits.claimStaleS

  /** `sec_status`. */
  def sectionStatus(k: Kit, p: Project, sec: Section): Status =
    if sec.omitted then Status(Omit)
    else
      val c = claim(p, sec.id)
      c match
        case Some(cl) if !isStale(k, cl) => Status(Claimed, cl.seat)
        case _ =>
          val st = SectionState.parse(p.stateOr(sec.id, StateKey.Status, Todo.render)) match
            case Accepted =>
              val f = p.sectionFile(sec.id)
              if Kit.plainFile(f) && Kit.sha(f) == p.stateRaw(sec.id, StateKey.AcceptedSha) then Accepted else Changed
            case Other("null") => Todo
            case other         => other
          Status(st, c.map(_.seat).getOrElse(""), c.isDefined)

  private def claimText(seat: String, id: String): String = Claim(seat, Kit.nowS()).render(id, Kit.nowIso())

  /** `try_claim`: atomic; true when the claim is the seat's now (new, resumed, or a stale one taken
    * over under the claims lock).
    */
  def tryClaim(k: Kit, p: Project, id: String, seat: String): Boolean =
    os.makeDir.all(p.dir / Names.Claims)
    val f = p.claimFile(id)
    if Kit.createNew(f, claimText(seat, id)) then true
    else claim(p, id) match
      case None                          => false
      case Some(c) if c.seat == seat     => true
      case Some(c) if !isStale(k, c)     => false
      case Some(_) =>
        k.lock(p, Names.Claims)
        val taken = claim(p, id) match
          case Some(c) if isStale(k, c) =>
            k.log(p, Some(seat), s"claim of ${c.seat} on $id is stale: taken over by $seat")
            os.remove(f)
            Kit.createNew(f, claimText(seat, id))
          case _ => false
        k.unlock(p, Names.Claims)
        taken

  /** The positional arguments and the options with a value, as the shell's while/case loops read
    * them. `flags` take no value.
    */
  private final case class Parsed(pos: List[String], opts: Map[String, String], flags: Set[String])

  private def parse(cmd: Cmd, args: List[String], withValue: Map[String, String], flags: Set[String], maxPos: Int): Parsed =
    def loop(rest: List[String], acc: Parsed): Parsed = rest match
      case Nil => acc.copy(pos = acc.pos.reverse)
      case o :: tail if withValue.contains(o) =>
        tail match
          case v :: more => loop(more, acc.copy(opts = acc.opts + (o -> v)))
          case Nil       => fail(s"${cmd.name}: $o needs ${withValue(o)}")
      case o :: tail if flags(o) => loop(tail, acc.copy(flags = acc.flags + o))
      case o :: _ if o.startsWith("-") => fail(s"${cmd.name}: unknown option $o")
      case a :: tail =>
        if acc.pos.length >= maxPos then fail(s"${cmd.name}: too many arguments")
        loop(tail, acc.copy(pos = a :: acc.pos))
    loop(args, Parsed(Nil, Map.empty, Set.empty))

  private val As = Map("--as" -> "a seat")

  // ---------------------------------------------------------------- new

  def newProject(k: Kit, args: List[String]): Int =
    val a = parse(Cmd.New, args, Map("--template" -> "a name"), Set.empty, 1)
    val slug = a.pos.headOption.getOrElse(fail("usage: thesis new <slug> [--template <name>]"))
    k.checkSlug(slug)
    val tpl = Template.load(k, a.opts.getOrElse("--template", ""))
    val dest = k.projDir(slug)
    if os.exists(dest) then fail(s"the project $slug exists ($dest)")
    val projects = k.home / Names.Projects
    scala.util.Try(os.makeDir.all(projects)).getOrElse(fail(s"cannot make $projects"))
    val tmp = Kit.tempDir(projects, s".new-$slug.").getOrElse(fail(s"cannot make a folder in $projects"))
    Names.ProjectDirs.foreach(d => os.makeDir(tmp / d))
    val Array(month, year) = Sh.out("date", "+%-m %Y").split(' '): @unchecked
    os.write(tmp / Names.ThesisJson, J.pretty(newThesis(tpl, month.toInt, year.toInt)))
    os.write(tmp / Names.Notes / Names.FactsMd, NewFiles.facts)
    os.write(tmp / Names.Notes / Names.GlossaryMd, NewFiles.glossary)
    os.write(tmp / Names.RefsBib, NewFiles.refs)
    os.write(tmp / Names.ReferencesMd, NewFiles.references)
    os.write(tmp / Names.Notes / Names.ThesisLog,
      s"${Kit.nowIso()} ${k.config.user.getOrElse("?")} new project from template ${tpl.name}\n")
    os.perms.set(tmp, "rwxr-xr-x")
    if scala.util.Try(os.move(tmp, dest)).isFailure then
      os.remove.all(tmp)
      fail("new: cannot move the project into place")
    say(s"thesis: new project $slug at $dest (template ${tpl.name})")
    say("  next: fill thesis.json (title, title_en, author, author_ref, advisor, examiners, course, month, year),")
    say("        write notes/facts.md and notes/glossary.md, set the sources of each section, then writers run:")
    say(s"        thesis fetch $slug --as <seat>")
    0

  /** The thesis.json of a new project: every front-page field still to fill. */
  def newThesis(tpl: Template, month: Int, year: Int): ujson.Value =
    import ThesisKey as K
    val toFill = ujson.Str(ThesisValue.ToFill)
    ujson.Obj(
      K.Version -> 1,
      K.Template -> tpl.name,
      K.Title -> toFill,
      K.TitleEn -> toFill,
      K.Author -> toFill,
      K.AuthorRef -> toFill,
      K.Advisor -> toFill,
      K.Examiners -> ujson.Arr(),
      K.Course -> ThesisValue.DefaultCourse,
      K.Month -> month,
      K.Year -> year,
      K.Language -> ThesisValue.Language,
      K.CitationStyle -> ThesisValue.CitationStyle,
      K.Lists -> ujson.Obj(K.Figures -> true, K.Tables -> true),
      K.Assets -> ujson.Obj(K.UfrjLogo -> ujson.Null),
      K.Sections -> tpl.defaultSections,
    )

  // ---------------------------------------------------------------- sections, status

  def sections(k: Kit, args: List[String]): Int = args match
    case Nil =>
      val dir = k.home / Names.Projects
      if !os.isDir(dir) then fail(s"no projects folder ($dir)")
      Text.sortC(os.list(dir).filter(d => os.isDir(d) && !d.last.startsWith(".")).map(_.last))
        .filter(n => os.isFile(dir / n / Names.ThesisJson)).foreach(say)
      0
    case List(slug) =>
      table(k, k.project(slug), say)
      0
    case _ => fail("usage: thesis sections [<slug>]")

  /** The words of a section's prose, if its file is there. */
  def wordCount(k: Kit, f: os.Path): Option[Int] =
    Option.when(Kit.plainFile(f))(Prose.words(Prose.sentences(os.read(f), k.profile.lists.abbreviations)))

  /** The table of `thesis sections <slug>`, one line at a time. */
  private def table(k: Kit, p: Project, emit: String => Unit): Unit =
    def row(cells: String*): String =
      cells.zip(List(6, 18, 11, 10, 16, 6)).map((c, w) => padBytes(c, w)).mkString(" ") + " " + cells.last
    def orEmpty(v: String, empty: String) = if v == "null" then empty else v
    emit(row("ORDER", "ID", "KIND", "STATUS", "BY", "ROUND", "WORDS/TARGET"))
    p.ordered.foreach { s =>
      val sec = k.section(p, s.id)
      val st = sectionStatus(k, p, sec)
      val by = if st.state == Claimed then st.by else orEmpty(p.stateOr(sec.id, StateKey.By, ""), "")
      val shown = if st.stale then s"${st.state.render} (stale claim)" else st.state.render
      val round = orEmpty(p.stateOr(sec.id, StateKey.Round, "0"), "0")
      val words = wordCount(k, p.sectionFile(sec.id)).map(_.toString).getOrElse("-")
      emit(row(sec.raw(SectionKey.Order), sec.id, sec.raw(SectionKey.Kind), shown, if by.isEmpty then "-" else by, round,
        s"$words/${sec.targetWordsShown}"))
    }

  def status(k: Kit, args: List[String]): Int =
    val p = args match
      case List(slug) => k.project(slug)
      case _          => fail("usage: thesis status <slug>")
    say(s"thesis status: ${p.slug}  (${p.title})")
    val questions = if os.isDir(p.notes) then os.walk(p.notes).count(f => f.last.endsWith(".questions.md") && os.size(f) > 0) else 0
    val verified = p.refRows.count(_.status == SourceStatus.Verified.render)
    val entries = if os.isFile(p.refsBib) then Bib.rows(os.read(p.refsBib)).count(_.isEntry) else 0
    say(s"  verified sources: $verified of $entries entries in refs.bib; open questions for the editor: $questions")
    // Each part runs as a subshell did: a refusal in it ends the part, not the command.
    def part(body: => Unit): Unit =
      try body
      catch case Exit(_, message) => { System.out.flush(); if message.nonEmpty then warn(message) }
    part(table(k, p, line => say(s"  $line")))
    val blocks = ArrayBuffer[String]()
    blocks ++= Validate.problems(p.json, k.profile, `final` = true).getOrElse(Nil)
    part(p.orderIds.foreach { id =>
      val st = sectionStatus(k, p, k.section(p, id)).state
      if st != Accepted then blocks += s"section $id is ${st.render}, not accepted"
    })
    if blocks.nonEmpty then
      say("  blocks assemble:")
      blocks.foreach(b => say(s"    $b"))
    else say("  nothing blocks assemble (it still runs the whole-work cite-check first)")
    val qa = p.build / Names.QaJson
    if os.isFile(qa) then
      val q = ujson.read(os.read(qa))
      val pass = J.get(q, QaKey.Pass).exists(v => !J.falsy(v))
      say(s"  last pdf-qa: ${if pass then "PASS" else "FAIL"} (${J.raw(J.get(q, QaKey.Pages))} pages)")
    0

  // ---------------------------------------------------------------- fetch, release

  def fetch(k: Kit, args: List[String]): Int =
    val a = parse(Cmd.Fetch, args, As, Set.empty, 2)
    val slug = a.pos.headOption.getOrElse(fail("usage: thesis fetch <slug> [<id>] [--as <seat>]"))
    val p = k.project(slug)
    val seat = k.seatName(a.opts.get("--as"))
    List(Names.Claims, Names.State, Names.Sections, Names.Notes).foreach(d => os.makeDir.all(p.dir / d))
    val got = a.pos.lift(1) match
      case Some(id) =>
        val sec = k.section(p, id)
        sectionStatus(k, p, sec).state match
          case Todo | Revise | Claimed => ()
          case Omit => fail(s"$slug/$id is omitted in thesis.json (status omit): the editor must set it to todo")
          case s    => fail(s"$slug/$id is ${s.render}: not for writing (the editor reopens a section with a revise verdict)")
        if !tryClaim(k, p, id, seat) then
          fail(s"$slug/$id is claimed by ${claim(p, id).map(_.seat).getOrElse("")} and the claim is not stale (after ${Profile.show(k.profile.limits.claimStaleS)} s)")
        Some(id)
      case None =>
        // First the sections that this seat already holds, then the first free one in order.
        val ids = p.orderIds
        def state(id: String) = sectionStatus(k, p, k.section(p, id))
        ids.find { c =>
          val st = state(c)
          st.state == Claimed && st.by == seat
        }.orElse(ids.find { c =>
          val st = state(c).state
          (st == Todo || st == Revise) && tryClaim(k, p, c, seat)
        })
    got match
      case None =>
        say(s"thesis: nothing to fetch in $slug for $seat (every section is claimed, drafted or accepted, or omitted)")
        3
      case Some(id) =>
        val sec = k.section(p, id)
        k.log(p, Some(seat), s"fetch $id by $seat")
        workOrder(k, p, sec, seat)
        0

  def release(k: Kit, args: List[String]): Int =
    val a = parse(Cmd.Release, args, As, Set("--force"), 2)
    if a.pos.length != 2 then fail("usage: thesis release <slug> <id> [--as <seat>] [--force]")
    val List(slug, id) = a.pos: @unchecked
    val p = k.project(slug)
    k.section(p, id)
    val seat = k.seatName(a.opts.get("--as"))
    val c = claim(p, id).getOrElse(fail(s"$slug/$id has no claim"))
    if c.seat != seat && !a.flags("--force") && !isStale(k, c) then
      fail(s"$slug/$id is claimed by ${c.seat}, not by $seat (--force to take it back)")
    os.remove(p.claimFile(id))
    k.log(p, Some(seat), s"release $id by $seat")
    say(s"thesis: released $slug/$id")
    0

  /** `work_order`: one self-contained work order on stdout. */
  private def workOrder(k: Kit, p: Project, sec: Section, seat: String): Unit =
    val id = sec.id
    val role = sec.raw(SectionKey.Role)
    val cls = sec.citeClass
    val target = k.profile.cite.scoreTargets.getOrElse(cls, 0.0)
    val w = sec.targetWordsShown
    val wn = Text.awkNum(w)
    val words = k.profile.words
    val rows = p.refRows
    val round = p.stateOr(id, StateKey.Round, "0")
    val stale = Profile.show(k.profile.limits.claimStaleS)
    say("THESIS WORK ORDER")
    say(s"project:  ${p.slug}")
    say(s"section:  $id   (${sec.raw(SectionKey.Kind)}, role $role)")
    say(s"title:    ${sec.title}")
    say(s"seat:     $seat, claimed ${Kit.nowIso()}; the claim is stale after $stale s")
    say(s"length:   about $w words (${(wn * words.targetToleranceLow).toLong} to ${(wn * words.targetToleranceHigh).toLong} accepted)")
    say(s"citation: class $cls: aim at ${fixed(target * 100, 0)} % of sentences with a mark (cite-score)")
    if round != "null" && round != "0" then
      say(s"round:    $round (the reviewer asked for changes: read review/$id.verdict.md and review/$id.review.md)")
    say("")
    say("BRIEF")
    val folded = Text.foldSpaces(sec.raw(SectionKey.Brief) + "\n", 100)
    Prose.lines(folded).foreach(l => say(s"  $l"))
    say("")
    say("SOURCES YOU MAY CITE (status verified in REFERENCES.md; the capture of each is the file named):")
    val sources = sec.sources
    val verified = sources.filter(s => RefRow.status(rows, s) == SourceStatus.Verified.render)
    verified.foreach(s => say(s"  [@$s]  sources/$s.md"))
    if verified.isEmpty then
      say(s"  (none yet: write what the facts support, cite nothing, and say in notes/$id.questions.md what you need)")
    val notVerified = sources.filterNot(verified.contains).map { s =>
      val st = RefRow.status(rows, s)
      s"$s(${if st.isEmpty then "no row" else st}) "
    }.mkString
    if notVerified.nonEmpty then say(s"NOT YET VERIFIED (do not cite): $notVerified")
    say("")
    say("READ (shared, read only): notes/facts.md  notes/glossary.md  refs.bib  REFERENCES.md")
    say(s"WRITE:                    sections/$id.md   (pandoc markdown), figures in figures/ if you have any")
    say(s"ASK:                      notes/$id.questions.md")
    say(s"HAND IN:                  thesis submit ${p.slug} $id --as $seat")
    say("                          (it runs build-section, lint, cite-check, slop and readability; it refuses with the reasons)")
    say(s"GIVE UP:                  thesis release ${p.slug} $id --as $seat")
    say("")
    say("RULES")
    rules(os.read(k.share / "lib" / Names.WorkOrderTxt), role, id).foreach(l => say(s"  $l"))
    say("")

  /** The lines of workorder.txt under `## common`, `## style` and `## role:<role>`, with @ID@ filled. */
  def rules(text: String, role: String, id: String): List[String] =
    Prose.lines(text).foldLeft((false, List.empty[String])) { case ((on, out), line) =>
      if line.startsWith("## ") then
        val name = line.split("[ \t]+").lift(1).getOrElse("")
        (name == "common" || name == "style" || name == s"role:$role", out)
      else if on then (on, line.replace("@ID@", id) :: out)
      else (on, out)
    }._2.reverse

  // ---------------------------------------------------------------- submit

  /** The gates of a submit, in the order they run. */
  val SubmitGates: List[Cmd] = List(Cmd.Lint, Cmd.BuildSection, Cmd.CiteCheck, Cmd.Slop, Cmd.Readability)

  /** The gates of a section's review report. */
  val ReviewGates: List[Cmd] = List(Cmd.Lint, Cmd.Readability, Cmd.Slop, Cmd.CiteCheck, Cmd.CiteScore)

  def submit(k: Kit, args: List[String]): Int =
    val a = parse(Cmd.Submit, args, As, Set.empty, 2)
    if a.pos.length != 2 then fail("usage: thesis submit <slug> <id> [--as <seat>]")
    val List(slug, id) = a.pos: @unchecked
    val p = k.project(slug)
    k.section(p, id)
    val seat = k.seatName(a.opts.get("--as"))
    if !claim(p, id).exists(_.seat == seat) then fail(s"$slug/$id is not claimed by $seat: thesis fetch $slug $id --as $seat")
    val sf = p.sectionFile(id)
    if !Kit.plainFile(sf) then fail(s"$slug/$id: write sections/$id.md first")
    say(s"thesis submit: $slug/$id by $seat")
    // Each gate runs in its own process: a refusal in it is a reason, not the end of the submit.
    val failed = SubmitGates.filter { gate =>
      val (code, out) = k.self(gate, slug, id)
      if code == 0 then say(s"  ok   ${gate.name}")
      else
        say(s"  FAIL ${gate.name}")
        Prose.lines(out).foreach(l => say(s"       $l"))
      code != 0
    }
    if failed.nonEmpty then
      val reasons = failed.map(" " + _.name).mkString
      k.log(p, Some(seat), s"submit $id refused:$reasons")
      fail(s"$slug/$id is not handed in. Gates that failed:$reasons. Fix the text, then run thesis submit again.")
    val sha = Kit.sha(sf)
    val round = J.get(p.readState(id), StateKey.Round.key).filterNot(J.falsy).getOrElse(ujson.Num(0))
    p.putState(id)(StateKey.Status -> ujson.Str(Drafted.render), StateKey.By -> ujson.Str(seat), StateKey.Sha -> ujson.Str(sha),
      StateKey.Drafted -> ujson.Str(Kit.nowIso()), StateKey.Round -> round)(StateKey.ReviewedSha, StateKey.ReportOk)
    os.remove(p.claimFile(id), checkExists = false)
    k.log(p, Some(seat), s"submit $id by $seat: drafted (sha ${sha.take(8)})")
    say(s"thesis: $slug/$id is drafted. The reviewer takes it from here.")
    0

  // ---------------------------------------------------------------- review-report, verdict

  def reviewReport(k: Kit, args: List[String]): Int =
    val (p, id) = args match
      case List(slug, id) => (k.project(slug), id)
      case _              => fail("usage: thesis review-report <slug> <id|final>")
    os.makeDir.all(p.review)
    os.makeDir.all(p.dir / Names.State)
    if id == Names.Final then finalReport(k, p) else sectionReport(k, p, id)

  private def finalReport(k: Kit, p: Project): Int =
    val out = p.review / "final.gates.md"
    val b = new StringBuilder
    def line(s: String) = b ++= s ++= "\n"
    def gate(cmd: Cmd, failNote: Boolean) =
      val (code, text) = k.self(cmd, p.slug)
      b ++= text
      if code != 0 && failNote then line(s"(failed: exit $code)")
    line(s"# Final review of ${p.slug}, ${Kit.nowIso()}")
    line("")
    line("Gates that run on the whole work. A machine wrote this report; the reviewer reads and decides.")
    line("")
    line("## cite-check (whole work)")
    line("```")
    gate(Cmd.CiteCheck, failNote = true)
    line("```")
    line("")
    line("## status")
    line("```")
    gate(Cmd.Status, failNote = false)
    line("```")
    line("")
    line("## ufrj-check (needs build/thesis.pdf from assemble)")
    line("```")
    gate(Cmd.UfrjCheck, failNote = true)
    line("```")
    Kit.atomicWrite(out, b.toString)
    say(s"thesis: wrote $out")
    0

  private def sectionReport(k: Kit, p: Project, id: String): Int =
    val sec = k.section(p, id)
    val sf = p.sectionFile(id)
    if !Kit.plainFile(sf) then fail(s"${p.slug}/$id: no sections/$id.md")
    val out = p.review / s"$id.gates.md"
    val b = new StringBuilder
    def line(s: String) = b ++= s ++= "\n"
    line(s"# Review of ${p.slug}/$id, ${Kit.nowIso()}")
    line("")
    line(s"Section sha256 ${Kit.sha(sf)}")
    line(s"Written by ${p.stateOr(id, StateKey.By, "?")}, round ${p.stateOr(id, StateKey.Round, "0")}. The gates below are local rules; the reviewer's verdict is a decision.")
    line("")
    val allOk = ReviewGates.map { g =>
      line(s"## ${g.name}")
      line("```")
      val (code, text) = k.self(g, p.slug, sec.id)
      b ++= text
      line("```")
      line(s"result: ${if code == 0 then "PASS" else s"FAIL (exit $code)"}")
      line("")
      code == 0
    }.forall(identity)
    line("## For the reviewer (by hand: no script can do these)")
    line("- Does each cited claim say what sources/<key>.md says? Read the passages.")
    line("- Is it plain pt-BR a student of the course reads once? Is any fact invented?")
    line("- Does the text match the UFRJ part and the brief, and stay inside this section?")
    line("")
    line(s"Gates: ${if allOk then "all PASS" else "at least one FAIL"}.")
    Kit.atomicWrite(out, b.toString)
    val sha = Kit.sha(sf)
    val drafted = J.get(p.readState(id), StateKey.Status.key).contains(ujson.Str(Drafted.render))
    val promote = Option.when(allOk && drafted)(StateKey.Status -> ujson.Str(Linted.render))
    p.putState(id)((List(StateKey.ReviewedSha -> ujson.Str(sha), StateKey.ReportOk -> ujson.Bool(allOk)) ++ promote)*)()
    k.log(p, None, s"review-report $id: ${if allOk then "PASS" else "FAIL"}")
    say(s"thesis: wrote $out (${if allOk then "all gates PASS" else "a gate FAILED"})")
    if allOk then 0 else 1

  def verdict(k: Kit, args: List[String]): Int =
    val a = parse(Cmd.Verdict, args, Map("--by" -> "a seat", "--note" -> "a file"), Set.empty, 3)
    val by = a.opts.getOrElse("--by", "")
    if a.pos.length < 2 || by.isEmpty then fail("usage: thesis verdict <slug> <id> accept|revise --by <seat> [--note <file>]")
    val decision = Decision.parse(a.pos.lift(2).getOrElse("")).fold(fail, identity)
    k.checkSeat(by)
    val p = k.project(a.pos(0))
    val id = k.section(p, a.pos(1)).id
    val slugId = s"${p.slug}/$id"
    val sf = p.sectionFile(id)
    if !Kit.plainFile(sf) then fail(s"$slugId: no sections/$id.md")
    val st = p.stateOr(id, StateKey.Status, Todo.render)
    SectionState.parse(st) match
      case Drafted | Linted => ()
      case _ => fail(s"$slugId is $st: a verdict needs a drafted section (status drafted or linted)")
    val writer = p.stateOr(id, StateKey.By, "")
    if writer == by then fail(s"$slugId: $by wrote this section and may not judge it")
    val sha = Kit.sha(sf)
    if p.stateRaw(id, StateKey.Sha) != sha then fail(s"$slugId: sections/$id.md changed after submit: the writer must submit again")
    val note = a.opts.get("--note")
    note.foreach { n =>
      if n.startsWith("/") || n.contains("..") then fail("verdict: --note must be a file inside the project (notes/ or review/), without ..")
      if !Kit.plainFileAt(p.dir, n) then fail(s"verdict: no note file ${p.dir}/$n")
    }
    val previous = p.stateOr(id, StateKey.Round, "0")
    val round = decision match
      case Decision.Accept =>
        if !Kit.plainFile(p.review / s"$id.review.md") then
          fail(s"$slugId: write review/$id.review.md first (the reviewer's findings); thesis only writes review/$id.gates.md")
        if p.stateRaw(id, StateKey.ReviewedSha) != sha then k.self(Cmd.ReviewReport, p.slug, id): Unit
        if p.stateRaw(id, StateKey.ReviewedSha) != sha then fail(s"$slugId: the gates did not run on the current text")
        if p.stateRaw(id, StateKey.ReportOk) != "true" then fail(s"$slugId: a gate failed on the current text (review/$id.gates.md): revise")
        p.putState(id)(StateKey.Status -> ujson.Str(Accepted.render), StateKey.AcceptedSha -> ujson.Str(sha),
          StateKey.VerdictBy -> ujson.Str(by), StateKey.VerdictAt -> ujson.Str(Kit.nowIso()))()
        os.remove(p.claimFile(id), checkExists = false)
        k.log(p, Some(by), s"verdict $id accept by $by (sha ${sha.take(8)})")
        previous
      case Decision.Revise =>
        val max = k.profile.limits.maxReviewRounds
        val n = previous.toIntOption.getOrElse(0)
        if n >= max then
          k.log(p, Some(by), s"verdict $id revise refused: round limit ${Profile.show(max)}")
          fail(s"$slugId has had $previous review rounds (the limit is ${Profile.show(max)}): ask the owner to decide. Nothing changed.")
        p.putState(id)(StateKey.Status -> ujson.Str(Revise.render), StateKey.Round -> ujson.Num(n + 1),
          StateKey.VerdictBy -> ujson.Str(by), StateKey.VerdictAt -> ujson.Str(Kit.nowIso()))(
          StateKey.ReviewedSha, StateKey.ReportOk, StateKey.AcceptedSha)
        // The claim goes back to the writer, so that the writer's next fetch resumes this section.
        os.makeDir.all(p.dir / Names.Claims)
        os.write.over(p.claimFile(id), claimText(writer, id))
        val next = (n + 1).toString
        k.log(p, Some(by), s"verdict $id revise by $by (round $next)")
        next
    note match
      case Some(n) => os.copy.over(os.Path(java.nio.file.Paths.get(p.dir.toString, n).normalize.toString), p.review / s"$id.verdict.md")
      case None    => os.write.over(p.review / s"$id.verdict.md", s"verdict: ${decision.render} by $by at ${Kit.nowIso()} (round $round)\n")
    say(s"thesis: $slugId: ${decision.render} by $by")
    0

/** The files that `thesis new` writes into a project. */
object NewFiles:
  val facts: String =
    """# Facts of the thesis
      |
      |One file for the whole work. Every section reads it; no section reads another section's text.
      |Write only what is true and checked: numbers with their unit, the setup, the dates, who decided what.
      |The author writes or confirms this file. A writer never adds an experience of the author.
      |
      || Fact | Value | Where it comes from |
      ||---|---|---|
      |""".stripMargin

  val glossary: String =
    """# Glossário
      |
      |One row a term. The first column is the word the thesis uses. A term that is an English word and is
      |listed here is not flagged as an anglicism, and the forms of one row count as one term.
      |
      || Termo | Definição | Observação |
      ||---|---|---|
      |""".stripMargin

  val refs: String =
    """% The sources of the thesis. Only the librarian adds an entry, and only after fetching the work and
      |% writing sources/<key>.md and a row in REFERENCES.md. Never invent an entry.
      |""".stripMargin

  val references: String =
    """# REFERENCES
      |
      || Key | Status | Checked against | Note |
      ||---|---|---|---|
      |
      |Status: `verified` (fetched, details match), `partial` (fetched, one detail unconfirmed: leave the field out
      |of refs.bib and write `unconfirmed: field` in the Note), `unverified` (not fetched: must not be cited).
      |""".stripMargin
