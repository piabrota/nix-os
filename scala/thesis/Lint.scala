package piabrota.thesis

import scala.collection.mutable.ArrayBuffer
import Prose.matches
import Level.{Fail, Warn}

/** The rules of `thesis lint`, by the name the report prints. */
enum LintRule(val name: String):
  case Character extends LintRule("character")
  case Placeholder extends LintRule("placeholder")
  case RawTex extends LintRule("raw-tex")
  case RawHtml extends LintRule("raw-html")
  case NumericCitation extends LintRule("numeric-citation")
  case PretextHeading extends LintRule("pretext-heading")
  case HeadingNumber extends LintRule("heading-number")
  case HeadingDepth extends LintRule("heading-depth")
  case PretextList extends LintRule("pretext-list")
  case FigureCaption extends LintRule("figure-caption")
  case FigureLabel extends LintRule("figure-label")
  case TableLabel extends LintRule("table-label")
  case TableCaption extends LintRule("table-caption")
  case NotCited extends LintRule("not-cited")
  case NoLabel extends LintRule("no-label")
  case NoChapter extends LintRule("no-chapter")
  case FigurePath extends LintRule("figure-path")
  case FigureFile extends LintRule("figure-file")
  case Length extends LintRule("length")
  case ResumoWords extends LintRule("resumo-words")
  case Keywords extends LintRule("keywords")
  case ResumoParagraphs extends LintRule("resumo-paragraphs")
  case Structure extends LintRule("structure")

/** A finding: FAIL or WARN, the line (0 for the whole section), the rule and the message. */
final case class Finding(level: Level, line: Int, rule: LintRule, message: String):
  /** The TSV row of the shell version: the sort order of the report comes from it. */
  def row: String = s"${level.render}\t$line\t${rule.name}\t$message"
  def render: String =
    if line == 0 then s"${level.render} ${rule.name}: $message"
    else s"${level.render} line $line ${rule.name}: $message"

/** A label (fig:x), a reference to one, or a figure path, and the line it is on. */
final case class Spot(name: String, line: Int)

/** The line checks of `thesis lint` on the raw markdown of one section: findings, labels
  * ({#fig:x} {#tbl:x} {#eq:x} {#sec:x}), references (@fig:x), image files and the headings.
  */
final case class LintScan(findings: Vector[Finding], labels: Vector[Spot], refs: Vector[Spot],
    figFiles: Vector[Spot], headings: Int):
  /** Labels of these kinds that no reference cites, in the order of the text, each with its last line. */
  def uncited(kinds: String*): Vector[Spot] =
    val cited = refs.map(_.name).toSet
    val last = labels.map(l => l.name -> l.line).toMap
    labels.map(_.name).distinct.filter(l => kinds.exists(k => l.startsWith(s"$k:")) && !cited(l)).map(l => Spot(l, last(l)))

object LintScan:
  import LintRule.*

  /** `allowed` holds the code points the PDF engine can set; `markers` the placeholders. */
  def apply(text: String, role: Option[Role], allowed: Set[Int], markers: List[String]): LintScan =
    val pretext = role.exists(_.pretext)
    val findings = ArrayBuffer[Finding]()
    val labels = ArrayBuffer[Spot]()
    val refs = ArrayBuffer[Spot]()
    val figFiles = ArrayBuffer[Spot]()
    var fence = false
    var mathBlock = false
    var tblOpen = false
    var tables = 0
    var tblStart = 0
    var captions = 0
    var headings = 0
    def out(level: Level, ln: Int, rule: LintRule, msg: String): Unit = findings += Finding(level, ln, rule, msg)
    def label(re: String, s: String, ln: Int): Boolean =
      re.r.findFirstIn(s) match
        case Some(m) => labels += Spot(m.drop(2).dropRight(1), ln); true
        case None    => false

    Prose.lines(text).zipWithIndex.foreach { (raw, i) =>
      val line = raw.stripSuffix("\r")
      val ln = i + 1
      line.codePoints.toArray.find(c => !allowed(c)).foreach { c =>
        out(Fail, ln, Character, s"the character \"${new String(java.lang.Character.toChars(c))}\" cannot be set by the PDF engine (Portuguese letters and common punctuation only; math goes in $$...$$, symbols as words)")
      }
      val low = line.toLowerCase
      markers.find(m => line.contains(m) || low.contains(m.toLowerCase) && m.matches("^[a-z ]+$"))
        .foreach(m => out(Fail, ln, Placeholder, s"marker $m is still in the text"))

      if matches("""^ {0,3}(```|~~~)""".r, line) then fence = !fence
      else if fence then ()
      else if matches("""^ *\$\$ *$""".r, line) then mathBlock = !mathBlock
      else if mathBlock then ()
      else if matches("""^ *\$\$.*\$\$""".r, line) then { label("""\{#eq:[A-Za-z0-9_-]+\}""", line, ln); () }
      else
        """@(fig|tbl|eq|sec|cap):[A-Za-z0-9_-]+""".r.findAllIn(line).foreach(r => refs += Spot(r.drop(1), ln))
        val stripped = line.replaceAll("`[^`]*`", "").replaceAll("""\$[^$]*\$""", "")
        if matches("""\\[A-Za-z@]+""".r, stripped) then
          out(Warn, ln, RawTex, "a backslash command is printed as text: raw TeX is switched off")
        if matches("""<[A-Za-z/!]""".r, stripped) && !matches("""<https?:""".r, stripped) then
          out(Warn, ln, RawHtml, "HTML is dropped: raw HTML is switched off")
        if matches("""\[[0-9]+([,–-][0-9]+)*\]""".r, stripped) && !stripped.contains("](") then
          out(Fail, ln, NumericCitation, "a numbered citation [n]: the system is author-date, write [@key]")

        if matches("^ *$".r, line) then tblOpen = false
        else if matches("""^ {0,3}#+ """.r, line) then
          val level = line.takeWhile(_ == '#').length
          val h = line.replaceFirst("""^ *#+ +""", "")
          if pretext then out(Fail, ln, PretextHeading, "this sheet has no headings")
          if matches("""^[0-9]+([.][0-9]+)*[.)]? """.r, h) then
            out(Fail, ln, HeadingNumber, "do not number headings by hand: LaTeX numbers them")
          if level > 4 then out(Warn, ln, HeadingDepth, s"heading of level $level (at most 4 are used)")
          label("""\{#sec:[A-Za-z0-9_-]+\}""", h, ln): Unit
          headings += 1
        else
          if pretext && matches("""^ *([-*+]|[0-9]+[.)]) +""".r, line) then
            out(Fail, ln, PretextList, "this sheet is one paragraph of text, not a list")
          if matches("""^ *!\[""".r, line) then
            val cap = line.replaceFirst("""^ *!\[""", "").replaceFirst("""\]\([^)]*\)[^\]]*$""", "")
            val path = line.replaceFirst("""^.*\]\(""", "").replaceFirst("""\).*$""", "").replaceFirst(" .*$", "")
            if matches("^ *$".r, cap) then out(Fail, ln, FigureCaption, "a figure needs a caption (the text between [ ])")
            """\{[^}]*#fig:[A-Za-z0-9_-]+[^}]*\}""".r.findFirstIn(line) match
              case Some(lab) => labels += Spot("""#fig:[A-Za-z0-9_-]+""".r.findFirstIn(lab).get.drop(1), ln)
              case None => out(Fail, ln, FigureLabel, "a figure needs a label, as {#fig:name}, so that the text can cite it")
            figFiles += Spot(path, ln)
          else if matches("""^ *\|""".r, line) || matches("""^ *[+][-=+]+[+] *$""".r, line) then
            if !tblOpen then { tblOpen = true; tables += 1; tblStart = ln }
          else if line.startsWith(": ") then
            captions += 1
            if !label("""\{#tbl:[A-Za-z0-9_-]+\}""", line, ln) then
              out(Fail, ln, TableLabel, "a table caption needs a label, as {#tbl:name}, so that the text can cite it")
            tblOpen = false
          else tblOpen = false
    }
    if tables != captions then
      out(Fail, tblStart, TableCaption, s"$tables table(s) but $captions caption line(s) `: caption {#tbl:name}`")
    LintScan(findings.toVector, labels.toVector, refs.toVector, figFiles.toVector, headings)

/** `thesis lint <slug> <id> [--allow-placeholders]`: the rules of the markdown, the characters, the
  * labels, the figure files and the length.
  */
object Lint:
  import LintRule.*

  def run(k: Kit, args: List[String]): Int =
    val (allow, pos) = args.foldLeft((false, Vector.empty[String])) {
      case ((_, pos), "--allow-placeholders") => (true, pos)
      case (_, o) if o.startsWith("-")        => fail(s"lint: unknown option $o")
      case ((allow, pos), a)                  => if pos.length >= 2 then fail("lint: too many arguments") else (allow, pos :+ a)
    }
    if pos.length != 2 then fail("usage: thesis lint <slug> <id> [--allow-placeholders]")
    val g = Gate(k, pos(0), pos(1))
    val markers = if allow then Nil else k.profile.lists.placeholderMarkers
    val scan = LintScan(g.text, g.sec.role, k.profile.lists.allowedChars, markers)
    val found = scan.findings ++ references(g.p, scan) ++ length(k.profile.words, g.sec, g.prose, scan.headings)
    val fails = found.count(_.level == Fail)
    val warns = found.count(_.level == Warn)
    found.sortBy(f => (f.line, f.row)).foreach(f => say(f.render))
    say(s"lint: ${g.p.slug}/${g.sec.id}: ${Prose.words(g.prose)} words, $fails fail, $warns warn")
    if fails == 0 then 0 else 1

  /** Labels never cited, references to no label or no section, and the figure files. */
  def references(p: Project, scan: LintScan): Vector[Finding] =
    val labels = scan.labels.map(l => l.name -> l.line).toMap
    val refs = scan.refs.map(r => r.name -> r.line).toMap
    val ids = p.sections.flatMap(_.idValue).toSet
    val notCited = labels.toVector.collect {
      case (l, ln) if (l.startsWith("fig:") || l.startsWith("tbl:")) && !refs.contains(l) =>
        Finding(Fail, ln, NotCited, s"$l is never cited in the text (write @$l)")
    }
    val noLabel = refs.toVector.collect {
      case (r, ln) if !r.startsWith("cap:") && !labels.contains(r) =>
        Finding(Fail, ln, NoLabel, s"@$r has no label in this section: a section may cite only its own figures, tables and equations")
    }
    val noChapter = scan.refs.filter(_.name.startsWith("cap:")).collect {
      case Spot(r, ln) if !ids(r.drop(4)) => Finding(Fail, ln, NoChapter, s"@cap:${r.drop(4)} names no section of thesis.json")
    }
    val figures = scan.figFiles.flatMap { case Spot(path, ln) =>
      if path.startsWith("figures/") && path.drop(8).exists(c => !(c.isLetterOrDigit && c < 128 || "._/-".contains(c)))
        || path.contains("/../") || path.contains("..") then
        Some(Finding(Fail, ln, FigurePath, s"the figure path $path may hold letters, digits, . _ / - only"))
      else if !path.startsWith("figures/") then
        Some(Finding(Fail, ln, FigurePath, s"the figure path $path must start with figures/"))
      else Option.when(!Kit.plainFileAt(p.dir, path))(
        Finding(Fail, ln, FigureFile, s"the figure file $path is missing (put it in the project folder figures/; PDF, PNG or JPEG)"))
    }
    notCited ++ noLabel ++ noChapter ++ figures

  /** The length against the target, and the rules of the resumo and of a chapter. */
  def length(rules: WordRules, sec: Section, rows: Vector[Sentence], headings: Int): Vector[Finding] =
    val words = Prose.words(rows)
    val target = sec.targetWords
    val (lo, hi) = (rules.targetToleranceLow, rules.targetToleranceHigh)
    val size =
      if target <= 0 then None
      else if words < target * lo then
        Some(Finding(Fail, 0, Length, s"$words words, under ${(lo * 100).toLong} % of the target ${target.toLong}"))
      else Option.when(words > target * hi)(
        Finding(Warn, 0, Length, s"$words words, over ${(hi * 100).toLong} % of the target ${target.toLong}"))
    val byRole = sec.role match
      case Some(Role.Resumo | Role.Abstract) =>
        val max = rules.resumoMax
        val kn = sec.keywordCount
        val paras = rows.filter(_.kind == SentenceKind.Paragraph).map(_.para).distinct.length
        List(
          Option.when(words > max)(Finding(Fail, 0, ResumoWords,
            s"$words words: the ${sec.raw(SectionKey.Role)} sheet holds at most $max (Res. 05/2012; Norma 2026, 7.3)")),
          Option.when(kn < rules.keywordsMin || kn > rules.keywordsMax)(Finding(Fail, 0, Keywords,
            s"$kn keywords in thesis.json, need ${rules.keywordsMin} to ${rules.keywordsMax}")),
          Option.when(paras > 1)(Finding(Warn, 0, ResumoParagraphs,
            s"$paras paragraphs: a resumo is one paragraph (NBR 6028, from memory)")),
        ).flatten
      case Some(Role.Chapter) =>
        Option.when(headings == 0 && words > 800)(Finding(Warn, 0, Structure,
          s"$words words and no heading: split the chapter in sections (# Heading)")).toList
      case _ => Nil
    size.toVector ++ byRole

/** `gate_prepare`: the project, the section and its text, which must be there, plain and not too big. */
final case class Gate(p: Project, sec: Section, file: os.Path, text: String, prose: Vector[Sentence])

object Gate:
  def apply(k: Kit, slug: String, id: String): Gate =
    val p = k.project(slug)
    val sec = k.section(p, id)
    val file = p.sectionFile(id)
    if !Kit.plainFile(file) then fail(s"$slug/$id: no sections/$id.md (or it is a link)")
    val max = k.profile.limits.sectionMaxBytes
    if os.size(file) > max then fail(s"$slug/$id: sections/$id.md is over ${Profile.show(max)} bytes")
    if os.size(file) == 0 then fail(s"$slug/$id: sections/$id.md is empty")
    val text = os.read(file)
    Gate(p, sec, file, text, Prose.sentences(text, k.profile.lists.abbreviations))
