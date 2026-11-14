package piabrota.design

import piabrota.lib.{Exit, Sh}

/** What the tests of the kit share: the sites, a stand-in of design/css, and the real files of the
  * repository when the tests run in a checkout (`just scala-test`). The Nix build has only scala/,
  * so the tests that read the real CSS, site/ or design/sites.nix are skipped there.
  */
object DesignFixtures:
  val sites: List[Site] = List(
    Site("www", "www", "https://www.piabrota.art/", Access.Public),
    Site("proof", "proof", "https://proof.piabrota.art/", Access.Public),
    Site("pirsig", "pirsig", "https://pirsig.piabrota.art/", Access.Public),
    Site("rig", "rig", "https://rig.piabrota.art/", Access.Login),
  )

  def sitesJson(dir: os.Path): os.Path =
    val file = dir / "sites.json"
    os.write.over(file, ujson.write(sites.map(s =>
      ujson.Obj("id" -> s.id, "label" -> s.label, "url" -> s.url, "host" -> "h", "line" -> "l", "access" -> s.access.id))))
    file

  lazy val repo: Option[os.Path] =
    Iterator.iterate(os.pwd.toIO)(_.getParentFile).takeWhile(_ != null).map(os.Path(_))
      .find(d => os.exists(d / "design" / "sites.nix"))

  lazy val realCss: Option[Css] = repo.map(r => Css(r / "design" / "css"))

  /** A small design/css with the shapes the code reads; each module's text is its own. */
  lazy val fakeCssDir: os.Path =
    val dir = os.temp.dir(prefix = "design-css")
    os.write(dir / "tokens.css", ":root {\n  --bg: #0B0D12;\n  --text: #EDEFF3;\n  color-scheme: dark;\n}\n@media (prefers-color-scheme: light) {\n  :root { --bg: #FFFFFF; }\n}\n")
    os.write(dir / "base.css", "/* base */\n.pb-wrap { margin: 0 auto; }\n")
    os.write(dir / "chrome.css", "/* chrome:\n   two lines */\n.pb-chrome--page { padding: 20px 0; }\n.pb-chrome--bar {\n  all: initial;\n}\n")
    Module.optional.filter(_ != Module.Chrome).foreach(m => os.write(dir / m.file, s"/* ${m.name} */\n.pb-${m.name} { color: red; }\n"))
    dir

  lazy val fakeCss: Css = Css(fakeCssDir)

class KitTest extends munit.FunSuite:
  import DesignFixtures.*

  private val evil = """<script>alert("x")</script> & 'q'"""
  private def safe(html: String): Unit =
    assert(!html.contains("<script>") && !html.contains("alert(\"x\")"), html)

  test("every text is escaped"):
    safe(Kit.hero(eyebrow = evil, title = evil, tail = evil, lede = evil, stats = List(Stat(evil, evil)),
      actions = List(Action(evil, "/x"))))
    safe(Kit.section(id = evil, title = evil, count = Some(1), note = evil, body = ""))
    safe(Kit.card(title = evil, line = evil, foot = evil, href = "/x", pills = List(Pill(evil), Pill(evil, Tone.Accent))))
    safe(Kit.footer(sites, evil, "proof"))
    safe(Kit.page(fakeCss, title = evil, description = evil, body = ""))
    assert(Kit.card("a\"b", href = "/x\"y").contains("""href="/x&quot;y""""))

  test("a link with a script scheme is refused"):
    intercept[Exit](Kit.card("t", href = "javascript:alert(1)"))
    val e = intercept[Exit](Kit.hero("t", actions = List(Action("l", " data:text/html,x"))))
    assert(e.message.contains("scheme"), e.message)
    assert(Kit.card("t", href = "https://example.org/a?b=c&d=e").contains("a?b=c&amp;d=e"))

  test("hero: eyebrow, title with a muted tail, lede, stats as a dl, one primary action"):
    val html = Kit.hero(eyebrow = "e", title = "t", tail = "· tail", lede = "l", stats = List(Stat("3", "pages")),
      actions = List(Action("go", "/a", Variant.Primary), Action("abc1234", "/b", Variant.Mono), Action("plain", "https://x.org/")))
    assert(html.contains("""<p class="pb-eyebrow">e</p>"""))
    assert(html.contains("""<h1 class="pb-title">t <span class="pb-tail">· tail</span></h1>"""))
    assert(html.contains("""<dl class="pb-stats"><div><dt>pages</dt><dd>3</dd></div></dl>"""))
    assertEquals("pb-btn--primary".r.findAllIn(html).size, 1)
    assert(html.contains("pb-btn--mono"))
    assert(html.contains("""<a class="pb-btn" href="https://x.org/" rel="noopener">plain</a>"""))
    assert("pb-stats|pb-actions|pb-lede|pb-eyebrow|pb-hero__mark".r.findFirstIn(Kit.hero("t")).isEmpty)

  test("section: heading, count and body; no typed number"):
    val html = Kit.section(id = "a", title = "T", count = Some(4), note = "n", body = "<p>b</p>")
    assert(html.startsWith("""<section class="pb-section" id="a">"""))
    assert(html.contains("""<h2 class="pb-section__title">T</h2><span class="pb-count">4</span>"""))
    assert(html.contains("<p>b</p>"))
    assert(!html.contains("§"))
    assert(Kit.main(html).startsWith("""<main class="pb-main""""))

  test("cards: a card has pills, a title, a line, a foot; a link covers it; an empty grid is nothing"):
    val html = Kit.card("T", "L", "/f", "/p", List(Pill("EN"), Pill("live", Tone.Ok)))
    assertEquals(html, """<li class="pb-card"><div class="pb-card__pills"><span class="pb-pill">EN</span><span class="pb-pill pb-pill--ok">live</span></div><h3 class="pb-card__title"><a href="/p">T</a></h3><p class="pb-card__line">L</p><p class="pb-card__foot">/f</p></li>""")
    assert("<a |pb-card__pills|pb-card__line|pb-card__foot".r.findFirstIn(Kit.card("T")).isEmpty)
    assertEquals(Kit.cardGrid(Nil), "")
    assertEquals(Kit.cardGrid(List("<li>a</li>", "<li>b</li>")), """<ul class="pb-cards"><li>a</li><li>b</li></ul>""")

  test("pill: each tone is its class; the plain pill has none"):
    assertEquals(Kit.pill(Pill("x", Tone.Ok)), """<span class="pb-pill pb-pill--ok">x</span>""")
    assertEquals(Kit.pill(Pill("x", Tone.Mono)), """<span class="pb-pill pb-pill--mono">x</span>""")
    assertEquals(Kit.pill(Pill("x", Tone.Off)), """<span class="pb-pill pb-pill--none">x</span>""")
    assertEquals(Kit.pill(Pill("x")), """<span class="pb-pill">x</span>""")

  test("chrome: the page header lists the public sites and marks the current one"):
    val html = Kit.chrome("proof", sites)
    assert(html.contains("""aria-current="page">proof</a>"""))
    assert(html.contains("""href="https://www.piabrota.art/">www</a>"""))
    assert(!html.contains("rig") && !html.contains("data-pb-chrome"))
    val e = intercept[Exit](Kit.chrome("nope", sites))
    assertEquals(e.message, """design kit: "nope" is not in design/sites.nix""")

  test("chrome: the bar carries the marker, the eye and a link back to the index"):
    val html = Kit.chrome("proof", sites, Chrome.Bar(Some("/")))
    assert(html.contains(Inject.marker))
    assert(html.contains("""<a class="pb-back" href="/">← proof index</a>"""))
    assert("""<svg [^>]*class="pb-eye"""".r.findFirstIn(html).isDefined)
    assert(!Kit.chrome("proof", sites, Chrome.Bar(None)).contains("pb-back"))

  test("the eye has one copy"):
    assertEquals("#BC2318".r.findAllIn(Kit.eye(28)).size, 1)
    assert(Kit.eye(22).contains("""width="22""""))

  test("footer: the public sites and the line"):
    val html = Kit.footer(sites, "Built.", "proof")
    assert(html.contains("<p>Built.</p>"))
    assert(html.contains("""aria-current="page">proof"""))
    assert(!html.contains("rig"))

  test("page: inlines tokens, base and exactly the modules asked, in a fixed order"):
    val css = fakeCss
    val html = Kit.page(css, title = "T", description = "D", modules = List(Module.Footer, Module.Cards),
      icons = """<link rel="icon" href="/i.svg">""", body = "<p>b</p>")
    val at = List(Module.Tokens, Module.Base, Module.Cards, Module.Footer).map(m => html.indexOf(css(m)))
    assert(at.forall(_ >= 0) && at == at.sorted, at)
    Module.optional.filterNot(Set(Module.Cards, Module.Footer)).foreach(m => assert(!html.contains(css(m)), s"${m.name} was not asked"))
    assert(html.startsWith("<!doctype html>\n<html lang=\"en\">"))
    assert(html.contains("""<title>T</title><meta content="D" name="description">"""))
    assert(html.contains("""<link rel="icon" href="/i.svg">"""))
    assert(html.endsWith("</style></head>\n<body><p>b</p></body></html>\n"))
    assert(!html.contains("<script"))
    assert(intercept[Exit](Kit.page(css, "T", "", "")).message.contains("description"))

  test("modules: every class is prefixed, and one needs no other but tokens and base"):
    assume(realCss.isDefined, "design/css is not here (the Nix build has only scala/)")
    val css = realCss.get
    val comment = """/\*[\s\S]*?\*/""".r
    for m <- Module.optional do
      val text = comment.replaceAllIn(css(m), "")
      val classes = """\.([a-z][\w-]*)""".r.findAllMatchIn(text).map(_.group(1)).toList
      assert(classes.nonEmpty && classes.forall(_.startsWith("pb-")), s"${m.name}: ${classes.filterNot(_.startsWith("pb-"))}")
      Module.optional.filter(_ != m).foreach(other => assert(!text.contains(s".pb-${other.name}"), s"${m.name} depends on ${other.name}"))

  // The values of the :root block of the dark part and of the light part, as name -> value.
  private def tokensOf(text: String): (Map[String, String], Map[String, String]) =
    val parts = text.split("""@media \(prefers-color-scheme: light\)""", 2)
    def read(block: String) =
      """(--[\w-]+):\s*([^;]+);""".r.findAllMatchIn(block).map(m => m.group(1) -> m.group(2).strip).toMap
    def root(s: String) = """:root\s*\{[^}]*\}""".r.findFirstIn(s).getOrElse("")
    (read(root(parts(0))), read(root(parts.lift(1).getOrElse(""))))

  private def repoFile(rel: String): String =
    assume(repo.isDefined, "the repository is not here (the Nix build has only scala/)")
    os.read(repo.get / os.RelPath(rel))

  test("drift: the tokens of the kit are those of site/static/style.css"):
    val (kitDark, kitLight) = tokensOf(repoFile("design/css/tokens.css"))
    val (homeDark, homeLight) = tokensOf(repoFile("site/static/style.css"))
    for (kit, home, mode) <- List((kitDark, homeDark, "dark"), (kitLight, homeLight, "light")); (name, value) <- home do
      kit.get(name).foreach(v => assertEquals(v, value, s"$mode $name"))
    for name <- List("--bg", "--surface", "--border", "--text", "--muted", "--accent", "--accent-text", "--ok", "--warn", "--none") do
      assert(kitDark.contains(name) && homeDark.contains(name), s"$name is in both")

  test("drift: the theme switch of site/static/style.css flips to the same tokens"):
    val text = repoFile("site/static/style.css")
    val (dark, light) = tokensOf(text)
    def flipped(scheme: String) =
      val block = s"""@media \\(prefers-color-scheme: $scheme\\) \\{\\s*:root:has\\(#theme:checked\\) \\{[^}]*\\}""".r
        .findFirstIn(text).getOrElse(fail(s"no theme switch for $scheme"))
      """(--[\w-]+):\s*([^;]+);""".r.findAllMatchIn(block).map(m => m.group(1) -> m.group(2).strip).toMap
    assertEquals(flipped("dark"), light, "checked on a dark system: the light tokens")
    val toDark = flipped("light")
    light.keys.foreach(name => assertEquals(toDark.get(name), dark.get(name), s"checked on a light system: dark $name"))

  test("drift: the tokens of the kit are the table of site/DESIGN.md"):
    val (dark, light) = tokensOf(repoFile("design/css/tokens.css"))
    val rows = repoFile("site/DESIGN.md").linesIterator.toList.flatMap { line =>
      val cells = line.split('|').map(_.strip).toList
      def found(i: Int, re: String) = cells.lift(i).map(re.r.findAllIn(_).toList).filter(_.nonEmpty)
      for names <- found(1, """--[\w-]+"""); d <- found(2, "#[0-9A-Fa-f]{6}"); l <- found(3, "#[0-9A-Fa-f]{6}")
      yield (names, d, l)
    }
    // `--sea` (the owner, 2026-11-11) is the home page's own token, not the kit's: it is checked
    // against site/static/style.css instead.
    val (siteDark, siteLight) = tokensOf(repoFile("site/static/style.css"))
    for (names, d, l) <- rows; (name, i) <- names.zipWithIndex do
      val (darkOf, lightOf) = if dark.contains(name) then (dark, light) else (siteDark, siteLight)
      assertEquals(darkOf.get(name), d.lift(i), s"dark $name")
      assertEquals(lightOf.get(name).orElse(darkOf.get(name)), l.lift(i), s"light $name")
    assertEquals(rows.size, 7, "the table rows with colours: bg, surface, border, text and muted, accent, accent-text, sea")

  test("sites.nix: the public sites have ids, addresses and a line"):
    assume(repo.isDefined, "design/sites.nix is not here (the Nix build has only scala/)")
    val out = Sh.outOpt("nix-instantiate", "--eval", "--json", "--strict", "-E",
      s"(import ${repo.get / "design" / "sites.nix"}).sites")
    assume(out.isDefined, "nix-instantiate is not on the path")
    val list = ujson.read(out.get).arr.toList.map(_.obj)
    assertEquals(list.map(_("id").str).distinct.size, list.size, "ids are unique")
    for s <- list do
      assertEquals(s.keys.toList.sorted, List("access", "host", "id", "label", "line", "url"))
      assert(Set("public", "login")(s("access").str))
      assertEquals(s("url").str.stripPrefix("https://").takeWhile(_ != '/'), s("host").str, s"${s("id").str}: url and host agree")
    assertEquals(list.filter(_("access").str == "login").map(_("id").str).sorted, List("hermes", "rig"))
