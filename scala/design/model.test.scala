package piabrota.design

class ModelTest extends munit.FunSuite:
  test("sites.json: each site with its access; a missing key or an unknown access is a message"):
    val ok = ujson.read("""[{"id":"proof","label":"proof","url":"https://proof.piabrota.art/","host":"h","access":"public"}]""")
    assertEquals(Site.parseAll(ok), Right(List(Site("proof", "proof", "https://proof.piabrota.art/", Access.Public))))
    assertEquals(Site.parseAll(ujson.read("""[{"id":"x","label":"x","url":"u"}]""")), Left("no access"))
    assertEquals(Site.parseAll(ujson.read("""[{"id":"x","label":"x","url":"u","access":"open"}]""")),
      Left("""design kit: access "open" is neither public nor login"""))
    assertEquals(Site.parseAll(ujson.read("{}")), Left("not a list"))

  test("site names: proof and pirsig, with the folder of their pages"):
    assertEquals(SiteName.parse("proof").map(_.prefix), Some("proof/"))
    assertEquals(SiteName.parse("pirsig").map(_.prefix), Some(""))
    assertEquals(SiteName.parse("other"), None)

  test("loc.json: rendered by language id, read back in the order of Language"):
    val counts = List(LocCount(Language.Lean, 18, 1264), LocCount(Language.Z3, 28, 2475))
    assertEquals(ujson.write(LocCount.render(counts)),
      """{"lean":{"label":"Lean 4","files":18,"lines":1264},"z3":{"label":"Z3","files":28,"lines":2475}}""")
    val reordered = ujson.read("""{"z3":{"label":"Z3","files":28,"lines":2475},"x":{},"lean":{"label":"Lean 4","files":18,"lines":1264}}""")
    assertEquals(LocCount.parse(reordered), Right(counts))
    assertEquals(LocCount.parse(ujson.read("""{"lean":{"files":1}}""")), Left("no lines"))

  test("languages: which files each one counts"):
    assert(Language.Lean.matches("a/B.lean") && Language.Agda.matches("C.agda"))
    assert(Language.Z3.matches("z3-scala/src/A.scala") && !Language.Z3.matches("other/A.scala"))

  test("flags: the first, the last and all the values of a name"):
    val f = Flags.parse(List("--a", "1", "--b", "2", "--a", "3", "--dangling"))
    assertEquals((f.first("a"), f.last("a"), f.all("a"), f.first("c")), (Some("1"), Some("3"), List("1", "3"), None))
    assertEquals(f.all("dangling"), Nil)

  test("css: DESIGN_CSS first, else design/css under the folder; neither is a message"):
    val dir = os.temp.dir(prefix = "css")
    os.write(dir / "design" / "css" / "tokens.css", ":root{}", createFolders = true)
    assertEquals(Css.locate(None, dir).map(_(Module.Tokens)), Right(":root{}"))
    assertEquals(Css.locate(None, dir / "design"), Left("DESIGN_CSS is not set: it names the folder of design/css"))
    assertEquals(Css.locate(Some("design/css"), dir).map(_(Module.Tokens)), Right(":root{}"))

  test("modules: tokens and base always, then the optional ones in a fixed order"):
    assertEquals(Module.optional.map(_.name), List("chrome", "hero", "section", "cards", "pills", "footer", "prose"))

  test("manifest: a page kind that is not known is a message"):
    val bad = ujson.read("""{"site":"proof","pages":[{"path":"p","href":"p","title":"t","group":"","lang":"en","kind":"x"}],"groups":{},"videos":null}""")
    assertEquals(Manifest.parse(bad), Left("no page kind x"))
