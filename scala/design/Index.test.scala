package piabrota.design

import piabrota.lib.TestKit

class IndexTest extends munit.FunSuite:
  import DesignFixtures.*

  private val rev = "b863c15e56a22afaab2fa228fe5eb85847c1d6c4"
  private def ctx = Index.Context(fakeCss, rev, sites, "")

  test("titles: entities decoded, white space folded, empty when missing"):
    assertEquals(ManifestScan.titleOf("<TITLE>z3-scala: every\nZ3 &amp; more &#39;x&#39; &#x41; </TITLE>"), "z3-scala: every Z3 & more 'x' A")
    assertEquals(ManifestScan.titleOf("<p>no title</p>"), "")
    assertEquals(ManifestScan.decode("&unknown; &LT;b&gt; &#x1F600;"), "&unknown; <b> 😀")
    assertEquals(ManifestScan.langOf("<html lang=\"pt-BR\">"), "pt-BR")
    assertEquals(ManifestScan.langOf("<HTML class=x LANG=en-US>"), "en-US")
    assertEquals(ManifestScan.langOf("<html>"), "en")

  test("groups: the first folder under proof/, docs/<name> for docs, a pirsig folder as it is"):
    assertEquals(ManifestScan.groupOf(SiteName.Proof, "proof/contextual-bandits/script/results.html"), "contextual-bandits")
    assertEquals(ManifestScan.groupOf(SiteName.Proof, "proof/docs/decisions/0001.html"), "docs/decisions")
    assertEquals(ManifestScan.groupOf(SiteName.Proof, "proof/index.html"), "")
    assertEquals(ManifestScan.groupOf(SiteName.Pirsig, "figures/para.html"), "figures")
    assertEquals(ManifestScan.groupTitle("z3-scala", "z3-scala: every Z3 check of this repository, in Scala · proof"), "z3-scala")
    assertEquals(ManifestScan.groupTitle("docs/decisions", ""), "Decisions")
    assertEquals(ManifestScan.groupTitle("contextual-bandits", ""), "Contextual bandits")

  private def tree(): os.Path =
    val dir = os.temp.dir(prefix = "proof-site")
    def put(path: String, html: String) = os.write(dir / os.RelPath(path), html, createFolders = true)
    put("proof/index.html", "<html lang=\"en\"><title>proof</title>")
    put("proof/a/index.html", "<html lang=\"en\"><title>Alpha: the first · proof</title>")
    put("proof/a/index.pt-BR.html", "<html lang=\"pt-BR\"><title>Alfa · proof</title>")
    put("proof/docs/diagrams/index.html", "<html lang=\"en\"><title>Diagrams · proof</title>")
    put("proof/docs/diagrams/en/x.html", "<html lang=\"en\"><title>One round: how it goes Diagram</title>archify-theme")
    put("proof/docs/diagrams/pt-BR/x.html", "<html lang=\"pt-BR\"><title>Diagrama Uma rodada</title>archify-theme")
    put("videos/index.html", "<html lang=\"pt-BR\"><title>Vídeos</title><p>2 vídeos indexados.</p>")
    dir

  test("scan: group, language, kind, the dark address of archify pages, the video count"):
    val m = ManifestScan.scan(tree(), SiteName.Proof)
    val by = m.pages.map(p => p.path -> p).toMap
    assertEquals(by("proof/docs/diagrams/en/x.html").href, "proof/docs/diagrams/en/x.html?theme=dark")
    assertEquals(by("proof/docs/diagrams/en/x.html").kind, PageKind.Diagram)
    assertEquals(by("proof/a/index.pt-BR.html").lang, "pt-BR")
    assertEquals(by("proof/a/index.html").href, "proof/a/index.html")
    assertEquals(m.groups, List(Group("a", "Alpha"), Group("docs/diagrams", "Diagrams")))
    assertEquals(m.videos, Some(2L))
    assert(!m.pages.exists(_.path == "index.html"))

  test("manifest JSON: the shape and the key order of manifest.mjs"):
    val groups = List(Group("b", "B"), Group("10", "Ten"), Group("2", "Two"), Group("02", "Zero two"))
    val m = Manifest(SiteName.Proof, Nil, Manifest.jsKeyOrder(groups)(_.id), None)
    assertEquals(ujson.write(m.render, indent = 1),
      "{\n \"site\": \"proof\",\n \"pages\": [],\n \"groups\": {\n  \"2\": \"Two\",\n  \"10\": \"Ten\",\n  \"b\": \"B\",\n  \"02\": \"Zero two\"\n },\n \"videos\": null\n}")
    assertEquals(Manifest.parse(ujson.read(ujson.write(m.render))), Right(m))

  test("proof index: a section for each group, then the diagrams by language; the repository index is an action, not a card"):
    val html = Index.proofIndex(ManifestScan.scan(tree(), SiteName.Proof), ctx)
    assert(html.contains("""<h2 class="pb-section__title">Alpha</h2><span class="pb-count">2</span>"""))
    assert(html.contains("""<h2 class="pb-section__title">Diagrams</h2><span class="pb-count">2</span>"""))
    assert(html.indexOf(">Alpha<") < html.indexOf(">Diagrams<"))
    assert(html.contains("""<h3 class="pb-sub">English</h3>"""))
    assert(html.contains("""<h3 class="pb-sub">Português (BR)</h3>"""))
    assert(html.indexOf(">English<") < html.indexOf(">Português (BR)<"))
    assert(html.contains("""href="proof/docs/diagrams/en/x.html?theme=dark""""))
    assert(html.contains("""<a class="pb-btn" href="proof/index.html">Its own index</a>"""))
    assert(!html.contains("""pb-card__title"><a href="proof/index.html""""))
    assert(html.contains("<dt>pages</dt><dd>2</dd>"))
    assert(html.contains("<dt>languages</dt><dd>2</dd>"))
    assert(html.contains(">b863c15</a>"))
    assert(!html.contains("<script"))

  test("proof index: the cards of a group show a language pill only when the group has two languages"):
    val html = Index.proofIndex(ManifestScan.scan(tree(), SiteName.Proof), ctx)
    val alpha = html.substring(html.indexOf("id=\"a\""), html.indexOf("id=\"diagrams\""))
    assertEquals("pb-pill".r.findAllIn(alpha).size, 2)

  test("diagram titles: the card splits \"Name: what it says\" and drops the Diagram word"):
    val html = Index.proofIndex(ManifestScan.scan(tree(), SiteName.Proof), ctx)
    assert(html.contains("""<h3 class="pb-card__title"><a href="proof/docs/diagrams/en/x.html?theme=dark">One round</a></h3><p class="pb-card__line">how it goes</p>"""))
    assertEquals(Index.cleanTitle(Page("p", "p", "Diagrama Uma rodada", "", "pt-BR", PageKind.Diagram)), "Uma rodada")
    assertEquals(Index.cleanTitle(Page("p", "p", "Diagrama Uma rodada · proof", "", "pt-BR", PageKind.Plain)), "Diagrama Uma rodada")

  test("pirsig index: the video count is said only when the page said it"):
    val m = ManifestScan.scan(tree(), SiteName.Pirsig)
    val withCount = Index.pirsigIndex(m, ctx)
    assert(withCount.contains("2 vídeos indexados"))
    assert(withCount.contains("<dt>video notes</dt><dd>2</dd>"))
    val without = Index.pirsigIndex(m.copy(videos = None), ctx)
    assert("indexado|<dt>video note".r.findFirstIn(without).isEmpty)
    assert(Index.pirsigIndex(m.copy(videos = Some(1)), ctx).contains("1 vídeo indexado<"))

  test("lines of code: blank and comment lines left out, block comments across lines, the badge's scan"):
    val agda = "{-# OPTIONS --safe #-}\nmodule M where\n\n-- a comment\n{- a\n   block -} x = 1\nopen import X -- after code\n"
    assertEquals(Loc.countCode(agda, Language.Agda), 3)
    assertEquals(Loc.countCode("/- doc -/\ntheorem t : True := trivial\n  --\n", Language.Lean), 1)
    // after code the line is not read further, so this /* opens nothing
    assertEquals(Loc.countCode("val p = \"src/*.F90\"\nval q = 1\n", Language.Z3), 2)
    assertEquals(Loc.countCode("a b\r\nc\u0085d", Language.Z3), 4)
    assertEquals(Loc.countCode(" // a comment after a no-break space\n", Language.Z3), 0)

  test("lines of code: Z3 is the Scala of z3-scala/, vendor/ is left out"):
    val dir = os.temp.dir(prefix = "proof-loc")
    def put(path: String, text: String) = os.write(dir / os.RelPath(path), text, createFolders = true)
    put("z3-scala/src/A.scala", "object A\n")
    put("other/B.scala", "object B\n")
    put("cycle/C.lean", "def c := 1\ndef d := 2\n")
    put("vendor/x/D.lean", "def d := 1\n")
    put("agda/src/E.agda", "e = 1\n")
    put("agda/vendor/F.agda", "f = 1\n")
    val c = Loc.count(dir).map(n => n.language -> n).toMap
    import Language.*
    assertEquals(List(c(Z3).files, c(Z3).lines, c(Lean).files, c(Lean).lines, c(Agda).files, c(Agda).lines), List(1, 1, 1, 2, 2, 2))

  test("proof index: the lines of Lean 4, Agda and Z3 in the hero, only when they were counted"):
    val loc = LocCount.parse(ujson.read("""{"lean":{"label":"Lean 4","files":18,"lines":1264},"agda":{"label":"Agda","files":14,"lines":617},"z3":{"label":"Z3","files":28,"lines":2475}}""")).fold(fail(_), identity)
    val html = Index.proofIndex(ManifestScan.scan(tree(), SiteName.Proof), ctx.copy(loc = loc))
    assert(html.contains("<dt>lines of Lean 4</dt><dd>1,264</dd>"))
    assert(html.contains("<dt>lines of Agda</dt><dd>617</dd>"))
    assert(html.contains("<dt>lines of Z3</dt><dd>2,475</dd>"))
    assertEquals(Index.locStats(Nil), Nil)
    assertEquals(Index.thousands(1234567), "1,234,567")
    assert(!Index.proofIndex(ManifestScan.scan(tree(), SiteName.Proof), ctx).contains("lines of"))

  test("proof-manifest, proof-loc and proof-index, as the build runs them"):
    val dist = tree()
    val work = os.temp.dir(prefix = "proof-cmd")
    val env = Map("DESIGN_CSS" -> fakeCssDir.toString)
    val manifest = TestKit.piabrota(Seq("proof-manifest", dist.toString, "proof"), env, work)
    assertEquals(manifest.exitCode, 0, manifest.err.text())
    assert(manifest.out.text().startsWith("{\n \"site\": \"proof\",\n \"pages\": [\n  {\n   \"path\": \"proof/a/index.html\",\n"))
    assert(manifest.out.text().endsWith("\n \"videos\": 2\n}\n"))
    os.write(work / "manifest.json", manifest.out.text())

    val src = os.temp.dir(prefix = "proof-src")
    os.write(src / "a" / "A.lean", "def a := 1\n-- no\n", createFolders = true)
    val loc = TestKit.piabrota(Seq("proof-loc", src.toString), env, work)
    assertEquals((loc.exitCode, loc.out.text()), (0, """{"lean":{"label":"Lean 4","files":1,"lines":1}}"""))
    os.write(work / "loc.json", loc.out.text())
    val empty = TestKit.piabrota(Seq("proof-loc", work.toString), env, work)
    assertEquals((empty.exitCode, empty.err.text()), (1, s"proof-loc: no Lean 4, Agda or Z3 file under $work\n"))

    val sitesFile = sitesJson(work).toString
    val index = TestKit.piabrota(Seq("proof-index", "proof", "manifest.json", "--rev", rev, "--sites", sitesFile,
      "--icons", "<link rel=\"icon\">", "--loc", "loc.json"), env, work)
    assertEquals(index.exitCode, 0, index.err.text())
    val html = index.out.text()
    assert(html.startsWith("<!doctype html>\n") && html.endsWith("</body></html>\n"))
    assert(html.contains("<link rel=\"icon\"><link href=\"https://fonts.googleapis.com\""))
    assert(html.contains("<dt>lines of Lean 4</dt><dd>1</dd>"))
    val bad = TestKit.piabrota(Seq("proof-index", "other", "manifest.json", "--rev", rev, "--sites", sitesFile), env, work)
    assertEquals(bad.exitCode, 1)
    assert(bad.err.text().startsWith("usage: proof-index <proof|pirsig>"))
