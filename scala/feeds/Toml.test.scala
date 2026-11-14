package piabrota.feeds

import scala.collection.immutable.ListMap
import Toml.*

class TomlTest extends munit.FunSuite:
  def parse(text: String): Either[String, Table] = Toml.parse(text, "t.toml")
  def fields(text: String): ListMap[String, Toml] = parse(text).fold(sys.error, _.fields)

  test("keys, tables and arrays of tables, in file order"):
    val f = fields("""
      |# a comment
      |title = "x - y"   # after a value
      |[output]
      |max_items = 80
      |min_score = 4.0
      |[[group]]
      |id = "a"
      |[[group]]
      |id = "b"
      |""".stripMargin)
    assertEquals(f.keys.toList, List("title", "output", "group"))
    assertEquals(f("title"), Str("x - y"))
    assertEquals(f("output"), Table(ListMap("max_items" -> Integer(80), "min_score" -> Decimal(4.0))))
    assertEquals(f("group"), Arr(Vector(Table(ListMap("id" -> Str("a"))), Table(ListMap("id" -> Str("b"))))))

  test("values"):
    val f = fields("""a = "q\"\\\u00e9\n"
      |b = 'C:\path'
      |c = -1_000
      |d = 1e3
      |e = true
      |f = false
      |g = ["x", "y",]
      |h = [
      |  "multi",  # a comment
      |  "line"
      |]
      |i = []
      |j = +0.5
      |""".stripMargin)
    assertEquals(f("a"), Str("q\"\\\u00e9\n"))
    assertEquals(f("b"), Str("C:\\path"))
    assertEquals(f("c"), Integer(-1000))
    assertEquals(f("d"), Decimal(1000.0))
    assertEquals((f("e"), f("f")), (Bool(true), Bool(false)))
    assertEquals(f("g"), Arr(Vector(Str("x"), Str("y"))))
    assertEquals(f("h"), Arr(Vector(Str("multi"), Str("line"))))
    assertEquals(f("i"), Arr(Vector.empty))
    assertEquals(f("j"), Decimal(0.5))

  test("windows line ends"):
    assertEquals(fields("a = 1\r\nb = 2\r\n").keys.toList, List("a", "b"))

  test("what is outside the subset fails and names its line"):
    def error(text: String) = parse(text).swap.getOrElse(fail(s"parsed: $text"))
    assert(error("a = 1\nb.c = 2").startsWith("t.toml:2: a dotted key is not supported: feed-build reads"))
    assert(error("\"a\" = 1").contains("a quoted key is not supported"))
    assert(error("a = { b = 1 }").contains("an inline table is not supported"))
    assert(error("a = \"\"\"x\"\"\"").contains("a multi-line string is not supported"))
    assert(error("a = 2026-11-04").contains("the value '2026-11-04'"))
    assert(error("a = 0x10").contains("the value '0x10'"))
    assert(error("[a.b]").contains("expected ']'"))

  test("mistakes fail and name their line"):
    def error(text: String) = parse(text).swap.getOrElse(fail(s"parsed: $text"))
    assertEquals(error("a = 1\na = 2"), "t.toml:2: key 'a' is set twice")
    assertEquals(error("[t]\n[t]"), "t.toml:2: [t] is defined twice")
    assertEquals(error("t = 1\n[[t]]"), "t.toml:2: [[t]] is also a key or a [table]")
    assertEquals(error("a = \"open"), "t.toml:1: expected '\"'")
    assertEquals(error("a = \"x\ny\""), "t.toml:1: a string ends at the end of its line")
    assertEquals(error("a = 1 2"), "t.toml:1: unexpected '2' after the value")
    assertEquals(error("a = [1 2]"), "t.toml:1: expected ',' or ']' in an array")
    assertEquals(error("a ="), "t.toml:1: expected a value")
    assertEquals(error("= 1"), "t.toml:1: expected a key")

  test("a bad configuration names the key"):
    def error(text: String) = parse(text).flatMap(Config.fromToml(_, "f.toml")).swap.getOrElse(fail("loaded"))
    assertEquals(error("[[group]]\nid = \"g\"\ntitle = \"G\""), "f.toml: bad configuration: the file has no 'title'")
    assertEquals(error("title = \"t\"\n[output]\nmax_itemz = 3"),
      "f.toml: bad configuration: [output] has an unknown key 'max_itemz'")
    assertEquals(error("title = \"t\"\n[output]\nmax_items = \"3\""),
      "f.toml: bad configuration: [output]: 'max_items' has the wrong type")
    val source = "\n[[source]]\nid = \"s\"\ngroup = \"g\"\nkind = \"feed\"\nweight = 1"
    val groups = "title = \"t\"\n[[group]]\nid = \"g\"\ntitle = \"G\""
    assertEquals(error(groups + source + source), "duplicate source id: s")
    assertEquals(error(groups + source.replace("feed", "rss")), "source s: unknown group or kind")
    assertEquals(error(groups + source + "\nurll = \"x\""),
      "f.toml: bad configuration: [[source]] number 1 has an unknown key 'urll'")
