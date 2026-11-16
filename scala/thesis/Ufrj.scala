package piabrota.thesis

import Text.{awkNum, padBytes, upcase}

/** `thesis ufrj-check <slug>`: gate 3, the patterns of the UFRJ final project on the whole work.
  * Every rule prints PASS, FAIL or CANNOT-CHECK with its source:
  *   R = Resolução nº 05/2012 of the Escola Politécnica, Anexo "Normas de Elaboração Gráfica" (in force)
  *   N = Norma Gráfica 2026 (a proposal for the Congregação; the 2012 text stays in force until approved)
  *   M = SiBI Manual for UFRJ academic works, 9th ed. (read only as search snippets)
  */
object Ufrj:
  enum Outcome:
    case Pass, Fail, CannotCheck
    def render: String = this match
      case Pass        => "PASS"
      case Fail        => "FAIL"
      case CannotCheck => "CANNOT-CHECK"

  /** Prints each rule as it is checked and counts the outcomes. */
  private final class Tally:
    import Outcome.*
    private val counts = scala.collection.mutable.Map[Outcome, Int]().withDefaultValue(0)
    def apply(o: Outcome, source: String, id: String, rule: String, detail: String): Unit =
      counts(o) += 1
      say(s"${padBytes(o.render, 12)} ${padBytes(s"[$source]", 22)} ${padBytes(id, 4)} $rule: $detail")
    def check(ok: Boolean, source: String, id: String, rule: String, yes: String, no: String): Unit =
      if ok then apply(Pass, source, id, rule, yes) else apply(Fail, source, id, rule, no)
    def checkSources(ok: Boolean, pass: String, fail: String, id: String, rule: String, yes: String, no: String): Unit =
      if ok then apply(Pass, pass, id, rule, yes) else apply(Fail, fail, id, rule, no)
    def cannot(source: String, id: String, rule: String, detail: String): Unit = apply(CannotCheck, source, id, rule, detail)
    def count(o: Outcome): Int = counts(o)

  def run(k: Kit, args: List[String]): Int =
    if args.length != 1 then fail("usage: thesis ufrj-check <slug>")
    BuildCommands.needTools("pdftotext", "pdfinfo")
    val p = k.project(args.head)
    val tpl = Template.of(k, p)
    val uf = Tally()
    say(s"ufrj-check: ${p.slug}")
    say("  R = Resolução nº 05/2012 (in force). N = Norma Gráfica 2026 (a proposal, not in force). M = SiBI Manual 9th ed. (read only as snippets).")
    val live = p.live

    // --- rules from thesis.json alone
    uf.checkSources(p.isPtBr, "R intro; N 6.1", "R intro; N 6.1", "U01", "language",
      "Portuguese (pt-BR)", "the work is written in Portuguese; English or Spanish need a justification to the Curso")
    val course = p.course
    val courseOf = k.profile.courses.find(_.name == course)
    uf.checkSources(courseOf.isDefined, "N 5.1, 5.2", "N 5.1", "U02", "course",
      s""""$course" is a course of the Escola Politécnica ("Curso de $course" form in every sheet is checked below)""",
      s""""$course" is not in the list of courses""")
    val degree = courseOf.flatMap(_.title).getOrElse("")
    uf.check(p.isAuthorDate, "R 3.1; N 9.1", "U03", "citation-system",
      "author-date for the whole work (one CSL file, one reference list)", "one system for the whole work: author-date")
    val numbered = p.orderIds.map(p.sectionFile).filter(Kit.plainFile).map(f => Cites(os.read(f), 9999).numbered.length).sum
    uf.check(numbered == 0, "R 3.1", "U04", "no-numbered-citations", "no [n] citation in any section",
      s"$numbered numbered citation(s): the system is author-date")
    val missingParts = RequiredParts.filterNot(part => live.exists(_.str(SectionKey.Part).contains(part)))
    uf.check(missingParts.isEmpty, "R §2", "U05", "textual-parts",
      "Introdução, Revisão da Literatura, Metodologia, Resultados and Conclusões are there (Discussão may be grouped with Resultados)",
      s"no section for:${missingParts.map(" " + _).mkString} (field part in thesis.json)")
    uf.check(live.exists(_.is(Role.Resumo)) && live.exists(_.is(Role.Abstract)), "R §1 g; N 7.1", "U06",
      "resumo-and-abstract", "both sections are in the work", "the work needs a resumo and an abstract")
    def order(kind: Kind, pick: Seq[Double] => Double) =
      val orders = live.filter(_.kind.contains(kind)).flatMap(_.order.flatMap(_.numOpt))
      if orders.isEmpty then 0.0 else pick(orders)
    uf.check(order(Kind.Pretextual, _.max) < order(Kind.Textual, _.min), "R §1, §2", "U07", "order-of-parts",
      "pre-textual, textual, post-textual sections are in that order", "a pre-textual section has a higher order than a textual one")

    // --- rules that need the built PDF
    val pdf = p.build / Names.ThesisPdf
    if !Kit.plainFile(pdf) then
      uf.cannot("-", "U10", "pdf", "no build/thesis.pdf: run thesis assemble, then ufrj-check again")
      return summary(p, uf)
    val text = os.proc("timeout", "-k", "5", k.popplerTimeout, "pdftotext", "-layout", pdf.toString, "-")
      .call(stdin = "", stdout = os.Pipe, stderr = os.Inherit, check = false)
    if text.exitCode != 0 then fail(s"${p.slug}: pdftotext failed")
    val pages = Poppler.pages(text.out.text())
    // Only the pages with text count, as the shell version kept a file for those only.
    val shown = pages.zipWithIndex.collect { case (pg, i) if pg.exists(c => c != ' ' && c != '\t' && c != '\n') => (i + 1) -> pg }.toMap
    val count = shown.size
    def raw(n: Int): Option[String] = shown.get(n).map(_ + "\n")
    def squash(s: String) = s.replace('\n', ' ').replaceAll("[ \t]+", " ").stripPrefix(" ").stripSuffix(" ")
    def pageHas(n: Int, s: String) = raw(n).exists(squash(_).contains(s))
    def firstPage(s: String): Option[Int] = (1 to count).find(n => raw(n).exists(_.split("\n").exists(_.contains(s))))
    def lastLine(n: Int): String =
      raw(n).toList.flatMap(_.split("\n")).filter(_.exists(c => c != ' ' && c != '\t')).lastOption
        .map(_.replaceAll("^[ \t]+|[ \t]+$", "")).getOrElse("")
    val courseUp = upcase(course)
    val title = p.title
    val titleUp = upcase(title)
    val year = p.year
    val month = BuildCommands.monthName(p).getOrElse("")
    val monthUp = upcase(month)

    // capa (page 1)
    if pageHas(1, "UNIVERSIDADE FEDERAL DO RIO DE JANEIRO") && pageHas(1, "ESCOLA POLITÉCNICA") && pageHas(1, s"CURSO DE $courseUp") && pageHas(1, titleUp) then
      val lines = raw(1).toList.flatMap(_.split("\n"))
      def lineOf(s: String) = Some(lines.indexWhere(_.contains(s))).filter(_ >= 0)
      val inOrder = (lineOf("UNIVERSIDADE FEDERAL"), lineOf("ESCOLA POLITÉCNICA"), lineOf(s"CURSO DE $courseUp")) match
        case (Some(a), Some(b), Some(c)) => a < b && b < c
        case _                           => false
      uf.checkSources(inOrder, "N 3.3; R §1 a", "N 3.3", "U10", "capa",
        "the institution in three capital lines (UFRJ, Escola Politécnica, Curso de ...) and the title", "the three institution lines are not in order")
    else uf(Outcome.Fail, "N 3.3; R §1 a", "U10", "capa", "page 1 lacks the three capital lines or the title")
    val logo = p.logo.getOrElse("")
    uf.check(logo.nonEmpty && Kit.plainFileAt(p.dir, logo), "N 3.1", "U11", "capa-logos",
      s"UFRJ logo ($logo) left and the Poli logo right, same height (by construction of the overlay; the look is not measured)",
      "no UFRJ logo: put the file under assets/ and set assets.ufrj_logo in thesis.json (the toolkit does not carry the UFRJ mark)")
    val mainTex = p.build / Names.Tex / "pt" / "main.tex"
    val (images, onCover) =
      if !os.isFile(mainTex) then ("", "")
      else
        val lines = Prose.lines(os.read(mainTex))
        var on = false
        val cover = lines.count { l =>
          if l.contains("% --- Capa") then on = true
          if l.contains("% --- Folha de rosto") then on = false
          on && l.contains("includegraphics")
        }
        (lines.count(_.contains("includegraphics")).toString, cover.toString)
    uf.check(images.nonEmpty && images == onCover && awkNum(onCover) <= 2, "N 3.2, 4.1", "U12", "no-other-logo",
      s"the only images the overlay places are on the cover ($onCover); no logo on the folha de rosto or de aprovação",
      s"$images images in the front pages, $onCover on the cover")
    uf.cannot("N 3.2", "U13", "figures-are-not-logos", "whether a figure inside a chapter is a logo cannot be told by a script")

    // folha de rosto (page 2): the natureza sentence of norma 4.2
    val natureza = s"Projeto de Graduação apresentado ao Curso de $course da Escola Politécnica, Universidade Federal do Rio de Janeiro, como requisito parcial à obtenção do título de $degree."
    uf.check(pageHas(2, natureza), "N 4.2; R §1 b", "U14", "natureza",
      "the sentence of norma 4.2 is on the folha de rosto, with the course and the title conferred", s"""the sentence "$natureza" is not on page 2""")
    uf.check(pageHas(2, s"$month de $year"), "R §1 b", "U15", "rosto-date", "month and year of the defence", s""""$month de $year" is not on page 2""")
    // folha de aprovação (page 3)
    uf.check(pageHas(3, "Examinada por") && pageHas(3, "RIO DE JANEIRO, RJ") && pageHas(3, s"$monthUp DE $year") && pageHas(3, titleUp),
      "R Anexo III", "U16", "aprovacao",
      """title in capitals, "Examinada por", the city and state in capitals, the month and year in capitals""",
      """page 3 lacks the title in capitals, "Examinada por", the city or the date in capitals""")
    val hyphens = raw(3).map(_.split("\n").count(_.matches(".*-[ ]*"))).map(_.toString).getOrElse("")
    uf.check(hyphens == "0", "R Anexo III item 9", "U17", "aprovacao-no-hyphenation",
      "no line of the folha de aprovação ends in a hyphen", s"$hyphens line(s) end in a hyphen")
    val last3 = lastLine(3)
    uf.check(last3.isEmpty || last3.exists(c => !"0123456789ivxl".contains(c)), "R Anexo III item 1", "U18", "aprovacao-no-number",
      s"""no page number (the last line is "$last3")""", s"the last line is a page number: $last3")
    // ficha catalográfica (page 4): a placeholder; the card is not made here
    uf.check(pageHas(4, "FICHA CATALOGRÁFICA") && pageHas(4, "fichacatalografica.sibi.ufrj.br"), "R §1 d; N 8.1", "U19", "ficha-sheet",
      "a sheet for the ficha catalográfica is in the right place (placeholder)", "page 4 is not the ficha sheet")
    uf.cannot("R §1 d; N 8.1", "U20", "ficha-card",
      "the card itself comes from the SiBI generator (http://fichacatalografica.sibi.ufrj.br/) and is put on that sheet by a person; it is not invented here")

    // order of the pre-textual sheets
    val chapters = live.filter(_.is(Role.Chapter)).map(_.title)
    val pRes = firstPage("RESUMO")
    val pAbs = firstPage("ABSTRACT")
    val pToc = firstPage("Sumário")
    val pCh = Poppler.pageWithLine(pages, pToc.getOrElse(0) + 1, chapters.headOption.getOrElse("null"))
    val pRef = Poppler.pageWithLine(pages, pCh.getOrElse(0) + 1, "Referências Bibliográficas")
    def show(o: Option[Int]) = o.map(_.toString).getOrElse("-")
    val inOrder = (pRes, pAbs, pToc, pCh, pRef) match
      case (Some(a), Some(b), Some(c), Some(d), Some(e)) => 4 < a && a < b && b < c && c < d && d < e
      case _                                             => false
    uf.check(inOrder, "R §1, §2, §3; N 7.1", "U21", "order",
      s"capa, folha de rosto, aprovação, ficha, resumo (p. ${show(pRes)}), abstract (p. ${show(pAbs)}), sumário (p. ${show(pToc)}), chapters (p. ${show(pCh)}), referências (p. ${show(pRef)})",
      s"the sheets are not in the order capa, rosto, aprovação, ficha, resumo, abstract, sumário, chapters, referências (found: resumo ${show(pRes)}, abstract ${show(pAbs)}, sumário ${show(pToc)}, chapter ${show(pCh)}, referências ${show(pRef)})")
    // resumo and abstract: own sheet, reference, up to 250 words, keywords
    val max = k.profile.words.resumoMax
    val grad = s"Graduação em $course"
    List((Role.Resumo, pRes, "Palavras-chave", "ABSTRACT"), (Role.Abstract, pAbs, "Keywords", "RESUMO")).foreach { (role, pg, kw, other) =>
      val kind = role.render
      pg.foreach { n =>
        val own = !pageHas(n, other)
        val before = raw(n).toList.flatMap(_.split("\n")).filterNot(_.matches("^[ \t]*$")).map(_.replaceAll("^[ \t]+|[ \t]+$", ""))
          .takeWhile(!_.startsWith(kw))
        val words = before.flatMap(_.split("[ \t]+")).count(w => s"[${Prose.Alnum}]".r.findFirstIn(w).isDefined)
        val id = s"U22${kind.head}"
        uf.check(own && pageHas(n, kw) && pageHas(n, grad), "N 7.1, 7.2, 5.2 d", id, s"$kind-sheet",
          s"""own sheet, title, reference with "$grad", text, keywords (the page holds about $words words with the title and the reference)""",
          s"""the $kind sheet is not alone, or lacks "$kw" or "$grad"""")
        live.find(_.is(role)).map(_.id).flatMap(sid => ProjectCommands.wordCount(k, p.sectionFile(sid))).foreach { wc =>
          uf.check(wc <= max, "R §1 g; N 7.3", s"U23${kind.head}", s"$kind-words", s"$wc words, at most $max", s"$wc words, over $max")
        }
      }
    }
    // roman numbers in the pre-textual part, arabic after
    val romanOk = (pRes.getOrElse(5) until pCh.getOrElse(0)).takeWhile(_ <= count).forall(n => lastLine(n) == roman(n))
    val arabic = lastLine(pCh.getOrElse(1))
    uf.checkSources(romanOk && arabic == "1", "R §1 (last paragraph), §2", "R §1, §2", "U24", "numbering",
      "roman numerals (i, ii, ...) from the resumo to the sumário, arabic from the first chapter, which is page 1",
      s"""the pre-textual pages are not numbered i, ii, ... or the first chapter is not page 1 (last line of that page: "$arabic")""")
    // the table of contents names every chapter with a number
    val toc = pToc.flatMap(raw).map(squash)
    val tocOk = chapters.filter(_.nonEmpty).forall { c =>
      val escaped = c.replaceAll("""([\]\[\\.*^$/])""", """\\$1""")
      toc.exists(s => s"[0-9]+ +$escaped".r.findFirstIn(s).isDefined)
    }
    uf.check(tocOk, "R §1 h, §2", "U25", "sumario", "the sumário lists every chapter with its number",
      "a chapter is missing from the sumário page (or not numbered)")
    uf.check(pRef.isDefined, "R §3", "U26", "referencias", """the list "Referências Bibliográficas" is after the last chapter""",
      """no "Referências Bibliográficas" heading""")
    uf.cannot("R §3.1; N 9.2 (NBR 6023:2025, NBR 10520:2023)", "U27", "reference-form",
      "the form of each reference and of each in-text mark follows the CSL file (an ABNT author-date style whose accuracy against the 2023 and 2025 norms is unverified); only cite-check's field rules are checked")

    // figures and tables: numbered, cited, caption above (table) and below (figure)
    val sectionsTex = p.build / Names.Tex / "pt" / Names.Sections
    val texFiles = if os.isDir(sectionsTex) then Text.sortC(os.list(sectionsTex).map(_.last).filter(_.matches("s.*\\.tex"))).map(sectionsTex / _) else Nil
    val captionDetail = texFiles.filter(os.isFile(_)).flatMap { f =>
      val (badT, badF) = captions(Prose.lines(os.read(f)))
      Option.when(badT != 0 || badF != 0)(s" ${f.last}:$badT $badF")
    }
    uf.check(captionDetail.isEmpty, "R §4", "U28", "caption-position",
      "table captions above, figure captions below (checked in the LaTeX of every section)", s"a caption is on the wrong side:${captionDetail.mkString}")
    val uncited = live.map(s => p.sectionFile(s.id)).filter(Kit.plainFile)
      .map(f => LintScan(os.read(f), None, k.profile.lists.allowedChars, Nil).uncited("fig", "tbl").length).sum
    uf.check(uncited == 0, "R §4", "U29", "figures-tables-cited",
      "every figure and table has a number (LaTeX) and is cited in its section", s"$uncited figure(s) or table(s) never cited")

    // the layout, from pdf-qa
    val qaFile = p.build / Names.QaJson
    if !os.isFile(qaFile) then uf.cannot("R intro", "U30", "layout", "no build/qa.json: run thesis pdf-qa")
    else
      val q = ujson.read(os.read(qaFile))
      def qv(path: String) = J.raw(J.path(q, path))
      uf.check(qv(QaKey.PageSizeOk) == "true", "R intro", "U30", "a4", "every page is A4 (210 x 297 mm)", s"${qv(QaKey.PagesNotA4)} page(s) are not A4")
      val Sides(mt, mb, ml, mr) = Sides.Names.map(side => qv(s"${QaKey.MinMargins}.$side"))
      uf.check(qv(QaKey.MarginsOk) == "true", "R Anexo VII", "U31", "margins",
        s"smallest margins top $mt, bottom $mb, left $ml, right $mr mm; minimum 25, 25, 30, 30 (text boxes only; page numbers excluded)",
        s"a margin is under the minimum 25, 25, 30, 30 mm: top $mt, bottom $mb, left $ml, right $mr")
      val sp = J.path(q, QaKey.LineSpacing).filterNot(J.falsy).map(J.rawValue).getOrElse("0")
      val page = k.profile.page
      val spt = page.lineSpacingTolerance
      val s = awkNum(sp)
      uf.check((s >= 1.5 - spt && s <= 1.5 + spt) || (s >= 2 - spt && s <= 2 + spt), "R intro; M", "U32", "spacing",
        s"line pitch of the body ${qv(QaKey.LinePitch)} pt = $sp x the single spacing of 12 pt type (1.5 or 2 allowed)",
        s"measured spacing $sp is not 1.5 or 2")
      val fam = qv(QaKey.BodyFamily)
      val size = qv(QaKey.BodySize)
      val famOk = page.fontFamiliesOk.exists(f => s"(?i)$f".r.findFirstIn(fam).isDefined)
      val want = Profile.show(page.bodyFontPt)
      uf.check(famOk && size == want, "R intro; N 2.1, 2.2", "U33", "font",
        s"""body font $fam at $size pt: a Times clone (TeX Gyre Termes) for "Times New Roman 12"""",
        s"body font $fam at $size pt; wanted a Times or Arial clone at $want pt")
      val biggest = qv(QaKey.MaxFontSize)
      uf.check(awkNum(biggest) <= page.titleFontMaxPt, "R intro", "U34", "title-size",
        s"the largest type is $biggest pt, at most ${Profile.show(page.titleFontMaxPt)} (Times 24)", s"a type of $biggest pt is over the title limit")
      uf.check(qv(QaKey.NonBlackFonts) == "0", "R §2", "U35", "black-text",
        "every font colour in the PDF is black (hyperref uses no coloured links)", s"${qv(QaKey.NonBlackFonts)} font(s) are not black")
    uf.cannot("R §2, §4", "U36", "figure-colour", "colour inside figures is not read; figures should read in black and white")
    val main = tpl.dir / "pinned" / "pt" / "project_main.tex"
    uf.check(os.isFile(main) && os.read(main).contains("oneside"), "R intro", "U37", "one-sided",
      "the class option oneside of the pinned template (pre- and post-textual one-sided)", "the template is not oneside")
    val ragged = texFiles.count(f => os.isFile(f) && "raggedright|flushleft|raggedleft".r.findFirstIn(os.read(f)).isDefined)
    uf.check(ragged == 0, "R intro", "U38", "justified", "no section turns justification off (the body is justified by default)",
      s"$ragged section file(s) set the alignment")
    uf.cannot("R intro", "U39", "originality",
      "that the work is original and credits third parties is for the author and the examiners; cite-check only checks that sources are recorded")
    uf.cannot("R intro", "U40", "spelling", "the current orthography is not checked by a script")
    uf.cannot("M", "U41", "manual",
      "the SiBI Manual (9th ed., 2025) was read only as search snippets; its rules (single spacing in quotes, footnotes, references and captions) are applied by the overlay, not checked against the full text")
    summary(p, uf)

  private def summary(p: Project, uf: Tally): Int =
    say(s"ufrj-check: ${p.slug}: ${uf.count(Outcome.Pass)} pass, ${uf.count(Outcome.Fail)} fail, ${uf.count(Outcome.CannotCheck)} cannot-check")
    if uf.count(Outcome.Fail) == 0 then 0 else 1

  /** Roman numerals in lower case, up to 39. */
  def roman(n: Int): String =
    val tens = List("", "x", "xx", "xxx", "xl").lift(n / 10).getOrElse("")
    val ones = List("", "i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix")(n % 10)
    tens + ones

  /** Table captions that are not right after \begin{longtable}, figure captions before the image. */
  def captions(lines: Seq[String]): (Int, Int) =
    var (badT, badF) = (0, 0)
    var (afterTable, inFigure, image) = (false, false, false)
    lines.foreach { l =>
      if l.startsWith("\\begin{longtable}") then afterTable = true
      else
        if afterTable then
          if !l.startsWith("\\caption{") then badT += 1
          afterTable = false
        if l.startsWith("\\begin{figure}") then { inFigure = true; image = false }
        else
          if inFigure && l.contains("\\includegraphics") then image = true
          if inFigure && l.startsWith("\\caption{") then
            if !image then badF += 1
            inFigure = false
    }
    (badT, badF)
