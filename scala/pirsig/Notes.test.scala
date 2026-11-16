package piabrota.pirsig

import java.time.{ZoneOffset, ZonedDateTime}

import BrainFixture.note

class NotesRulesTest extends munit.FunSuite:
  val existing = Set("10 Repo awesome-ocean-science")
  def validate(notes: ujson.Value*): Seq[String] = Notes.validate(ujson.Arr.from(notes), existing)
  def links(target: String, why: String) = ujson.Arr(ujson.Obj("target" -> target, "why" -> why))

  test("a good note passes"):
    assertEquals(validate(note()), Nil)

  test("the rules"):
    val cases = List(
      "approved is the owner's word" -> note("status" -> "approved"),
      "needs its source" -> note("type" -> "literature"),
      "no note in the brain" -> note("links" -> links("nothing", "x")),
      "has no reason" -> note("links" -> links("10 Repo awesome-ocean-science", "")),
      "no link" -> note("links" -> ujson.Arr()),
      "email" -> note("body" -> "Fale com joao@example.com."),
      "lowercase-with-hyphens" -> note("tags" -> ujson.Arr("Big Tag")),
      "more than one idea" -> note("body" -> "palavra " * 501),
    )
    for (expected, n) <- cases do
      assert(validate(n).exists(_.contains(expected)), s"$expected: ${validate(n)}")

  test("links inside one call, and proposed_link"):
    val batch = Seq(note("title" -> "A", "links" -> links("B", "B explains A")),
      note("title" -> "B", "links" -> ujson.Arr(), "proposed_link" -> "a note on Luhmann's box"))
    assertEquals(validate(batch*), Nil)

  test("the files"):
    val now = ZonedDateTime.of(2026, 11, 3, 22, 0, 0, 0, ZoneOffset.UTC)
    val batch = Seq(
      note("title" -> "Notas ligadas voltam", "tags" -> ujson.Arr("pkm"), "links" -> links("Uma ideia, uma nota", "a mesma regra")),
      note("title" -> "Uma ideia, uma nota", "proposed_link" -> "uma nota sobre Luhmann"),
    ).map(NoteDraft.parse)
    val files = Notes.build(batch, Map("10 Repo awesome-ocean-science" -> "Repo: awesome-ocean-science"), now)
    assertEquals(files.map(_.path), Seq("brain/Inbox/202611032200-notas-ligadas-voltam.md",
      "brain/Inbox/202611032201-uma-ideia-uma-nota.md"))
    val Seq(first, second) = files.map(_.content)
    assert(first.startsWith("---\nid: \"202611032200\"\ntitle: \"Notas ligadas voltam\"\nkind: fleeting\n"), first)
    assert(first.contains("tags: [\"pkm\", \"status/unverified\", \"hermes\"]\ncreated: 2026-11-03T22:00:00+00:00\n---\n\n# Notas"), first)
    assert(!first.contains("pirsig:"))
    assert(first.contains("- [[202611032201-uma-ideia-uma-nota]] Uma ideia, uma nota: a mesma regra"), first)
    assert(second.contains("- [[10 Repo awesome-ocean-science]] Repo: awesome-ocean-science: an example"), second)
    assert(second.contains("\n⚠ uma nota sobre Luhmann\n"), second)

  test("1 to 20 notes"):
    for batch <- List(ujson.Arr(), ujson.Str("not a list"), ujson.Arr.from(Seq.fill(21)(note()))) do
      assertEquals(Notes.validate(batch, existing), Seq("give 1 to 20 notes"))

  test("the same title twice in one call"):
    assertEquals(validate(note("title" -> "A"), note("title" -> "a")),
      Seq("two notes have the same title: one idea, one note"))

  test("title length and the source of a literature note"):
    assertEquals(validate(note("title" -> "a" * 160)), Nil)
    assertEquals(validate(note("type" -> "literature", "source" -> "Autor, 2020")), Nil)
    for title <- List("a" * 161, "") do
      assertEquals(validate(note("title" -> title)), Seq("note 1: the title is one line of at most 160 characters"))

  test("the word limit and email addresses"):
    assertEquals(validate(note("body" -> "palavra " * 501)), Seq("note 1: 501 words; more than 500 is more than one idea"))
    assertEquals(validate(note("title" -> "a@b.co", "body" -> "c@d.co e")),
      Seq.fill(2)("note 1: an email address; people appear by nickname only"))

  test("every rule, in order, with the note's number"):
    val bad = note("title" -> "x\ny", "type" -> "poem", "status" -> "approved", "body" -> "", "source" -> "a@b.co",
      "tags" -> ujson.Arr("Big"), "links" -> links("x\ny", ""))
    assertEquals(validate(note("title" -> "Ok"), bad), Seq(
      "note 2: the title is one line of at most 160 characters",
      "note 2: type is one of fleeting, literature, permanent",
      "note 2: status is one of unverified, partial, verified, open-question (approved is the owner's word)",
      "note 2: no body",
      "note 2: an email address; people appear by nickname only",
      "note 2: tag 'Big' is not lowercase-with-hyphens",
      "note 2: the link to 'x\\ny' has no reason",
      "note 2: links to itself",
    ))

  test("slugs drop marks and keep six words"):
    assertEquals(Notes.slugify("Ação é coração, não CÓDIGO! um dois três"), "acao-e-coracao-nao-codigo-um")
    assertEquals(Notes.slugify("¿?"), "untitled")
    assertEquals(Notes.slugify("Links beat folders", 5), "links-beat-folders")

class NotesPullRequestTest extends munit.FunSuite:
  test("search finds a note of the brain"):
    assume(BrainFixture.gitThere, "git is not on the PATH")
    val f = BrainFixture()
    val out = f.tool("pirsig_note_search", ujson.Obj("query" -> "ocean"))
    assertEquals(out("matches")(0)("zid").str, "10")
    assertEquals(out("matches")(0)("stem").str, "10 Repo awesome-ocean-science")
    assertEquals(out("repo").str, "piabrota/pirsig")
    assertEquals(f.tool("pirsig_note_search", ujson.Obj("query" -> " ")), ujson.Obj("error" -> "no query"))

  test("submit pushes a hermes/ branch and opens a pull request"):
    assume(BrainFixture.gitThere, "git is not on the PATH")
    val f = BrainFixture()
    val out = f.tool("pirsig_notes_submit", ujson.Obj("request" -> "The owner asked to save one idea.", "notes" -> ujson.Arr(note())))
    assert(!out.obj.contains("error"), out)
    assertEquals(out.obj.keys.toList, List("files", "branch", "pr"))
    assertEquals(out("branch").str, "hermes/notes-links-beat-folders")
    assertEquals(out("pr").str, "https://github.com/piabrota/pirsig/pull/1")
    val files = f.originFiles(out("branch").str)
    assert(files.contains(out("files")(0).str), files)
    assert(files.contains("src/main.rs"), "the sparse checkout must not drop files from the commit")
    val log = os.read.lines(f.ghLog)
    assertEquals(log.take(2), Seq("pr", "create"))
    assert(log.contains("hermes/notes-links-beat-folders"))
    // the same idea again gets a branch of its own
    val again = f.tool("pirsig_notes_submit", ujson.Obj("request" -> "Again.", "notes" -> ujson.Arr(note())))
    assertEquals(again("branch").str, "hermes/notes-links-beat-folders-2")

  test("submit refuses broken notes and a missing request"):
    assume(BrainFixture.gitThere, "git is not on the PATH")
    val f = BrainFixture()
    val out = f.tool("pirsig_notes_submit", ujson.Obj("request" -> "x", "notes" -> ujson.Arr(note("status" -> "approved"))))
    assertEquals(out("error").str, "the notes break the smart-note rules; fix them and call again")
    assert(out("problems").arr.nonEmpty)
    assert(!os.exists(f.ghLog))
    assertEquals(f.tool("pirsig_notes_submit", ujson.Obj("notes" -> ujson.Arr(note()))),
      ujson.Obj("error" -> "say in `request` what the owner asked for"))

  test("PIRSIG_REPO and PIRSIG_BASE choose the repository"):
    assume(BrainFixture.gitThere, "git is not on the PATH")
    val f = BrainFixture()
    assertEquals(f.tool("pirsig_note_search", ujson.Obj("query" -> "x"), Map("PIRSIG_REPO" -> "not-a-repo")),
      ujson.Obj("error" -> "not a GitHub repository: not-a-repo"))
    val out = f.tool("pirsig_note_search", ujson.Obj("query" -> "x"), Map("PIRSIG_BASE" -> "dev"))
    assert(out("error").str.startsWith("git clone --quiet failed: "), out)

class BrainTest extends munit.FunSuite:
  /** A Brain whose checkout is already a clone of the fixture's origin, so no test needs gh. */
  def brain(): Brain =
    val f = BrainFixture()
    val b = Brain(f.tmp / "data", "piabrota/pirsig", "main")
    os.proc("git", "clone", "--quiet", f.origin, b.path).call(stderr = os.Pipe)
    b

  test("a pull request writes only new files under brain/"):
    assume(BrainFixture.gitThere, "git is not on the PATH")
    val b = brain()
    for bad <- List("src/evil.rs", "brain/../src/main.rs", "brain", "/etc/passwd") do
      assertEquals(intercept[BrainError](b.openPr(Seq(NewFile(bad, "x")), "x", "t", "b")).message,
        s"refused: $bad is outside brain/")
    val known = "brain/Zettelkasten/10 Repo awesome-ocean-science.md"
    assertEquals(intercept[BrainError](b.openPr(Seq(NewFile(known, "x")), "x", "t", "b")).message,
      s"refused: $known is already in piabrota/pirsig; a note is never rewritten")
    assertEquals(intercept[BrainError](b.openPr(Nil, "x", "t", "b")).message, "nothing to submit")

  test("a repository name is owner/name"):
    assertEquals(intercept[BrainError](Brain(os.temp.dir(), "a/b/c", "main")).message, "not a GitHub repository: a/b/c")

  test("front matter: flat keys, JSON strings, the body after it"):
    val FrontMatter(fm, body) = FrontMatter.parse(BrainFixture.Note10)
    assertEquals(fm, Map("pirsig" -> "note", "zid" -> "10", "title" -> "Repo: awesome-ocean-science", "kind" -> "literature"))
    assertEquals(body, "# Repo: awesome-ocean-science\n\nAn index of ocean data.\n")
    assertEquals(FrontMatter.parse("no front matter"), FrontMatter(Map.empty, "no front matter"))
    assertEquals(FrontMatter.parse("---\na: \"b\\\"\n - c: d\n---\nx").fields, Map("a" -> "b\\"))

  test("the commit body is the PR body's first paragraph"):
    assertEquals(Brain.commitBody("# Title\n\nThe reason.\n\nMore."), "The reason.")
    assertEquals(Brain.commitBody("  "), "")
