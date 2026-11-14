package piabrota.reels

import Json.*

/** One beat to a picture: a background (or the frames of a 3d shot), SVG layers, the ASS captions. */
object Scene:
  /** The safe area, in whole pixels: x0 y0 x1 y1. */
  def safeRect(tk: Toolkit): Seq[Long] =
    val safe = tk.profile.json.at("safe")
    def f(k: String) = safe.at(k).number
    Seq(tk.W * f("side"), tk.H * f("top"), tk.W * (1 - f("side")), tk.H * (1 - f("bottom"))).map(jqRound)

  /** True when the box "x1 y1 x2 y2" is in the safe area (2 px of slack for the edges). */
  def insideSafe(tk: Toolkit, box: String): Boolean =
    val Seq(sx0, sy0, sx1, sy1) = safeRect(tk): @unchecked
    box.split(' ').toSeq.map(_.toLongOption) match
      case Seq(Some(x1), Some(y1), Some(x2), Some(y2)) =>
        x1 >= sx0 - 2 && y1 >= sy0 - 2 && x2 <= sx1 + 2 && y2 <= sy1 + 2
      case _ => false

  /** The bounding box of what the captions draw at that time, "x1 y1 x2 y2" or "none". The file is
    * the mask variant of the script (everything white).
    */
  private def textbox(tk: Toolkit, ass: os.Path, seconds: String): String =
    val bb = tk.tmp / "bbox.txt"
    os.write.over(bb, "")
    if !tk.ff("-f", "lavfi", "-i", s"color=c=black:s=${tk.W}x${tk.H}:r=${tk.FPS}:d=1",
        "-vf", s"setpts=PTS+$seconds/TB,ass=filename=$ass:fontsdir=${tk.fonts},format=gray,bbox=min_val=40,metadata=mode=print:file=$bb",
        "-frames:v", "1", "-f", "null", "-") then fail("cannot measure the captions")
    bboxOf(bb)

  /** A step of the captions, or None when it failed; its error goes to stderr, in jq's words. */
  private def drawn[A](f: => A): Option[A] =
    try Some(f)
    catch
      case JqError(msg) =>
        System.err.println(s"jq: error (at <unknown>): $msg")
        None

  /** The background PNG of the style, cached by its content. */
  private def ensureBg(tk: Toolkit, p: Project): os.Path =
    val key = drawn(Captions.backgroundKey(p.style)).getOrElse(fail("cannot draw the background"))
    val bg = p.dir.cache / s"bg-${shaOf(Nil, prefix = key).take(12)}.png"
    if !os.isFile(bg) then
      val svg = drawn(Captions.background(p.style, tk.profile.json)).getOrElse(fail("cannot draw the background"))
      os.write.over(tk.tmp / "bg.svg", svg)
      val part = Name.partPng(bg)
      if !tk.svgToPng("-w", tk.W.toString, "-h", tk.H.toString, (tk.tmp / "bg.svg").toString, part.toString) then
        fail("resvg failed on the background")
      os.move(part, bg, replaceExisting = true)
    bg

  private def input(tk: Toolkit, p: Project, id: String, hin: Double, total: Double, dur: Double, last: Boolean): (SceneInput, Shot) =
    val beat = p.spJson.at("beats").items.find(_.at("id") === Jv.Str(id)).getOrElse(fail(s"no beat $id in the screenplay"))
    val shot = Gate.shotOf(p, id)
    (SceneInput(p.spJson, beat, shot.json, p.style, tk.profile.json, hin, total, dur, last), shot)

  /** Renders one beat to `out`. A .png makes a still `at` seconds into the clip; anything else a
    * clip of `total` seconds.
    */
  def render(tk: Toolkit, p: Project, id: String, out: os.Path, hin: Double, total: Double, dur: Double,
      last: Boolean, at: String = ""): Unit =
    val still = out.last.endsWith(".png")
    val (in, shot) = input(tk, p, id, hin, total, dur, last)
    val ass = p.dir.ass(id)
    val assText = drawn(Captions.ass(in, mask = false)).getOrElse(fail(s"beat $id: the scene script failed"))
    os.write.over(Name.part(ass), assText)
    os.move(Name.part(ass), ass, replaceExisting = true)
    val planJson = drawn(Captions.plan(in)).getOrElse(fail(s"beat $id: the scene plan failed"))
    val planText = Json.compact(planJson)
    val plan = ScenePlan.from(planJson)

    // The captions must stay in the safe area: one frame of the mask, when the animations are done
    // (75 % of the beat).
    val mask = tk.tmp / s"$id.mask.ass"
    os.write.over(mask, drawn(Captions.ass(in, mask = true)).getOrElse(fail(s"beat $id: the mask script failed")))
    val box = textbox(tk, mask, Json.num(hin + dur * 0.75))
    if box == Box.Empty then note(s"beat $id: warning: no caption or drawing in the picture")
    else if !insideSafe(tk, box) then
      fail(s"beat $id: the picture leaves the safe area: box $box, safe ${safeRect(tk).mkString(" ")} (x1 y1 x2 y2). Shorten the lines or lower text_layout.scale in the shotlist")

    // A 3d shot (shotlist kind "3d") takes the PNG sequence of reel blender as its picture, in place
    // of the background and its slow zoom. The captions and the SVG layers go over it as on any
    // beat. A still of a 3d beat before its frames exist falls back to the flat background.
    val fdir = p.dir.frames(id)
    val threeD = shot.kind == ShotKind.ThreeD
    val frames = if threeD then glob(fdir, "", ".png").filter(plainFile) else Nil
    if threeD && frames.isEmpty then
      if still then note(s"beat $id: warning: a 3d shot with no frames yet: the picture shows the flat background")
      else fail(s"beat $id is a 3d shot with no frames: the artist-3d runs reel blender ${p.slug} $id")
    val nf = jqRound(total * tk.FPS)
    val totalS = Json.num(total)

    val (inputs, graph0, bgSha, framesSha) =
      if frames.nonEmpty then
        if !noLinks(fdir) then fail(s"beat $id: frames/$id has a symbolic link: reel blender writes files, not links")
        val start = frames.head.last.stripSuffix(".png").toDoubleOption.map(Json.num)
          .getOrElse(fail(s"beat $id: the frame ${frames.head.last} has no number"))
        (Seq("-framerate", tk.p("blender", "fps"), "-start_number", start, "-i", s"$fdir/%04d.png"),
          s"[0:v]fps=${tk.FPS},scale=${tk.W}:${tk.H}:force_original_aspect_ratio=increase,crop=${tk.W}:${tk.H},setsar=1,tpad=stop_mode=clone:stop_duration=$totalS[b0]",
          ShotKind.ThreeD.key, shaOf(glob(fdir, "", ".png")))
      else
        val bg = ensureBg(tk, p)
        val (z0, z1, grain) = (plan.zoom0, plan.zoom1, plan.grain)
        val zoom = s"[0:v]zoompan=z='$z0+($z1-$z0)*on/$nf':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=1:s=${tk.W}x${tk.H}:fps=${tk.FPS}"
        // The grain is seeded from the approved screenplay, so the same screenplay gives the same pixels.
        val noise = if grain != "0" then s",noise=alls=$grain:allf=t:all_seed=${Integer.parseInt(p.hash.take(7), 16)}" else ""
        (Seq("-framerate", tk.FPS.toString, "-loop", "1", "-t", totalS, "-i", bg.toString), s"$zoom$noise[b0]", tk.sha(bg), "")

    val (dy0, dh, dw) = (plan.diagramY0, plan.diagramH, plan.diagramW)
    // The layer names were checked by the plan: direction/svg/<name>.svg, no other folder.
    val layers = plan.layers
    val layerParts = layers.zipWithIndex.map { (layer, i) =>
      val k = i + 1
      val svg = layer.svg
      if !plainFile(p.dir.root / os.RelPath(svg)) then
        fail(s"beat $id: the layer $svg is missing or is a link: the creative director draws it in direction/svg/")
      val png = p.dir.layers / s"$id-$k.png"
      if !tk.svgToPng("-w", dw, "-h", dh, (p.dir.root / os.RelPath(svg)).toString, png.toString) then fail(s"resvg failed on $svg")
      (Seq("-framerate", tk.FPS.toString, "-loop", "1", "-t", totalS, "-i", png.toString),
        s";[$k:v]format=rgba,fade=t=in:st=${layer.at}:d=${layer.fade}:alpha=1[l$k];[b${k - 1}][l$k]overlay=x=(W-w)/2:y=$dy0+($dh-h)/2:format=auto[b$k]")
    }
    val graph = graph0 + layerParts.map(_._2).mkString +
      s";[b${layers.length}]ass=filename=$ass:fontsdir=${tk.fonts},scale=out_color_matrix=bt709:out_range=tv,format=yuv420p[v]"
    val allInputs = inputs ++ layerParts.flatMap(_._1)

    // A clip is skipped only when nothing it depends on changed: the frame graph, the plan, the
    // captions, the SVG layers, the background, the profile, the fonts folder, and the two files
    // the gate stands on: the approved screenplay and the shotlist. A re-approved screenplay or a
    // new shotlist therefore renders every beat again; a clip never outlives its approval.
    val keyText = Seq(graph, planText, nf.toString, bgSha, tk.profileText, p.hash, p.shotsSha, tk.fonts.toString, framesSha)
      .map(_ + "\n").mkString
    val key = shaOf(ass +: layers.map(l => p.dir.root / os.RelPath(l.svg)), prefix = keyText)
    val keyFile = out / os.up / s"${out.last}.key"
    val part = Name.part(out)

    if still then
      val partPng = Name.partPng(out)
      os.remove(partPng)
      if !tk.ffp(allInputs ++ Seq("-filter_complex", graph, "-map", "[v]", "-threads", "2", "-ss", at,
          "-frames:v", "1", "-f", "image2", "-update", "1", partPng.toString)*) then fail(s"beat $id: ffmpeg failed")
      os.move(partPng, out, replaceExisting = true)
    else if os.isFile(out) && os.isFile(keyFile) && os.read(keyFile).stripSuffix("\n") == key then
      note(s"beat $id: up to date")
    else
      Seq(out, keyFile, part).foreach(os.remove(_))
      if !tk.ffp(allInputs ++ Seq("-filter_complex", graph, "-map", "[v]", "-an", "-c:v", "libx264",
          "-preset", "veryfast", "-crf", tk.p("video", "scene_crf"), "-pix_fmt", "yuv420p", "-colorspace", "bt709",
          "-color_primaries", "bt709", "-color_trc", "bt709", "-color_range", "tv", "-r", tk.FPS.toString,
          "-frames:v", nf.toString, "-threads", "2", "-fflags", "+bitexact", "-flags:v", "+bitexact",
          "-map_metadata", "-1", "-f", "mp4", part.toString)*) then fail(s"beat $id: ffmpeg failed")
      os.move(part, out, replaceExisting = true)
      os.write.over(Name.part(keyFile), key + "\n")
      os.move(Name.part(keyFile), keyFile, replaceExisting = true)

  /** The clip of a beat, with the handles of its transitions, in build/scenes/. */
  def buildClip(tk: Toolkit, p: Project, id: String): Unit =
    val c = p.cut(id).getOrElse(fail(s"no beat $id in the screenplay"))
    render(tk, p, id, p.dir.clip(id), c.hin / tk.FPS, c.frames / tk.FPS,
      (c.e - c.s) / tk.FPS, p.isLast(id))

  def scene(tk: Toolkit, args: List[String]): Int =
    if args.length != 2 then fail("usage: reel scene <slug> <beat>")
    val p = Gate.load(tk, args.head)
    Gate.requireShotlist(tk, p)
    buildClip(tk, p, args(1))
    say(s"scene ${args(1)}: ${p.dir.clip(args(1))}")
    0

  /** A number as the shell toolkit accepted it for --at. */
  private val Number = """-?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?""".r

  /** The options of `reel still`, in any order; the last one of a kind wins. */
  def stillOptions(rest: List[String], o: StillOptions = StillOptions("", "")): StillOptions = rest match
    case "--at" :: v :: more => stillOptions(more, o.copy(at = v))
    case "--at" :: Nil        => fail("--at needs seconds")
    case "-o" :: v :: more    => stillOptions(more, o.copy(out = v))
    case "-o" :: Nil          => fail("-o needs a file")
    case opt :: _             => fail(s"unknown option: $opt")
    case Nil                  => o

  def still(tk: Toolkit, args: List[String]): Int =
    if args.length < 2 then fail("usage: reel still <slug> <beat> [--at <seconds into the beat>] [-o <file.png>]")
    val slug :: id :: rest = args: @unchecked
    val opts = stillOptions(rest)
    val o = opts.out
    if o.nonEmpty && !o.endsWith(".png") then fail("-o: the file must end in .png")
    val p = Gate.load(tk, slug)
    if p.hasShots then Gate.requireShotlist(tk, p)
    val c = p.cut(id).getOrElse(fail(s"no beat $id in the screenplay"))
    val dur = (c.e - c.s) / tk.FPS
    val at = if opts.at.isEmpty then Json.num(jqRound(dur * 0.75 * 1000) / 1000.0) else opts.at
    val ok = at match
      case Number(_*) => at.toDouble >= 0 && at.toDouble < dur
      case _          => false
    if !ok then fail(s"--at must be from 0 to ${Json.num(dur)} seconds")
    val out = if o.isEmpty then p.dir.storyboard / s"$id.png" else os.Path(o, os.pwd)
    render(tk, p, id, out, 0, dur, dur, p.isLast(id), at)
    say(s"still $id at $at s: ${if o.isEmpty then out.toString else o}")
    0
