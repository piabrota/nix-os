package piabrota.thesis

import piabrota.lib.{Sh, TestKit}

/** `piabrota thesis` as a seat runs it, on one sample project in a temporary folder: names, claims,
  * submit and verdict, hostile text, the gates, a hung TeX run, assemble and publish. It needs the
  * toolkit's data (THESIS_SHARE) and its programs on the PATH (pandoc, pdfLaTeX, poppler), as
  * thesis/default.nix's passthru.tests.run gives them; without them every test here is skipped.
  * The tests run in order and share the project.
  */
class ThesisTest extends munit.FunSuite:
  private lazy val share: Option[os.Path] =
    sys.env.get("THESIS_SHARE").map(os.Path(_)).filter(d => os.isFile(d / "profile.json"))
  private lazy val ready: Boolean =
    share.isDefined && List("pandoc", "pdflatex", "pdftotext", "pdfinfo").forall(Sh.which(_).isDefined)
  private lazy val root: os.Path = os.temp.dir(prefix = "thesis-test")
  private def home = root / "home"
  private def outbox = root / "outbox"
  private def p = home / "projects" / "sample"

  private def thesis(args: String*): os.CommandResult = thesisWith(Map.empty, args*)
  private def thesisWith(env: Map[String, String], args: String*): os.CommandResult =
    os.makeDir.all(home)
    TestKit.piabrota("thesis" +: args, env = Map("THESIS_HOME" -> home.toString, "THESIS_OUTBOX" -> outbox.toString,
      "LC_ALL" -> "C.UTF-8") ++ env)
  private def all(r: os.CommandResult) = r.out.text() + r.err.text()

  private def check(name: String)(body: => Unit): Unit =
    test(name):
      assume(ready, "no toolkit: THESIS_SHARE and pandoc, pdflatex and poppler on the PATH")
      body
  private def ok(r: os.CommandResult): Unit = assertEquals(r.exitCode, 0, all(r))
  private def refused(r: os.CommandResult): Unit = assertNotEquals(r.exitCode, 0, all(r))
  private def write(f: os.Path, text: String): Unit = os.write.over(f, text, createFolders = true)
  private def editJson(f: os.Path)(edit: ujson.Value => Unit): Unit =
    val v = ujson.read(os.read(f))
    edit(v)
    os.write.over(f, v.render(indent = 2))
  private def sections(v: ujson.Value) = v("sections").arr

  override def afterAll(): Unit = os.remove.all(root)

  test("usage without a command, exit 2"):
    assume(share.isDefined, "no THESIS_SHARE")
    val r = thesis()
    assertEquals(r.exitCode, 2)
    assert(r.out.text().startsWith("thesis: a final project for the Escola Politécnica of UFRJ"), all(r))

  test("an unknown command is refused with the usage on stderr"):
    assume(share.isDefined, "no THESIS_SHARE")
    val r = thesis("nosuch")
    assertEquals(r.exitCode, 1)
    assert(r.err.text().endsWith("thesis: unknown command: nosuch\n"), all(r))

  test("no toolkit data is a clear error"):
    val r = thesisWith(Map("THESIS_SHARE" -> (root / "none").toString), "help")
    assertEquals(r.exitCode, 1)
    assertEquals(r.err.text(), s"thesis: cannot find the toolkit data (THESIS_SHARE=${root / "none"})\n")

  // --- names
  check("bad slugs are refused")(List("../x", "a b", "-x", "a/b").foreach(s => refused(thesis("new", s))))
  check("a good slug is accepted")(ok(thesis("new", "sample")))
  check("a second new of the same slug is refused")(refused(thesis("new", "sample")))
  check("bad and unknown section ids are refused")(List("../x", "a b", "nosuch").foreach(id => refused(thesis("lint", "sample", id))))
  check("a seat name with a slash is refused")(refused(thesis("fetch", "sample", "--as", "../evil")))

  // --- fetch: parallel callers get different sections
  check("three parallel fetches get three different sections, and a claim can be resumed and released"):
    ok(thesis("new", "par"))
    val env = Map("THESIS_HOME" -> home.toString, "THESIS_OUTBOX" -> outbox.toString)
    val runs = List("writer-a", "writer-b", "writer-c").map { seat =>
      os.proc(TestKit.bin, "thesis", "fetch", "par", "--as", seat).spawn(env = env, stderr = os.Pipe)
    }
    val got = runs.map { r =>
      val out = r.stdout.text()
      r.waitFor()
      "(?m)^section: *([A-Za-z0-9_-]+)".r.findFirstMatchIn(out).map(_.group(1)).getOrElse("")
    }
    assert(got.forall(_.nonEmpty), got)
    assertEquals(got.distinct.length, 3, got)
    val a = got.head
    assert(s"(?m)^section: *$a".r.findFirstIn(thesis("fetch", "par", "--as", "writer-a").out.text()).isDefined)
    refused(thesis("fetch", "par", a, "--as", "writer-b"))
    ok(thesis("release", "par", a, "--as", "writer-a"))
    assert(!os.exists(home / "projects" / "par" / "claims" / s"$a.claim"))

  // --- the sample project: a tiny thesis with one real section
  private val resumo = "A previsão de ondas depende de modelos caros. Este texto de teste descreve um porte para GPU que reproduz os bits do código em Fortran, medido em uma grade pequena.\n"

  check("lint passes on a plain resumo"):
    editJson(p / "thesis.json") { t =>
      t("title") = "Previsão de ondas e portes para GPU"; t("title_en") = "Wave forecasting and GPU ports"
      t("author") = "Autora Teste"; t("author_ref") = "TESTE, Autora"; t("advisor") = "Prof. Orientador Teste, D.Sc."
      sections(t).foreach { s =>
        s("status") = "omit"
        if s("id").str == "resumo" then
          s("status") = "todo"; s("target_words") = 40; s("keywords") = ujson.Arr("ondas", "GPU", "Fortran")
        if s("id").str == "introducao" then s("target_words") = 120
      }
    }
    write(p / "sections" / "resumo.md", resumo)
    ok(thesis("lint", "sample", "resumo"))

  check("submit refuses an **[AUTHOR: placeholder and names it"):
    thesis("fetch", "sample", "resumo", "--as", "writer-a"): Unit
    write(p / "sections" / "resumo.md", resumo + "\n**[AUTHOR: ask what the author measured]**\n")
    refused(thesis("submit", "sample", "resumo", "--as", "writer-a"))
    assert(thesis("lint", "sample", "resumo").out.text().contains("placeholder"))
    write(p / "sections" / "resumo.md", resumo)

  check("submit refuses a seat that did not claim the section")(refused(thesis("submit", "sample", "resumo", "--as", "writer-b")))
  check("submit hands in a clean section")(ok(thesis("submit", "sample", "resumo", "--as", "writer-a")))
  check("a writer may not judge a section")(refused(thesis("verdict", "sample", "resumo", "accept", "--by", "writer-a")))
  check("accept needs the reviewer's own review file")(refused(thesis("verdict", "sample", "resumo", "accept", "--by", "reviewer")))

  check("verdict accept records the hash, and the section is accepted"):
    write(p / "review" / "resumo.review.md", "Findings: none. Gates read.\n")
    ok(thesis("verdict", "sample", "resumo", "accept", "--by", "reviewer"))
    assert("resumo .* accepted".r.findFirstIn(thesis("sections", "sample").out.text()).isDefined)

  // --- build, hostile text, raw TeX
  private def intro(text: String) = write(p / "sections" / "introducao.md", text)

  check("hostile characters build, escaped"):
    intro("# Teste de caracteres\n\nTexto hostil: 100% \\write18{id} e \\input{/etc/passwd} & $ # _ { } ~ ^ ação, coração e açúcar.\n\nMais um parágrafo com `código` e **negrito** e *itálico*, para o teste.\n")
    ok(thesis("build-section", "sample", "introducao"))
    val tex = os.read(p / "build" / "introducao.tex")
    assert(tex.contains("textbackslash"))
    assert(!tex.contains("\\input{/etc/passwd}"))
    assert(!tex.linesIterator.exists(_.matches("""^[^%]*\\write18.*""")))
    assert(os.size(p / "build" / "introducao.preview.pdf") > 0)

  check("math: a macro off the list and \\write18 are refused, plain math builds"):
    intro("# Math\n\nUma conta $\\input{/etc/passwd}$ no texto.\n")
    refused(thesis("build-section", "sample", "introducao"))
    intro("# Math\n\nUma conta $\\write18{id}$ no texto.\n")
    refused(thesis("build-section", "sample", "introducao"))
    intro("# Math\n\nUma conta $x^2 + \\frac{a}{b}$ no texto.\n")
    ok(thesis("build-section", "sample", "introducao"))

  check("an emoji is refused with a clear line"):
    intro("# Emoji\n\nUm texto com 😀 dentro.\n")
    refused(thesis("lint", "sample", "introducao"))
    assert(all(thesis("build-section", "sample", "introducao")).contains("cannot set"))

  check("an image outside figures/ is refused"):
    intro("# Imagem\n\n![x](/etc/passwd){#fig:a}\n\nVer @fig:a.\n")
    refused(thesis("lint", "sample", "introducao"))

  // --- slop
  check("slop fails a stock-phrase paragraph"):
    intro("""No cenário atual, a previsão de ondas desempenha um papel fundamental em diversos setores da sociedade. Vale ressaltar que os modelos numéricos robustos oferecem um panorama abrangente e holístico do oceano. Além disso, é importante destacar que a computação em GPU se tornou um verdadeiro paradigma de desempenho, de precisão e de eficiência. Dessa forma, os pesquisadores buscam alavancar essa tecnologia revolucionária. Em suma, a previsão de ondas é essencial.
             |
             |Além disso, ao longo dos anos, os modelos espectrais evoluíram de forma significativa e hoje abrem caminho para um leque de aplicações. Nesse sentido, cabe salientar que o WAVEWATCH III é uma ferramenta robusta, flexível e poderosa. Dessa forma, o presente trabalho propõe uma abordagem inovadora, abrangente e eficiente. Portanto, é crucial compreender esse contexto.
             |""".stripMargin)
    refused(thesis("slop", "sample", "introducao"))

  check("slop passes a plain paragraph and says it is no detector"):
    intro("""Uma previsão de ondas só serve se chegar antes do mar. O WAVEWATCH III resolve o balanço de energia das ondas em cada ponto de uma grade, e repete o trabalho a cada passo de tempo. Em máquinas com CPU, o custo cresce com a grade e com o número de dias previstos.
             |
             |As placas gráficas fazem o mesmo cálculo em milhares de pontos ao mesmo tempo. Quem leva o código para elas muda a ordem das contas, e uma soma feita em outra ordem pode mudar o último bit. Por isso a meta é dura: a saída em GPU deve ser igual, bit a bit, à do código em Fortran.
             |
             |O trabalho porta uma parcela do modelo. A parcela foi escolhida pelo tempo que ocupa no perfil do código. A comparação lê os dois resultados como inteiros de 32 bits e conta os que diferem.
             |""".stripMargin)
    val r = thesis("slop", "sample", "introducao")
    ok(r)
    assert(r.out.text().contains("not a detector"))

  // --- cite-check
  check("cite-check: unverified refused, verified needs a capture, then passes"):
    intro("O modelo foi descrito por um grupo de teste [@exemplo2026a]. O texto seguinte repete a afirmação com outras palavras, para o teste.\n")
    write(p / "refs.bib", "@article{exemplo2026a,\n  author = {Ficticio, Autor},\n  title = {Um artigo fictício de teste},\n  journal = {Revista de Teste},\n  year = {2020},\n  volume = {1},\n  doi = {10.9999/teste.2020.1}\n}\n")
    write(p / "REFERENCES.md", "| Key | Status | Checked against | Note |\n|---|---|---|---|\n| exemplo2026a | unverified | not fetched | FAKE |\n")
    val r = thesis("cite-check", "sample", "introducao")
    refused(r)
    assert(r.out.text().contains("unverified"))
    write(p / "REFERENCES.md", os.read(p / "REFERENCES.md").replace("| unverified |", "| verified |"))
    refused(thesis("cite-check", "sample", "introducao"))
    write(p / "sources" / "exemplo2026a.md", "URL: https://example.invalid/x\nRetrieved: 2026-11-05\nDOI check: none (fictitious)\n\n> \"texto fictício\" (p. 1)\n")
    ok(thesis("cite-check", "sample", "introducao"))

  check("cite-check refuses a key not in refs.bib and a numbered citation"):
    intro("O modelo foi descrito [@naoexiste2020]. Segue um texto de teste.\n")
    refused(thesis("cite-check", "sample", "introducao"))
    intro("O modelo foi descrito (Silva, 2020) e [3] outra coisa.\n")
    refused(thesis("cite-check", "sample", "introducao"))

  // --- a broken template fails clearly; a hung TeX run is stopped
  private lazy val ownShare: os.Path =
    val d = root / "share"
    os.copy(share.get, d, followLinks = true)
    Kit.ownerWritable(d)
    d
  private def preamble = ownShare / "templates" / "forecast-energy-demand" / "overlay" / "preamble.tex"

  check("a missing overlay file fails and names the file"):
    intro("Texto simples para a prévia do teste.\n")
    os.remove(preamble)
    val r = thesisWith(Map("THESIS_SHARE" -> ownShare.toString), "build-section", "sample", "introducao")
    refused(r)
    assert(all(r).contains("preamble.tex"), all(r))

  check("a hung TeX run is stopped by the time limit and says so"):
    os.copy.over(share.get / "templates" / "forecast-energy-demand" / "overlay" / "preamble.tex", preamble)
    os.perms.set(preamble, "rw-r--r--")
    os.write.append(preamble, "\\def\\thesisloop{\\thesisloop}\\thesisloop\n")
    val start = System.currentTimeMillis
    val r = thesisWith(Map("THESIS_SHARE" -> ownShare.toString, "THESIS_TEX_TIMEOUT" -> "3"), "build-section", "sample", "introducao")
    refused(r)
    assert(System.currentTimeMillis - start < 20000, "the run took too long: the timeout did not stop it")
    assert(all(r).contains("stopped"), all(r))

  // --- assemble, publish, edit after accept
  check("assemble builds the PDF and pdf-qa passes"):
    intro("Texto simples.\n")
    write(p / "refs.bib", "")
    write(p / "REFERENCES.md", "| Key | Status | Checked against | Note |\n|---|---|---|---|\n")
    ok(thesis("assemble", "sample"))
    assert(os.size(p / "build" / "thesis.pdf") > 0)
    assertEquals(ujson.read(os.read(p / "build" / "qa.json"))("pass"), ujson.True)

  check("publish copies to the outbox, refuses to overwrite, --replace overwrites"):
    ok(thesis("publish", "sample"))
    refused(thesis("publish", "sample"))
    ok(thesis("publish", "sample", "--replace"))
    List("thesis.pdf", "qa.json", "REFERENCES.md").foreach(f => assert(os.size(outbox / "sample" / f) > 0, f))

  check("an edit after accept shows as changed and blocks assemble and publish"):
    os.write.append(p / "sections" / "resumo.md", "\nUma frase nova depois do aceite.\n")
    assert("resumo .* changed".r.findFirstIn(thesis("sections", "sample").out.text()).isDefined)
    refused(thesis("assemble", "sample"))
    refused(thesis("publish", "sample", "--replace"))
