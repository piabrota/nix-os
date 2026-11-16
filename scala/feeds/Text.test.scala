package piabrota.feeds

import java.time.Instant

class TextTest extends munit.FunSuite:
  test("html entities, as Python's html.unescape"):
    assertEquals(Html.unescape("&amp;&lt;&gt;&quot;&apos;&#39;&#x41;&eacute;&mdash;&hellip;"), "&<>\"''Aé—…")
    assertEquals(Html.unescape("&amp &copy2026 &ampx; &nope; &#0; &#x110000; &#150;"), "& ©2026 &x; &nope; � � –")
    assertEquals(Html.unescape("no entity"), "no entity")

  test("white space, as Python's \\s"):
    assertEquals(Text.words(" a  b\t\nc "), "a b c")
    assertEquals(Text.strip("  x 　"), "x")

  test("the summary counts code points"):
    val emoji = "🌊" * 500
    assertEquals(Text.length(Text.summarize(emoji)), Text.SummaryMax)

  test("terms match whole words and phrases, ignoring case"):
    val t = Terms(List("nix flake", "nix", "c++"))
    assert(t.in("Nix flakes are fine"))
    assert(t.in("about NIX."))
    assert(!t.in("unix and nixos"))
    assert(t.in("C++ news"))
    assert(Terms(List("aa")).in("aaa aa"))
    assert(!Terms(Nil).in("anything"))
    assert(Terms(List("café")).in("Le CAFÉ!"))
    assert(!Terms(List("ma")).in("maçã"))

  test("rfc 822 and iso dates"):
    def at(s: String) = Some(Instant.parse(s))
    assertEquals(Dates.parse("Tue, 03 Nov 2026 09:00:00 GMT"), at("2026-11-03T09:00:00Z"))
    assertEquals(Dates.parse("3 Nov 2026 09:00 EST"), at("2026-11-03T14:00:00Z"))
    assertEquals(Dates.parse("Tue,03 November 26 09:00:00 +0530"), at("2026-11-03T03:30:00Z"))
    assertEquals(Dates.parse("Nov 03 2026 09:00:00 XYZ"), at("2026-11-03T09:00:00Z"))
    assertEquals(Dates.parse("2026-11-04"), at("2026-11-04T00:00:00Z"))
    assertEquals(Dates.parse("2026-11-04 09:00:00.250-0300"), at("2026-11-04T12:00:00.250Z"))
    assertEquals(Dates.parse("2026-13-04T00:00:00Z"), None)
    assertEquals(Dates.isoZ(Instant.parse("2026-11-04T09:00:00.999Z")), "2026-11-04T09:00:00Z")

  test("links split and join as urllib.parse"):
    assertEquals(Links.normalise("HTTPS://Ex.org/a b/?q=a/b&x=%E2%9C%93&e=&f&utm_x=1"),
      "https://ex.org/a b?q=a%2Fb&x=%E2%9C%93&e=&f=")
    assertEquals(Links.normalise("  https://ex.org/p?q=a+b  "), "https://ex.org/p?q=a+b")
    assertEquals(Links.normalise("/relative/path/"), "/relative/path")
    assertEquals(Links.host("https://user@API.GitHub.com:443/x"), "api.github.com")
    assertEquals(Links.quotePlus("a b/ç~"), "a+b%2F%C3%A7~")
    assertEquals(Links.unquotePlus("a+b%2F%C3%A7%zz"), "a b/ç%zz")

  test("item ids are the ones the Python script wrote to state.json"):
    // hashlib.sha256(b"https://example.org/posts/omp-1?id=7").hexdigest()[:16]
    assertEquals(Links.itemId("https://Example.org/posts/omp-1/?utm_source=rss&id=7#top"), "74e89383a35e85fe")
    assertEquals(Links.normaliseTitle("Release: v2.0! ma\u00e7\u00e3 x_y \u00b2"), "release v2 0 ma\u00e7\u00e3 x_y \u00b2")

