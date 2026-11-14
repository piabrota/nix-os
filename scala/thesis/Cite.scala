package piabrota.thesis

import scala.collection.mutable
import Text.{fixed, sortC}
import Level.{Fail, Warn}

/** Gate 4, professional citation (the rules of h0ffmann/closed-source: never invent a reference,
  * fetch every source before citing it, record the check in REFERENCES.md). cite-check says what is
  * wrong; cite-score counts marks, not truth.
  */
object CiteCheck:
  private val Aliases = Map("journal" -> "journaltitle", "address" -> "location", "year" -> "date",
    "school" -> "institution", "institution" -> "school")

  /** One line of the report. The report is sorted by `row`, as the shell version sorted its TSV. */
  final case class Problem(level: Level, where: String, message: String):
    def row: String = s"${level.render}\t$where\t$message"
    def render: String = s"${level.render} $where: $message"

  /** A key cited in a section, on a line. */
  final case class Cited(key: String, section: String, line: Int)

  def run(k: Kit, args: List[String]): Int =
    if args.isEmpty || args.length > 2 then fail("usage: thesis cite-check <slug> [<id>]")
    val p = k.project(args.head)
    val whole = args.length == 1
    val sid = args.lift(1).map { id =>
      k.section(p, id)
      if !Kit.plainFile(p.sectionFile(id)) then fail(s"${p.slug}/$id: no sections/$id.md")
      id
    }
    val sectionIds = sid.map(List(_)).getOrElse(p.orderIds)
    if !Kit.plainFile(p.refsBib) then fail(s"${p.slug}: no refs.bib")
    if !Kit.plainFile(p.references) then fail(s"${p.slug}: no REFERENCES.md")
    val bib = Bib.rows(os.read(p.refsBib))
    val rows = RefRow.rows(os.read(p.references))
    val bibKeys = sortC(bib.filter(_.isEntry).map(_.key))
    val bibKeySet = bibKeys.toSet
    val rowKeys = rows.map(_.key).toSet
    val out = mutable.ArrayBuffer[Problem]()
    def add(level: Level, where: String, msg: String): Unit = out += Problem(level, where, msg)
    def field(key: String, f: String): Option[String] =
      bib.find(r => r.key == key && !r.isEntry && (r.field == f || Aliases.get(f).contains(r.field)) && r.value.nonEmpty)
        .map(_.value)

    val maxQuote = k.profile.words.inlineQuoteMaxWords
    val cited = sectionIds.flatMap { id =>
      val f = p.sectionFile(id)
      if !Kit.plainFile(f) then
        if whole then add(Fail, s"sections/$id.md", "the section file is missing")
        Nil
      else
        val c = Cites(os.read(f), maxQuote)
        c.quotes.foreach(q => add(Fail, s"sections/$id.md:${q.line}", s"an inline quotation of ${q.words} words: a quotation of three lines or more goes in a block (> text), NBR 10520"))
        c.hand.foreach(m => add(Warn, s"sections/$id.md:${m.line}", s"${m.text} typed by hand: write [@key], so that the reference list and the mark agree"))
        c.numbered.foreach(m => add(Fail, s"sections/$id.md:${m.line}", s"the numbered citation ${m.text}: one system for the whole work, author-date (Res. 05/2012; Norma 2026, 9.1)"))
        c.keys.map(m => Cited(m.text, id, m.line))
    }.distinct
    val citedKeys = sortC(cited.map(_.key).distinct)
    val citedKeySet = citedKeys.toSet

    groupsInOrder(bib.filter(_.isEntry))(_.key).foreach { (key, entries) =>
      if entries.length > 1 then
        add(Fail, s"refs.bib:$key", s"the key $key is defined ${entries.length} times (lines${entries.map(" " + _.value).mkString})")
    }
    groupsInOrder(rows)(_.key).foreach { (key, rs) =>
      if rs.length > 1 then add(Fail, s"REFERENCES.md:$key", s"the key $key has ${rs.length} rows")
    }

    cited.foreach { c =>
      val (key, where) = (c.key, s"sections/${c.section}.md:${c.line}")
      if !bibKeySet(key) then
        add(Fail, where, s"@$key is not in refs.bib: never invent a reference; ask the librarian to fetch it first")
      else RefRow.status(rows, key) match
        case "" => add(Fail, where, s"@$key has no row in REFERENCES.md: not cited until it is verified")
        case st => SourceStatus.parse(st) match
          case Some(SourceStatus.Verified) => ()
          case Some(_) => add(Fail, where, s"@$key has the status $st: only verified sources may be cited")
          case None    => add(Fail, where, s"""@$key has the unknown status "$st" (verified, partial or unverified)""")
    }

    val toCheck = if whole then bibKeys else bibKeys.filter(citedKeySet)
    toCheck.foreach { key =>
      checkFields(k.profile.cite, key, bib, field, add)
      checkSourceFile(p, key, add)
    }

    // The ABNT CSL puts the disambiguation letter before the year (a2022) and on the access date too.
    val firstAuthor = mutable.LinkedHashMap[String, String]()
    val year = mutable.LinkedHashMap[String, String]()
    bib.foreach { r =>
      if r.field == "author" then firstAuthor(r.key) = r.value.replaceFirst(" and .*$", "").replaceFirst(",.*$", "").toLowerCase
      if r.field == "year" then year(r.key) = r.value
    }
    firstAuthor.keys.filter(year.contains).toList.groupBy(key => (firstAuthor(key), year(key))).toList
      .foreach { case ((a, y), keys) =>
        if keys.length > 1 then
          add(Warn, "refs.bib", s"${keys.length} entries with the first author $a and the year $y (${keys.mkString(" ")}): the CSL file letters them badly (a2022, and the access date too); check the list in the PDF, or tell the reviewer")
      }

    if whole then
      bibKeys.foreach { key =>
        if !rowKeys(key) then add(Fail, "REFERENCES.md", s"the key $key of refs.bib has no row")
        if !citedKeySet(key) then
          add(Fail, s"refs.bib:$key", s"the entry $key is cited by no section (the reference list would show it): remove it")
      }
      rows.map(_.asShellRead).foreach { r =>
        if !bibKeySet(r.key) then
          if r.status == SourceStatus.Unverified.render then add(Warn, s"REFERENCES.md:${r.key}", "unverified row with no refs.bib entry (fine: it may not be cited)")
          else add(Fail, s"REFERENCES.md:${r.key}", s"a row with the status ${r.status} and no entry in refs.bib")
      }
    rows.map(_.asShellRead).foreach { r =>
      if r.status == SourceStatus.Partial.render then
        val fields = unconfirmed(r.note)
        if fields.isEmpty then
          add(Fail, s"REFERENCES.md:${r.key}", """a partial row must say which detail is unconfirmed: "unconfirmed: field" in the Note""")
        else
          fields.split(" ").filter(_.nonEmpty).foreach { f =>
            if field(r.key, f).isDefined then
              add(Fail, s"refs.bib:${r.key}", s"the field $f is unconfirmed (REFERENCES.md) and must not be in the entry")
          }
    }

    val fails = out.count(_.level == Fail)
    val warns = out.count(_.level == Warn)
    out.distinct.sortBy(_.row).foreach(x => say(x.render))
    say(s"cite-check: ${p.slug}${sid.map("/" + _).getOrElse("")}: ${citedKeys.length} cited key(s), $fails fail, $warns warn")
    say("  Not checked by a machine: that a source supports the claim it is cited for. The reviewer reads sources/<key>.md for that.")
    say("  Not checked: the same key used with different meanings in two sections.")
    if fails == 0 then 0 else 1

  /** What a Note names after "unconfirmed:", commas as blanks; "" when it names nothing. */
  def unconfirmed(note: String): String =
    """.*[Uu]nconfirmed:[ ]*([A-Za-z, ]*).*""".r.unapplySeq(note).flatMap(_.headOption)
      .getOrElse("").replace(',', ' ')

  /** The fields that profile.json cite.bib_required names for the entry's type, the year, the DOI
    * and the URL.
    */
  private def checkFields(rules: CiteRules, key: String, bib: Vector[BibRow], field: (String, String) => Option[String],
      add: (Level, String, String) => Unit): Unit =
    val kind = bib.find(_.key == key).map(_.kind).getOrElse("")
    val required = rules.bibRequired.getOrElse(kind, Nil)
    if required.isEmpty then
      add(Warn, s"refs.bib:$key", s"entry type @$kind has no field rule in the profile: fields not checked")
    else
      required.foreach { r =>
        if !r.split('|').exists(alt => field(key, alt).isDefined) then
          add(Fail, s"refs.bib:$key", s"@$kind needs the field ${r.replace('|', ' ')} (NBR 6023)")
      }
    val y = field(key, "year").getOrElse("")
    if !y.matches("[0-9]{4}(-.*)?") then add(Fail, s"refs.bib:$key", s"""the year is not four digits: "$y"""")
    field(key, "doi").foreach { doi =>
      if rules.doiRegex.r.findFirstIn(doi).isEmpty then
        add(Fail, s"refs.bib:$key", s"""doi "$doi" is not a bare DOI (10.NNNN/suffix, no https://doi.org/ in front)""")
    }
    field(key, "url").foreach { url =>
      if field(key, "urldate").isEmpty then
        add(Fail, s"refs.bib:$key", "a url needs the access date (urldate = {YYYY-MM-DD}): NBR 6023")
      if !url.matches("^https?://[^ ]+$") then add(Fail, s"refs.bib:$key", s"""url "$url" is not an http(s) address""")
    }

  /** sources/<key>.md, the librarian's capture: URL, retrieval date, DOI check, a quoted passage. */
  private def checkSourceFile(p: Project, key: String, add: (Level, String, String) => Unit): Unit =
    val file = p.dir / Names.Sources / s"$key.md"
    val where = s"sources/$key.md"
    if !Kit.plainFile(file) then
      add(Fail, where, s"no capture file for the key $key (the librarian writes it: URL, retrieval date, quoted passages, DOI check)")
    else
      val lines = Prose.lines(os.read(file)).map(_.replace("*", "").replaceFirst("^[ \t]*[-+][ \t]+", "").replaceFirst("^[ \t]+", ""))
      def has(re: String, lower: Boolean = true) =
        lines.exists(l => re.r.findFirstIn(if lower then l.toLowerCase else l).isDefined)
      if !has("""^url:[ \t]*(https?://[^ \t]+|none)""") then add(Fail, where, "no line `URL: https://...` (or `URL: none` for a printed work)")
      if !has("""^retrieved:[ \t]*[0-9]{4}-[0-9]{2}-[0-9]{2}""") then add(Fail, where, "no line `Retrieved: YYYY-MM-DD`")
      if !has("""^doi check:[ \t]*[^ \t]""") then add(Fail, where, "no line `DOI check: ...` (say `none` when the work has no DOI)")
      if !has("""^>[ \t]*[^ \t]""", lower = false) then
        add(Fail, where, "no quoted passage (a line starting with >): the claim must rest on what the source says")

  /** Groups by key, in the order each key first appears. */
  def groupsInOrder[A](xs: Seq[A])(key: A => String): List[(String, Seq[A])] =
    val g = xs.groupBy(key)
    xs.map(key).distinct.map(k => k -> g(k)).toList

/** `thesis cite-score <slug> <id> [--strict]`: the share of sentences with a citation mark, against
  * the target of the section's cite_class.
  */
object CiteScore:
  def run(k: Kit, args: List[String]): Int =
    val strict = args.contains("--strict")
    val rest = args.filter(_ != "--strict").flatMap(_.split("[ \t\n]+").filter(_.nonEmpty))
    rest match
      case List(slug, id) => score(k, Gate(k, slug, id), strict)
      case _              => fail("usage: thesis cite-score <slug> <id> [--strict]")

  private def score(k: Kit, g: Gate, strict: Boolean): Int =
    val cls = g.sec.citeClass
    val rules = k.profile.cite
    val target = rules.scoreTargets.getOrElse(cls,
      fail(s"""${g.p.slug}/${g.sec.id}: cite_class "$cls" is not in profile.json cite.score_targets"""))
    val counted = g.prose.filter(s => s.isProse && s.words >= rules.scoreMinWords.toInt)
    val (marked, unmarked) = counted.partition(s => "§[CNDUF]§".r.findFirstIn(s.text).isDefined ||
      Cites.Hand.findFirstIn(s.text).isDefined)
    val n = counted.length
    val pct = if n == 0 then "0.0" else fixed(100.0 * marked.length / n, 1)
    val ok = n == 0 || pct.toDouble / 100 >= target
    say(s"cite-score: ${g.p.slug}/${g.sec.id}: ${marked.length} of $n sentences of ${Profile.show(rules.scoreMinWords)} words or more carry a citation mark = $pct % (class $cls, target >= ${fixed(target * 100, 0)} %): ${if ok then "OK" else "BELOW TARGET"}")
    say("  It counts marks ([@key], DOI, URL, footnote, (Author, 2016)), not truth. 100 % is not the goal: Resultados and Conclusões own their results.")
    if !ok then
      say("  sentences with no mark (first 5; line, text):")
      unmarked.take(5).foreach(s => say(s"    line ${s.line}: ${Text.take(s.text, 100)}"))
    if !strict || ok then 0 else 1
