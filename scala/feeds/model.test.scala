package piabrota.feeds

import java.time.LocalDate
import FeedTest.*

class ModelTest extends munit.FunSuite:
  test("a source kind by its feeds.toml name"):
    assertEquals(SourceKind.values.toList.map(k => SourceKind.parse(k.key)), SourceKind.values.toList.map(Some(_)))
    assertEquals(SourceKind.parse("rss"), None)

  test("the state round trip, sorted by id"):
    val state = State(Map("b" -> "2026-11-04", "a" -> "2026-11-03"))
    assertEquals(state.render, "{\n  \"seen\": {\n    \"a\": \"2026-11-03\",\n    \"b\": \"2026-11-04\"\n  }\n}")
    assertEquals(State.parse(state.render), state)
    assertEquals(State.parse("not json"), State.empty)
    assertEquals(State.parse("""{"seen": {"a": 1, "b": "x"}}"""), State(Map("b" -> "x")))
    assertEquals(State.empty.withSeen(List("a"), LocalDate.parse("2026-11-04")), State(Map("a" -> "2026-11-04")))

  test("the paths: the command line first, then the feeds home"):
    val home = os.root / "h" / "feeds"
    val env = Environment(home, None)
    assertEquals(Paths.of(Args(), env), Paths(home / "feeds.toml", home / "out", home / "state.json"))
    assertEquals(Paths.of(Args(out = Some(os.root / "o")), env).out, os.root / "o")

  test("the environment"):
    val vars = Map("HERMES_HOME" -> "/srv/hermes", "GITHUB_TOKEN" -> "t")
    assertEquals(Environment.from(vars.get), Environment(os.root / "srv" / "hermes" / "feeds", Some("t")))
    assertEquals(Environment.from(_ => None), Environment(os.home / ".hermes" / "feeds", None))
    assertEquals(Environment.from(Map("HERMES_HOME" -> "~/h").get).feedsHome, os.home / "h" / "feeds")

  test("the request of each kind"):
    assertEquals(FeedBuild.requestFor(source, Now, Some("t")), Request("https://example.org/feed"))
    val gh = FeedBuild.requestFor(source.copy(kind = SourceKind.GithubSearch, query = "q"), Now, Some("t"))
    assert(gh.url.startsWith(GithubApi.SearchUrl), gh.url)
    assertEquals(gh.headers, Seq(GithubApi.Accept, "Authorization" -> "Bearer t"))

  test("a source with an unknown kind after a duplicate id: the duplicate is named"):
    val row = ConfigReader.SourceRow("a", "agents", None)
    val good = ConfigReader.SourceRow("a", "agents", Some(source))
    val groups = List(Group("agents", "Agents"))
    assertEquals(ConfigReader.checkSources(List(good, row), groups), Left("duplicate source id: a"))
    assertEquals(ConfigReader.checkSources(List(row), groups), Left("source a: unknown group or kind"))
    assertEquals(ConfigReader.checkSources(List(good), groups), Right(List(source)))

  test("the items not yet seen, at the digest threshold"):
    val seenItem = item.copy(link = "https://x/seen", score = 9.0)
    val newItem = item.copy(link = "https://x/new", score = 9.0)
    val weak = item.copy(link = "https://x/weak", score = 1.0)
    val report = Report(Cfg, Nil, Nil, List(seenItem, newItem, weak), Nil, Now)
    val seen = State(Map(Links.itemId(seenItem.link) -> "2026-11-04"))
    assertEquals(FeedBuild.fresh(report, seen), List(newItem))
