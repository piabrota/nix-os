package piabrota.feeds

import piabrota.lib.TestKit

/** `piabrota feed-build` as the cron job runs it, with a stand-in curl that serves the fixtures. */
class FeedBuildCliTest extends munit.FunSuite:
  val config = """
    |title = "Test feed"
    |[[group]]
    |id = "agents"
    |title = "Agents"
    |[[interest]]
    |name = "Undated"
    |weight = 4
    |terms = ["no date"]
    |[[source]]
    |id = "rss"
    |group = "agents"
    |kind = "feed"
    |url = "https://example.org/rss.xml"
    |weight = 5
    |pinned = true
    |[[source]]
    |id = "limited"
    |group = "agents"
    |kind = "feed"
    |url = "https://example.org/limited.xml"
    |weight = 5
    |[[source]]
    |id = "big"
    |group = "agents"
    |kind = "feed"
    |url = "https://big.example/feed.xml"
    |weight = 1
    |limit = 2
    |[[source]]
    |id = "gh"
    |group = "agents"
    |kind = "github_search"
    |query = "topic:x"
    |weight = 2
    |""".stripMargin

  /** Logs its arguments and stdin, then answers by URL: a fixture, an HTTP 429, a feed that never
    * ends, or a timeout.
    */
  val curl = """#!/bin/sh
    |echo "$*" >> "$WORK/curl.args"
    |cat >> "$WORK/curl.stdin"
    |while [ $# -gt 0 ]; do [ "$1" = --url ] && url=$2; shift; done
    |case "$url" in
    |  https://example.org/rss.xml) cat "$WORK/rss.xml" ;;
    |  https://example.org/limited.xml) echo 'curl: (22) The requested URL returned error: 429' >&2; exit 22 ;;
    |  https://big.example/*) echo '<rss><channel>'; yes '<item><title>Again</title><link>https://big.example/1</link></item>' ;;
    |  *) echo 'curl: (28) Operation timed out after 20000 milliseconds' >&2; exit 28 ;;
    |esac
    |""".stripMargin

  def setup(): os.Path =
    val work = os.temp.dir(prefix = "feed-cli")
    os.write(work / "feeds.toml", config)
    os.write(work / "rss.xml", Fixtures.Rss)
    work

  def run(work: os.Path, args: String*): os.CommandResult =
    TestKit.piabrota(Seq("feed-build", "--config", (work / "feeds.toml").toString, "--out", (work / "out").toString,
      "--state", (work / "state.json").toString) ++ args,
      env = Map("WORK" -> work.toString, "GITHUB_TOKEN" -> "dummy"), fakes = Some(TestKit.fakes("curl" -> curl)))

  test("each source's answer goes to health.json; a 5xx or a timeout is asked twice"):
    val work = setup()
    val r = run(work)
    assertEquals(r.exitCode, 0, r.err.text())
    val health = ujson.read(os.read(work / "out" / "health.json"))("sources")
    assertEquals(health("rss")("status").str, "ok")
    assertEquals((health("limited")("status").str, health("limited")("error").str), ("error", "HTTP 429"))
    assertEquals((health("gh")("status").str, health("gh")("error").str), ("error", "timeout"))
    // A feed that never ends is read up to 1.5 MB, then parsed.
    assertEquals((health("big")("status").str, health("big")("items").num), ("ok", 2.0))
    val calls = os.read.lines(work / "curl.args")
    assertEquals(calls.count(_.contains("https://api.github.com/search/repositories?q=topic%3Ax")), 2)
    assertEquals(calls.count(_.contains("https://example.org/limited.xml")), 1)
    assert(calls.forall(_.contains("--user-agent Mozilla/5.0 (compatible; piabrota-feed/1.0;")), calls.head)
    // The token goes on stdin, never on the command line.
    val stdin = os.read(work / "curl.stdin")
    assert(stdin.contains("Accept: application/vnd.github+json\nAuthorization: Bearer dummy\n"), stdin)
    assert(!calls.exists(_.contains("dummy")))
    assert(r.out.text().endsWith("Sources with errors: limited, gh\n"), r.out.text())

  test("--opml-only asks no network"):
    val work = setup()
    val r = run(work, "--opml-only")
    assertEquals((r.exitCode, r.out.text()), (0, ""))
    assert(!os.exists(work / "curl.args"))
    assertEquals(os.list(work / "out").map(_.last), IndexedSeq("sources.opml"))

  test("a bad command line exits 2 with the usage"):
    val r = TestKit.piabrota(Seq("feed-build", "--bogus"))
    assertEquals(r.exitCode, 2)
    assert(r.err.text().startsWith("usage: feed-build [-h]"), r.err.text())
    assert(r.err.text().contains("feed-build: error: unrecognized arguments: --bogus"), r.err.text())
    val help = TestKit.piabrota(Seq("feed-build", "--help"))
    assertEquals(help.exitCode, 0)
    assert(help.out.text().contains("--opml-only           write sources.opml and stop"))

  test("a missing configuration exits 1"):
    val r = TestKit.piabrota(Seq("feed-build", "--config", "/nonexistent/feeds.toml", "--dry-run"))
    assertEquals((r.exitCode, r.err.text()), (1, "error: /nonexistent/feeds.toml: no such file\n"))
