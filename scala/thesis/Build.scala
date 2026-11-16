package piabrota.thesis

import scala.collection.mutable.ArrayBuffer
import piabrota.lib.Sh
import Text.{awkNum, fixed}

/** pandoc turns markdown into LaTeX and fills the front pages from thesis.json; pdfLaTeX makes the
  * PDF. No network, no shell escape, a time limit on every pandoc and TeX call.
  */
object Tex:
  /** The reader: raw TeX, raw attributes, raw HTML, YAML blocks, TeX macros and automatic identifiers
    * are off, so what the author writes is text and markdown, never TeX. Math is the one place that
    * reaches TeX as written; filters/thesis.lua allows only listed macros.
    */
  val From = "markdown-raw_tex-raw_attribute-raw_html-yaml_metadata_block-latex_macros-auto_identifiers"

  /** `pd`: pandoc, timed, with its messages kept in pandoc.err. */
  def pandoc(k: Kit, args: Seq[String]): Int =
    System.out.flush()
    val cmd = k.timed(Seq("timeout", "-k", "5", k.pandocTimeout, "pandoc", "--fail-if-warnings") ++ args)
    val code = os.proc(cmd).call(env = k.childEnv, stdin = "", stdout = os.Inherit,
      stderr = os.PathRedirect(k.tmp / "pandoc.err"), check = false).exitCode
    if code == 124 || code == 137 then note(s"pandoc stopped: no result after ${k.pandocTimeout} s")
    code

  /** `pd_fail`: pandoc's messages, then the refusal. */
  def pandocFail(k: Kit, what: String): Nothing =
    System.out.flush()
    Prose.lines(os.read(k.tmp / "pandoc.err")).foreach(l => System.err.println(s"  pandoc: $l"))
    fail(what)

  /** A title or a name for a chapter command, escaped by pandoc. */
  def escape(k: Kit, text: String): String =
    val r = os.proc("timeout", "-k", "5", k.pandocTimeout, "pandoc", "-f", From, "-t", "latex", "--wrap=none")
      .call(env = k.childEnv, stdin = text + "\n", stdout = os.Pipe, stderr = os.Inherit, check = false)
    r.out.text().replace('\n', ' ').replaceAll(" *$", "")

  /** `make_fragment`: the LaTeX of one section. Mode final cites every work through nocite and
    * prints no list; preview puts the section's own references at its end.
    */
  def fragment(k: Kit, p: Project, sec: Section, tpl: Template, out: os.Path, preview: Boolean): Unit =
    val id = sec.id
    val ids = p.sections.map(_.id).mkString(",")
    val meta = k.tmp / s"meta-$id.yaml"
    os.write.over(meta, s"section-id: '$id'\nsection-ids: '$ids'\nlang: pt-BR\n" +
      (if preview then "" else "nocite: '@*'\nsuppress-bibliography: true\n"))
    val csl = cslFile(k, tpl)
    if !os.isFile(csl) then fail(s"the CSL file is missing: $csl")
    val body = k.tmp / s"frag-$id.body"
    val code = pandoc(k, Seq("-f", From, "-t", "latex", "--wrap=none", "--top-level-division=chapter",
      "--shift-heading-level-by=1", "--no-highlight", "--lua-filter", (k.filters / "thesis.lua").toString,
      "--metadata-file", meta.toString, "--bibliography", p.refsBib.toString, "--csl", csl.toString,
      "--citeproc", "-o", body.toString, p.sectionFile(id).toString))
    if code != 0 then pandocFail(k, s"${p.slug}/$id: pandoc refused the section (the messages above; every warning fails the build)")
    val chapter = sec.role match
      case Some(Role.Chapter | Role.Appendix) => s"\\chapter{${escape(k, sec.title)}}\\label{ch:$id}\n"
      case _                                  => ""
    val text = os.read(body)
    val shown =
      if !preview then text
      else text.split("\n", -1).map { l =>
        if l == "\\protect\\phantomsection\\label{refs}" then s"\\chapter*{Referências Bibliográficas}\n$l" else l
      }.mkString("\n")
    val tmp = out / os.up / s"${out.last}.tmp"
    os.write.over(tmp, chapter + shown)
    os.move(tmp, out, replaceExisting = true)

  /** The template's CSL file in share/thesis/csl. */
  def cslFile(k: Kit, tpl: Template): os.Path = k.share / "csl" / tpl.csl

  /** `tex_tree`: dir/shared (pinned), dir/overlay, dir/assets, dir/figures and dir/pt to build in. */
  def tree(p: Project, tpl: Template, dir: os.Path): Unit =
    List("pt/sections", "overlay", "assets").foreach(d => os.makeDir.all(dir / os.RelPath(d)))
    tpl.pinnedDirs.foreach { d =>
      val src = tpl.dir / "pinned" / os.RelPath(d)
      if !os.isDir(src) then fail(s"template ${tpl.name}: the pinned folder $d is missing ($src)")
      Kit.copyTree(src, dir / os.RelPath(d))
    }
    Kit.ownerWritable(dir)
    tpl.preamble.foreach { f =>
      val src = tpl.dir / os.RelPath(f)
      if !os.isFile(src) then fail(s"template ${tpl.name}: the overlay file $f is missing")
      os.copy.over(src, dir / "overlay" / src.last)
    }
    if os.isDir(p.dir / Names.Figures) then Kit.copyTree(p.dir / Names.Figures, dir / Names.Figures)
    Kit.ownerWritable(dir)

  /** The \documentclass line of the template's pinned main file. */
  def documentclassLine(tpl: Template): String =
    val main = tpl.dir / os.RelPath(tpl.documentclassFrom)
    if !os.isFile(main) then fail(s"template ${tpl.name}: the main file $main is missing")
    Prose.lines(os.read(main)).find(_.startsWith("\\documentclass"))
      .getOrElse(fail(s"template ${tpl.name}: no \\documentclass line in the main file"))

  /** The page of the template filled by pandoc: main.latex or preview.latex. */
  def page(k: Kit, tpl: Template, template: String, metadata: os.Path, out: os.Path): Int =
    pandoc(k, Seq("-f", From, "-t", "latex", "-s", "--template", (tpl.dir / "overlay" / template).toString,
      "--metadata-file", metadata.toString, "-V", s"documentclass-line=${documentclassLine(tpl)}", "-V", "tables=true",
      "-V", "graphics=true", "-V", "csl-refs=true", "-V", "indent=true", "-o", out.toString))

  /** `run_tex`: pdfLaTeX passes until the references settle; true when main.pdf is made. */
  def run(k: Kit, dir: os.Path): Boolean =
    val passes = k.profile.limits.texPassesMax
    val settled = (1 to passes).iterator.map { n =>
      System.out.flush()
      val cmd = k.timed(Seq("timeout", "-k", "5", k.texTimeout, "nice", "-n", "10", "pdflatex", "-no-shell-escape",
        "-interaction=nonstopmode", "-halt-on-error", "-file-line-error", "main.tex"))
      val code = os.proc(cmd).call(cwd = dir, env = k.childEnv + ("HOME" -> k.tmp.toString), stdin = "",
        stdout = os.PathRedirect(dir / "tex-run.out"), mergeErrIntoOut = true, check = false).exitCode
      if code == 124 || code == 137 then
        note(s"pdflatex stopped: no result after ${k.texTimeout} s (pass $n)")
        Some(false)
      else if code != 0 then
        note(s"pdflatex failed (pass $n). The first errors:")
        Text.grepContext(Prose.lines(readLog(dir / "tex-run.out")), """^[^ ]+:[0-9]+:|^!""".r, 6, 3)
          .foreach(l => System.err.println(s"  tex: $l"))
        Some(false)
      else if """Rerun to get|Label\(s\) may have changed|Please \(re\)run""".r.findFirstIn(readLog(dir / Names.MainLog)).isEmpty then
        Some(true)
      else None
    }.collectFirst { case Some(ok) => ok }
    settled.getOrElse {
      note(s"the references did not settle in $passes passes")
      false
    }

  /** Problems that a TeX run that succeeded can still have, at most 10 lines. */
  def logFindings(log: os.Path): List[String] =
    val re = """LaTeX Warning: (Reference|Citation) .* undefined|Missing character|Undefined control sequence|LaTeX Warning: There were undefined references|Package hyperref Warning: Token not allowed""".r
    Prose.lines(readLog(log)).filter(l => re.findFirstIn(l).isDefined).take(10).toList

  /** A TeX log is bytes, not always UTF-8: a bad sequence becomes U+FFFD. */
  def readLog(f: os.Path): String =
    if os.isFile(f) then new String(os.read.bytes(f), java.nio.charset.StandardCharsets.UTF_8) else ""

  def pdfPages(pdf: os.Path): String =
    Sh.outOpt("pdfinfo", pdf).toList.flatMap(Prose.lines).collectFirst {
      case l if l.startsWith("Pages:") => l.split("\\s+").lift(1).getOrElse("")
    }.getOrElse("")

/** `thesis build-section`, `assemble`, `pdf-qa` and `publish`. */
object BuildCommands:
  import Tex.*

  def needTools(tools: String*): Unit =
    tools.foreach(t => if Sh.which(t).isEmpty then fail(s"missing tool: $t"))

  /** `thesis build-section <slug> <id>`: build/<id>.tex and a one-section preview PDF. */
  def buildSection(k: Kit, args: List[String]): Int =
    if args.length != 2 then fail("usage: thesis build-section <slug> <id>")
    needTools("pandoc", "pdflatex")
    val g = Gate(k, args(0), args(1))
    val (p, sec) = (g.p, g.sec)
    val slugId = s"${p.slug}/${sec.id}"
    val tpl = Template.of(k, p)
    val build = p.build
    os.makeDir.all(build)
    val work = Kit.tempDir(build, ".work.").getOrElse(fail(s"cannot make a folder in $build"))
    try
      val bad = LintScan(g.text, sec.role, k.profile.lists.allowedChars, Nil).findings
        .filter(f => f.level == Level.Fail && f.rule == LintRule.Character)
      if bad.nonEmpty then
        bad.take(3).foreach(f => note(s"line ${f.line}: ${f.message}"))
        fail(s"$slugId: the text has characters the PDF engine cannot set (see above)")
      tree(p, tpl, work / Names.Tex)
      fragment(k, p, sec, tpl, build / s"${sec.id}.tex", preview = false)
      fragment(k, p, sec, tpl, work / Names.Tex / "pt" / Names.Sections / "frag.tex", preview = true)
      val pretext = sec.role.exists(_.pretext)
      val meta = k.tmp / "preview.json"
      os.write.over(meta, J.pretty(ujson.Obj("section-title" -> sec.title, "pretext" -> pretext)))
      if page(k, tpl, Names.PreviewLatex, meta, work / Names.Tex / "pt" / "main.tex") != 0 then
        pandocFail(k, s"$slugId: pandoc cannot make the preview page")
      val t0 = Kit.nowS()
      val pt = work / Names.Tex / "pt"
      val log = build / s"${sec.id}.preview.log"
      if !run(k, pt) then
        scala.util.Try(os.copy.over(pt / Names.MainLog, log))
        fail(s"$slugId: the preview did not build (log: build/${sec.id}.preview.log)")
      // An @cap: reference points at another chapter: open in a preview, resolved in the whole work.
      val found = logFindings(pt / Names.MainLog)
      val real = found.filterNot(l => """Reference .ch:[^']*' .*undefined|There were undefined references""".r.findFirstIn(l).isDefined)
      if real.nonEmpty then
        os.copy.over(pt / Names.MainLog, log)
        System.out.flush()
        real.foreach(l => System.err.println(s"  tex: $l"))
        fail(s"$slugId: the preview has unresolved references or missing characters (log: build/${sec.id}.preview.log)")
      if found.nonEmpty then note("the references to other chapters stay open in the preview; they resolve in the whole work")
      val pdf = build / s"${sec.id}.preview.pdf"
      os.copy.over(pt / "main.pdf", build / s"${sec.id}.preview.pdf.tmp")
      os.move(build / s"${sec.id}.preview.pdf.tmp", pdf, replaceExisting = true)
      val pages = Some(pdfPages(pdf)).filter(_.nonEmpty).getOrElse("?")
      k.log(p, None, s"build-section ${sec.id}: $pages page(s), ${Kit.nowS() - t0} s")
      say(s"thesis: $slugId: build/${sec.id}.tex and build/${sec.id}.preview.pdf ($pages pages)")
      0
    finally os.remove.all(work)

  private val Months = List("janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho", "agosto", "setembro",
    "outubro", "novembro", "dezembro")

  def monthName(p: Project): Option[String] =
    p.field(ThesisKey.Month).flatMap(_.numOpt).map(_.toInt - 1).flatMap(Months.lift)

  /** `thesis assemble <slug>`: every section accepted by a verdict, the gates of the whole work,
    * then the PDF and pdf-qa.
    */
  def assemble(k: Kit, args: List[String]): Int =
    if args.length != 1 then fail("usage: thesis assemble <slug>")
    needTools("pandoc", "pdflatex", "pdfinfo")
    val p = k.project(args.head)
    val slug = p.slug
    val tpl = Template.of(k, p)
    val t0 = Kit.nowS()
    val problems = Validate.problems(p.json, k.profile, `final` = true).getOrElse(fail(s"$slug: thesis.json cannot be checked"))
    if problems.nonEmpty then
      System.out.flush()
      problems.foreach(x => System.err.println(s"  thesis.json: $x"))
      fail(s"$slug: thesis.json is not ready (see above)")
    val notAccepted = p.orderIds.flatMap { id =>
      val st = ProjectCommands.sectionStatus(k, p, k.section(p, id)).state
      Option.when(st != SectionState.Accepted)(s"  $id is ${st.render}")
    }
    if notAccepted.nonEmpty then
      System.out.flush()
      notAccepted.foreach(System.err.println)
      fail(s"$slug: not every section is accepted by a verdict (a section edited after its accept counts as changed)")
    k.lock(p, "assemble")
    val build = p.build
    os.makeDir.all(build)
    os.makeDir.all(k.outDir(slug))
    // The gates that need the whole work: lint without placeholders on every section, cite-check.
    p.orderIds.foreach { id =>
      val (code, out) = k.self(Cmd.Lint, slug, id)
      if code != 0 then
        Prose.lines(out).foreach(l => System.err.println(s"  $l"))
        fail(s"$slug/$id: lint fails (placeholders such as **[AUTHOR: ...]** or **[ANALYSIS]** must be gone)")
    }
    val (ccCode, ccOut) = k.self(Cmd.CiteCheck, slug)
    if ccCode != 0 then
      Prose.lines(ccOut).foreach(l => System.err.println(s"  $l"))
      fail(s"$slug: cite-check of the whole work fails")
    val work = Kit.tempDir(build, ".asm.").getOrElse(fail(s"cannot make a folder in $build"))
    try
      val tex = work / Names.Tex
      tree(p, tpl, tex)
      val hasLogo = p.logo match
        case None => false
        case Some(logo) =>
          if logo.startsWith("assets/") && logo.drop(7).exists(c => !(c.isLetterOrDigit && c < 128 || "._/-".contains(c)))
            || logo.contains("..") || logo.startsWith("/") then
            fail(s"$slug: assets.ufrj_logo must be a plain path under assets/ (letters, digits, . _ / -)")
          if !logo.startsWith("assets/") || !List(".pdf", ".png", ".jpg", ".jpeg").exists(logo.endsWith) then
            fail(s"$slug: assets.ufrj_logo must be a PDF, PNG or JPEG file under assets/")
          if !Kit.plainFileAt(p.dir, logo) then fail(s"$slug: the UFRJ logo file $logo is missing")
          os.copy.over(p.dir / os.RelPath(logo), tex / Names.Assets / s"ufrj-logo.${logo.split('.').last}")
          true
      // Fragments, in order, as s01.tex, s02.tex, ...
      val files = p.orderIds.zipWithIndex.map { (id, i) =>
        val f = f"s${i + 1}%02d"
        fragment(k, p, k.section(p, id), tpl, tex / "pt" / Names.Sections / s"$f.tex", preview = false)
        id -> f
      }.toMap
      // The reference list of every entry of refs.bib (cite-check made sure none is unused).
      os.write.over(k.tmp / "meta-refs.yaml", "nocite: '@*'\nlang: pt-BR\n")
      os.write.over(k.tmp / "stub.md", "::: {#refs}\n:::\n")
      val csl = cslFile(k, tpl)
      if pandoc(k, Seq("-f", From, "-t", "latex", "--wrap=none", "--metadata-file", (k.tmp / "meta-refs.yaml").toString,
          "--bibliography", p.refsBib.toString, "--csl", csl.toString, "--citeproc",
          "-o", (tex / "pt" / "refs.tex").toString, (k.tmp / "stub.md").toString)) != 0 then
        pandocFail(k, s"$slug: pandoc cannot make the reference list")
      val meta = k.tmp / "meta.json"
      os.write.over(meta, J.pretty(frontPages(k, p, files, hasLogo).getOrElse(fail(s"$slug: cannot build the front-page data from thesis.json"))))
      if page(k, tpl, Names.MainLatex, meta, tex / "pt" / "main.tex") != 0 then pandocFail(k, s"$slug: pandoc cannot fill the template")
      val pt = tex / "pt"
      if !run(k, pt) then
        scala.util.Try(os.copy.over(pt / Names.MainLog, build / Names.MainLog))
        fail(s"$slug: the PDF did not build (log: build/main.log)")
      val found = logFindings(pt / Names.MainLog)
      if found.nonEmpty then
        os.copy.over(pt / Names.MainLog, build / Names.MainLog)
        System.out.flush()
        found.foreach(l => System.err.println(s"  tex: $l"))
        fail(s"$slug: the PDF has unresolved references or missing characters (log: build/main.log)")
      // Keep the tree and the log, replace the PDF atomically.
      os.remove.all(build / Names.Tex)
      Kit.copyTree(tex, build / Names.Tex)
      os.copy.over(pt / "main.pdf", build / "thesis.pdf.tmp")
      os.move(build / "thesis.pdf.tmp", build / Names.ThesisPdf, replaceExisting = true)
      os.copy.over(pt / Names.MainLog, build / Names.MainLog)
      // What was assembled: the hash of every accepted section, for publish.
      val assembled = ujson.Obj.from(p.orderIds.map(id => id -> ujson.Str(Kit.sha(p.sectionFile(id)))))
      Kit.atomicWrite(build / Names.AssembledJson, J.pretty(assembled))
      os.copy.over(build / Names.ThesisPdf, k.outDir(slug) / "thesis.pdf.tmp")
      os.move(k.outDir(slug) / "thesis.pdf.tmp", k.outDir(slug) / Names.ThesisPdf, replaceExisting = true)
      val peak = if os.isFile(k.tmp / "times") then
        Prose.lines(os.read(k.tmp / "times")).flatMap(_.split(" ").lift(1)).flatMap(_.toLongOption).maxOption.getOrElse(0L)
      else 0L
      k.log(p, None, s"assemble: ${pdfPages(build / Names.ThesisPdf)} pages, ${Kit.nowS() - t0} s, peak child $peak KiB")
      k.unlock(p, "assemble")
    finally os.remove.all(work)
    pdfQa(k, List(slug))

  /** The data of the front pages and the order of the sections, for main.latex. */
  private def frontPages(k: Kit, p: Project, files: Map[String, String], hasLogo: Boolean): Option[ujson.Value] =
    import ThesisKey as K
    def value(key: String) = p.field(key).getOrElse(ujson.Null)
    for
      title <- p.field(K.Title).flatMap(_.strOpt)
      courseName <- p.field(K.Course).flatMap(_.strOpt)
      deg <- k.profile.courses.find(_.name == courseName).flatMap(_.title)
      month <- monthName(p)
      year <- p.field(K.Year)
    yield ujson.Obj(
      "title" -> title, "title-plain" -> title, "title-upper" -> Text.upcase(title),
      "author" -> value(K.Author), "author-plain" -> value(K.Author),
      "author-ref" -> value(K.AuthorRef), "advisor" -> value(K.Advisor),
      "examiners" -> value(K.Examiners),
      "no-examiners" -> p.field(K.Examiners).flatMap(_.arrOpt).forall(_.isEmpty),
      "course" -> courseName, "course-upper" -> Text.upcase(courseName), "degree" -> deg, "degree-upper" -> Text.upcase(deg),
      "month-name" -> month, "month-upper" -> Text.upcase(month), "year" -> J.rawValue(year),
      "has-ufrj-logo" -> hasLogo,
      "list-figures" -> J.path(p.json, K.ListFigures).getOrElse(ujson.Null), "list-tables" -> J.path(p.json, K.ListTables).getOrElse(ujson.Null),
      "has-appendix" -> p.live.exists(_.is(Role.Appendix)),
      "sections" -> ujson.Arr.from(p.live.map { s =>
        ujson.Obj.from(List(
          "id" -> J.get(s.json, SectionKey.Id).getOrElse(ujson.Null),
          "file" -> files.get(s.id).map(ujson.Str(_)).getOrElse(ujson.Null),
          "keywords" -> J.get(s.json, SectionKey.Keywords).filterNot(J.falsy).getOrElse(ujson.Arr()),
        ) ++ Role.values.map(r => s"is-${r.render}" -> ujson.Bool(s.is(r))))
      }),
    )

  /** `thesis pdf-qa <slug>`: A4, fonts, ??, margins, titles in order; build/qa.json. */
  def pdfQa(k: Kit, args: List[String]): Int =
    if args.length != 1 then fail("usage: thesis pdf-qa <slug>")
    needTools("pdfinfo", "pdftotext", "pdffonts", "pdftohtml")
    val p = k.project(args.head)
    val slug = p.slug
    val pdf = p.build / Names.ThesisPdf
    if !Kit.plainFile(pdf) then fail(s"$slug: no build/thesis.pdf: run thesis assemble first")
    val page = k.profile.page
    val q = k.tmp / "qa"
    os.makeDir.all(q)
    def poppler(cmd: String*): os.CommandResult =
      os.proc("timeout", "-k", "5", k.popplerTimeout, cmd).call(stdin = "", stdout = os.Pipe, stderr = os.Pipe, check = false)

    val info = poppler("pdfinfo", "-f", "1", "-l", "9999", pdf.toString)
    if info.exitCode != 0 then fail(s"$slug: pdfinfo cannot read the PDF: ${Prose.lines(info.err.text()).headOption.getOrElse("")}")
    val infoLines = Prose.lines(info.out.text())
    def infoField(prefix: String, n: Int) =
      infoLines.find(_.startsWith(prefix)).flatMap(_.split("\\s+").lift(n)).getOrElse("")
    val pages = infoField("Pages:", 1)
    val version = infoField("PDF version:", 2)
    val ((pw, ph), tol) = (page.paperMm, page.paperToleranceMm)
    val notA4 = infoLines.filter(_.matches("^Page +[0-9]+ size:.*")).count { l =>
      val f = l.split("\\s+")
      val w = awkNum(f.lift(3).getOrElse("")) * 25.4 / 72
      val h = awkNum(f.lift(5).getOrElse("")) * 25.4 / 72
      w < pw - tol || w > pw + tol || h < ph - tol || h > ph + tol
    }
    val fonts = Poppler.fonts(poppler("pdffonts", pdf.toString).out.text())
    val notEmbedded = fonts.count(!_.embedded)
    val textRun = poppler("pdftotext", "-layout", pdf.toString, (q / "text.txt").toString)
    if textRun.exitCode != 0 then
      System.err.print(textRun.err.text())
      fail(s"$slug: pdftotext failed")
    val text = os.read(q / "text.txt")
    val unresolved = Prose.lines(text).count(_.contains("??"))
    val nulls = Prose.lines(text).count(_.contains("(null)"))
    // Every chapter title is a line of the text, in the order of thesis.json, after the table of contents.
    val pagesText = Poppler.pages(text)
    val titles = p.live.filter(_.is(Role.Chapter)).map(_.title).filter(_.nonEmpty)
    val tocPage = Poppler.firstPage(pagesText, 1)(_.matches("(?s)(.*\n)? *Sumário *\n.*"))
    val missing = Poppler.notInOrder(pagesText, tocPage.getOrElse(1), titles)
    val bboxRun = poppler("pdftotext", "-bbox-layout", pdf.toString, (q / "bbox.html").toString)
    if bboxRun.exitCode != 0 then
      System.err.print(bboxRun.err.text())
      fail(s"$slug: pdftotext -bbox-layout failed")
    val box = Poppler.bbox(os.read(q / "bbox.html"), page.bboxFooterZonePt)
    val xml = poppler("pdftohtml", "-xml", "-zoom", "1", "-i", "-q", "-stdout", pdf.toString)
    val font = Poppler.fontXml(if xml.exitCode == 0 then xml.out.text() else "")
    val mainLog = p.build / Names.MainLog
    val logLines = if os.isFile(mainLog) then Prose.lines(Tex.readLog(mainLog)) else Vector.empty
    val overfull = if os.isFile(mainLog) then logLines.count(_.contains("Overfull \\hbox")).toString else ""
    val overMax = logLines.flatMap(l => """^Overfull \\hbox \(([0-9.]*)pt too wide\).*""".r.unapplySeq(l).flatMap(_.headOption))
      .sortBy(v => (awkNum(v), v)).lastOption.getOrElse("")
    val exact = Poppler.layout(logLines).map(_.margins).getOrElse(Sides("0", "0", "0", "0"))
    val exactOk = exact.zip(page.marginMinMm).toList.forall((v, min) => awkNum(v) + 0.05 >= min)
    val measuredOk = box.margins.zip(page.marginMinMm).toList.forall((v, min) => awkNum(v) + page.marginToleranceMm >= min)
    val marginsOk = exactOk && measuredOk && awkNum(overMax) <= page.overfullMaxPt
    val pass = notA4 == 0 && notEmbedded == 0 && unresolved == 0 && nulls == 0 && missing.isEmpty && marginsOk && pages.nonEmpty
    val pitch = awkNum(box.pitch)
    def num(s: String): ujson.Value = J.literal(s)
    def sides(s: Sides[String]) = ujson.Obj.from(Sides.Names.zip(s).toList.map((name, v) => name -> num(v)))
    val qa = ujson.Obj(
      QaKey.Pass -> pass,
      QaKey.Pages -> num(pages), "pdf_version" -> version,
      QaKey.PageSizeOk -> (notA4 == 0), QaKey.PagesNotA4 -> notA4,
      "fonts" -> ujson.Arr.from(fonts.map(_.json)), "fonts_all_embedded" -> (notEmbedded == 0),
      "unresolved_refs" -> unresolved, "null_strings" -> nulls,
      "titles_in_order" -> missing.isEmpty, "titles_missing" -> ujson.Arr.from(missing.map(ujson.Str(_))),
      QaKey.MinMargins -> sides(box.margins),
      "layout_margins_mm" -> sides(exact),
      QaKey.MarginsOk -> marginsOk,
      QaKey.LinePitch -> num(box.pitch),
      QaKey.LineSpacing -> (if pitch > 0 then ujson.Num(math.round(pitch / page.singleBaselineskipPt * 100).toDouble / 100) else ujson.Null),
      "body_font" -> ujson.Obj("family" -> font.family, "size_pt" -> num(font.size)),
      QaKey.MaxFontSize -> num(font.maxSize), QaKey.NonBlackFonts -> font.nonBlack,
      "overfull_boxes" -> num(overfull), "overfull_max_pt" -> num(overMax),
      "note" -> "layout_margins_mm is exact: the text block of the TeX run (log lines thesis-layout). min_margins_mm is measured on the line boxes of poppler (pdftotext -bbox-layout), page numbers in the footer zone left out; those boxes stand about 1.2 mm outside the glyphs, so they get a tolerance (profile layout.margin_tolerance_mm). Figures are not measured. The pitch is the median distance of consecutive body lines.",
    )
    Kit.atomicWrite(p.build / Names.QaJson, J.pretty(qa))
    say(s"pdf-qa: $slug: ${if pages.isEmpty then "0" else pages} pages, A4 ${notA4 == 0}, fonts embedded ${notEmbedded == 0}, ?? $unresolved, (null) $nulls, titles in order ${missing.isEmpty}, margins ok $marginsOk")
    say(s"  margins mm (top bottom left right): ${box.margins.toList.mkString(" ")}; line pitch ${box.pitch} pt; body font ${font.family} ${font.size} pt; largest ${font.maxSize} pt; overfull boxes $overfull")
    missing.foreach(t => say(s"  title not found in order: $t"))
    say(s"pdf-qa: $slug: ${if pass then "PASS" else "FAIL"} (build/qa.json)")
    if pass then 0 else 1

  /** `thesis publish <slug> [--replace]`: thesis.pdf, qa.json, REFERENCES.md and review/ to the outbox. */
  def publish(k: Kit, args: List[String]): Int =
    val (replace, pos) = args.foldLeft((false, Vector.empty[String])) {
      case ((_, pos), "--replace")     => (true, pos)
      case (_, o) if o.startsWith("-") => fail(s"publish: unknown option $o")
      case ((replace, pos), a)         => if pos.nonEmpty then fail("publish: too many arguments") else (replace, pos :+ a)
    }
    val slug = pos.headOption.getOrElse(fail("usage: thesis publish <slug> [--replace]"))
    val p = k.project(slug)
    val build = p.build
    val qa = build / Names.QaJson
    val pdf = build / Names.ThesisPdf
    val qaOk = os.isFile(qa) && J.get(ujson.read(os.read(qa)), QaKey.Pass).contains(ujson.True)
    if !qaOk then fail(s"$slug: no passing pdf-qa (build/qa.json): run thesis assemble")
    if !Kit.plainFile(pdf) then fail(s"$slug: no build/thesis.pdf")
    if !(os.mtime(pdf) > os.mtime(p.dir / Names.ThesisJson)) then fail(s"$slug: thesis.json is newer than the PDF: assemble again")
    // Every section as accepted, still the same text as assembled.
    if !os.isFile(build / Names.AssembledJson) then fail(s"$slug: no build/assembled.json: assemble again")
    val assembled = ujson.read(os.read(build / Names.AssembledJson))
    p.orderIds.foreach { id =>
      val st = ProjectCommands.sectionStatus(k, p, k.section(p, id)).state
      if st != SectionState.Accepted then fail(s"$slug/$id is ${st.render}: assemble and review again before publish")
      if !J.str(assembled, id).contains(Kit.sha(p.sectionFile(id))) then fail(s"$slug/$id changed after the PDF was assembled: assemble again")
    }
    val dest = k.outbox / slug
    if os.exists(dest) && !replace then fail(s"$dest exists (another run?): use --replace to overwrite it")
    scala.util.Try(os.makeDir.all(k.outbox)).getOrElse(fail(s"cannot make the outbox ${k.outbox}"))
    val t = Kit.tempDir(k.outbox, s".pub.$slug.").getOrElse(fail(s"cannot write in the outbox ${k.outbox}"))
    val copied = scala.util.Try {
      os.copy(pdf, t / Names.ThesisPdf)
      os.copy(qa, t / Names.QaJson)
      os.copy(p.references, t / Names.ReferencesMd)
    }
    if copied.isFailure then
      os.remove.all(t)
      fail("publish: cannot copy the files")
    os.makeDir(t / Names.Review)
    if os.isDir(p.review) then
      os.list(p.review).filter(f => !f.last.startsWith(".") && os.isFile(f)).foreach(f => os.copy(f, t / Names.Review / f.last))
    os.perms.set(t, "rwxr-xr-x")
    if os.exists(dest, followLinks = false) then os.remove.all(dest)
    if scala.util.Try(os.move(t, dest)).isFailure then
      os.remove.all(t)
      fail(s"publish: cannot move the files into $dest")
    k.log(p, None, s"publish to $dest")
    say(s"thesis: published $slug to $dest (thesis.pdf, qa.json, REFERENCES.md, review/)")
    0

/** What poppler and the TeX log say about the PDF. */
object Poppler:
  /** The pages of `pdftotext -layout`, split at form feeds as awk's RS = "\f" does. */
  def pages(text: String): Vector[String] =
    if text.isEmpty then Vector.empty else text.stripSuffix("\f").split("\f", -1).toVector

  /** The first page, from page `from` on (1-based), for which the test holds. */
  def firstPage(pages: Vector[String], from: Int)(test: String => Boolean): Option[Int] =
    (from.max(1) to pages.length).find(n => test(pages(n - 1)))

  /** The first page from `from` on with a line that is exactly `line`, blanks around it aside. */
  def pageWithLine(pages: Vector[String], from: Int, line: String): Option[Int] =
    firstPage(pages, from)(_.split("\n", -1).exists(_.replaceAll("^[ \t]+|[ \t]+$", "") == line))

  /** A font of `pdffonts`: name and emb are None when the line is too short to hold them. */
  final case class PdfFont(name: Option[String], emb: Option[String], kind: String):
    def embedded: Boolean = emb.contains("yes")
    def json: ujson.Value =
      def opt(v: Option[String]): ujson.Value = v.map(ujson.Str(_)).getOrElse(ujson.Null)
      ujson.Obj("name" -> opt(name), "emb" -> opt(emb), "type" -> kind)

  /** The fonts of `pdffonts`, after the two header lines. */
  def fonts(out: String): Vector[PdfFont] =
    out.split("\n", -1).drop(2).filter(_.nonEmpty).map { line =>
      val f = line.split(" +", -1).toVector
      PdfFont(f.lift(0), f.lift(f.length - 5), f.slice(1, (f.length - 6).max(1)).mkString(" "))
    }.toVector

  /** The chapter titles not found in order, each looked for after the page of the one before. */
  def notInOrder(pages: Vector[String], from: Int, titles: List[String]): List[String] =
    titles.foldLeft((from, List.empty[String])) { case ((last, missing), t) =>
      pageWithLine(pages, last + 1, t) match
        case Some(pg) => (pg, missing)
        case None     => (last, t :: missing)
    }._2.reverse

  final case class Box(margins: Sides[String], pitch: String)

  /** Margins and the line pitch from `pdftotext -bbox-layout`, page by page: the smallest margin of
    * any page in mm, and the median distance between consecutive lines of the pages with 20 lines or
    * more. A line that is only a page number in the last `zone` pt of the page is the footer.
    */
  def bbox(html: String, zone: Double): Box =
    def attr(s: String, name: String): Double =
      s"""$name="([^"]*)"""".r.findFirstMatchIn(s).map(m => awkNum(m.group(1))).getOrElse(0.0)
    var w = 0.0
    var h = 0.0
    var mt, mb, ml, mr = 1e9
    var x0, y0, x1, y1 = 0.0
    val words = ArrayBuffer[String]()
    val ys = ArrayBuffer[Double]()
    val pitches = ArrayBuffer[Double]()
    def endPage(): Unit =
      if ys.length >= 20 then
        ys.sliding(2).foreach { pair =>
          val d = pair(1) - pair(0)
          if d >= 15 && d <= 40 then pitches += d
        }
      ys.clear()
    Prose.lines(html).foreach { l =>
      if l.contains("<page ") then { endPage(); w = attr(l, "width"); h = attr(l, "height") }
      else if l.contains("<line ") then
        x0 = attr(l, "xMin"); y0 = attr(l, "yMin"); x1 = attr(l, "xMax"); y1 = attr(l, "yMax"); words.clear()
      else if l.contains("<word ") then words += l.replaceFirst("^[^>]*>", "").replaceFirst("</word>.*$", "")
      else if l.contains("</line>") then
        val footer = words.length == 1 && words.head.matches("^([0-9]+|[ivxlcdm]+)$") && y0 > h - zone
        if !footer then
          ys += y0
          ml = ml.min(x0 * 25.4 / 72)
          mr = mr.min((w - x1) * 25.4 / 72)
          mt = mt.min(y0 * 25.4 / 72)
          mb = mb.min((h - y1) * 25.4 / 72)
    }
    endPage()
    Box(Sides(fixed(mt, 1), fixed(mb, 1), fixed(ml, 1), fixed(mr, 1)),
      fixed(ReadabilityNumbers.median(pitches.toSeq), 2))

  final case class Font(family: String, size: String, maxSize: String, nonBlack: Int)

  /** The fonts of the text from `pdftohtml -xml`: the one with most characters, the biggest size,
    * and how many are not black.
    */
  def fontXml(xml: String): Font =
    val size = scala.collection.mutable.Map[String, Double]()
    val family = scala.collection.mutable.Map[String, String]()
    val count = scala.collection.mutable.LinkedHashMap[String, Int]()
    var nonBlack = 0
    var maxSize = 0.0
    def attr(s: String, name: String) = s"""$name="([^"]*)"""".r.findFirstMatchIn(s).map(_.group(1))
    Prose.lines(xml).foreach { l =>
      if l.contains("<fontspec ") then
        val id = attr(l, "id").getOrElse("")
        size(id) = awkNum(attr(l, "size").getOrElse(""))
        family(id) = attr(l, "family").getOrElse("")
        val col = attr(l, "color").getOrElse("")
        if col.toLowerCase != "#000000" && col.nonEmpty then nonBlack += 1
      else if l.contains("<text ") then
        attr(l, "font").foreach { id =>
          val t = l.replaceFirst("^[^>]*>", "").replaceFirst("</text>.*$", "").replaceAll("<[^>]*>", "")
          val n = t.codePointCount(0, t.length)
          count(id) = count.getOrElse(id, 0) + n
          if size.getOrElse(id, 0.0) > maxSize && n > 2 then maxSize = size(id)
        }
    }
    val best = count.foldLeft(Option.empty[(String, Int)]) { (b, x) => if b.forall(x._2 > _._2) then Some(x) else b }.map(_._1)
    Font(best.flatMap(family.get).getOrElse(""), best.flatMap(size.get).map(Text.g6).getOrElse(""), Text.g6(maxSize), nonBlack)

  final case class TexLayout(margins: Sides[String], baselineskip: String)

  /** The exact margins in mm and the baselineskip in pt, from the `thesis-layout key=value` lines
    * that the overlay writes to the TeX log.
    */
  def layout(log: Seq[String]): Option[TexLayout] =
    val v = log.flatMap { l =>
      """^thesis-layout ([a-z]+)=(.*)$""".r.unapplySeq(l).collect { case List(key, value) =>
        key -> awkNum(value.replaceFirst("pt.*$", ""))
      }
    }.toMap.withDefaultValue(0.0)
    Option.when(log.exists(_.startsWith("thesis-layout textwidth="))) {
      val pt = 25.4 / 72.27
      val left = (72.27 + v("hoffset") + v("oddsidemargin")) * pt
      val right = v("paperwidth") * pt - left - v("textwidth") * pt
      val top = (72.27 + v("voffset") + v("topmargin") + v("headheight") + v("headsep")) * pt
      val bottom = v("paperheight") * pt - top - v("textheight") * pt
      TexLayout(Sides(top, bottom, left, right).map(fixed(_, 2)), fixed(v("baselineskip"), 2))
    }
