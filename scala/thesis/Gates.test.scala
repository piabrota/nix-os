package piabrota.thesis

/** The parsers behind the gates, on small inputs. The whole commands are in ThesisTest. */
class GatesTest extends munit.FunSuite:
  test("Cites finds keys, hand-typed marks and numbered citations, not cross-references"):
    val c = Cites("Ver [@a2020; @b:x, p. 2] e @fig:um, (Silva, 2020) e [3].\n\n`@code` $@m$\n", 40)
    assertEquals(c.keys.map(_.text), Vector("a2020", "b:x"))
    assertEquals(c.hand, Vector(Mark(1, "(Silva, 2020)")))
    assertEquals(c.numbered, Vector(Mark(1, "[3]")))

  test("Cites counts a long inline quotation"):
    val c = Cites("Ele disse \"um dois três quatro cinco\" ontem.\n", 3)
    assertEquals(c.quotes, Vector(InlineQuote(1, 5)))

  test("Bib.rows reads entries and fields, and skips @comment"):
    val rows = Bib.rows("@comment{x}\n@Article{k1,\n  Title = {Um {T}ítulo\n   longo},\n  year = 2020\n}\n")
    assertEquals(rows.map(r => (r.key, r.kind, r.field)), Vector(("k1", "article", "@entry"), ("k1", "article", "title"), ("k1", "article", "year")))
    assertEquals(rows(0).value, "2")

  test("RefRow.rows skips the header and the rule, and lower-cases the status"):
    val rows = RefRow.rows("| Key | Status | Checked against | Note |\n|---|---|---|---|\n| `k1` | **Verified** | pdf | ok |\n")
    assertEquals(rows, Vector(RefRow("k1", "verified", "pdf", "ok")))

  test("Prose.sentences does not end a sentence at an abbreviation"):
    val s = Prose.sentences("O Dr. Silva mediu. Depois saiu.\n", Set("dr"))
    assertEquals(s.count(_.isProse), 2)

  test("Validate wants the front-page data only for the final work"):
    val profile = Profile.from(ujson.read("""{"courses":[{"name":"Engenharia Naval"}],"cite":{"score_targets":{"medium":0.3,"none":0}}}"""))
    val t = ujson.read("""{"course":"Engenharia Naval","month":3,"year":2027,"language":"pt-BR","citation_style":"author-date",
      "examiners":[],"title":"A PREENCHER","sections":[{"id":"resumo","kind":"pretextual","role":"resumo","order":10,
      "title":"Resumo","brief":"b","target_words":200,"status":"todo","cite_class":"none"}]}""")
    assertEquals(Validate.problems(t, profile, `final` = false), Some(Nil))
    assert(Validate.problems(t, profile, `final` = true).exists(_.contains("title is not filled")))

  test("Validate reports a repeated order with the ids that use it"):
    val profile = Profile.from(ujson.read("""{"courses":[],"cite":{"score_targets":{"medium":0.3}}}"""))
    val t = ujson.read("""{"sections":[{"id":"a","order":1},{"id":"b","order":1}]}""")
    assert(Validate.problems(t, profile, `final` = false).exists(_.contains("the order 1 is used by a, b")))

  test("Validate cannot check a thesis.json whose sections are not a list"):
    assertEquals(Validate.problems(ujson.read("""{"sections":3}"""), Profile.from(ujson.Obj()), `final` = false), None)

  test("Claim renders and parses its seat and epoch"):
    val c = Claim("writer-a", 1700000000L)
    assertEquals(Claim.parse(c.render("intro", "2023-11-14T22:13:20Z")), Some(c))
    assertEquals(Claim.parse("seat=\nepoch=1\n"), None)

  test("SectionState keeps a word it does not know"):
    assertEquals(SectionState.parse("linted"), SectionState.Linted)
    assertEquals(SectionState.parse("odd").render, "odd")

  test("Decision.parse refuses anything but accept and revise"):
    assertEquals(Decision.parse("revise"), Right(Decision.Revise))
    assertEquals(Decision.parse("ok"), Left("verdict: say accept or revise"))

  test("RefRow.asShellRead moves the cells after an empty one left, as read did"):
    assertEquals(RefRow("k", "partial", "", "unconfirmed: year").asShellRead, RefRow("k", "partial", "unconfirmed: year", ""))

  test("Profile.from reads the numbers, the bands of the slop signals and the allowed characters"):
    val p = Profile.from(ujson.read("""{"limits":{"claim_stale_s":7200},"slop":{"weights":{"dashes":8},"warn":{"dashes":2.0},
      "max":{"dashes":12}},"lists":{"allowed_chars":[[97,99]],"abbreviations":["dr prof","sr"]},
      "layout":{"margin_min_mm":{"top":25,"left":30}}}"""))
    assertEquals(Profile.show(p.limits.claimStaleS), "7200")
    assertEquals(p.slop.bands(Signal.Dashes), Band(8, 2, 12))
    assertEquals(p.lists.allowedChars, Set(97, 98, 99))
    assertEquals(p.lists.abbreviations, Set("dr", "prof", "sr"))
    assertEquals(p.page.marginMinMm, Sides(25.0, 0.0, 30.0, 0.0))

  test("Config falls back to the defaults and refuses a share without profile.json"):
    val share = os.temp.dir()
    os.write(share / Names.ProfileJson, "{}")
    val env = Map(Config.Env.Share -> share.toString, Config.Env.Seat -> "ana")
    val c = Config.fromEnv(env.get, os.root).toOption.get
    assertEquals((c.share, c.home, c.seat, c.pandocTimeout), (share, os.Path(Config.DefaultHome), Some("ana"), None))
    assert(Config.fromEnv(Map(Config.Env.Share -> "/nonexistent").get, os.root).isLeft)
    os.remove.all(share)

  test("Kit.memberFolder: the first folder under home, not projects/ or out/"):
    assertEquals(Kit.memberFolder("/h/ana/x", "/h"), Some("ana"))
    assertEquals(Kit.memberFolder("/h/projects/s", "/h"), None)
    assertEquals(Kit.memberFolder("/elsewhere", "/h"), None)

  test("ProjectCommands.rules keeps the common, style and role sections"):
    val text = "## common\na @ID@\n## role:chapter\nb\n## role:resumo\nc\n## style\nd\n"
    assertEquals(ProjectCommands.rules(text, "chapter", "intro"), List("a intro", "b", "d"))

  test("Poppler.notInOrder looks for each title after the page of the one before"):
    val pages = Vector("Sumário\n", " Um \n", "Dois\n", "Um\n")
    assertEquals(Poppler.notInOrder(pages, 1, List("Dois", "Um", "Três")), List("Três"))
    assertEquals(Poppler.notInOrder(pages, 1, List("Um", "Dois")), Nil)

  test("Lint.length: under the target fails, and a resumo needs its keywords"):
    val rules = WordRules(250, 3, 6, 40, 0.5, 1.6)
    val sec = Section("resumo", ujson.read("""{"id":"resumo","role":"resumo","target_words":200,"keywords":["a"]}"""))
    val rows = Prose.sentences("Uma frase curta aqui.\n", Set.empty)
    assertEquals(Lint.length(rules, sec, rows, 0).map(f => (f.level, f.rule)), Vector((Level.Fail, LintRule.Length), (Level.Fail, LintRule.Keywords)))

  test("ReadabilityNumbers.syllables counts vowel groups and splits strong pairs"):
    assertEquals(List("casa", "poesia", "saúde", "x").map(ReadabilityNumbers.syllables), List(2, 3, 3, 1))
