package piabrota.design

import piabrota.lib.{Exit, TestKit}

class InjectTest extends munit.FunSuite:
  import DesignFixtures.*

  private def css = realCss.getOrElse(fakeCss)
  private def foreign(body: String = "<main>x</main>") =
    s"""<!doctype html><html><head><title>t</title><script>var s = "<body class=fake>";</script></head>\n<body class="a">$body</body></html>"""

  test("inject: the bar goes right after the real <body> tag, once"):
    val once = Inject.injectHtml(css, foreign(), "proof", sites, Some("/"))
    assert(once.contains("</head>\n<body class=\"a\"><style>"))
    assertEquals(once.split(Inject.marker, -1).length - 1, 1)
    assertEquals(Inject.injectHtml(css, once, "proof", sites, Some("/")), once)
    assert(once.contains("""<script>var s = "<body class=fake>";</script>"""), "the page is otherwise the same")
    assert(once.endsWith("<main>x</main></body></html>"))

  test("inject: a tag in capitals, comments between </head> and <body>, and no </head>"):
    val upper = Inject.injectHtml(css, "<HTML><HEAD></HEAD>\n<!-- <body x> -->\n<BODY ID=b>y</BODY>", "proof", sites, None)
    assert(upper.contains("<BODY ID=b><style>"), upper)
    val noHead = Inject.injectHtml(css, "<html><title>t</title><body>first<body>second", "proof", sites, None)
    assert(noHead.startsWith("<html><title>t</title><body><style>"), noHead)

  test("inject: marks the current site; fails with a message when there is no <body>"):
    val html = Inject.injectHtml(css, foreign(), "proof", sites, Some("/"))
    assert(html.contains("""href="https://proof.piabrota.art/" aria-current="page">proof"""))
    assert(html.contains("← proof index"))
    val e = intercept[Exit](Inject.injectHtml(css, "<html><head></head><p>x</p></html>", "proof", sites, None, "x/y.html"))
    assertEquals(e.message, "x/y.html: no <body> tag, so the brand bar has no place to go")

  test("inject: the bar's CSS starts with the dark tokens; the archify rule only on archify pages"):
    assert(Inject.barStyle(css).startsWith(".pb-chrome--bar{--bg: #0B0D12;"), Inject.barStyle(css))
    assert(!Inject.barStyle(css).contains("--bg: #FFFFFF") && !Inject.barStyle(css).contains(".toolbar"))
    assert(Inject.barStyle(css, "archify-theme").contains(".pb-chrome--bar ~ .toolbar"))
    assert(!Inject.barStyle(fakeCss).contains("/*"), "comments are dropped")
    assertEquals(Inject.barStyle(fakeCss).linesIterator.toList(1),
      ".pb-chrome--page { padding: 20px 0; } .pb-chrome--bar { all: initial; }")

  test("inject: every selector of the bar's CSS is scoped to .pb-chrome"):
    assume(realCss.isDefined, "design/css is not here (the Nix build has only scala/)")
    for html <- List("", "archify-theme") do
      val rules = "@media[^{]*\\{".r.replaceAllIn(Inject.barStyle(realCss.get, html), "")
      val selectors = """(?:^|\})\s*([^{}@]+)\{""".r.findAllMatchIn(rules).map(_.group(1).strip).toList
      assert(selectors.size > 10, selectors)
      for s <- selectors; part <- s.split(',') do assert(part.contains(".pb-chrome"), s"selector outside the bar: $part")

  test("design-inject inject and check, as the build runs them"):
    val dir = os.temp.dir(prefix = "inject")
    os.write(dir / "dist" / "a" / "page.html", foreign(), createFolders = true)
    os.write(dir / "dist" / "done.html", s"<body><div ${Inject.marker}></div></body>")
    os.write(dir / "dist" / "index.html", "<html><body>index</body></html>")
    val sitesFile = sitesJson(dir)
    val env = Map("DESIGN_CSS" -> fakeCssDir.toString)
    val check = TestKit.piabrota(Seq("design-inject", "check", "dist", "--except", "done.html"), env, dir)
    assertEquals(check.exitCode, 1)
    assertEquals(check.err.text(), "no brand bar in: a/page.html, index.html\n")
    val r = TestKit.piabrota(Seq("design-inject", "inject", "dist/a", "--current", "proof", "--sites", sitesFile.toString, "--index", "/"), env, dir)
    assertEquals(r.exitCode, 0, r.err.text())
    assertEquals(r.err.text(), "brand bar: 1 of 1 pages changed in dist/a\n")
    assert(os.read(dir / "dist" / "a" / "page.html").contains("""<a class="pb-back" href="/">← proof index</a>"""))
    val ok = TestKit.piabrota(Seq("design-inject", "check", "dist", "--except", "index.html"), env, dir)
    assertEquals((ok.exitCode, ok.err.text()), (0, "brand bar: every page of dist has it, except index.html\n"))
    val none = TestKit.piabrota(Seq("design-inject", "check", "dist/a"), env, dir)
    assertEquals(none.err.text(), "brand bar: every page of dist/a has it, except none\n")

  test("design-inject: a page without <body>, an unknown site, a wrong command"):
    val dir = os.temp.dir(prefix = "inject")
    os.write(dir / "d" / "x" / "y.html", "<html><p>x</p></html>", createFolders = true)
    val env = Map("DESIGN_CSS" -> fakeCssDir.toString)
    val sitesFile = sitesJson(dir).toString
    val r = TestKit.piabrota(Seq("design-inject", "inject", "d", "--current", "proof", "--sites", sitesFile), env, dir)
    assertEquals((r.exitCode, r.err.text()), (1, "x/y.html: no <body> tag, so the brand bar has no place to go\n"))
    os.write.over(dir / "d" / "x" / "y.html", "<body></body>")
    val unknown = TestKit.piabrota(Seq("design-inject", "inject", "d", "--current", "nope", "--sites", sitesFile), env, dir)
    assertEquals((unknown.exitCode, unknown.err.text()), (1, "design kit: \"nope\" is not in design/sites.nix\n"))
    val usage = TestKit.piabrota(Seq("design-inject", "bogus", "d"), env, dir)
    assertEquals((usage.exitCode, usage.err.text()), (1, "usage: design-inject inject|check <dir> ...\n"))
