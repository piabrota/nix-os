package piabrota.reels

import piabrota.lib.Sh
import Json.*

/** The checks of the finished file, the contact sheet, the hand-over to the outbox. QA never looks
  * at the shotlist: it measures the MP4 against the profile and the approved screenplay, so a wrong
  * scene cannot hide behind its own plan. Every number of qa.json is read from the file itself,
  * never from render.json or from an earlier QA.
  */
object Qa:
  /** The box of what a frame draws, from its edges (the picture minus a blurred copy of itself),
    * and the luminance range inside that box (0 for none). The background is a smooth gradient, so
    * only text, shapes and drawings leave edges.
    */
  private def measureFrame(tk: Toolkit, png: os.Path): (String, Int) =
    val bb = tk.tmp / "qa-bbox.txt"
    os.write.over(bb, "")
    if !tk.ff("-i", png.toString, "-vf",
        s"split[a][b];[b]gblur=sigma=3[bl];[a][bl]blend=all_mode=difference,format=gray,bbox=min_val=${tk.p("qa", "edge_min")},metadata=mode=print:file=$bb",
        "-frames:v", "1", "-f", "null", "-") then fail(s"cannot measure $png")
    val box = bboxOf(bb)
    if box == Box.Empty then (box, 0)
    else
      val Array(x1, y1, x2, y2) = box.split(' ').map(_.toInt)
      val st = tk.tmp / "qa-stats.txt"
      os.write.over(st, "")
      if !tk.ff("-i", png.toString, "-vf", s"crop=${x2 - x1 + 1}:${y2 - y1 + 1}:$x1:$y1,format=gray,signalstats,metadata=mode=print:file=$st",
          "-frames:v", "1", "-f", "null", "-") then fail(s"cannot measure the contrast of $png")
      val kv = metadata(st)
      def y(k: String) = kv.get(k).flatMap(_.toIntOption).getOrElse(0)
      (box, y("lavfi.signalstats.YMAX") - y("lavfi.signalstats.YMIN"))

  /** One frame of the file at that second; false past the end, where ffmpeg writes nothing and
    * says nothing.
    */
  private def frameAt(tk: Toolkit, mp4: os.Path, seconds: String, out: os.Path): Boolean =
    val part = Name.partPng(out)
    os.remove(out)
    os.remove(part)
    if !tk.ff("-ss", seconds, "-i", mp4.toString, "-frames:v", "1", "-f", "image2", "-update", "1", part.toString) then
      fail(s"cannot take the frame at $seconds s")
    os.isFile(part) && { os.move(part, out, replaceExisting = true); true }

  /** The byte offsets of the top-level boxes moov and mdat, -1 for a missing one. Reads the box
    * headers only: size (4 bytes, or 8 after size 1) and type, so a file whose index is at the end
    * (no +faststart) shows moov after mdat.
    */
  def mp4Boxes(file: os.Path): (Long, Long) =
    val total = os.size(file)
    @scala.annotation.tailrec
    def walk(off: Long, moov: Long, mdat: Long): (Long, Long) =
      if off >= total then (moov, mdat)
      else
        val h = os.read.bytes(file, off, math.min(16L, total - off).toInt)
        def u(from: Int, to: Int) = h.slice(from, to).foldLeft(0L)((a, b) => (a << 8) | (b & 0xff))
        if h.length < 8 then (moov, mdat)
        else
          val len = if u(0, 4) == 1 then (if h.length < 16 then -1L else u(8, 16)) else u(0, 4)
          val kind = new String(h.slice(4, 8), "ISO-8859-1")
          val moov2 = if kind == "moov" && moov < 0 then off else moov
          val mdat2 = if kind == "mdat" && mdat < 0 then off else mdat
          if len < 8 then (moov2, mdat2) else walk(off + len, moov2, mdat2)
    walk(0L, -1L, -1L)

  /** The loudnorm measurement of the audio as JSON, or null when the file has no audio stream. */
  private def loudness(tk: Toolkit, mp4: os.Path): String =
    val audio = os.proc(Tool.Timeout.bin, "-k", "5", "60", Tool.Ffprobe.bin, "-v", "error", "-select_streams", "a",
      "-show_entries", "stream=index", "-of", "csv=p=0", mp4).call(stderr = os.Inherit, check = false).out.text()
    if audio.strip().isEmpty then "null"
    else
      val log = tk.ffl("-i", mp4.toString, "-vn", "-af",
        s"loudnorm=I=${tk.p("audio", "target_lufs")}:TP=${tk.p("audio", "true_peak")}:LRA=11:print_format=json", "-f", "null", "-")
        .getOrElse(fail("loudness measurement failed"))
      Audio.loudnormBlock(log).map(Json.compact).getOrElse(fail("cannot read the loudness measurement"))

  /** Where QA looks (qaplan.jq): id, probe second, start second, "1" when the beat has text. */
  private def plan(tk: Toolkit, p: Project): Seq[Array[String]] =
    val tl = Json.compact(ujson.Arr.from(p.timeline.map(c => ujson.Obj("id" -> c.id, "tr" -> c.tr, "S" -> c.s, "E" -> c.e,
      "hin" -> c.hin, "hout" -> c.hout, "frames" -> c.frames, "dq" -> c.dq))))
    tk.jq(Seq("-r", "--argjson", "profile", tk.profileText, "--argjson", "sp", p.spText, "-f", tk.rule(Rule.QaPlan)),
      "cannot plan the QA", stdin = tl).linesIterator.filter(_.nonEmpty).map(_.split('\t')).toSeq

  /** A frame at the probe and at the start of every beat, as bNN.png and bNN-start.png; the frame
    * at qa.hook_probe_s is hook.png.
    */
  private def extract(tk: Toolkit, p: Project, mp4: os.Path, rd: OutDir): Unit =
    os.makeDir.all(rd.qa)
    frameAt(tk, mp4, tk.p("qa", "hook_probe_s"), rd.hook)
    for Array(id, probe, start, _) <- plan(tk, p) do
      if !frameAt(tk, mp4, probe, rd.frame(id)) then note(s"no frame at $probe s: the file is shorter than the screenplay")
      frameAt(tk, mp4, start, rd.startFrame(id))

  /** The problems of one beat's frame: missing, empty, out of the safe area, low contrast. */
  def beatProblems(probe: String, box: String, range: Int, text: Boolean, safe: Seq[Long], slack: Long, minRange: Int): Seq[String] =
    val b = if box == Box.Empty || box == Box.Missing then None else Some(box.split(' ').map(_.toDouble).toSeq)
    val safeText = safe.mkString(" ")
    Seq(
      Option.when(box == Box.Missing)(s"no frame at $probe s: reel.mp4 is shorter than the screenplay"),
      Option.when(text && b.isEmpty && box != Box.Missing)(s"the screenplay has text but the frame at $probe s draws nothing"),
      b.filter(b => b(0) < safe(0) - slack || b(1) < safe(1) - slack || b(2) > safe(2) + slack || b(3) > safe(3) + slack)
        .map(_ => s"the picture at $probe s leaves the safe area: drawn $box, safe $safeText (x1 y1 x2 y2, slack $slack px)"),
      Option.when(text && b.isDefined && range < minRange)(s"low contrast at $probe s: luminance range $range, at least $minRange wanted"),
    ).flatten

  def qa(tk: Toolkit, args: List[String]): Int =
    if args.length != 1 then fail("usage: reel qa <slug>")
    val slug = args.head
    val p = Gate.load(tk, slug)
    val rd = tk.out(slug)
    val mp4 = rd.reel
    // An old report is void the moment QA starts: a QA that dies halfway leaves none.
    os.remove(rd.qaReport)
    os.remove(Name.part(rd.qaReport))
    if !plainFile(mp4) then fail(s"no reel to check: $mp4 (reel render $slug)")
    val qd = rd.qa
    val probe = os.proc(Tool.Timeout.bin, "-k", "5", "60", Tool.Ffprobe.bin, "-v", "error", "-print_format", "json", "-show_format",
      "-show_streams", mp4).call(stderr = os.Inherit, check = false)
    if probe.exitCode != 0 then fail(s"ffprobe cannot read $mp4: it is not a video file")
    extract(tk, p, mp4, rd)

    val safe = Scene.safeRect(tk)
    val slack = tk.pInt("qa", "safe_slack_px")
    val minRange = tk.pInt("qa", "min_text_range")
    val beats = for Array(id, at, _, txt) <- plan(tk, p) yield
      val (box, range) = if os.isFile(rd.frame(id)) then measureFrame(tk, rd.frame(id)) else (Box.Missing, 0)
      val problems = beatProblems(at, box, range, txt == "1", safe, slack, minRange)
      // The probe second is written as qaplan.jq printed it.
      s"""{"id":${Json.compact(id)},"probe_s":$at,"frame":${Json.compact(s"qa/$id.png")},"has_text":${txt == "1"},""" +
        s""""drawn":${Json.compact(box)},"luminance_range":$range,"problems":${Json.compact(ujson.Arr.from(problems.map(ujson.Str(_))))},""" +
        s""""pass":${problems.isEmpty}}"""
    os.write.over(tk.tmp / "qa-beats.jsonl", beats.map(_ + "\n").mkString)
    val hook = if os.isFile(rd.hook) then measureFrame(tk, rd.hook)._1 else Box.Empty
    val (moov, mdat) = mp4Boxes(mp4)
    val loud = loudness(tk, mp4)
    // What render.json says about the file: a claim to check, not a fact. The report carries the
    // file's own hash; the two checks "made from the approved screenplay" and "is the file that reel
    // render wrote" fail when render.json is missing or does not match.
    val claim = RenderClaim.from(if plainFile(rd.renderReport) then Json.readFile(rd.renderReport) else None)

    val report = tk.jqCall(Seq("--argjson", "profile", tk.profileText, "--arg", "slug", slug,
      "--argjson", "fmt", p.screenplay.format, "--argjson", "loud", loud,
      "--argjson", "moov", moov.toString, "--argjson", "mdat", mdat.toString,
      "--slurpfile", "beats", (tk.tmp / "qa-beats.jsonl").toString, "--arg", "hook", hook,
      "--arg", "reel_sha", tk.sha(mp4), "--arg", "sp_sha", p.hash, "--arg", "render_sha", claim.screenplaySha,
      "--arg", "render_reel", claim.reelSha, "-f", tk.rule(Rule.QaReport)), stdin = probe.out.bytes)
      .getOrElse(fail("cannot write the QA report"))
    os.write.over(Name.part(rd.qaReport), report)
    os.move(Name.part(rd.qaReport), rd.qaReport, replaceExisting = true)
    // jq prints the report's lines, so its numbers read as they are written in qa.json.
    print(tk.jq(Seq("-r", """.checks[] | "\(if .pass then "pass" else "FAIL" end)  \(.name): \(.got)"""", rd.qaReport.toString), "cannot read the QA report"))
    print(tk.jq(Seq("-r", """.beats[] | "\(if .pass then "pass" else "FAIL" end)  beat \(.id) at \(.probe_s) s: drawn \(.drawn), luminance range \(.luminance_range)"""", rd.qaReport.toString), "cannot read the QA report"))
    print(tk.jq(Seq("-r", """.failures[] | "  -> \(.)"""", rd.qaReport.toString), "cannot read the QA report"))
    if Json.readFile(rd.qaReport).exists(_.at("pass").truthy) then
      say(s"qa: PASS (${rd.qaReport}, frames in $qd)")
      0
    else
      say(s"qa: FAIL (${rd.qaReport})")
      1

  /** reel.mp4 must be the file that `reel render` wrote for the screenplay that is approved now:
    * render.json names both, by hash. Returns the out folder.
    */
  private def requireFreshReel(tk: Toolkit, slug: String, hash: String): OutDir =
    val rd = tk.out(slug)
    if !plainFile(rd.reel) then fail(s"no reel: ${rd.reel} (reel render $slug)")
    if !plainFile(rd.renderReport) then fail(s"no render.json: reel.mp4 was not made by reel render $slug")
    val claim = RenderClaim.from(Json.readFile(rd.renderReport))
    if claim.screenplaySha != hash then fail(s"reel.mp4 was made from another screenplay: reel render $slug again")
    if claim.reelSha != tk.sha(rd.reel) then
      fail(s"reel.mp4 is not the file that reel render wrote: reel render $slug again")
    rd

  /** All the beat frames in one PNG, in order, 270 px wide, four to a row. */
  def contactSheet(tk: Toolkit, args: List[String]): Int =
    if args.length != 1 then fail("usage: reel contact-sheet <slug>")
    val slug = args.head
    val p = Gate.load(tk, slug)
    val rd = requireFreshReel(tk, slug, p.hash)
    extract(tk, p, rd.reel, rd)
    val n = p.timeline.length
    for c <- p.timeline do
      if !os.isFile(rd.frame(c.id)) then fail(s"no frame for beat ${c.id}: reel.mp4 is shorter than the screenplay")
    val cols = math.min(4, n)
    val rows = (n + cols - 1) / cols
    val part = Name.partPng(rd.contactSheet)
    os.remove(part)
    if !tk.ff("-framerate", "1", "-i", s"${rd.qa}/b%02d.png", "-vf",
        s"scale=270:-2,tile=${cols}x$rows:padding=8:margin=8:color=0x222222", "-frames:v", "1", "-f", "image2", "-update", "1",
        part.toString) then fail("cannot make the contact sheet")
    os.move(part, rd.contactSheet, replaceExisting = true)
    say(s"contact sheet: ${rd.contactSheet} ($n beats)")
    0

  /** The finished reel to the outbox, where Hermes reads it. Needs a QA report that passed, made for
    * this very file and this very screenplay: the hashes in qa.json are compared with the file and
    * the approval as they are now (a report older than either does not match). One folder a slug,
    * written under a hidden name and moved in with one rename; an existing folder is kept unless
    * --replace says to swap it, and no other slug is ever touched.
    */
  def publish(tk: Toolkit, args: List[String]): Int =
    if args.isEmpty || args.length > 2 then fail("usage: reel publish <slug> [--replace]")
    val slug = args.head
    val replace = args.lift(1) match
      case None | Some("")   => false
      case Some("--replace") => true
      case Some(other)       => fail(s"unknown option: $other")
    val a = Gate.requireApproved(tk, slug)
    val rd = requireFreshReel(tk, slug, a.hash)
    if !plainFile(rd.qaReport) then fail(s"no QA report: run reel qa $slug first")
    val report = QaVerdict.from(Json.readFile(rd.qaReport).getOrElse(ujson.Null))
    if !report.passed then fail(s"the QA of $slug did not pass: fix it, render and run reel qa again")
    if report.reelSha != tk.sha(rd.reel) then fail(s"reel.mp4 changed after its QA: run reel qa $slug again")
    if report.screenplaySha != a.hash then fail("the QA is of another screenplay: render and run reel qa again")
    val review = a.dir.review
    if os.isDir(review) && !noLinks(review) then fail("review/ has a symbolic link: publish copies files, not links")
    val dest = tk.outbox / slug
    if present(dest) && !replace then fail(s"$dest exists: use --replace to swap it (only this slug is touched)")
    try os.makeDir.all(tk.outbox)
    catch case _: java.io.IOException => fail(s"cannot make ${tk.outbox}")
    // Staged inside the outbox, so the files take the folder's default ACL, and moved in with one rename.
    val stage = tk.outbox / s".$slug${Name.Part}"
    val old = tk.outbox / s".$slug.old"
    os.remove.all(stage)
    os.remove.all(old)
    if !tryMakeDir(stage) then fail(s"cannot write to ${tk.outbox}")
    def abort(message: String): Nothing =
      os.remove.all(stage)
      fail(message)
    // cp, not a copy in Scala: the files get the mode that cp gives them under the unit's umask.
    if Sh.run(Tool.Cp.bin, rd.reel, rd.qaReport, a.sp, a.dir.approval, s"$stage/") != 0 then abort("copy failed")
    if os.isDir(review) && Sh.run(Tool.Cp.bin, "-R", review, stage / review.last) != 0 then abort("copy of review failed")
    // The unit's UMask is 077, and a default ACL does not lift it on this box's ext4 (tested): Hermes
    // reads through the group of the folder, so the group gets its read bit here, not from the umask.
    if Sh.run(Tool.Chmod.bin, "-R", "g+rX", stage) != 0 then abort("cannot set the mode of the files")
    if present(dest) then
      try os.move(dest, old)
      catch case _: java.io.IOException => abort("cannot move the old folder aside")
    try os.move(stage, dest)
    catch
      case _: java.io.IOException =>
        if os.exists(old) then os.move(old, dest)
        abort("cannot move the folder into place")
    os.remove.all(old)
    say(s"published: $dest (${os.size(dest / Name.Reel)} bytes)")
    0

