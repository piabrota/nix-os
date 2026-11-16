package piabrota.metrics

import piabrota.lib.TestKit

/** The export on the page's fixtures: healthy, stale, missing, hostile (the old
  * metrics/test/export_test.py).
  */
class ExportTest extends munit.FunSuite:
  /** The fixtures' ts are seconds before now, as the preview serves them: `run` adds Base. */
  private val Base = 1800000000L
  // A sample line of the text format 0.0.4: a name, optional labels, a number.
  private val SampleLine = """[a-z_][a-z0-9_]*(\{([a-z_]+="([^"\\\n]|\\["\\n])*",?)*\})? -?[0-9][0-9.eE+-]*""".r
  private val FirstTs = "\"ts\":(-?[0-9]+)".r

  private def run(c: String, extra: Map[String, String] = Map.empty): (os.Path, ujson.Value, String) =
    val work = os.temp.dir(prefix = "export")
    Fixtures.cases(c).foreach { (name, text) =>
      // The first "ts" is the host's own, before "interval"; the text is kept, Infinity included.
      val ts = FirstTs.findFirstMatchIn(text).get
      os.write(work / name, text.patch(ts.start, s"\"ts\":${ts.group(1).toLong + Base}", ts.end - ts.start))
    }
    extra.foreach((name, text) => os.write(work / name, text))
    val r = TestKit.piabrota(Seq("metrics-export"), Map("OUT_DIR" -> work.toString, "METRICS_NOW" -> Base.toString))
    assertEquals(r.exitCode, 0, r.err.text())
    (work, ujson.read(os.read(work / "all.json")), os.read(work / "metrics.prom"))

  private def checkFormat(prom: String): Unit =
    val names = collection.mutable.Set[String]()
    prom.linesIterator.foreach { line =>
      if line.startsWith("# TYPE ") then
        val name = line.split(' ')(2)
        assert(!names.contains(name), s"one TYPE line for each name: $name")
        names += name
      else if !line.startsWith("# HELP ") then
        assert(SampleLine.matches(line), line)
        assert(names.contains(line.split("[{ ]")(0)), s"a sample after its TYPE: $line")
    }

  test("healthy"):
    val (work, doc, prom) = run("healthy")
    assertEquals(doc("hosts").obj.keys.toSeq.sorted, Seq("piabrota", "piabrota2"))
    assert(doc("hosts")("piabrota2")("fresh").bool)
    assertEquals(doc("hosts")("piabrota2")("data"), ujson.read(os.read(work / "piabrota2.json")))
    checkFormat(prom)
    assert(prom.contains("piabrota_host_fresh{host=\"piabrota2\"} 1"))
    assert(prom.contains("piabrota_hosts 2"))
    assert("""piabrota_memory_bytes\{host="piabrota2",kind="total"\} \d+""".r.findFirstIn(prom).isDefined)
    assert("""piabrota_inventory\{host="piabrota2",item="packages"\} \d+""".r.findFirstIn(prom).isDefined)
    assertEquals(os.perms(work / "metrics.prom").toString, "rw-r--r--")
    assertEquals(os.list(work).filter(_.last.endsWith(".tmp")).map(_.last), Seq.empty[String])

  test("the sites and their visits"):
    val (_, doc, prom) = run("healthy")
    val sites = doc("hosts")("piabrota2")("data")("domains")("list").arr
    assert(sites.nonEmpty)
    sites.foreach { s =>
      val name = s("name").str
      assert(prom.contains(s"""piabrota_site_up{host="piabrota2",site="$name"} ${if s("up").bool then 1 else 0}"""))
      s.obj.get("views").foreach(v =>
        assert(prom.contains(s"""piabrota_site_views_24h{host="piabrota2",site="$name"} ${v.num.toLong}""")))
    }

  test("stale"):
    val (_, doc, prom) = run("stale")
    assert(!doc("hosts")("piabrota")("fresh").bool)
    assertEquals(doc("hosts")("piabrota")("age_s").num, 120.0)
    assert(prom.contains("piabrota_host_fresh{host=\"piabrota\"} 0"))
    assert(prom.contains("piabrota_sample_age_seconds{host=\"piabrota\"} 120"))

  test("missing"):
    val (_, doc, prom) = run("missing")
    assertEquals(doc("hosts").obj.keys.toSeq, Seq("piabrota2"))
    assert(prom.contains("piabrota_hosts 1"))

  test("hostile"):
    val (work, doc, prom) = run("hostile")
    assertEquals(doc("hosts").obj.keys.toSeq.sorted, Seq("piabrota", "piabrota2"))
    checkFormat(prom)
    assert(!prom.contains("Infinity") && !prom.contains("NaN"))
    // all.json is strict JSON: the Infinity of the input is the largest double, as jq writes it.
    val all = os.read(work / "all.json")
    assert(!all.contains("Infinity"))
    assert(all.contains("\"rigs\":1.7976931348623157e+308"))

  test("files that are left out"):
    val (_, doc, prom) = run("missing", Map(
      "other.json" -> """{"host":"piabrota"}""", "broken.json" -> "{", "Upper.json" -> """{"host":"Upper"}""",
      "all.json" -> """{"host":"all"}""", "big.json" -> ("""{"host":"big","x":"""" + "a" * 70000 + "\"}")))
    assertEquals(doc("hosts").obj.keys.toSeq, Seq("piabrota2"))
    checkFormat(prom)

  test("an empty folder"):
    val work = os.temp.dir(prefix = "export")
    assertEquals(TestKit.piabrota(Seq("metrics-export"), Map("OUT_DIR" -> work.toString)).exitCode, 0)
    assertEquals(ujson.read(os.read(work / "all.json"))("hosts"), ujson.Obj())
    assert(os.read(work / "metrics.prom").contains("piabrota_hosts 0"))

  test("a bad METRICS_STALE exits 2"):
    val r = TestKit.piabrota(Seq("metrics-export"), Map("OUT_DIR" -> os.temp.dir().toString, "METRICS_STALE" -> "x"))
    assertEquals(r.exitCode, 2)
    assertEquals(r.err.text().trim, "export: bad METRICS_STALE")

class FixturesTest extends munit.FunSuite:
  test("the copy in Fixtures.test.scala matches metrics/test/fixtures"):
    // Only where the repository is beside the sources (`just scala-test`), not in the Nix build.
    val dir = os.pwd / os.up / "metrics" / "test" / "fixtures"
    assume(os.isDir(dir), "metrics/test/fixtures is not here")
    val files = os.walk(dir).filter(os.isFile).map(f => f.relativeTo(dir).segments.toList).collect {
      case List(c, "data", name) => (c, name)
    }
    assertEquals(files.toSet, Fixtures.cases.toSeq.flatMap((c, fs) => fs.keys.map(c -> _)).toSet)
    files.foreach((c, name) => assertEquals(Fixtures.cases(c)(name) + "\n", os.read(dir / c / "data" / name), s"$c/$name"))

class JsonTest extends munit.FunSuite:
  test("numbers keep their text, as jq 1.7 writes them back"):
    val text = """{"a":30.0,"b":0.25,"c":-0,"d":100000000000000000001,"e":[1,true,null,"x"]}"""
    assertEquals(Json.parse(text).map(Json.write), Some(text))

  test("a literal with an exponent is written as jq 1.7's decNumber writes it"):
    val in = "[0.0000001,0.000001,10e1,0.5e1,12e-1,0e5,1.000,0.10,-0.0,1E-7,123.456e-10,1e-3,5e0,-1.5e9]"
    assertEquals(Json.parse(in).map(Json.write),
      Some("[1E-7,0.000001,1.0E+2,5,1.2,0E+5,1.000,0.10,-0.0,1E-7,1.23456E-8,0.001,5,-1.5E+9]"))

  test("Infinity and NaN are read, and written as jq writes them"):
    assertEquals(Json.parse("[Infinity,-Infinity,NaN]").map(Json.write),
      Some("[1.7976931348623157e+308,-1.7976931348623157e+308,null]"))

  test("strings get jq's escapes"):
    assertEquals(Json.parse("\"a\\\"b\\\\c\\n\\u0001\\u007f\u00e9\\/\"").map(Json.write), Some("\"a\\\"b\\\\c\\n\\u0001\\u007f\u00e9/\""))

  test("bad JSON is None"):
    List("{", "{\"a\":1,}", "[1 2]", "01", "\"x", "{} x", "nul").foreach(t => assertEquals(Json.parse(t), None, t))

  test("an object keeps its order, and a repeated key keeps its place with the last value"):
    assertEquals(Json.parse("""{"b":1,"a":2,"b":3}""").map(Json.write), Some("""{"b":3,"a":2}"""))
