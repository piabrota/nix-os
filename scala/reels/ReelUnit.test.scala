package piabrota.reels

class ReelUnitSuite extends munit.FunSuite:
  test("numbers print as jq prints them") {
    assertEquals(Json.num(0.22 - 0.55), "-0.33000000000000007")
    assertEquals(Json.num(60 / 112.0), "0.5357142857142857")
    assertEquals(Json.num(15 - 0.6), "14.4")
    assertEquals(Json.num(8 / 30.0), "0.26666666666666666")
    assertEquals(Json.num(3.0), "3")
    assertEquals(Json.num(-1.0), "-1")
    assertEquals(Json.num(0.0001), "0.0001")
    assertEquals(Json.num(2.5 + 0.1), "2.6")
  }

  test("compact JSON is jq's") {
    val v = ujson.Obj("a" -> ujson.Arr(1.0, 2.5), "b" -> "x\"y\n\u0001é", "c" -> ujson.Null)
    assertEquals(Json.compact(v), """{"a":[1,2.5],"b":"x\"y\n\u0001é","c":null}""")
  }

  test("jq-style access") {
    import Json.*
    val v = ujson.read("""{"a": {"b": false}, "n": 15}""")
    assertEquals(v.at("a").at("b").or(ujson.Str("d")).text, "d")
    assertEquals(v.at("x").at("y"), ujson.Null)
    assertEquals(v.at("n").text, "15")
    assertEquals(ujson.Str("s").at("k"), ujson.Null)
  }

  test("the music gain moves at each cut where the level changes") {
    val sp = ujson.read("""{"beats": [
      {"t_in": 0, "sound": {"music": "on"}},
      {"t_in": 2.5, "sound": {}},
      {"t_in": 6, "sound": {"music": "low"}},
      {"t_in": 10, "sound": {"silence": true}}]}""")
    assertEquals(Audio.gainExpr(Screenplay.from(sp).beats),
      "0.55+(-0.33000000000000007)*clip((t-5.85)/0.3,0,1)+(-0.22)*clip((t-9.85)/0.3,0,1)")
  }

  test("every music preset and sound effect has its voices") {
    for p <- Seq("pulse", "ambient", "tension", "upbeat") do
      assert(MusicPreset.parse(p).exists(Audio.voices(_, "0.5").nonEmpty), p)
    assertEquals(MusicPreset.parse(MusicPreset.NoMusic), None)
    for s <- Seq("whoosh", "tick", "hit", "riser", "pop") do assert(Sfx.parse(s).isDefined, s)
    assertEquals(Sfx.parse("boom"), None)
  }

  test("the loudnorm block is read from the log") {
    val log = "[Parsed_loudnorm_0 @ 0x1]\n{\n\t\"input_i\" : \"-23.10\",\n\t\"input_tp\" : \"-inf\"\n}\nmore"
    assertEquals(Audio.loudnormBlock(log).map(_("input_i").str), Some("-23.10"))
    assertEquals(Audio.loudnormBlock("no block"), None)
  }

  test("the top-level boxes of an MP4 are found from their headers") {
    def box(kind: String, size: Int): Array[Byte] =
      java.nio.ByteBuffer.allocate(size).putInt(size).put(kind.getBytes("ISO-8859-1")).array()
    val large = java.nio.ByteBuffer.allocate(24).putInt(1).put("mdat".getBytes("ISO-8859-1")).putLong(24).array()
    val dir = os.temp.dir()
    os.write(dir / "fast.mp4", box("ftyp", 16) ++ box("moov", 40) ++ box("mdat", 16))
    os.write(dir / "slow.mp4", box("ftyp", 16) ++ large ++ box("moov", 8))
    os.write(dir / "broken.mp4", box("ftyp", 16) ++ Array[Byte](0, 0, 0, 2, 'm', 'o', 'o', 'v'))
    assertEquals(Qa.mp4Boxes(dir / "fast.mp4"), (16L, 56L))
    assertEquals(Qa.mp4Boxes(dir / "slow.mp4"), (40L, 16L))
    assertEquals(Qa.mp4Boxes(dir / "broken.mp4"), (16L, -1L))
  }

  test("a beat's frame: missing, empty, outside the safe area, low contrast") {
    val safe = Seq(65L, 269L, 1015L, 1248L)
    def problems(box: String, range: Int, text: Boolean) = Qa.beatProblems("1.5", box, range, text, safe, 8, 60)
    assertEquals(problems("100 300 900 1000", 200, text = true), Nil)
    assertEquals(problems("missing", 0, text = true), Seq("no frame at 1.5 s: reel.mp4 is shorter than the screenplay"))
    assertEquals(problems("none", 0, text = true), Seq("the screenplay has text but the frame at 1.5 s draws nothing"))
    assertEquals(problems("none", 0, text = false), Nil)
    assertEquals(problems("100 300 900 1700", 200, text = false),
      Seq("the picture at 1.5 s leaves the safe area: drawn 100 300 900 1700, safe 65 269 1015 1248 (x1 y1 x2 y2, slack 8 px)"))
    assertEquals(problems("100 300 900 1000", 20, text = true),
      Seq("low contrast at 1.5 s: luminance range 20, at least 60 wanted"))
  }

  test("the stats of the timed runs") {
    val s = Render.stats(Seq("1.25 2048", "0.75 10342", ""))
    assertEquals(s.map(Json.compact), Some("""{"ffmpeg_wall_s":2,"peak_rss_mib":10.1,"runs":2,"per_run":[[1.25,2],[0.75,10.1]]}"""))
    assertEquals(Render.stats(Nil).map(Json.compact), Some("""{"ffmpeg_wall_s":0,"peak_rss_mib":0,"runs":0,"per_run":[]}"""))
    assertEquals(Render.stats(Seq("Command exited with non-zero status 1")), None)
  }

  test("a QA report passes only when every check and beat passes") {
    val good = ujson.read("""{"schema": "reels.qa/1", "pass": true, "checks": [{"pass": true}], "beats": [{"pass": true}], "failures": []}""")
    assert(QaVerdict.passed(good))
    val bad = ujson.read("""{"schema": "reels.qa/1", "pass": true, "checks": [{"pass": false}], "beats": [], "failures": []}""")
    assert(!QaVerdict.passed(bad))
    assert(!QaVerdict.passed(ujson.Null))
  }

  test("control characters are dropped, tabs and line breaks kept") {
    assertEquals(printable("a\u0001b\tc\nd\u001be\u007f"), "ab\tc\nde")
  }

  test("a slug is lowercase letters, digits and -, not - first, at most 41") {
    Gate.checkSlug("good-slug-1")
    for bad <- Seq("", "-x", "a/b", "Upper", "a_b", "a" * 42) do
      intercept[piabrota.lib.Exit](Gate.checkSlug(bad))
  }

  test("a long reel is assembled in stages of at most max inputs") {
    assertEquals(Stage.plan(5, 8), Seq(Stage(1, 0, 5, true)))
    assertEquals(Stage.plan(10, 4), Seq(Stage(1, 0, 4, false), Stage(2, 4, 7, false), Stage(3, 7, 10, true)))
    assertEquals(Stage.plan(0, 4), Nil)
  }

  test("a lint finding is read from the rules' JSON") {
    val fs = Finding.all(ujson.read("""[{"level": "error", "beat": null, "rule": "r", "msg": "m"},
      {"level": "warn", "beat": "b01", "rule": "s", "msg": "n"}]"""))
    assertEquals(fs, Seq(Finding(Level.Error, "--", "r", "m"), Finding(Level.Warn, "b01", "s", "n")))
    assertEquals(Gate.findings(fs), ("ERROR  --  [r]  m\nwarn   b01  [s]  n\nlint: 1 error(s), 1 warning(s)", false))
  }
