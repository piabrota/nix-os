package piabrota.reels

import Json.*
import Jv.{Null, Str}

/** The rules that were jq programs, on small inputs. Each expected value is what jq 1.8.2 printed
  * for the same input with the jq programs of reels/lib/ before they became Scala.
  */
class RulesSuite extends munit.FunSuite:
  private def j(text: String): Jv = Json.read(text).getOrElse(fail(s"not JSON: $text"))

  private val profile = j("""{"schema":"reels.profile/1","formats":[15,30],"voice":false,"hook":{"max_t_out":3},"beat":{"min_s":0.8},"text":{"max_cps":15,"max_lines":5,"max_chars_per_line":28},"safe":{"top":0.14,"bottom":0.35,"side":0.06},"video":{"width":1080,"height":1920,"fps":30,"codec":"h264","pix_fmt":"yuv420p","crf":20,"preset":"medium","scene_crf":12,"x264_params":"rc-lookahead=20:ref=2:bframes=2","threads":1,"max_inputs":4},"audio":{"codec":"aac","rate":48000,"channels":2,"bitrate":"128k","target_lufs":-14,"true_peak":-1.0,"premix_peak":-2.0,"true_peak_slack":0.5,"lufs_tolerance":2.0},"qa":{"duration_tolerance_s":0.05,"min_text_range":60,"hook_probe_s":0.5,"probe_frac":0.7,"edge_min":40,"safe_slack_px":8,"audio_tolerance_s":0.1},"transition":{"default_s":0.4,"max_s":1.0},"roles":["hook","setup","turn","proof","payoff","cta","loop"],"claim_status":["own","sourced","needs-check"],"transitions":["cut","fade","fadeblack","fadewhite","slideleft","slideright","slideup","slidedown","wipeleft","wiperight","wipeup","wipedown","circleopen","circleclose","dissolve","zoomin"],"scenes":["title_card","big_number","bullet_reveal","quote","split_compare","timeline","diagram_reveal","kinetic_text","outro_loop"],"music_presets":["pulse","ambient","tension","upbeat","none"],"music_levels":["on","low","off"],"sfx":["whoosh","tick","hit","riser","pop"],"blender":{"max_frames":240,"fps":24,"samples":16,"threads":2},"limits":{"ffmpeg_timeout_s":300,"resvg_timeout_s":60,"blender_timeout_s":3600},"sfx_per_beat":6}""")
  private val style = j("""{"schema":"reels.style/1","name":"piabrota","colors":{"bg":"#0B0D12","surface":"#14171F","border":"#2A303C","fg":"#EDEFF3","muted":"#9AA3B2","accent":"#BC2318","accent_text":"#FF6B5E"},"fonts":{"title":{"family":"Fjalla One","bold":false,"lh":0.80,"w":{"upper":0.325,"lower":0.27,"digit":0.295,"space":0.11,"other":0.16}},"text":{"family":"Inter Variable","bold":false,"lh":1.02,"w":{"upper":0.62,"lower":0.46,"digit":0.49,"space":0.25,"other":0.3}}},"motion":{"ease":"out_cubic","stagger":0.14,"enter_s":0.45,"pop":1.06,"blur":10,"bg_zoom":[1.0,1.05],"grain":3},"background":{"glow_color":"accent","glow_opacity":0.28,"glow_x":0.12,"glow_y":0.10,"glow_r":0.75}}""")
  private val sp = j("""{"schema":"reels.screenplay/1","slug":"t","title":"Tt","format":15,"logline":"L","audience":"A","language":"en","loop":true,
    "claims":[{"id":"c1","text":"x","source":"own","status":"own"}],
    "look":{"style":"piabrota"},"music":{"preset":"pulse","bpm":112},
    "beats":[
     {"id":"b01","t_in":0,"t_out":2.5,"role":"hook","visual":{"describe":"a big *word* that goes on and on past the width of the picture column","scene":"kinetic_text","params":{}},"text":["Hello *world*","two"],"sound":{"music":"on","sfx":[{"name":"hit","at":0.25}]},"transition":"cut","note":""},
     {"id":"b02","t_in":2.5,"t_out":9,"role":"proof","visual":{"describe":"count","scene":"big_number","params":{}},"text":["R$ 1.234,5 mil","a label"],"claims":["c1"],"sound":{"music":"low","sfx":[]},"transition":"fade","note":"n"},
     {"id":"b03","t_in":9,"t_out":15,"role":"cta","visual":{"describe":"end","scene":"outro_loop","params":{}},"text":["follow","@handle"],"sound":{"silence":true},"transition":"slideup","transition_s":0.5,"note":""}]}""")
  private val styles = Seq("mono", "paper", "piabrota")

  // ---- jq's numbers, reading and errors

  test("a computed number prints in its shortest form, with jq's exponents") {
    assertEquals(jqDouble(0.1 * 3), "0.30000000000000004")
    assertEquals(jqDouble(1e-5), "1e-05")
    assertEquals(jqDouble(1e15), "1000000000000000")
    assertEquals(jqDouble(1e16), "1e+16")
    assertEquals(jqDouble(1e21), "1e+21")
    assertEquals(jqDouble(5e-324), "5e-324")
    assertEquals(jqDouble(-0.0), "0")
    assertEquals(jqDouble(Double.NaN), "null")
    assertEquals(jqDouble(Double.PositiveInfinity), "1.7976931348623157e+308")
  }

  test("a number that was read keeps its text") {
    def text(s: String) = literal(s).map(numText)
    assertEquals(text("1.0"), Some("1.0"))
    assertEquals(text("1e2"), Some("1E+2"))
    assertEquals(text("100e-2"), Some("1.00"))
    assertEquals(text("0.0e-3"), Some("0.0000"))
    assertEquals(text("1e-7"), Some("1E-7"))
    assertEquals(text("1.5e-6"), Some("0.0000015"))
    assertEquals(text("-0.60"), Some("-0.60"))
    assertEquals(compact(j("[15.000000, 0.80, 1.05]")), "[15.000000,0.80,1.05]")
    assertEquals(compact(j("[1.0]")(0.0) * Jv.num(1)), "1")
  }

  test("the reader takes what jq takes and refuses what jq refuses") {
    assertEquals(Json.parseText("[01, 1., .5, +1]").map(_.map(d => compact(d.value))), Some(Vector("[1,1,0.5,1]")))
    assertEquals(Json.parseText("1 2 {\"a\":3}").map(_.length), Some(3))
    assertEquals(Json.parseText("[1,]"), None)
    assertEquals(Json.parseText("\"\\ud800\""), None)
    assertEquals(Json.parseText("\"a\u0001\""), None)
    assertEquals(Json.parse(Array(0xff.toByte)), None)
    assertEquals(Json.read("1 2"), None)
  }

  test("the line of a value is the line jq names in its errors") {
    assertEquals(Json.parseText("{\"a\":\n1}\n[2,\n3]").map(_.map(_.line)), Some(Vector(2, 3)))
    assertEquals(Json.parseText("1 2\n3").map(_.map(_.line)), Some(Vector(1, 1, 1)))
    assertEquals(Json.parseText("1\n").map(_.map(_.line)), Some(Vector(1)))
  }

  test("jq -e .: the last value must be neither null nor false") {
    val dir = os.temp.dir()
    def valid(text: String) = { os.write.over(dir / "f.json", text); Json.valid(dir / "f.json") }
    assert(valid("{}"))
    assert(valid("null 1"))
    assert(!valid("1 null"))
    assert(!valid(""))
    assert(!valid("{"))
  }

  test("errors say what jq says") {
    def msg(f: => Any) = intercept[JqError](f).msg
    assertEquals(msg(Jv.num(5)("a")), "Cannot index number with string (\"a\")")
    assertEquals(msg(Str("x").iter), "Cannot iterate over string (\"x\")")
    assertEquals(msg(Str("x") / Jv.num(60)), "string (\"x\") and number (60) cannot be divided")
    assertEquals(msg(Jv.num(1) / Jv.num(0)), "number (1) and number (0) cannot be divided because the divisor is zero")
    assertEquals(msg(Str("151515151515151515151515151515151515") / Jv.num(60)),
      "string (\"151515151515151515151515...\") and number (60) cannot be divided")
    assertEquals(msg(j("[1111111111,2222222222,3333333333,44444]") / Jv.num(60)),
      "array ([1111111111,2222222222,33...]) and number (60) cannot be divided")
    assertEquals(msg(j("""{"aaaaaaaaaa":1111111111,"b":2222222222}""") / Jv.num(60)),
      "object ({\"aaaaaaaaaa\":1111111111,...}) and number (60) cannot be divided")
    assertEquals(msg(j("""[["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]]""") / Jv.num(60)),
      "array ([[\"aaaaaaaaaaaaaaaaaaaaaa...]) and number (60) cannot be divided")
    assertEquals(msg(Str("aéééééééééééééééééééééééééééé") / Jv.num(60)), "string (\"aééééééééééé...\") and number (60) cannot be divided")
    assertEquals(msg(Null * Jv.num(3)), "null (null) and number (3) cannot be multiplied")
  }

  test("// takes the right side for null and false, and lets an error through") {
    assertEquals(alt(Null, Jv.num(1)), Jv.num(1))
    assertEquals(alt(Jv.False, Jv.num(1)), Jv.num(1))
    assertEquals(alt(Jv.num(0), Jv.num(1)), Jv.num(0))
    intercept[JqError](alt(Jv.num(1)("claims"), Jv.EmptyArr))
  }

  test("strings, slices and order as jq has them") {
    assertEquals(Str("ab") * Jv.num(2.7), Str("abab"))
    assertEquals(Str("ab") * Jv.num(-1), Null)
    assertEquals(Jv.Arr(Vector(Str("a"), Str("b"), Str("c"))).slice(Some(0), Some(1.5)), j("""["a","b"]"""))
    assertEquals(sort(Seq(Str("x"), Jv.num(1), Jv.num(3)))(1), Jv.num(3))
    assertEquals(split("a  b ", " "), Vector("a", "", "b", ""))
    assertEquals(join(Seq(Str("a"), Jv.num(1), Null, Jv.True), ","), "a,1,,true")
  }

  // ---- the screenplay and the shotlist

  test("the lint of a sound screenplay: a warning only") {
    assertEquals(Lint.screenplay(sp, profile, styles),
      Seq(Finding(Level.Warn, "b02", "scene", "big_number: the first line is the number: 8 characters or fewer reads best")))
  }

  test("the lint of the skeleton refuses its TODOs") {
    val fs = Lint.screenplay(Drafts.skeleton("s15", Jv.num(15)), profile, styles)
    assert(fs.exists(f => f.rule == "placeholder" && f.level == Level.Error), fs.toString)
  }

  test("a screenplay that the rules cannot read is an error, never a pass") {
    val broken = j("""{"beats": [1, 2], "claims": [{"id": "c1"}]}""")
    assertEquals(Lint.screenplay(broken, profile, styles),
      Seq(Finding(Level.Error, Finding.NoBeat, "lint", "the rules cannot read this file: Cannot index number with string (\"claims\")")))
    assertEquals(Lint.screenplay(Jv.num(1), profile, styles),
      Seq(Finding(Level.Error, Finding.NoBeat, "schema", "the file must hold one JSON object")))
  }

  test("the default shotlist and its lint") {
    val sl = Drafts.shotlist(sp, style, "abc")
    assertEquals(sl("shots").size, 3)
    assertEquals(compact(sl("shots")(0.0)),
      """{"beat":"b01","scene":"kinetic_text","kind":"flat","params":{},"camera":{"zoom":[1.0,1.05]},"motion":{"ease":"out_cubic","stagger":0.14,"enter_s":0.45,"pop":1.06,"blur":10},"text_layout":{"y":0.5,"scale":1},"palette":{"main":"fg","emph":"accent_text","sub":"muted","bar":"accent"},"transition":"cut","note":""}""")
    assertEquals(Lint.shotlist(sl, sp, style, profile, "abc"), Nil)
    def set(v: Jv, beat: Int, key: String, field: String, x: Jv): Jv =
      val shots = v("shots").items
      val shot = shots(beat)
      v + Jv.obj("shots" -> Jv.Arr(shots.updated(beat, shot + Jv.obj(key -> (shot(key) + Jv.obj(field -> x))))))
    val bad = set(set(set(sl, 1, "palette", "main", Str("border")), 2, "motion", "ease", Str("bounce")), 0, "camera", "zoom", j("[1, 2]"))
    assertEquals(Lint.shotlist(bad, sp, style, profile, "abc"), Seq(
      Finding(Level.Error, "b01", "camera", "camera.zoom is [from, to], each from 1.0 to 1.3"),
      Finding(Level.Error, "b02", "contrast", "palette.main = border: contrast 1.5 to the background, at least 4.5 is needed"),
      Finding(Level.Error, "b03", "motion", "motion.ease is linear, out_quad, out_cubic or out_quart")))
  }

  test("the skeleton of a 15 s reel") {
    val sk = Drafts.skeleton("s", Jv.num(15))
    assert(pretty(sk).startsWith("{\n  \"schema\": \"reels.screenplay/1\",\n  \"slug\": \"s\",\n  \"title\": \"TODO\",\n  \"format\": 15,"))
    assertEquals(sk("beats").items.map(b => plain(b("t_out"))), Vector("2.5", "6", "10", "12.8", "15"))
    assertEquals(plain(sk("music")("bpm")), "112")
    assertEquals(plain(Drafts.skeleton("s", Jv.num(30))("music")("bpm")), "96")
  }

  // ---- frames, views, captions, QA

  test("the frame plan: whole frames, a centred fade, a handle on each side") {
    assertEquals(Frames.timeline(sp, profile), Vector(
      Cut("b01", "cut", 0, 75, 0, 6, 81, 0, 0),
      Cut("b02", "fade", 75, 270, 6, 8, 209, 12, 2.3),
      Cut("b03", "slideup", 270, 450, 8, 0, 188, 16, 8.733333333333333)))
  }

  test("where QA looks: clear of the transitions") {
    assertEquals(Frames.probes(Frames.timeline(sp, profile), sp, profile), Vector(
      Probe("b01", "1.767", "0", true), Probe("b02", "7.067", "2.5", true), Probe("b03", "13.2", "9", true)))
  }

  private def lines(program: (Jv, String => Unit) => Unit): String =
    Views.each(Vector(Doc(sp, 1)), "sp.json")(program).out

  test("the A/V script") {
    val out = lines(Views.screenplay).split("\n", -1).toVector
    assertEquals(out.take(4), Vector("Tt  (t, 15 s, en, loops)", "logline:  L", "audience: A", "look:     piabrota    music: pulse 112 bpm"))
    assertEquals(out.slice(7, 13), Vector(
      "b01  0.0 - 2.5 s  HOOK  [kinetic_text]  in: cut",
      "    a big *word* that goes on and on past the     |  Hello world",
      "    width of the picture column                   |  two",
      "                                                  |  ",
      "                                                  |  music: on",
      "                                                  |  sfx: hit at 0.3 s"))
    assertEquals(out.slice(14, 16), Vector("b02  2.5 - 9.0 s  PROOF  [big_number]  in: fade", "    note: n"))
    assertEquals(out.takeRight(3), Vector("CLAIMS", "  c1  [own]  x  (source: own)", ""))
  }

  test("the table read") {
    // A beat with no flag keeps the two spaces before the empty flag column.
    assertEquals(lines(Views.timing(_, profile, _)), Seq(
      "TABLE READ  (reading speed limit 15 characters per second)",
      "",
      "beat   role       length   chars     cps    needs     hold  flag",
      "b01    hook        2.5 s      14     5.6    0.9 s    1.6 s  ",
      "b02    proof       6.5 s      21     3.2    1.4 s    5.1 s  ",
      "b03    cta         6.0 s      13     2.2    0.9 s    5.1 s  ",
      "",
      "worst beat: b01  5.6 cps, 1.6 s to hold after reading",
      "total: 15.0 s, 48 characters, 3.2 cps on average",
      "result: OK",
      "").mkString("\n"))
  }

  test("a view goes on after a value it cannot read, and says where") {
    val p = Views.each(Vector(Doc(Jv.num(1), 3), Doc(sp, 9)), "/x.json")(Views.screenplay)
    assertEquals(p.err, Vector("jq: error (at /x.json:3): Cannot index number with string (\"beats\")"))
    assert(p.out.startsWith("Tt  (t, 15 s, en, loops)\n"))
  }

  private def scene(i: Int, hin: Double, total: Double, dur: Double, last: Boolean): SceneInput =
    SceneInput(sp, sp("beats")(i.toDouble), Drafts.shotlist(sp, style, "abc")("shots")(i.toDouble), style, profile, hin, total, dur, last)

  test("kinetic text: the words slam in one by one") {
    val ass = Captions.ass(scene(0, 0, 2.5, 2.5, last = false), mask = false).linesIterator.toVector
    assertEquals(ass.length, 20)
    assertEquals(ass(16), """Dialogue: 1,0:00:00.00,0:00:02.50,Title,,0,0,0,,{\an5\pos(540,666.4)\fs230\bord0\shad0}{\alpha&HFF&\blur10\fscx119\fscy119\t(0,120,\alpha&H00&)\t(0,300,\blur0\fscx100\fscy100)}{\1c&HF3EFED&}Hello {\alpha&HFF&\blur10\fscx119\fscy119\t(140,260,\alpha&H00&)\t(140,440,\blur0\fscx100\fscy100)}{\1c&H5E6BFF&}world""")
    assertEquals(ass(17), """Dialogue: 1,0:00:00.00,0:00:02.50,Title,,0,0,0,,{\an5\pos(540,850.4)\fs230\bord0\shad0}{\alpha&HFF&\blur10\fscx119\fscy119\t(280,400,\alpha&H00&)\t(280,580,\blur0\fscx100\fscy100)}{\1c&HF3EFED&}two""")
    assertEquals(ass(10), "Style: Default,Inter Variable,60,&H00F3EFED,&H00F3EFED,&H00120D0B,&H00120D0B,0,0,0,0,100,100,0,0,1,0,0,5,0,0,0,1")
  }

  test("big number: it counts up, then holds") {
    val ass = Captions.ass(scene(1, 1.0 / 30, 6.533333333333333, 6.5, last = false), mask = false).linesIterator.toVector
    assertEquals(ass.length, 41)
    assertEquals(ass(16), """Dialogue: 1,0:00:00.03,0:00:00.10,Title,,0,0,0,,{\an5\pos(540,674.7)\fs261\bord0\shad0\1c&H5E6BFF&}R$ 0.137,5 mil""")
    assertEquals(ass(17), """Dialogue: 1,0:00:00.10,0:00:00.17,Title,,0,0,0,,{\an5\pos(540,674.7)\fs261\bord0\shad0\1c&H5E6BFF&}R$ 0.380,5 mil""")
    assertEquals(ass(ass.length - 3), """Dialogue: 1,0:00:01.26,0:00:01.31,Body,,0,0,0,,{\an5\move(540,889.4,540,889.3)\alpha&H00&\blur0\fs66\bord0\shad0}{\1c&HF3EFED&}a {\1c&HF3EFED&}label""")
  }

  test("big number with no number in its first line: no script at all") {
    val beat = sp("beats")(1.0) + Jv.obj("text" -> j("""["many", "x"]"""))
    assertEquals(Captions.ass(scene(1, 0, 6.5, 6.5, last = false).copy(beat = beat), mask = false), "")
  }

  test("outro: the last line is the handle, and a loop reel fades out") {
    val in = scene(2, 8.0 / 30, 6.266666666666667, 6, last = true)
    val ass = Captions.ass(in, mask = false).linesIterator.toVector
    assertEquals(ass.length, 36)
    assertEquals(ass(16), """Dialogue: 1,0:00:00.27,0:00:00.32,Title,,0,0,0,,{\an5\move(540,705.4,540,688.9)\alpha&HAB&\blur6.7\fs190\bord0\shad0}{\1c&HF3EFED&}follow""")
    assertEquals(ass(ass.length - 3), """Dialogue: 1,0:00:00.86,0:00:06.27,Title,,0,0,0,,{\an5\pos(540,799.4)\fs170\bord0\shad0\fad(0,350)}{\1c&H5E6BFF&}@handle""")
    assertEquals(compact(Captions.plan(in)), """{"zoom":[1.05,1.0],"grain":3,"layers":[],"diagram":{"y0":268.8000000000001,"h":560,"w":950}}""")
    assert(Captions.ass(in, mask = true).linesIterator.drop(16).forall(l => !l.contains("&HF3EFED&")))
  }

  test("a motion value of the wrong type fails where jq failed") {
    val in = scene(2, 0, 6, 6, last = false)
    val shot = in.shot + Jv.obj("motion" -> j("""{"enter_s": false}"""))
    assertEquals(intercept[JqError](Captions.ass(in.copy(shot = shot), mask = false)).msg,
      "number (3.9000000000000004) and boolean (false) cannot be subtracted")
  }

  test("a layer of the plan must be an SVG under direction/svg/") {
    val in = scene(0, 0, 2.5, 2.5, last = false)
    def withLayers(ls: String) = in.copy(shot = in.shot + Jv.obj("params" -> j(s"""{"layers": $ls}""")))
    assertEquals(compact(Captions.plan(withLayers("""["direction/svg/a.svg"]"""))("layers")),
      """[{"svg":"direction/svg/a.svg","at":0.15,"fade":0.35}]""")
    assertEquals(intercept[JqError](Captions.plan(withLayers("""["../x.svg"]"""))).msg,
      "layer \"../x.svg\": write direction/svg/<name>.svg")
    assertEquals(intercept[JqError](Captions.plan(withLayers("\"x\""))).msg, "string (\"x\") has no keys")
  }

  test("the pieces of a caption") {
    assertEquals(Captions.words("a *b*c d  *e f*"), Vector(
      Word(Vector(Run("a", false))), Word(Vector(Run("b", true), Run("c", false))), Word(Vector(Run("d", false))),
      Word(Vector(Run("e", true))), Word(Vector(Run("f", true)))))
    assertEquals(Captions.escape("{a}\\b\u0001\u2028"), "(a)/b  ")
    assertEquals(Captions.assTime(3725.456), "1:02:05.46")
    assertEquals(Captions.assColor(Str("#FF6B5E")), "&H5E6BFF&")
    assertEquals(Captions.assStyleColor(Str("#0B0D12")), "&H00120D0B")
    assertEquals(Captions.assAlpha(0.25), "&HBF&")
  }

  test("the background of a style") {
    val svg = Captions.background(style, profile).split("\n", -1).toVector
    assertEquals(svg.length, 11)
    assertEquals(svg(3), """<radialGradient id="glow" gradientUnits="userSpaceOnUse" cx="129.6" cy="192" r="810"><stop offset="0" stop-color="#BC2318" stop-opacity="0.28"/><stop offset="1" stop-color="#BC2318" stop-opacity="0"/></radialGradient>""")
    assertEquals(svg(4), """<radialGradient id="vig" cx="0.5" cy="0.5" r="0.75"><stop offset="0.55" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity="0.4"/></radialGradient>""")
    assert(Captions.backgroundKey(style).startsWith("""{"colors":{"bg":"#0B0D12","""))
    assert(Captions.backgroundKey(style).endsWith(""""glow_r":0.75}}""" + "\n"))
  }

  test("the QA report: every number as the file has it") {
    val probe = j("""{"streams":[{"codec_type":"video","codec_name":"h264","profile":"High","width":1080,"height":1920,"sample_aspect_ratio":"1:1","pix_fmt":"yuv420p","r_frame_rate":"30/1","nb_frames":"450"},
      {"codec_type":"audio","codec_name":"aac","sample_rate":"48000","channels":2,"duration":"15.010000"}],
      "format":{"format_name":"mov,mp4,m4a,3gp,3g2,mj2","duration":"15.000000","size":"123456","bit_rate":"65843"}}""")
    val beats = Vector(
      j("""{"id":"b01","probe_s":1.7,"frame":"qa/b01.png","has_text":true,"drawn":"1 2 3 4","luminance_range":200,"problems":[],"pass":true}"""),
      j("""{"id":"b02","probe_s":6.5,"frame":"qa/b02.png","has_text":true,"drawn":"none","luminance_range":0,"problems":["no picture"],"pass":false}"""))
    val facts = QaFacts("t", Jv.num(15), j("""{"input_i":"-14.60","input_tp":"-inf","input_lra":"0.60"}"""), 40, 1000, beats,
      "1 2 3 4", "0123456789abcdef", "fedcba9876543210", "fedcba9876543210", "")
    assertEquals(compact(QaReport.report(probe, profile, facts)),
      """{"schema":"reels.qa/1","slug":"t","format":15,"pass":false,"reel_sha256":"0123456789abcdef","screenplay_sha256":"fedcba9876543210","facts":{"bytes":123456,"duration_s":15.000000,"size":"1080x1920","fps":"30/1","video":"h264 High yuv420p","audio":"aac 48000 Hz 2 ch","bit_rate":65843},"loudness":{"lufs":-14.60,"true_peak_dbtp":-99,"lra":0.60},"checks":[{"name":"container","pass":true,"got":"mov,mp4,m4a,3gp,3g2,mj2","want":"mp4"},{"name":"streams","pass":true,"got":"1 video, 1 audio","want":"1 video, 1 audio"},{"name":"video codec","pass":true,"got":"h264","want":"h264"},{"name":"size","pass":true,"got":"1080x1920","want":"1080x1920"},{"name":"pixel aspect","pass":true,"got":"1:1","want":"1:1"},{"name":"pixel format","pass":true,"got":"yuv420p","want":"yuv420p"},{"name":"frame rate","pass":true,"got":"30/1","want":"30/1"},{"name":"frames","pass":true,"got":"450","want":450},{"name":"duration","pass":true,"got":15.000000,"want":"15 +- 0.05"},{"name":"audio codec","pass":true,"got":"aac","want":"aac"},{"name":"audio rate","pass":true,"got":"48000","want":48000},{"name":"audio channels","pass":true,"got":2,"want":2},{"name":"audio length","pass":true,"got":15.010000,"want":"15 +- 0.1"},{"name":"faststart (moov before mdat)","pass":true,"got":"moov at 40, mdat at 1000","want":"moov first"},{"name":"loudness (LUFS)","pass":true,"got":-14.60,"want":"-14 +- 2.0"},{"name":"true peak (dBTP)","pass":true,"got":-99,"want":"at most -0.5"},{"name":"made from the approved screenplay","pass":true,"got":"fedcba98","want":"fedcba98"},{"name":"is the file that reel render wrote","pass":false,"got":"no render.json","want":"01234567"},{"name":"hook picture at 0.5 s","pass":true,"got":"1 2 3 4","want":"something drawn"}],"beats":[{"id":"b01","probe_s":1.7,"frame":"qa/b01.png","has_text":true,"drawn":"1 2 3 4","luminance_range":200,"problems":[],"pass":true},{"id":"b02","probe_s":6.5,"frame":"qa/b02.png","has_text":true,"drawn":"none","luminance_range":0,"problems":["no picture"],"pass":false}],"failures":["is the file that reel render wrote: got no render.json, want 01234567","beat b02: no picture"]}""")
  }
