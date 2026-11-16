package piabrota.feeds

import java.nio.charset.StandardCharsets.UTF_8
import java.time.{Duration, Instant}
import scala.xml.Elem
import piabrota.lib.Exit

/** The tests of the Python script (hermes/feeds/tests/test_build_feed.py), with the network as a
  * function: no test opens a socket. FeedBuildCli.test.scala runs the binary with a stand-in curl.
  */
object FeedTest:
  val Now: Instant = Instant.parse("2026-11-04T12:00:00Z")

  def config(toml: String): Config =
    Toml.parse(toml, "test.toml").flatMap(Config.fromToml(_, "test.toml")).fold(sys.error, identity)

  val Base = """
    |title = "Test feed"
    |[output]
    |min_score = 4.0
    |digest_items = 5
    |digest_min_score = 6.0
    |[negative]
    |terms = ["giveaway"]
    |[[group]]
    |id = "agents"
    |title = "Agents"
    |[[group]]
    |id = "science"
    |title = "Science"
    |[[interest]]
    |name = "Coding agents"
    |origin = "chat"
    |weight = 4
    |terms = ["omp", "claude code"]
    |[[interest]]
    |name = "Rust"
    |origin = "profile"
    |weight = 3
    |terms = ["rust"]
    |""".stripMargin

  val Cfg: Config = config(Base)

  /** No HERMES_HOME and no token: every run of a test names its files. */
  val Env: Environment = Environment(os.home / ".hermes" / "feeds", None)

  val RunConfig = """
    |title = "Test feed"
    |[output]
    |max_items = 10
    |digest_items = 5
    |digest_per_group = 10
    |digest_min_score = 6.0
    |[negative]
    |terms = ["giveaway"]
    |[[group]]
    |id = "agents"
    |title = "Agents"
    |[[group]]
    |id = "science"
    |title = "Science"
    |[[interest]]
    |name = "Coding agents"
    |origin = "chat"
    |weight = 4
    |terms = ["omp"]
    |[[interest]]
    |name = "Rust"
    |origin = "profile"
    |weight = 3
    |terms = ["rust"]
    |[[source]]
    |id = "rss"
    |group = "agents"
    |kind = "feed"
    |url = "https://example.org/rss.xml"
    |weight = 5
    |limit = 10
    |max_age_days = 30
    |[[source]]
    |id = "atom"
    |group = "science"
    |kind = "feed"
    |url = "https://example.org/atom.xml"
    |weight = 3
    |pinned = true
    |limit = 10
    |max_age_days = 60
    |[[source]]
    |id = "gh"
    |group = "agents"
    |kind = "github_search"
    |query = "topic:x created:>{d7}"
    |weight = 2
    |limit = 10
    |max_age_days = 14
    |""".stripMargin

  def source: Source = Source(id = "s", group = "agents", kind = SourceKind.Feed, weight = 3, maxAgeDays = 21,
    pinnedKeep = 3, url = "https://example.org/feed")

  def item: Item = Item(title = "T", link = "https://example.org/a", summary = "", date = Now, dated = true,
    source = "s", group = "agents")

  def hoursAgo(h: Double): Instant = Now.minusMillis((h * 3600000).toLong)
  def daysAgo(d: Int): Instant = Now.minus(Duration.ofDays(d))
  def bytes(s: String): Array[Byte] = s.getBytes(UTF_8)
  def utc(s: String): Instant = Instant.parse(s)

  /** A network in a list: the first prefix that starts the URL gives the answer. */
  final class FakeFetch(responses: List[(String, Either[FetchError, Array[Byte]])]) extends Fetch:
    private val asked = scala.collection.mutable.ListBuffer.empty[String]
    def calls: List[String] = synchronized(asked.toList)
    def apply(url: String, headers: Seq[(String, String)]): Either[FetchError, Array[Byte]] =
      synchronized(asked += url)
      responses.collectFirst { case (prefix, answer) if url.startsWith(prefix) => answer }
        .getOrElse(throw AssertionError(s"unexpected URL $url"))

  def goodResponses: List[(String, Either[FetchError, Array[Byte]])] = List(
    "https://example.org/rss.xml" -> Right(bytes(Fixtures.Rss)),
    "https://example.org/atom.xml" -> Right(bytes(Fixtures.Atom)),
    "https://api.github.com/" -> Right(bytes(Fixtures.Github)),
  )

  def loadXml(text: String): Elem = Parse.xml(text)

  def atomOf(data: Array[Byte]): Elem = loadXml(new String(data, UTF_8))

import FeedTest.*

class ParsingTest extends munit.FunSuite:
  test("rss"):
    val items = Parse.feed(bytes(Fixtures.Rss), source, Now)
    assertEquals(items.map(_.title), List("Oh-my-pi & omp: release notes", "A complicated story", "An item with no date"))
    assertEquals(items(0).summary, "Short teaser & more.")
    assertEquals(items(0).date, utc("2026-11-04T06:00:00Z"))
    assertEquals(items(1).summary, "The Rust port, in full.")
    assertEquals(items(1).date, utc("2026-11-02T12:00:00Z"))

  test("an item without a link is dropped and one without a date gets the run time"):
    val items = Parse.feed(bytes(Fixtures.Rss), source, Now)
    assert(!items.map(_.title).contains("An item with no link"))
    assertEquals((items.last.date, items.last.dated), (Now, false))

  test("atom"):
    val items = Parse.feed(bytes(Fixtures.Atom), source, Now)
    assertEquals(items.map(_.title), List("v1.2.0", "v1.1.0"))
    assertEquals(items(0).link, "https://example.org/releases/v1.2.0")
    assertEquals(items(0).summary, "Fixes & adds Nix flake support.")
    assertEquals(items(1).date, utc("2026-10-01T06:30:00Z"))
    assertEquals(items(1).summary, "Plain summary.")

  test("a cut feed keeps its complete items"):
    val items = Parse.feed(bytes(Fixtures.PodcastCut), source.copy(limit = 6), Now)
    assertEquals(items.map(_.title), List("Episode 3: omp in practice", "Episode 2", "Episode 1"))

  test("the limit stops early"):
    assertEquals(Parse.feed(bytes(Fixtures.PodcastCut), source.copy(limit = 2), Now).length, 2)

  test("no item and broken XML is an error"):
    intercept[ParseError](Parse.feed(bytes("<html><body>Please wait"), source, Now))
    intercept[ParseError](Parse.feed(Array.emptyByteArray, source, Now))

  test("a feed in ISO-8859-1"):
    val text = "<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?><rss><channel><item><title>Olá maçã</title>" +
      "<link>https://x/1</link></item></channel></rss>"
    val items = Parse.feed(text.getBytes(java.nio.charset.StandardCharsets.ISO_8859_1), source, Now)
    assertEquals(items.map(_.title), List("Olá maçã"))

  test("html is stripped"):
    val text = "<p>Tom &amp; <b>Jerry</b>&nbsp;said&#33;</p>\n\n<br/>  a &lt; b and c &gt; d"
    assertEquals(Text.clean(text), "Tom & Jerry said! a < b and c > d")

  test("the summary is cut at 400"):
    assertEquals(Text.summarize("<p>" + "word " * 200 + "</p>").length, 399)

  test("control characters are removed"):
    assertEquals(Text.clean("a\u0000b\u001bc"), "abc")

  test("dates"):
    val expected = Some(utc("2026-11-04T09:00:00Z"))
    assertEquals(Dates.parse("Wed, 04 Nov 2026 06:00:00 -0300"), expected)
    assertEquals(Dates.parse("2026-11-04T09:00:00Z"), expected)
    assertEquals(Dates.parse("2026-11-04T11:00:00+02:00"), expected)
    assertEquals(Dates.parse("2026-11-04T09:00:00"), expected)
    assertEquals(Dates.parse("yesterday"), None)
    assertEquals(Dates.parse(""), None)

  test("github items"):
    val items = Parse.github(bytes(Fixtures.Github), source.copy(kind = SourceKind.GithubSearch, limit = 10), Now)
    assertEquals(items.map(_.title), List("acme/omp-tools", "acme/quiet", "acme/big"))
    assertEquals(items(0).link, "https://github.com/acme/omp-tools")
    assertEquals((items(0).summary, items(0).stars), ("Tools for omp users", 99))
    assertEquals(items(0).date, utc("2026-11-02T08:00:00Z"))
    assertEquals(items(1).summary, "")

  test("a github item is dated by its last push"):
    val repos = """{"items": [
      {"full_name": "old/active", "html_url": "https://github.com/old/active",
       "created_at": "2019-03-01T00:00:00Z", "pushed_at": "2026-11-03T12:00:00Z"},
      {"full_name": "old/no-push", "html_url": "https://github.com/old/no-push",
       "created_at": "2026-10-30T08:00:00Z", "pushed_at": null}]}"""
    val src = source.copy(kind = SourceKind.GithubSearch, weight = 2, maxAgeDays = 21)
    val List(active, noPush) = Parse.github(bytes(repos), src, Now): @unchecked
    assertEquals(active.date, utc("2026-11-03T12:00:00Z"))
    assertEquals(noPush.date, utc("2026-10-30T08:00:00Z"))
    assert(active.dated && noPush.dated)
    // base 2 + recency 2.0 (24 hours old), no stars
    assertEquals(Score.scoreItem(active, src, Cfg, Now).map(_.score), Some(4.0))
    val feed = atomOf(Outputs.atom(Report(Cfg, Nil, Nil, List(active), Nil, Now)))
    assertEquals((feed \ "entry" \ "updated").text, "2026-11-03T12:00:00Z")

  test("a github item pushed long ago is too old"):
    val repos = """{"items": [{"full_name": "old/idle", "html_url": "https://github.com/old/idle",
      "created_at": "2026-11-02T00:00:00Z", "pushed_at": "2019-03-01T00:00:00Z"}]}"""
    val src = source.copy(kind = SourceKind.GithubSearch, weight = 5, maxAgeDays = 21)
    val List(idle) = Parse.github(bytes(repos), src, Now): @unchecked
    assertEquals(Score.scoreItem(idle, src, Cfg, Now), None)

  test("github query dates"):
    val src = source.copy(kind = SourceKind.GithubSearch, query = "topic:x created:>{d7} pushed:>{d14} a:>{d30}", limit = 7)
    val url = FeedBuild.githubUrl(src, Now)
    assert(url.startsWith("https://api.github.com/search/repositories?"))
    val params = Links.queryPairs(url.split("\\?", 2)(1)).toMap
    assertEquals(params("q"), "topic:x created:>2026-10-28 pushed:>2026-10-21 a:>2026-10-05")
    assertEquals((params("sort"), params("order"), params("per_page")), ("stars", "desc", "7"))

  test("the github token only when it is set"):
    assertEquals(FeedBuild.githubHeaders(None), Seq("Accept" -> "application/vnd.github+json"))
    assertEquals(FeedBuild.githubHeaders(Some("dummy")).toMap.get("Authorization"), Some("Bearer dummy"))

  test("the apple genre filter"):
    val wanted = source.copy(kind = SourceKind.AppleChart, genres = List("Technology"), limit = 100)
    val items = Parse.apple(bytes(Fixtures.Apple), wanted, Now)
    assertEquals(items.map(_.title), List("Agents Weekly"))
    assertEquals((items(0).dated, items(0).date), (false, Now))
    assertEquals(items(0).summary, "Acme Labs. Technology, Podcasts")
    assertEquals(Parse.apple(bytes(Fixtures.Apple), source.copy(kind = SourceKind.AppleChart), Now).length, 3)

class LinkTest extends munit.FunSuite:
  test("normalise a link"):
    val link = "https://Example.org/posts/omp-1/?utm_source=rss&id=7&UTM_medium=x#top"
    assertEquals(Links.normalise(link), "https://example.org/posts/omp-1?id=7")
    assertEquals(Links.normalise("https://example.org/"), "https://example.org")

  test("the item id is stable across link variants"):
    val a = Links.itemId("https://Example.org/a/?utm_source=x#frag")
    assertEquals(a, Links.itemId("https://example.org/a"))
    assertEquals(a.length, 16)

  test("dedupe by link keeps the highest score"):
    val low = item.copy(link = "https://example.org/a/?utm_source=x", title = "Low", score = 5.0)
    val high = item.copy(link = "https://EXAMPLE.org/a", title = "High", score = 7.0)
    val other = item.copy(link = "https://example.org/b", title = "Other", score = 1.0)
    assertEquals(Score.dedupe(List(low, high, other)).map(_.title).toSet, Set("High", "Other"))

  test("dedupe by title"):
    val a = item.copy(link = "https://a.example/1", title = "Release: v2.0!", score = 4.0)
    val b = item.copy(link = "https://b.example/2", title = "release v2 0", score = 6.0)
    assertEquals(Score.dedupe(List(a, b)).map(_.score), List(6.0))

class ScoringTest extends munit.FunSuite:
  test("word boundaries"):
    val interest = Cfg.interests.head
    assert(Score.interestPoints(interest, item.copy(title = "Oh-my-pi and omp")) > 0)
    assert(Score.interestPoints(interest, item.copy(title = "OMP, again")) > 0)
    assert(Score.interestPoints(interest, item.copy(title = "Claude Code")) > 0)
    assertEquals(Score.interestPoints(interest, item.copy(title = "A complicated story")), 0.0)
    assertEquals(Score.interestPoints(interest, item.copy(title = "Tromp", summary = "pomp")), 0.0)

  test("the title beats the summary and counts once"):
    val interest = Cfg.interests.head
    assertEqualsDouble(Score.interestPoints(interest, item.copy(title = "omp omp", summary = "omp")), 4.8, 1e-9)
    assertEqualsDouble(Score.interestPoints(interest, item.copy(summary = "omp")), 1.6, 1e-9)

  test("the interest sum is capped"):
    val cfg = Cfg.copy(interests = List(Interest("A", 5, Terms(List("alpha"))), Interest("B", 5, Terms(List("beta")))))
    assertEquals(Score.interestScore(item.copy(title = "alpha beta"), cfg.interests), InterestScore(8.0, List("A", "B")))

  test("the exact score of one item"):
    // base 3 + title "omp" (3 * 4 / 5 * 2 = 4.8) + summary "rust" (1 * 3 / 5 * 2 = 1.2) + recency 2.0
    val it = item.copy(title = "Fixing the omp loop", summary = "Written in Rust", date = hoursAgo(12))
    val scored = Score.scoreItem(it, source.copy(weight = 3, maxAgeDays = 10), Cfg, Now).get
    assertEquals(scored.score, 11.0)
    assertEquals(scored.matched, List("Coding agents", "Rust"))

  test("a github item has a stars bonus"):
    val src = source.copy(kind = SourceKind.GithubSearch, weight = 2, maxAgeDays = 10)
    // recency at 2 days of 10: 2 * (1 - 1 / 9) = 1.78; stars: log10(100) / 1.5 = 1.33
    val scored = Score.scoreItem(item.copy(title = "acme/tool", date = hoursAgo(48), stars = 99), src, Cfg, Now)
    assertEquals(scored.map(_.score), Some(5.1))
    assertEquals(Score.starsBonus(1000000000), 3.0)
    assertEquals(Score.starsBonus(0), 0.0)

  test("the recency bonus"):
    val src = source.copy(maxAgeDays = 21)
    def bonus(i: Item) = Score.recencyBonus(i, src, Now)
    assertEquals(bonus(item.copy(date = Now)), 2.0)
    assertEquals(bonus(item.copy(date = hoursAgo(24))), 2.0)
    assertEquals(bonus(item.copy(date = daysAgo(11))), 1.0)
    assertEquals(bonus(item.copy(date = daysAgo(21))), 0.0)
    assertEquals(bonus(item.copy(date = Now, dated = false)), 0.0)

  test("a negative term drops an item by its title or summary"):
    val src = source.copy(weight = 5)
    assertEquals(Score.scoreItem(item.copy(title = "Free GIVEAWAY of omp"), src, Cfg, Now), None)
    assertEquals(Score.scoreItem(item.copy(title = "omp", summary = "a giveaway"), src, Cfg, Now), None)
    assert(Score.scoreItem(item.copy(title = "omp"), src, Cfg, Now).isDefined)

  test("requires_match"):
    val items = List(item.copy(title = "About omp", link = "https://x/1"), item.copy(title = "Nothing", link = "https://x/2"))
    val kept = Score.selectItems(source.copy(weight = 5, requiresMatch = true), items, Cfg, Now)
    assertEquals(kept.map(_.title), List("About omp"))
    assertEquals(Score.selectItems(source.copy(weight = 5), items, Cfg, Now).length, 2)

  test("min_score"):
    val weak = item.copy(title = "Nothing", date = daysAgo(20))
    assertEquals(Score.selectItems(source.copy(weight = 1), List(weak), Cfg, Now), Nil)
    assertEquals(Score.selectItems(source.copy(weight = 4), List(weak), Cfg, Now).length, 1)

  test("max_age_days"):
    val items = List(
      item.copy(link = "https://x/new", date = daysAgo(4)),
      item.copy(link = "https://x/old", date = daysAgo(6)),
      item.copy(link = "https://x/undated", dated = false),
    )
    val kept = Score.selectItems(source.copy(weight = 5, maxAgeDays = 5), items, Cfg, Now).map(_.link).toSet
    assertEquals(kept, Set("https://x/new", "https://x/undated"))

  test("a pinned source keeps its newest items whatever their score"):
    val items = List(1, 2, 4, 5).map(d => item.copy(link = s"https://x/$d", date = daysAgo(d)))
    val pinned = source.copy(weight = 1, pinned = true, pinnedKeep = 2, maxAgeDays = 10)
    assertEquals(Score.selectItems(pinned, items, Cfg, Now).map(_.link).toSet, Set("https://x/1", "https://x/2"))
    assertEquals(Score.selectItems(source.copy(weight = 1, maxAgeDays = 10), items, Cfg, Now), Nil)

  test("pinned items older than max_age_days are dropped"):
    val items = List(1, 4, 5).map(d => item.copy(link = s"https://x/$d", date = daysAgo(d)))
    val src = source.copy(weight = 1, pinned = true, pinnedKeep = 3, maxAgeDays = 3)
    assertEquals(Score.selectItems(src, items, Cfg, Now).map(_.link), List("https://x/1"))

  test("exclude_terms drop a title with the whole word"):
    val titles = List("v0.5.0-canary.3", "Canary build 7", "Canaryx 1", "v0.5.0")
    val items = titles.zipWithIndex.map((t, n) => item.copy(title = t, link = s"https://x/$n", summary = "canary in the summary"))
    val kept = Score.selectItems(source.copy(weight = 5, excludeTerms = List("canary")), items, Cfg, Now)
    assertEquals(kept.map(_.title), List("Canaryx 1", "v0.5.0"))
    assertEquals(Score.selectItems(source.copy(weight = 5), items, Cfg, Now).length, 4)

  test("the source keys exclude_terms and pinned_keep"):
    val cfg = config(Base.replace("[output]\n", "[output]\npinned_keep = 3\n") + """
      |[[source]]
      |id = "a"
      |group = "agents"
      |kind = "feed"
      |weight = 3
      |url = "https://x/a"
      |pinned = true
      |pinned_keep = 1
      |exclude_terms = ["canary", "nightly build"]
      |[[source]]
      |id = "b"
      |group = "agents"
      |kind = "feed"
      |weight = 3
      |url = "https://x/b"
      |""".stripMargin)
    val List(first, second) = cfg.sources: @unchecked
    assertEquals((first.pinnedKeep, first.excludeTerms), (1, List("canary", "nightly build")))
    assertEquals((second.pinnedKeep, second.excludeTerms), (3, Nil))
    val dropped = item.copy(title = "The Nightly Build is out")
    assert(Score.isExcluded(dropped, first))
    assert(!Score.isExcluded(dropped, second))

  test("rank orders by score, then date"):
    val a = item.copy(link = "https://x/a", score = 5.0, date = hoursAgo(5))
    val b = item.copy(link = "https://x/b", score = 5.0, date = hoursAgo(1))
    val c = item.copy(link = "https://x/c", score = 9.0, date = hoursAgo(50))
    assertEquals(Score.rank(List(a, b, c)).map(_.link.last), List('c', 'b', 'a'))

  test("round half to even on the exact value, as Python"):
    assertEquals(Score.round1(0.25), 0.2)
    assertEquals(Score.round1(0.35), 0.3) // 0.35 is 0.34999... as a double
    assertEquals(Score.round1(5.0 + 1.0 / 3), 5.3)

class OutputTest extends munit.FunSuite:
  def report(items: List[Item], now: Instant = Now, errors: List[String] = Nil, output: Output = Cfg.output): Report =
    Report(Cfg.copy(output = output), Nil, Nil, items, errors, now)

  def scoredItems: List[Item] = List(
    item.copy(title = "First & <best>", link = "https://x/1?a=1&b=2", score = 8.4, matched = List("Rust")),
    item.copy(title = "Second", link = "https://x/2", score = 6.0, group = "science", source = "arxiv"),
  )

  test("the atom feed parses and every entry is complete"):
    val root = atomOf(Outputs.atom(report(scoredItems)))
    assertEquals((root.label, root.namespace), ("feed", Outputs.Atom))
    for parent <- root +: (root \ "entry").collect { case e: Elem => e }; name <- List("id", "title", "updated") do
      assert((parent \ name).text.trim.nonEmpty, name)
    assertEquals((root \ "id").text, "tag:piabrota.art,2026:feed:personal")
    assertEquals((root \ "updated").text, "2026-11-04T12:00:00Z")
    val first = (root \ "entry").head
    assertEquals((first \ "title").text, "[agents] First & <best>")
    assertEquals(((first \ "link") \@ "rel", (first \ "link") \@ "href"), ("alternate", "https://x/1?a=1&b=2"))
    assertEquals((first \ "summary") \@ "type", "text")
    assertEquals((first \ "summary").text, "score 8.4 - s - Rust\n")
    assertEquals((first \ "category").map(_ \@ "term"), List("agents", "Rust"))

  test("the atom feed is byte for byte what ElementTree wrote"):
    val one = item.copy(title = "A \"q\" & b", link = "https://x/1?a=1&b=\"2\"", score = 8.4, stars = 3)
    val text = new String(Outputs.atom(report(List(one))), UTF_8)
    assertEquals(text,
      "<?xml version='1.0' encoding='utf-8'?>\n<feed xmlns=\"http://www.w3.org/2005/Atom\">" +
        "<id>tag:piabrota.art,2026:feed:personal</id><title>Test feed</title><updated>2026-11-04T12:00:00Z</updated>" +
        "<author><name>Test feed</name></author><entry><title>[agents] A \"q\" &amp; b</title>" +
        "<link rel=\"alternate\" href=\"https://x/1?a=1&amp;b=&quot;2&quot;\" />" +
        s"<id>tag:piabrota.art,2026:item:${Links.itemId(one.link)}</id><updated>2026-11-04T12:00:00Z</updated>" +
        "<summary type=\"text\">score 8.4 - s - 3 stars\n</summary><category term=\"agents\" /></entry></feed>")

  test("atom entry ids are stable between runs"):
    def ids(now: Instant) = (atomOf(Outputs.atom(report(scoredItems, now))) \ "entry" \ "id").map(_.text)
    assertEquals(ids(Now), ids(Now.plusSeconds(3 * 3600)))
    assert(ids(Now).forall(_.startsWith("tag:piabrota.art,2026:item:")))

  test("an atom feed without items is valid"):
    assertEquals((atomOf(Outputs.atom(report(Nil))) \ "entry").length, 0)

  test("the digest format and groups"):
    val it = item.copy(title = "A_b *c* [d]", link = "https://x/1", score = 8.4, source = "src", date = daysAgo(2))
    val later = item.copy(title = "Sci", link = "https://x/2", score = 6.0, group = "science", date = hoursAgo(5))
    assertEquals(Outputs.renderDigest(List(later, it), Cfg, Now, Nil).linesIterator.toList, List(
      "# Digest 2026-11-04",
      "",
      "## Agents",
      "- **8.4** A\\_b \\*c\\* \\[d\\] - src, 2d",
      "  <https://x/1>",
      "",
      "## Science",
      "- **6.0** Sci - s, 5h",
      "  <https://x/2>",
    ))

  test("the digest date is the date in Sao Paulo"):
    val late = utc("2026-11-05T01:00:00Z")
    assertEquals(Outputs.renderDigest(Nil, Cfg, late, Nil).linesIterator.next(), "# Digest 2026-11-04")

  test("the digest error line"):
    assertEquals(Outputs.renderDigest(Nil, Cfg, Now, List("bad", "worse")).linesIterator.toList.last,
      "Sources with errors: bad, worse")

  test("the digest is cut in whole items"):
    val items = (0 until 5).toList.map(n => item.copy(title = s"Item $n " + "x" * 200, link = s"https://x/$n", score = 9.0 - n / 10.0))
    val r = report(items, errors = List("bad"), output = Cfg.output.copy(digestPerGroup = 5))
    val chosen = Outputs.pickDigest(items, r, 700)
    val text = Outputs.renderDigest(chosen, Cfg, Now, List("bad"))
    assert(text.length <= 700)
    assertEquals(chosen, items.take(chosen.length))
    assert(chosen.nonEmpty && chosen.length < 5)
    assertEquals(text.split("- \\*\\*", -1).length - 1, chosen.length)
    assertEquals(text.split("  <https://", -1).length - 1, chosen.length)
    assert(text.endsWith("Sources with errors: bad\n"))

  test("the digest item limit"):
    val items = (0 until 9).toList.map(n => item.copy(link = s"https://x/$n", score = 9.0))
    assertEquals(Outputs.pickDigest(items, report(items, output = Cfg.output.copy(digestPerGroup = 9))).length, 5)

  def busy = (0 until 30).toList.map(n => item.copy(link = s"https://x/a$n", score = 9.0 - n / 10.0))
  def calm = (0 until 3).toList.map(n => item.copy(link = s"https://x/s$n", score = 5.0 - n, group = "science"))

  test("the feed share of a group is capped in the first pass"):
    val chosen = Score.selectForFeed(busy ++ calm, Output(maxItems = 17, maxPerGroup = 14))
    assertEquals(chosen.count(_.group == "agents"), 14)
    assertEquals(chosen.count(_.group == "science"), 3)

  test("the room that is left goes to the best of the rest"):
    val chosen = Score.selectForFeed(busy ++ calm, Output(maxItems = 20, maxPerGroup = 14))
    assertEquals(chosen.length, 20)
    assertEquals(chosen.count(_.group == "agents"), 17)
    assertEquals(chosen.map(_.score), chosen.map(_.score).sorted.reverse)
    assertEquals(chosen.filter(_.group == "agents").map(_.link).toSet, (0 until 17).map(n => s"https://x/a$n").toSet)

  test("the first pass never goes over max_items"):
    val items = for g <- List("agents", "science"); n <- (0 until 4).toList yield item.copy(link = s"https://x/$g$n", score = 9.0 - n, group = g)
    assertEquals(Score.selectForFeed(items, Output(maxItems = 5, maxPerGroup = 14)).length, 5)

  test("the share takes a pinned item before a better score"):
    val items = (0 until 5).toList.map(n => item.copy(link = s"https://x/$n", score = 9.0 - n)) :+
      item.copy(link = "https://x/pinned", score = 1.0, pinned = true)
    val chosen = Score.selectForFeed(items, Output(maxItems = 3, maxPerGroup = 3))
    assertEquals(chosen.map(_.link), List("https://x/0", "https://x/1", "https://x/pinned"))

  test("the digest takes at most digest_per_group of one group"):
    val items = for g <- List("agents", "science"); n <- (0 until 10).toList yield item.copy(link = s"https://x/$g$n", score = 9.0 - n / 10.0, group = g)
    val chosen = Score.selectForDigest(items, Output(digestItems = 18, digestPerGroup = 3))
    assertEquals(chosen.length, 6)
    assertEquals(chosen.map(_.link).toSet, (for g <- List("agents", "science"); n <- 0 until 3 yield s"https://x/$g$n").toSet)

  test("the digest is cut at digest_items with the best first"):
    val items = for g <- List("agents", "science"); n <- (0 until 4).toList
    yield item.copy(link = s"https://x/$g$n", score = 9.0 - n / 10.0 - (if g == "science" then 1 else 0), group = g)
    val chosen = Score.selectForDigest(items, Output(digestItems = 4, digestPerGroup = 3))
    assertEquals(chosen.map(_.link), List("https://x/agents0", "https://x/agents1", "https://x/agents2", "https://x/science0"))

  test("digest sections follow the config, not the score"):
    val science = item.copy(title = "Sci", link = "https://x/s", score = 9.0, group = "science")
    val agents = item.copy(title = "Agt", link = "https://x/a", score = 7.0)
    val r = report(List(science, agents))
    val text = Outputs.renderDigest(Outputs.pickDigest(List(science, agents), r), r.cfg, Now, Nil)
    assert(text.indexOf("## Agents") < text.indexOf("## Science"))
    assertEquals(Outputs.renderDigest(List(science), r.cfg, Now, Nil).split("## ", -1).length - 1, 1)

  test("opml"):
    val cfg = config(Base + """
      |[[source]]
      |id = "f1"
      |group = "agents"
      |kind = "feed"
      |weight = 3
      |url = "https://x/a?q=1&r=2"
      |[[source]]
      |id = "g1"
      |group = "agents"
      |kind = "github_search"
      |weight = 3
      |query = "topic:x"
      |[[source]]
      |id = "c1"
      |group = "science"
      |kind = "apple_chart"
      |weight = 3
      |url = "https://x/chart"
      |""".stripMargin)
    val data = Outputs.opml(cfg, cfg.sources)
    val root = loadXml(new String(data, UTF_8))
    assertEquals(root \@ "version", "2.0")
    val groups = root \ "body" \ "outline"
    assertEquals(groups.map(_ \@ "text"), List("Agents"))
    val feeds = groups.head \ "outline"
    assertEquals(feeds.map(f => (f \@ "type", f \@ "text", f \@ "xmlUrl")), List(("rss", "f1", "https://x/a?q=1&r=2")))
    assertEquals(new String(data, UTF_8),
      "<?xml version='1.0' encoding='utf-8'?>\n<opml version=\"2.0\"><head><title>Test feed</title></head><body>" +
        "<outline text=\"Agents\" title=\"Agents\"><outline type=\"rss\" text=\"f1\" title=\"f1\" " +
        "xmlUrl=\"https://x/a?q=1&amp;r=2\" /></outline></body></opml>")

  test("prune seen"):
    val old = Dates.utcDate(daysAgo(61)).toString
    val edge = Dates.utcDate(daysAgo(60)).toString
    assertEquals(State(Map("old" -> old, "edge" -> edge, "bad" -> "x")).pruned(Now), State(Map("edge" -> edge)))

class FetchTest extends munit.FunSuite:
  test("retry once on a timeout and on a 5xx"):
    for failure <- List(FetchError.Timeout, FetchError.Http(503)) do
      var calls = 0
      val sleeps = scala.collection.mutable.ListBuffer.empty[Double]
      def get() =
        calls += 1
        if calls == 1 then Left(failure) else Right(bytes("ok"))
      assertEquals(Fetch.withRetry(() => get(), sleeps += _).map(new String(_, UTF_8)), Right("ok"))
      assertEquals((calls, sleeps.toList), (2, List(2.0)))

  test("the second failure is the answer"):
    assertEquals(Fetch.withRetry(() => Left(FetchError.Timeout), _ => ()), Left(FetchError.Timeout))

  test("no retry on a 4xx"):
    for code <- List(403, 404, 429) do
      var calls = 0
      val answer = Fetch.withRetry(() => { calls += 1; Left(FetchError.Http(code)) }, _ => ())
      assertEquals((answer, calls), (Left(FetchError.Http(code)), 1))

  test("one request per host at a time"):
    val active = java.util.concurrent.atomic.AtomicInteger(0)
    val peak = java.util.concurrent.atomic.AtomicInteger(0)
    val probe: Fetch = (_, _) =>
      peak.accumulateAndGet(active.incrementAndGet(), (a, b) => math.max(a, b))
      Thread.sleep(10)
      active.decrementAndGet()
      Right(Array.emptyByteArray)
    val fetcher = Fetcher(open = probe)
    val threads = (1 to 6).map(_ => Thread(() => { fetcher("https://same.example/x", Nil); () }))
    threads.foreach(_.start())
    threads.foreach(_.join())
    assertEquals(peak.get, 1)

  test("a gap between github queries"):
    val sleeps = scala.collection.mutable.ListBuffer.empty[Double]
    val fetcher = Fetcher(open = (_, _) => Right(bytes("{}")), sleep = sleeps += _, clock = () => 100.0)
    fetcher("https://api.github.com/a", Nil)
    assertEquals(sleeps.toList, Nil)
    fetcher("https://api.github.com/b", Nil)
    assertEquals(sleeps.toList, List(7.0))
    fetcher("https://example.org/", Nil)
    fetcher("https://example.org/", Nil)
    assertEquals(sleeps.toList, List(7.0))

class RunTest extends munit.FunSuite:
  final case class Result(code: Int, stdout: String, stderr: String, fake: FakeFetch)

  val dir = FunFixture[os.Path](
    setup = _ =>
      val d = os.temp.dir(prefix = "feed")
      os.write(d / "feeds.toml", RunConfig)
      d,
    teardown = d => os.remove.all(d),
  )

  def runMain(d: os.Path, extra: String*)(responses: List[(String, Either[FetchError, Array[Byte]])] = goodResponses): Result =
    val fake = FakeFetch(responses)
    val out = java.io.ByteArrayOutputStream()
    val args = List("--config", (d / "feeds.toml").toString, "--out", (d / "out").toString,
      "--state", (d / "state.json").toString) ++ extra
    val (code, stderr) = Console.withOut(out) {
      try (FeedBuild.main(args, Env, fake, Now), "")
      catch case Exit(code, message) => (code, message + "\n")
    }
    Result(code, out.toString(UTF_8), stderr, fake)

  def entries(d: os.Path) = loadXml(os.read(d / "out" / "feed.atom")) \ "entry"
  def health(d: os.Path) = ujson.read(os.read(d / "out" / "health.json"))("sources")

  dir.test("the first run writes all outputs and prints the best"): d =>
    val r = runMain(d)()
    assertEquals((r.code, r.stderr), (0, ""))
    assert(r.stdout.startsWith("# Digest 2026-11-04\n"), r.stdout)
    assert(r.stdout.replace("\\", "").contains("Oh-my-pi & omp: release notes"))
    assert(r.stdout.length <= 1900)
    for name <- List("feed.atom", "digest.md", "sources.opml", "health.json") do assert(os.isFile(d / "out" / name), name)
    assertEquals(os.list(d / "out").filter(_.last.startsWith(".")), IndexedSeq.empty)
    assert(os.isFile(d / "state.json"))

  dir.test("a pinned source keeps a low score"): d =>
    runMain(d)()
    assert((entries(d) \ "title").map(_.text).contains("[science] v1.1.0"))

  dir.test("the second run prints nothing and the feed keeps its items"): d =>
    val first = runMain(d)()
    val count = entries(d).length
    val second = runMain(d)()
    assert(first.stdout.nonEmpty)
    assertEquals((second.code, second.stdout), (0, ""))
    assertEquals(entries(d).length, count)

  dir.test("the state holds the printed items only"): d =>
    runMain(d)()
    val seen = ujson.read(os.read(d / "state.json"))("seen").obj
    assertEquals(seen.values.map(_.str).toSet, Set("2026-11-04"))
    assertEquals(seen(Links.itemId("https://example.org/posts/omp-1?id=7")).str, "2026-11-04")
    assert(!seen.contains(Links.itemId("https://example.org/releases/v1.1.0")))
    assert(os.read(d / "state.json").startsWith("{\n  \"seen\": {\n    \""))

  dir.test("--no-state ignores and keeps the state"): d =>
    runMain(d)()
    val before = os.read(d / "state.json")
    val r = runMain(d, "--no-state")()
    assertEquals(r.code, 0)
    assert(r.stdout.nonEmpty)
    assertEquals(os.read(d / "state.json"), before)

  dir.test("--dry-run writes no file"): d =>
    val r = runMain(d, "--dry-run")()
    assertEquals(r.code, 0)
    assert(r.stdout.nonEmpty)
    assert(!os.exists(d / "out"))
    assert(!os.exists(d / "state.json"))

  dir.test("a failing source goes to health.json and the run exits 0"): d =>
    val r = runMain(d)(goodResponses.map {
      case ("https://example.org/atom.xml", _) => "https://example.org/atom.xml" -> Left(FetchError.Http(429))
      case other                               => other
    })
    assertEquals(r.code, 0)
    assertEquals(r.stdout.linesIterator.toList.last, "Sources with errors: atom")
    val h = health(d)
    assertEquals((h("atom")("status").str, h("atom")("error").str), ("error", "HTTP 429"))
    assertEquals(h("rss")("status").str, "ok")
    assertEquals(h("rss")("items").num, 3.0)
    assertEquals(h("rss")("newest").str, "2026-11-04T06:00:00Z")
    assertEquals(h("rss")("error"), ujson.Null)

  dir.test("an unparsable source is an error, not a crash"): d =>
    val r = runMain(d)(goodResponses.map {
      case ("https://example.org/atom.xml", _) => "https://example.org/atom.xml" -> Right(bytes("<html>blocked"))
      case other                               => other
    })
    assertEquals(r.code, 0)
    assertEquals(health(d)("atom")("status").str, "error")

  dir.test("every source failing exits 1 and keeps the old feed"): d =>
    runMain(d)()
    val old = os.read.bytes(d / "out" / "feed.atom")
    val r = runMain(d)(List("https://" -> Left(FetchError.Failed("down"))))
    assertEquals((r.code, r.stdout), (1, ""))
    assert(r.stderr.contains("no source ran"))
    assertEquals(os.read.bytes(d / "out" / "feed.atom").toList, old.toList)
    assertEquals(health(d).obj.values.map(_("status").str).toSet, Set("error"))

  dir.test("the deadline skips the sources not started"): d =>
    val r = runMain(d, "--max-seconds", "0")()
    assertEquals((r.code, r.fake.calls), (1, Nil))
    assert(r.stderr.contains("no source ran"))
    assertEquals(health(d).obj.values.map(_("status").str).toSet, Set("skipped"))

  dir.test("an unknown source id runs nothing"): d =>
    val r = runMain(d, "--dry-run", "--source", "does-not-exist")()
    assertEquals((r.code, r.stdout, r.fake.calls), (1, "", Nil))
    assert(r.stderr.contains("no source ran"))

  dir.test("--source limits the run"): d =>
    val r = runMain(d, "--source", "rss")()
    assertEquals((r.code, r.fake.calls), (0, List("https://example.org/rss.xml")))

  dir.test("a github source asks the dated query"): d =>
    val r = runMain(d, "--source", "gh")()
    assertEquals(r.fake.calls.length, 1)
    assert(r.fake.calls.head.contains("created%3A%3E2026-10-28"), r.fake.calls.head)

  dir.test("--opml-only writes the opml and asks no network"): d =>
    val r = runMain(d, "--opml-only")()
    assertEquals((r.code, r.stdout, r.fake.calls), (0, "", Nil))
    val outlines = (loadXml(os.read(d / "out" / "sources.opml")) \\ "outline").filter(o => (o \@ "type").nonEmpty)
    assertEquals(outlines.map(_ \@ "text").toSet, Set("rss", "atom"))
    assertEquals(os.list(d / "out").map(_.last).toSet, Set("sources.opml"))

  dir.test("a write failure exits 1"): d =>
    os.write(d / "out", "a file, not a folder")
    val r = runMain(d)()
    assertEquals(r.code, 1)
    assert(r.stderr.startsWith("error:"), r.stderr)

  dir.test("a bad configuration exits 1 and names the file"): d =>
    os.write.over(d / "feeds.toml", RunConfig.replace("weight = 5", "weight = \"5\""))
    val r = runMain(d)()
    assertEquals(r.code, 1)
    assert(r.stderr.startsWith(s"error: ${d / "feeds.toml"}: bad configuration: "), r.stderr)

  test("the command line, as argparse read it"):
    val a = FeedBuild.parseArgs(List("--dry-run", "--source", "a", "b", "--max-seconds=5", "--source", "c")).toOption.get
    assertEquals((a.dryRun, a.sources, a.maxSeconds), (true, List("a", "b", "c"), 5.0))
    assertEquals(FeedBuild.parseArgs(List("--config")), Left("argument --config: expected one argument"))
    assertEquals(FeedBuild.parseArgs(List("--source")), Left("argument --source: expected at least one argument"))
    assertEquals(FeedBuild.parseArgs(List("extra")), Left("unrecognized arguments: extra"))

/** The real feeds.toml. The Nix build sees only scala/, so these run with `just scala-test`. */
class RealConfigTest extends munit.FunSuite:
  val file: os.Path = os.pwd / os.up / "hermes" / "feeds" / "feeds.toml"

  override def beforeEach(context: BeforeEach): Unit = assume(os.isFile(file), s"$file is not here")

  def raw: Toml.Table = Toml.parse(os.read(file), file.toString).fold(sys.error, identity)
  def tables(name: String): Vector[Map[String, Toml]] = raw.fields(name) match
    case Toml.Arr(ts) => ts.collect { case Toml.Table(f) => f.toMap }
    case _            => Vector.empty

  test("sources"):
    val sources = tables("source")
    val ids = sources.map(_("id"))
    val groups = tables("group").map(_("id")).toSet
    assertEquals(ids.distinct.length, ids.length)
    for s <- sources do
      for key <- List("id", "group", "kind", "weight") do assert(s.contains(key), s"${s("id")} $key")
      assert(groups(s("group")), s("id").toString)
      assert(SourceKind.values.map(k => Toml.Str(k.key)).contains(s("kind")), s("id").toString)
      assert((1 to 5).map(Toml.Integer(_)).contains(s("weight")), s("id").toString)

  test("interests"):
    for i <- tables("interest") do
      assert(i("name") != Toml.Str(""))
      assert(Set(Toml.Str("chat"), Toml.Str("profile"))(i("origin")), i("name").toString)
      assert((1 to 5).map(Toml.Integer(_)).contains(i("weight")), i("name").toString)
      assert(i("terms") != Toml.Arr(Vector.empty), i("name").toString)

  test("the command loads it"):
    val cfg = Config.load(file).fold(sys.error, identity)
    assertEquals(cfg.sources.length, tables("source").length)
    assertEquals(cfg.interests.length, tables("interest").length)

  test("the new source and output keys"):
    val cfg = Config.load(file).fold(sys.error, identity)
    for s <- cfg.sources do
      assert(s.excludeTerms.forall(_.nonEmpty), s.id)
      assert(s.pinnedKeep >= 1, s.id)
    for s <- tables("source") if s.contains("exclude_terms") do assert(s("exclude_terms") != Toml.Arr(Vector.empty), s("id").toString)
    assert(cfg.output.maxPerGroup >= 1 && cfg.output.digestPerGroup >= 1)

  test("the sources of the first run's fixes"):
    val cfg = Config.load(file).fold(sys.error, identity)
    val byId = cfg.sources.map(s => s.id -> s).toMap
    assertEquals(byId("hermes-releases").excludeTerms, List("canary"))
    for name <- List("latent-space", "oxide-and-friends", "rustacean-station", "gleaming-the-tube",
        "cognitive-revolution", "changelog", "practical-ai") do
      assertEquals((byId(s"pod-$name").pinned, byId(s"pod-$name").pinnedKeep), (true, 2), name)
    assertEquals((cfg.output.maxPerGroup, cfg.output.digestPerGroup, cfg.output.digestItems), (14, 3, 18))
