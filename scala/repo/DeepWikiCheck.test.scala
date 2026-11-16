package piabrota.repo

class DeepWikiCheckTest extends munit.FunSuite:
  def plan(json: String) = DeepWikiCheck.parse(ujson.read(json))

  test("a good plan has no problem"):
    assertEquals(DeepWikiCheck.problems(plan("""{"repo_notes":[],"pages":[{"title":"A","purpose":"p"},{"title":"B","purpose":"q","parent":"A"}]}""")), Nil)

  test("every rule"):
    val long = "x" * 10001
    val found = DeepWikiCheck.problems(plan(s"""{"pages":[{"title":"A","purpose":""},{"title":"A","purpose":"p","parent":"Z","page_notes":[{"content":"$long"}]}]}"""))
    assertEquals(found, List(
      "repo_notes is missing (use [] for none)",
      """a page needs a title and a purpose: {"title":"A","purpose":""}""",
      "duplicate page title: A",
      "page A: parent Z is not a page",
      "a note has 10001 characters: at most 10000",
    ))

  test("no pages"):
    assertEquals(DeepWikiCheck.problems(plan("""{"repo_notes":[]}""")), List("pages must list at least one page"))
