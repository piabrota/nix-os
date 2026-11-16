package piabrota.reels

import piabrota.lib.{Sh, TestKit}
import scala.collection.mutable.ListBuffer

/** The real `reel` on the 15 s example, as a seat runs it: the gate (every command that makes a file
  * refuses without a matching approval), hostile text, slug rules, the lint, the render and its
  * determinism, the QA with files that must fail, publish, 3d shots (a stub stands in for blender:
  * Blender is never run here), the seats of the rig, atomicity and the ffmpeg time limit.
  *
  * It needs REELS_SHARE (the toolkit's share/reels) and ffmpeg, ffprobe, resvg and jq on the PATH,
  * and is skipped without them; reels/default.nix's passthru.tests.run gives it all. REELS_SPECS
  * and REELS_OPENRIG_NIX (openrig/specs and openrig.nix) default to the checkout's. About six
  * minutes; the tests run in order and build on each other.
  */
class ReelSuite extends munit.FunSuite:
  override val munitTimeout = scala.concurrent.duration.Duration(60, "min")

  private val share = sys.env.get("REELS_SHARE").filter(_.nonEmpty).map(os.Path(_, os.pwd))
  private val available = share.isDefined && Seq("ffmpeg", "ffprobe", "resvg", "jq").forall(Sh.which(_).isDefined)

  private lazy val t = os.temp.dir(prefix = "reels-test")
  private lazy val rh = t / "rh"
  private lazy val ob = t / "outbox"

  /** `reel <args>` with the test's folders, in t/cwd. */
  private def reel(args: Seq[String], lang: String = "C", env: Map[String, String] = Map.empty,
      fakes: Option[os.Path] = None, shareDir: Option[os.Path] = None): os.CommandResult =
    for d <- Seq("home", "tmp", "cwd") do os.makeDir.all(t / d)
    TestKit.piabrota("reel" +: args, cwd = t / "cwd", fakes = fakes, env = Map(
      "HOME" -> (t / "home").toString, "XDG_CACHE_HOME" -> (t / "cache").toString, "TMPDIR" -> (t / "tmp").toString,
      "LANG" -> lang, "REELS_HOME" -> rh.toString, "REELS_OUTBOX" -> ob.toString,
      "REELS_SHARE" -> shareDir.getOrElse(share.get).toString) ++ env)

  private def r(args: String*): os.CommandResult = reel(args)
  private def output(res: os.CommandResult): String = res.out.text() + res.err.text()
  private def tail(s: String, n: Int): String = s.linesIterator.toSeq.takeRight(n).mkString(" | ")

  /** The checks of one test: each failure is kept, and the test fails with all of them at its end. */
  private val failures = ListBuffer[String]()
  private def check(cond: Boolean, what: => String): Unit = if !cond then failures += what

  private def section(name: String)(body: => Unit)(using munit.Location): Unit =
    test(name) {
      assume(available, "REELS_SHARE, ffmpeg, ffprobe, resvg or jq is missing")
      failures.clear()
      body
      assert(failures.isEmpty, failures.mkString("\n"))
    }

  private def mustOk(what: String, res: os.CommandResult): Unit =
    check(res.exitCode == 0, s"$what: ${tail(output(res), 3)}")
  private def mustOk(what: String, args: String*): Unit = mustOk(what, r(args*))

  /** A non-zero exit and the text in the output. */
  private def mustFail(what: String, text: String, res: os.CommandResult): Unit =
    if res.exitCode == 0 then check(false, s"$what: it succeeded")
    else check(output(res).contains(text), s"$what: refused, but not with \"$text\": ${tail(output(res), 2)}")
  private def mustFail(what: String, text: String, args: String*): Unit = mustFail(what, text, r(args*))

  private def proj(slug: String) = rh / "projects" / slug
  private def sp(slug: String) = proj(slug) / "screenplay.json"
  private def outd(slug: String) = rh / "out" / slug
  private def sl(slug: String) = proj(slug) / "direction" / "shotlist.json"

  private def jqEdit(file: os.Path, filter: String): Unit =
    val res = os.proc("jq", filter, file).call(check = false)
    assert(res.exitCode == 0, s"jq $filter: ${res.err.text()}")
    os.write.over(file, res.out.bytes)
  private def edit(slug: String, filter: String): Unit = jqEdit(sp(slug), filter)
  private def editSl(slug: String, filter: String): Unit = jqEdit(sl(slug), filter)

  /** A signature of every file the project and its output hold. */
  private def files(slug: String): String =
    Seq(proj(slug), outd(slug)).filter(os.exists).flatMap(os.walk(_))
      .filter(p => os.isLink(p) || os.isFile(p, followLinks = false))
      .map(p => s"${p.relativeTo(rh)} ${if os.isLink(p) then os.readLink(p).toString else Sh.out("sha256sum", p).take(64)}")
      .sorted.mkString("\n")

  private def sha(file: os.Path): String = Sh.out("sha256sum", file).take(64)
  private def fresh(slug: String, format: String): Unit = r("new", slug, format, "--example")
  private def approved(slug: String): Unit =
    fresh(slug, "15")
    r("approve", slug)
    r("shotlist", slug)

  section("slugs") {
    for s <- Seq("../x", "a/b", "a b", "-x", "", ".hidden", "Upper", "a_b", "a;b", "a$(id)", "a" * 42) do
      mustFail(s"reel new '$s' is refused", "slug", "new", s, "30")
    mustFail("reel new x 20 is refused", "15 or 30", "new", "x", "20")
    mustFail("reel new x 30 --bogus is refused", "unknown option", "new", "x", "30", "--bogus")
    check(!os.exists(rh / "x"), "a bad slug made a folder")
    val n = if os.isDir(rh / "projects") then os.list(rh / "projects").length else 0
    check(n == 0, s"a bad slug made $n project(s)")
    mustFail("lint ../x is refused", "slug", "lint", "../x")
    mustFail("still ../x b01 is refused", "slug", "still", "../x", "b01")
    mustFail("publish a/b is refused", "slug", "publish", "a/b")
  }

  section("the command line") {
    val none = r()
    check(none.exitCode == 2 && none.out.text().startsWith("reel: the Reels Fabric toolkit"), "reel with no command: usage and exit 2")
    val help = r("help")
    check(help.exitCode == 0 && help.out.text().contains("reel publish <slug> [--replace]"), "reel help")
    mustFail("an unknown command is refused", "reel: unknown command: bogus", "bogus")
    val noShare = reel(Seq("lint", "x"), shareDir = Some(t / "nothing"))
    check(noShare.exitCode == 1 && noShare.err.text().contains("reel: cannot find the toolkit data (REELS_SHARE="),
      s"no share: ${output(noShare)}")
    mustFail("a REELS_HOME with a space is refused", "REELS_HOME: unsupported character",
      reel(Seq("lint", "x"), env = Map("REELS_HOME" -> (t / "a b").toString)))
  }

  section("the gate: no approval, no file") {
    fresh("gate", "15")
    mustOk("the example lints", "lint", "gate")
    val cmds = Seq("still gate b01", "scene gate b01", "music gate", "mix gate", "render gate", "shotlist gate", "qa gate",
      "contact-sheet gate", "publish gate", "blender gate b01")
    for c <- cmds do mustFail(s"'reel $c' refuses before approval", "not approved", c.split(' ').toSeq*)
    check(!os.exists(outd("gate") / "reel.mp4"), "a reel exists before approval")
    mustOk("approve", "approve", "gate", "--by", "tester")
    mustOk("shotlist", "shotlist", "gate")
    mustOk("still b02 after approval", "still", "gate", "b02")
    os.copy.over(proj("gate") / "direction" / "storyboard" / "b02.png", t / "b02-before.png")

    // One character changed after approval: every command refuses, and none writes a file.
    edit("gate", """.beats[1].text[0] = "Praia boa hoje!"""")
    val before = files("gate")
    for c <- cmds.map(c => if c == "shotlist gate" then "shotlist gate --force" else c) do
      mustFail(s"'reel $c' refuses after an edit", "changed after its approval", c.split(' ').toSeq*)
    check(before == files("gate"), "a refused command wrote a file")

    // Forms of approval that must not count.
    val h = sha(sp("gate"))
    val ap = proj("gate") / "screenplay.approved"
    def tryApproval(what: String, text: String): Unit =
      os.write.over(ap, text)
      mustFail(s"approval: $what", "approval", "still", "gate", "b01")
    tryApproval("upper case hash", s"${h.toUpperCase}  screenplay.json\n")
    tryApproval("short hash", s"${h.take(8)}  screenplay.json\n")
    tryApproval("another file name", s"$h  other.json\n")
    tryApproval("a line before the hash", s"approved by me\n$h  screenplay.json\n")
    tryApproval("CRLF", s"$h  screenplay.json\r\n")
    os.write.over(ap, s"$h  screenplay.json\napproved by someone\nand more lines\n")
    mustOk("approval: extra lines after the hash are fine", "music", "gate")
    os.remove(ap)
    os.write.over(t / "real.approved", s"$h  screenplay.json\n")
    os.symlink(ap, t / "real.approved")
    mustFail("approval: a symbolic link", "not approved", "still", "gate", "b01")
    os.remove(ap)
    os.write.over(ap, s"$h  screenplay.json\n")
    os.move(sp("gate"), t / "moved.json")
    os.symlink(sp("gate"), t / "moved.json")
    mustFail("screenplay.json: a symbolic link", "link", "still", "gate", "b01")
    os.remove(sp("gate"))
    os.move(t / "moved.json", sp("gate"))

    // Re-approval: a changed beat renders again, and an old shotlist is stale.
    mustOk("re-approve after the edit", "approve", "gate")
    mustFail("a shotlist of the old text is stale", "another version", "still", "gate", "b01")
    mustOk("shotlist --force", "shotlist", "gate", "--force")
    mustOk("still b02 after re-approval", "still", "gate", "b02")
    check(os.read.bytes(proj("gate") / "direction" / "storyboard" / "b02.png").toSeq != os.read.bytes(t / "b02-before.png").toSeq,
      "the changed beat gave the old picture")
    def upToDate(slug: String, beat: String) = output(r("scene", slug, beat)).contains("up to date")
    check(!upToDate("gate", "b02"), "scene b02 reused a clip after a re-approval")
    val c1 = sha(proj("gate") / "build" / "scenes" / "b02.mp4")
    check(upToDate("gate", "b02"), "an unchanged beat was rendered again")
    edit("gate", """.beats[1].text[0] = "Praia boa hoje?"""")
    mustFail("the clip cache does not serve a stale scene", "changed after its approval", "scene", "gate", "b02")
    mustOk("approve again", "approve", "gate")
    mustOk("shotlist --force again", "shotlist", "gate", "--force")
    check(!upToDate("gate", "b02"), "scene b02 served a stale clip")
    check(sha(proj("gate") / "build" / "scenes" / "b02.mp4") != c1, "the clip did not change with the text")
    // a change that touches no beat still voids the cache: the key holds the approved hash
    edit("gate", """.logline = "Another logline for the same beats"""")
    mustOk("approve the logline change", "approve", "gate")
    mustOk("shotlist --force after the logline change", "shotlist", "gate", "--force")
    check(!upToDate("gate", "b02"), "a clip outlived its approval")
  }

  section("hostile text") {
    fresh("evil", "15")
    edit("evil", """.beats[1].text = ["it's \"ok\": 100%", "a;b,c [x] <y> & *em*"]
      | .beats[2].text = ["$(touch PWN) `id`", "pts eif:1:d %pts"]
      | .beats[3].text = ["São João — ação", "Ünïcödé ñ 🌊"]""")
    mustOk("hostile text passes the lint", "lint", "evil")
    mustOk("approve", "approve", "evil")
    mustOk("shotlist", "shotlist", "evil")
    for b <- Seq("b02", "b03", "b04") do mustOk(s"still $b with hostile text", "still", "evil", b)
    check(!os.exists(t / "cwd" / "PWN") && !os.exists(t / "PWN"), "a command in the text ran")
    val ass = os.read(proj("evil") / "build" / "scenes" / "b03.ass")
    // The words of a line are separate runs with their own tags, so each word is looked for on its own.
    check(Seq("$(touch", "PWN)", "`id`", "%pts", "eif:1:d").forall(ass.contains), "the captions changed the text")
    val line = """^(Dialogue: [0-9]+,[0-9:.]+,[0-9:.]+,[A-Za-z]+,,0,0,0,,|\[|Format:|Style:|ScriptType:|PlayRes|WrapStyle:|ScaledBorderAndShadow:|; beat|$).*""".r
    check(ass.split("\n", -1).forall(l => line.matches(l)), "the script has a line that is not an event")
    for bad <- Seq("""a\\nb""", """a\nb""", """a\tb""", """a{\\fs500}b""", "%{pts}", "%{eif:1:d}", """x\\y""") do
      edit("evil", s""".beats[2].text = ["$bad"]""")
      mustFail(s"text '$bad' is refused", "lint", "approve", "evil")
    edit("evil", """.beats[2].text = [""]""")
    mustFail("an empty line is refused", "lint", "approve", "evil")
    edit("evil", """.beats[2].text = ["*odd", "x"]""")
    mustFail("an odd * is refused", "lint", "approve", "evil")
    edit("evil", """.beats[2].text = ["WWWWWWWWWWWWWWWWWWWWWWWWWWWW"]""")
    // The screenplay changed, so the shotlist of the example is stale and the lint says so: that is right.
    mustFail("a changed screenplay makes the old shotlist stale", "another version", "lint", "evil")
    mustOk("approve the 28 letters", "approve", "evil")
    mustOk("new shotlist for the 28 letters", "shotlist", "evil", "--force")
    mustOk("28 letters W: lint", "lint", "evil")
    val w = r("still", "evil", "b03")
    check(w.exitCode == 0 || output(w).contains("safe area"), s"a 28 letter word: ${output(w)}")
    // the palette and the style reach SVG and file names
    fresh("pal", "15")
    edit("pal", """.look.palette = {accent: "#fff\"/><script>"}""")
    mustFail("a palette value with markup is refused", "palette", "approve", "pal")
    edit("pal", """.look = {style: "../../etc/passwd"}""")
    mustFail("a style with a path is refused", "style", "approve", "pal")
    fresh("bid", "15")
    edit("bid", """.beats[1].id = "b02;touch PWN"""")
    mustFail("a beat id with a command is refused", "id must be b02", "approve", "bid")
    fresh("slugin", "15")
    edit("slugin", """.slug = "slugin\n"""")
    mustFail("a slug with a line break is refused", "slug", "approve", "slugin")
    fresh("lay", "15")
    edit("lay", """.beats[1].visual.scene = "diagram_reveal" | .beats[1].visual.params = {layers: ["direction/svg/../../x.svg"]}""")
    mustFail("a layer path outside direction/svg is refused", "layer", "approve", "lay")
    approved("lay2")
    editSl("lay2", """.shots[1].params = {layers: ["direction/svg/../../../../etc/passwd"]}""")
    mustFail("a layer path in the shotlist is refused", "layer", "still", "lay2", "b02")
  }

  section("the lint") {
    fresh("lint31", "30")
    edit("lint31", ".beats[-1].t_out = 31")
    mustFail("a 31 s screenplay fails", "the format is 30 s", "lint", "lint31")
    fresh("lint4", "15")
    edit("lint4", ".beats[0].t_out = 4 | .beats[1].t_in = 4")
    mustFail("a hook of 4 s fails", "it must end by 3 s", "lint", "lint4")
    fresh("lintlong", "15")
    edit("lintlong", """.beats[1].text = ["This line is far too long to read in time", "and so is this other one"]""")
    mustFail("overlong text fails", "characters", "lint", "lintlong")
    fresh("lintvo", "15")
    edit("lintvo", """.beats[0].vo = "hello"""")
    mustFail("a vo field fails", "vo (voice-over)", "lint", "lintvo")
    fresh("lintsil", "15")
    edit("lintsil", """.music = {preset: "none"} | .beats |= map(.sound.sfx = [])""")
    mustFail("a reel with no sound fails", "no sound at all", "lint", "lintsil")
    fresh("lintjson", "15")
    os.write.over(sp("lintjson"), "[1,2]")
    mustFail("a screenplay that is not an object fails", "one JSON object", "lint", "lintjson")
    os.write.over(sp("lintjson"), """{"schema": 3}""")
    mustFail("a screenplay of the wrong shape fails closed", "ERROR", "lint", "lintjson")
    os.write.over(sp("lintjson"), "not json")
    mustFail("a screenplay that is not JSON fails", "not valid JSON", "lint", "lintjson")
    // the read-only commands work on any file
    val view = r("screenplay-view", (share.get / "examples" / "15" / "screenplay.json").toString)
    check(view.exitCode == 0 && view.out.text().contains("PICTURE"), s"screenplay-view of a file: ${output(view)}")
    val timing = r("timing-report", (share.get / "examples" / "15" / "screenplay.json").toString)
    check(timing.out.text().contains("TABLE READ") && timing.out.text().contains("result: "), s"timing-report: ${output(timing)}")
  }

  section("locales") {
    approved("loc")
    for l <- Seq("C", "C.UTF-8", "pt_BR.UTF-8") do
      mustOk(s"still with LANG=$l", reel(Seq("still", "loc", "b03", "-o", (t / s"loc-$l.png").toString), lang = l))
    check(os.exists(t / "loc-C.png") && os.read.bytes(t / "loc-C.png").toSeq == os.read.bytes(t / "loc-C.UTF-8.png").toSeq,
      "the picture changes with the locale")
    mustFail("still -o needs .png", ".png", "still", "loc", "b03", "-o", (t / "x.mp4").toString)
  }

  private def reelf = outd("film") / "reel.mp4"

  /** The file as out/film/reel.mp4, with a render.json that names it, so that QA judges the file
    * and not its provenance.
    */
  private def forge(file: os.Path): Unit =
    os.copy.over(file, reelf)
    os.write.over(outd("film") / "render.json",
      s"""{"screenplay_sha256": "${sha(sp("film"))}", "reel_sha256": "${sha(reelf)}"}""")

  private def ffmpeg(args: String*): Unit =
    Sh.run(Seq("ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y") ++ args)

  private def qaFails(what: String, text: String): Unit =
    val res = r("qa", "film")
    if res.exitCode == 0 then check(false, s"QA accepted: $what")
    else check(output(res).contains(text),
      s"QA failed, but not with \"$text\" for: $what: ${output(res).linesIterator.filter(l => l.contains("FAIL") || l.contains("->")).take(3).mkString(" | ")}")
    val qa = outd("film") / "qa.json"
    if os.exists(qa) then check(ujson.read(os.read(qa))("pass") == ujson.False, s"  qa.json says pass true: $what")
    check(r("publish", "film").exitCode != 0, s"  publish accepted: $what")

  section("render and QA (the 15 s example)") {
    approved("film")
    val res = r("render", "film")
    mustOk("render", res)
    check(res.out.text().contains("render: ") && res.out.text().contains("MiB peak in one ffmpeg"), s"render's line: ${res.out.text()}")
    val rj = ujson.read(os.read(outd("film") / "render.json"))
    check(rj("slug").str == "film" && rj("reel_sha256").str == sha(reelf) && rj("screenplay_sha256").str == sha(sp("film")),
      s"render.json: $rj")
    mustOk("qa passes on the render", "qa", "film")
    mustOk("contact-sheet", "contact-sheet", "film")
    check(os.isFile(outd("film") / "qa" / "contact-sheet.png"), "no contact sheet")
    os.copy.over(reelf, t / "base.mp4")
    val h1 = sha(reelf)
    os.remove.all(proj("film") / "build")
    os.makeDir(proj("film") / "build")
    r("render", "film")
    check(h1 == sha(reelf), s"two renders differ: $h1 ${sha(reelf)}")
    mustOk("qa passes on the second render", "qa", "film")

    forge(t / "base.mp4")
    mustOk("QA passes on the forged copy of a good render", "qa", "film")
    val base = (t / "base.mp4").toString
    // Re-encoded, so the length is exact and the faststart check does not add a second failure.
    // (-c copy of 14.9 s keeps whole packets and gives 14.967 s, inside the 0.05 s tolerance.)
    ffmpeg("-i", base, "-t", "14.9", "-preset", "ultrafast", "-movflags", "+faststart", (t / "short.mp4").toString)
    forge(t / "short.mp4")
    qaFails("a 14.9 s video", "FAIL  duration")
    // 449 frames and 14.95 s of sound: inside the duration tolerance, one frame short: only "frames" sees it.
    ffmpeg("-i", base, "-frames:v", "449", "-t", "14.95", "-preset", "ultrafast", "-movflags", "+faststart", (t / "short2.mp4").toString)
    forge(t / "short2.mp4")
    qaFails("a 14.95 s video (449 frames)", "FAIL  frames")
    ffmpeg("-i", base, "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo", "-map", "0:v", "-map", "1:a", "-t", "15", "-c:v", "copy",
      "-c:a", "aac", (t / "silent.mp4").toString)
    forge(t / "silent.mp4")
    qaFails("a silent track", "FAIL  loudness")
    ffmpeg("-i", base, "-map", "0:v", "-map", "0:a", "-c:v", "copy", "-af", "volume=20dB", "-c:a", "aac", "-b:a", "128k",
      "-movflags", "+faststart", (t / "clip.mp4").toString)
    forge(t / "clip.mp4")
    qaFails("audio that clips", "FAIL  true peak")
    ffmpeg("-i", base, "-an", "-c:v", "copy", "-movflags", "+faststart", (t / "noaudio.mp4").toString)
    forge(t / "noaudio.mp4")
    qaFails("a video with no audio stream", "FAIL  streams")
    ffmpeg("-i", base, "-vf", "scale=720:1280", "-preset", "ultrafast", "-c:a", "copy", "-movflags", "+faststart", (t / "small.mp4").toString)
    forge(t / "small.mp4")
    qaFails("a 720x1280 video", "FAIL  size")
    ffmpeg("-i", base, "-r", "25", "-preset", "ultrafast", "-c:a", "copy", "-movflags", "+faststart", (t / "fps25.mp4").toString)
    forge(t / "fps25.mp4")
    qaFails("a 25 fps video", "FAIL  frame rate")
    ffmpeg("-i", base, "-c", "copy", (t / "slow.mp4").toString)
    forge(t / "slow.mp4")
    qaFails("a video with its moov atom at the end", "FAIL  faststart")
    ffmpeg("-i", base, "-vf", "drawbox=x=100:y=1700:w=800:h=110:color=white:t=fill", "-preset", "ultrafast", "-c:a", "copy",
      "-movflags", "+faststart", (t / "unsafe.mp4").toString)
    forge(t / "unsafe.mp4")
    qaFails("text drawn in the unsafe zone", "leaves the safe area")
    ffmpeg("-i", base, "-vf", "drawbox=x=0:y=0:w=iw:h=ih:color=0x14171f:t=fill:enable='between(t,4.6,5.4)'", "-preset", "ultrafast",
      "-c:a", "copy", "-movflags", "+faststart", (t / "blank.mp4").toString)
    forge(t / "blank.mp4")
    qaFails("a blank frame at a beat", "beat b02: the screenplay has text but the frame")
    os.write.over(t / "garbage.mp4", "this is not a video")
    forge(t / "garbage.mp4")
    qaFails("a file that is not a video", "not a video")
    // provenance: a good file that render did not make
    forge(t / "base.mp4")
    jqEdit(outd("film") / "render.json", """.reel_sha256 = "0000"""")
    qaFails("a file that render did not write", "FAIL  is the file that reel render wrote")
    os.remove(outd("film") / "render.json")
    qaFails("a file with no render.json", "FAIL  made from the approved screenplay")
  }

  section("publish") {
    forge(t / "base.mp4")
    os.remove(outd("film") / "qa.json")
    mustFail("publish with no QA report", "no QA report", "publish", "film")
    mustOk("qa", "qa", "film")
    os.makeDir.all(ob / "other")
    os.write.over(ob / "other" / "keep.txt", "keep")
    mustOk("publish", "publish", "film")
    check(Seq("reel.mp4", "qa.json", "screenplay.json", "screenplay.approved").forall(n => os.isFile(ob / "film" / n)),
      "publish left files out")
    check(os.perms(ob / "film" / "reel.mp4").contains(java.nio.file.attribute.PosixFilePermission.GROUP_READ),
      "the group cannot read the published file")
    mustFail("a second publish is refused", "use --replace", "publish", "film")
    mustOk("publish --replace", "publish", "film", "--replace")
    check(os.read(ob / "other" / "keep.txt") == "keep", "another slug changed")
    check(!os.list(ob).exists(_.last.startsWith(".")), "publish left a hidden folder in the outbox")
    mustFail("publish --bogus is refused", "unknown option", "publish", "film", "--bogus")
    os.makeDir.all(proj("film") / "review")
    os.symlink(proj("film") / "review" / "link.md", os.Path("/etc/hostname"))
    mustFail("a link in review/ is refused", "symbolic link", "publish", "film", "--replace")
    os.remove(proj("film") / "review" / "link.md")
    os.write.append(reelf, "x")
    mustFail("publish after the file changed", "not the file that reel render wrote", "publish", "film", "--replace")
    forge(t / "base.mp4")
    edit("film", """.logline = "changed after the qa"""")
    mustFail("publish after the screenplay changed", "changed after its approval", "publish", "film", "--replace")
  }

  // The real Blender is never run here. A stub named blender stands in for it: it keeps the
  // arguments and the environment it got, writes the PNG sequence the real one would, and ends like
  // the real one does on EEVEE (a crash) when the last engine that it was told to use is not CYCLES.
  private val stub = """#!/bin/sh
    |printf '%s\n' "$*" >>"$STUB_LOG"
    |printf 'HOME=%s CONFIG=%s CACHE=%s\n' "$HOME" "${XDG_CONFIG_HOME:-}" "${XDG_CACHE_HOME:-}" >>"$STUB_LOG"
    |mode='' out='' w='' h='' reel_engine='' engine='' pyfiles=''
    |while [ $# -gt 0 ]; do
    |  case $1 in
    |    --reel-mode) mode=$2 ;;
    |    --reel-out) out=$2 ;;
    |    --reel-width) w=$2 ;;
    |    --reel-height) h=$2 ;;
    |    --reel-engine) reel_engine=$2 ;;
    |    --python) pyfiles="$pyfiles $2" ;;
    |  esac
    |  shift
    |done
    |for f in $pyfiles; do
    |  case $f in
    |    *reel_blender.py) engine=$reel_engine ;;
    |    *)
    |      while IFS= read -r line; do
    |        case $line in
    |          *"render.engine = '"*)
    |            e=${line#*"render.engine = '"}
    |            engine=${e%%"'"*}
    |            ;;
    |        esac
    |      done <"$f"
    |      ;;
    |  esac
    |done
    |case $mode in
    |  probe) echo "REEL_FRAMES 1 $STUB_FRAMES" ;;
    |  render)
    |    [ -z "${STUB_EXIT:-}" ] || exit "$STUB_EXIT"
    |    if [ "$engine" != CYCLES ]; then
    |      echo "EGL error, segmentation fault ($engine)" >&2
    |      exit 139
    |    fi
    |    ffmpeg -nostdin -loglevel error -y -f lavfi -i "color=c=$STUB_COLOR:s=${w}x${h}" -frames:v "$STUB_FRAMES" "${out%####}%04d.png"
    |    ;;
    |esac
    |""".stripMargin
  private lazy val stubDir = TestKit.fakes("blender" -> stub)
  private def stubLog = t / "stub.log"

  /** `reel` with the stub first in the PATH: `frames` frames of `color`, `exit` its exit code. */
  private def rb(args: String*)(using s: Stub): os.CommandResult =
    reel(args, fakes = Some(stubDir), env = Map("STUB_LOG" -> stubLog.toString, "STUB_FRAMES" -> s.frames.toString,
      "STUB_COLOR" -> s.color, "STUB_EXIT" -> s.exit))
  private final case class Stub(frames: Int = 24, color: String = "0x3060a0", exit: String = "")

  private def nframes(dir: os.Path): Int = if os.isDir(dir) then os.list(dir).count(_.last.endsWith(".png")) else 0

  /** The colour at x=20, y=20 (the captions never reach that corner). The clip is yuv420p: the crop
    * filter rounds a 1x1 crop down to the chroma grid (0x0), so convert to rgb24 first.
    */
  private def pixel(video: os.Path, second: String): Seq[Int] =
    os.proc("ffmpeg", "-nostdin", "-loglevel", "error", "-ss", second, "-i", video, "-vf", "format=rgb24,crop=1:1:20:20",
      "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgb24", "-").call(check = false).out.bytes.toSeq.map(_ & 0xff)
  private def near(rgb: Seq[Int], want: Int*): Boolean = rgb.length == 3 && rgb.zip(want).forall((a, b) => math.abs(a - b) < 10)

  section("3d shots (a stub stands in for blender)") {
    approved("td")
    mustOk("the default shotlist lints with kind flat", "lint", "td")
    editSl("td", """.shots[2].kind = "3d" | .shots[2].frames = "frames/b03"""")
    mustOk("a shot of kind 3d with its frames path lints", "lint", "td")
    editSl("td", """.shots[2].frames = "frames/b02"""")
    mustFail("a 3d shot with another beat's frames is refused", "frames/b03", "lint", "td")
    editSl("td", """.shots[2].kind = "4d" | .shots[2].frames = "frames/b03"""")
    mustFail("a shot kind that is not flat or 3d is refused", "kind is flat or 3d", "lint", "td")
    editSl("td", """.shots[2].kind = "flat" | .shots[2].frames = "frames/b03"""")
    mustFail("frames on a flat shot is refused", "kind 3d only", "lint", "td")
    editSl("td", """.shots[2].kind = "3d" | .shots[2].frames = "frames/b03" | .shots[3].kind = "3d" | .shots[3].frames = "../x"""")
    mustFail("frames with a path out of frames/ is refused", "frames/b04", "lint", "td")
    editSl("td", """.shots[3].kind = "flat" | del(.shots[3].frames)""")
    mustFail("reel blender on a flat shot is refused", "not of kind 3d", "blender", "td", "b02")
    mustFail("reel blender with no blender in the PATH", "blender is not in the PATH", "blender", "td", "b03")
    given Stub = Stub()
    mustFail("reel blender with no scene file", "no scene file", rb("blender", "td", "b03"))
    os.makeDir.all(proj("td") / "blender")
    // a scene file that asks for EEVEE, as many scenes do
    os.write.over(proj("td") / "blender" / "b03.py",
      os.read(share.get / "examples" / "blender" / "spin.py") + "\nbpy.context.scene.render.engine = 'BLENDER_EEVEE'\n")
    os.write.over(stubLog, "")
    mustFail("a scene of 241 frames is refused", "needs 241 frames", rb("blender", "td", "b03")(using Stub(frames = 241)))
    mustFail("a scene of 300 frames is refused and the message names the budget", "the budget is 240",
      rb("blender", "td", "b03")(using Stub(frames = 300)))
    check(!os.exists(proj("td") / "frames" / "b03") && !os.exists(proj("td") / "frames" / "b03.part"), "a refused scene left frames")
    check(!os.read(stubLog).contains("--reel-mode render"), "a refused scene was rendered")
    mustFail("a blender that fails ends the command", "blender failed (exit code 3)", rb("blender", "td", "b03")(using Stub(exit = "3")))
    check(!os.exists(proj("td") / "frames" / "b03") && !os.exists(proj("td") / "frames" / "b03.part"), "a failed blender left frames")
    mustOk("a scene of exactly 240 frames is rendered", rb("blender", "td", "b03")(using Stub(frames = 240)))
    check(nframes(proj("td") / "frames" / "b03") == 240, s"frames/b03 holds ${nframes(proj("td") / "frames" / "b03")} files")
    os.write.over(stubLog, "")
    val done = rb("blender", "td", "b03")
    mustOk("reel blender renders the 24 frames of the example", done)
    check(done.out.text().startsWith(s"blender b03: ${proj("td")}/frames/b03 (24 frames, "), s"blender's line: ${done.out.text()}")
    check(nframes(proj("td") / "frames" / "b03") == 24, "a new render did not replace the old frames")
    check(os.isFile(proj("td") / "frames" / "b03" / "0001.png") && !os.exists(proj("td") / "frames" / "b03.part"), "frame names or a .part folder")
    // the engine: CYCLES on the CPU, set by the toolkit after the scene file, never EEVEE
    val log = os.read(stubLog)
    check(log.contains("--reel-engine CYCLES --reel-device CPU"), "the toolkit did not ask for CYCLES on the CPU")
    check(!log.contains("EEVEE"), "EEVEE is on the command line")
    check("""--python [^ ]*/blender/b03.py --python [^ ]*reel_blender.py""".r.findFirstIn(log).isDefined,
      "the toolkit's script does not come after the scene file")
    check(log.contains("-b --factory-startup --threads 2 "), "blender flags")
    check(log.contains("--reel-samples 16 --reel-width 1080 --reel-height 1920 --reel-fps 24 "), "samples, size or rate")
    val home = log.linesIterator.filter(_.startsWith("HOME=")).toSeq.lastOption.getOrElse("")
    val inside = s"${proj("td")}/"
    check(home.startsWith(s"HOME=$inside") && home.contains(s" CONFIG=$inside") && home.contains(s" CACHE=$inside"),
      s"blender ran with a home outside the project: $home")
    // the picture of the beat is the sequence, and a new sequence makes a new clip
    val clip = proj("td") / "build" / "scenes" / "b03.mp4"
    mustOk("reel scene takes the sequence as the picture", rb("scene", "td", "b03"))
    check(near(pixel(clip, "1"), 48, 96, 160), s"the clip does not show the frames: ${pixel(clip, "1")}")
    check(output(r("scene", "td", "b03")).contains("up to date"), "the clip was rendered again for the same frames")
    mustOk("a new sequence", rb("blender", "td", "b03")(using Stub(color = "0xa03060")))
    check(!output(r("scene", "td", "b03")).contains("up to date"), "the clip outlived its frames")
    check(near(pixel(clip, "1"), 160, 48, 96), s"the new clip shows: ${pixel(clip, "1")}")
    // a 3d beat with no frames yet: a still falls back to the flat picture, a clip is refused
    editSl("td", """.shots[3].kind = "3d" | .shots[3].frames = "frames/b04"""")
    mustFail("a 3d beat with no frames has no clip", "no frames", "scene", "td", "b04")
    mustOk("a 3d beat with no frames has a flat still", "still", "td", "b04", "-o", (t / "b04-flat.png").toString)
    mustFail("render stops at a 3d beat with no frames", "no frames", "render", "td")
    editSl("td", """.shots[3].kind = "flat" | del(.shots[3].frames)""")
    os.symlink(proj("td") / "frames" / "b03" / "9999.png", os.Path("/etc/hostname"))
    mustFail("a link in the frames is refused", "symbolic link", "scene", "td", "b03")
    os.remove(proj("td") / "frames" / "b03" / "9999.png")
    // the whole reel with one 3d beat
    mustOk("render with a 3d beat", "render", "td")
    mustOk("qa passes on a reel with a 3d beat", "qa", "td")
    approved("gate3d")
    editSl("gate3d", """.shots[2].kind = "3d" | .shots[2].frames = "frames/b03"""")
    os.makeDir.all(proj("gate3d") / "blender")
    os.copy.over(proj("td") / "blender" / "b03.py", proj("gate3d") / "blender" / "b03.py")
    edit("gate3d", """.logline = "Another logline"""")
    mustFail("reel blender after the screenplay changed", "changed after its approval", rb("blender", "gate3d", "b03"))
  }

  section("the crew: the seats of the rig and of the specs") {
    val specs = os.Path(sys.env.getOrElse("REELS_SPECS", "../openrig/specs"), os.pwd)
    assume(os.isDir(specs / "rigs" / "reels-fabric"), "no specs next to the tests (REELS_SPECS)")
    val rig = os.read(specs / "rigs" / "reels-fabric" / "rig.yaml")
    val nix = os.Path(sys.env.getOrElse("REELS_OPENRIG_NIX", (specs / os.up / os.up / "openrig.nix").toString), os.pwd)
    val lines = rig.linesIterator.toSeq
    for seat <- Seq("creative-director", "producer-editor", "artist-3d", "music-director", "qa") do
      check(lines.contains(s"      - id: $seat"), s"rig.yaml has no seat $seat")
      check(rig.contains(s"cwd: /var/lib/openrig/work/reels-fabric/$seat"), s"the seat $seat has no cwd of its own")
      check(rig.contains(s"crew-$seat@reels-fabric"), s"rig.yaml does not name crew-$seat@reels-fabric")
      check(rig.contains(s"""agent_ref: "local:../../agents/reels-$seat""""), s"the seat $seat has no agent_ref")
      for f <- Seq("agent.yaml", "guidance/role.md", "startup/context.md") do
        check(os.isFile(specs / "agents" / s"reels-$seat" / os.RelPath(f)), s"reels-$seat has no $f")
      val role = specs / "agents" / s"reels-$seat" / "guidance" / "role.md"
      check(os.isFile(role) && os.read.lines(role).length <= 50, s"the role of $seat is too long")
      if os.isFile(nix) then check(os.read(nix).contains(s"\"$seat\""), s"openrig.nix has no folder for $seat")
    check(lines.count(_.startsWith("      - id: ")) == 5, "the rig has not five seats")
    check(lines.count(_.contains("kind: delegates_to")) == 4, "the rig has not four edges")
    // no seat of the old rig, in the rig, in the agents or in their norms
    val old = """reels-(writer|script-editor|director|maker)|(story|studio)[-.](writer|script-editor|director|maker|qa)""".r
    val texts = (Seq(specs / "rigs" / "reels-fabric") ++ os.list(specs / "agents").filter(_.last.startsWith("reels-")))
      .flatMap(os.walk(_)).filter(os.isFile(_))
    val named = texts.filter(f => old.findFirstIn(os.read(f)).isDefined)
    check(named.isEmpty, s"a seat of the old rig is still named: ${named.take(2).mkString(", ")}")
    check(!Seq("writer", "script-editor", "director", "maker").exists(n => os.exists(specs / "agents" / s"reels-$n")),
      "an agent of the old rig is still there")
    check(os.read(specs / "agents" / "reels-shared" / "guidance" / "norms.md").toLowerCase.contains("executive producer"),
      "the norms do not name the executive producer")
    check(!lines.exists(_.startsWith("      - id: executive")), "the executive producer is a seat")
  }

  section("failed ffmpeg, stale lock, time limit") {
    approved("atom")
    val fake = TestKit.fakes("ffmpeg" -> "#!/bin/sh\nexit 1\n")
    def fk(args: String*) = reel(args, fakes = Some(fake))
    os.makeDir.all(outd("atom"))
    os.write.over(outd("atom") / "reel.mp4", "old")
    os.write.over(outd("atom") / "render.json", "{}")
    os.write.over(outd("atom") / "qa.json", """{"pass":true}""")
    check(fk("render", "atom").exitCode != 0, "render with a failing ffmpeg succeeded")
    check(os.list(outd("atom")).isEmpty, s"a failed render left files in out/: ${os.list(outd("atom")).map(_.last)}")
    check(fk("qa", "atom").exitCode != 0, "qa accepted after a failed render")
    check(fk("publish", "atom").exitCode != 0, "publish accepted after a failed render")
    // a lock of a dead process is taken over; a lock of a live one is respected
    val lock = proj("atom") / "build" / "render.lock"
    os.makeDir.all(lock)
    os.write.over(lock / "pid", "999999\n")
    check(!output(fk("render", "atom")).contains("another render"), "a stale lock blocked the render")
    os.makeDir.all(lock)
    os.write.over(lock / "pid", s"${scala.scalanative.posix.unistd.getpid()}\n")
    check(output(fk("render", "atom")).contains("another render"), "a live lock was ignored")
    os.remove.all(lock)
    // the time limit: a profile of 2 s and an ffmpeg that sleeps
    val share2 = t / "share2"
    os.copy(share.get, share2, followLinks = true)
    os.walk(share2).foreach(p => os.perms.set(p, os.perms(p) + java.nio.file.attribute.PosixFilePermission.OWNER_WRITE))
    jqEdit(share2 / "profile.json", ".limits.ffmpeg_timeout_s = 2")
    val sleepy = TestKit.fakes("ffmpeg" -> "#!/bin/sh\nexec sleep 60\n")
    val s0 = System.currentTimeMillis()
    val hung = reel(Seq("still", "atom", "b01"), fakes = Some(sleepy), shareDir = Some(share2))
    val d = (System.currentTimeMillis() - s0) / 1000
    check(hung.exitCode != 0, "a hung ffmpeg did not fail")
    check(d <= 30, s"a hung ffmpeg held the run for $d s")
    check(output(hung).contains("ffmpeg stopped: no result after 2 s"), s"no line about the time limit: ${output(hung)}")
  }
