package piabrota.reels

import piabrota.lib.Sh

/** `reel blender`, the 3D shots. One shot is one Blender Python scene, <project>/blender/<beat>.py,
  * rendered headless to the PNG sequence <project>/frames/<beat>/%04d.png. The engine is Cycles on
  * the CPU, always: EEVEE needs a GPU and a display, and it crashes on this box. The scene file is
  * loaded first, and then a driver of the toolkit sets the engine, the device, the samples, no
  * denoising, the size and the output, so a scene file cannot choose another engine.
  * docs/REELS.md ("3D shots with Blender").
  */
object Blender:
  /** The driver, run by Blender's own Python after the scene file: Blender runs no other language.
    * Options come after "--" as name/value pairs. probe prints the frame range and stops; render
    * sets the contract and renders the animation.
    */
  val driver: String =
    """import sys
      |
      |import bpy
      |
      |argv = sys.argv[sys.argv.index("--") + 1:]
      |opt = {argv[i]: argv[i + 1] for i in range(0, len(argv) - 1, 2)}
      |scene = bpy.context.scene
      |
      |if opt["--reel-mode"] == "probe":
      |    print("REEL_FRAMES %d %d" % (scene.frame_start, scene.frame_end))
      |    sys.exit(0)
      |
      |scene.render.engine = opt["--reel-engine"]
      |scene.cycles.device = opt["--reel-device"]
      |scene.cycles.samples = int(opt["--reel-samples"])
      |# The denoiser (OpenImageDenoise) took 1.6 GiB more at 1080x1920 (2174 MiB against 536 MiB in one
      |# frame, measured), and the unit has 2 GiB for every seat. A scene cannot turn it on.
      |scene.cycles.use_denoising = False
      |scene.render.resolution_x = int(opt["--reel-width"])
      |scene.render.resolution_y = int(opt["--reel-height"])
      |scene.render.resolution_percentage = 100
      |scene.render.fps = int(opt["--reel-fps"])
      |scene.render.fps_base = 1.0
      |scene.render.image_settings.file_format = "PNG"
      |scene.render.image_settings.color_mode = "RGB"
      |scene.render.use_file_extension = True
      |scene.render.filepath = opt["--reel-out"]
      |bpy.ops.render.render(animation=True)
      |""".stripMargin

  /** One Blender run, in a home of its own inside the project, never the real one. Low priority,
    * with the time limit. Its output goes to `log`; returns the exit code.
    */
  private def run(tk: Toolkit, p: Project, blender: String, mode: BlenderMode, scene: os.Path, log: os.Path,
      out: String = BlenderMode.NoOutput): Int =
    val home = p.dir.blenderHome
    try Seq("config", "cache").foreach(d => os.makeDir.all(home / d))
    catch case _: java.io.IOException => fail(s"cannot make $home")
    val script = tk.tmp / "reel_blender.py"
    os.write.over(script, driver)
    val seconds = tk.p("limits", "blender_timeout_s")
    val cmd = limited(seconds, Seq(blender, "-b", "--factory-startup", "--threads", tk.p("blender", "threads"),
      "--python-exit-code", "1", "--python", scene.toString, "--python", script.toString, "--",
      "--reel-mode", mode.key, "--reel-engine", "CYCLES", "--reel-device", "CPU", "--reel-samples", tk.p("blender", "samples"),
      "--reel-width", tk.W.toString, "--reel-height", tk.H.toString, "--reel-fps", tk.p("blender", "fps"), "--reel-out", out))
    val homeEnv = Map(EnvVar.UserHome -> home.toString, EnvVar.XdgConfig -> (home / "config").toString,
      EnvVar.XdgCache -> (home / "cache").toString)
    val code = tk.timed(cmd, homeEnv, stdout = os.PathRedirect(log), mergeErr = true)
    if code == 124 then note(s"blender stopped: no result after $seconds s")
    code

  private def tail(log: os.Path): Unit =
    if os.exists(log) then os.read.lines(log).takeRight(15).foreach(System.err.println)

  def blender(tk: Toolkit, args: List[String]): Int =
    if args.length != 2 then fail("usage: reel blender <slug> <shot id> (the shot id is the beat id)")
    val List(slug, id) = args: @unchecked
    val p = Gate.load(tk, slug)
    Gate.requireShotlist(tk, p)
    if !id.matches("b[0-9][0-9]") then fail(s"the shot id is a beat id, like b03: $id")
    val shot = Gate.shotOf(tk, p, id)
    if !shot.listed then fail(s"no shot $id in the shotlist")
    if shot.kind != ShotKind.ThreeD then
      fail(s"shot $id is not of kind 3d: the creative director marks it in direction/shotlist.json")
    val blender = tk.cfg.blender.orElse(Sh.which(Tool.Blender.bin).map(_.toString))
      .filter(b => java.io.File(b).canExecute)
      .getOrElse(fail("blender is not in the PATH: it is off on this host (piabrota.openrig.reels.blender.enable, docs/REELS.md)"))
    val scene = p.dir.blenderScene(id)
    if !plainFile(scene) then fail(s"no scene file (or a link): the artist-3d writes $scene")
    val max = tk.pInt("blender", "max_frames")

    // The frame range first, so that a scene which is too long is refused before it costs minutes.
    val probeLog = tk.tmp / "blender-probe.log"
    val probe = run(tk, p, blender, BlenderMode.Probe, scene, probeLog)
    if probe != 0 then
      tail(probeLog)
      fail(s"shot $id: the scene file failed (blender exit code $probe)")
    val (f0, f1) = """REEL_FRAMES (-?[0-9]+) (-?[0-9]+)""".r.findFirstMatchIn(os.read(probeLog))
      .map(m => (m.group(1).toLong, m.group(2).toLong))
      .getOrElse(fail(s"shot $id: the scene file did not give a frame range"))
    val n = f1 - f0 + 1
    if n < 1 then fail(s"shot $id: frame_end ($f1) is before frame_start ($f0)")
    if n > max then
      fail(s"shot $id needs $n frames: the budget is $max (blender.max_frames in profile.json, ${tk.p("blender", "fps")} fps). Shorten the scene")

    val dir = p.dir.frames(id)
    val part = Name.part(dir)
    os.remove.all(part)
    try os.makeDir.all(part)
    catch case _: java.io.IOException => fail(s"cannot make $part")
    note(s"shot $id: $n frames, Cycles on the CPU, ${tk.p("blender", "samples")} samples, ${tk.W}x${tk.H}")
    val renderLog = tk.tmp / "blender-render.log"
    val code = run(tk, p, blender, BlenderMode.Render, scene, renderLog, s"$part/####")
    if code != 0 then
      tail(renderLog)
      os.remove.all(part)
      fail(s"shot $id: blender failed (exit code $code)")
    val got = glob(part, "", ".png").count(os.isFile(_))
    if got != n then
      tail(renderLog)
      os.remove.all(part)
      fail(s"shot $id: blender wrote $got frames, not $n")
    os.remove.all(dir)
    try os.move(part, dir)
    catch case _: java.io.IOException => fail(s"cannot move the frames into place: $dir")
    val last = os.read.lines(tk.times).lastOption.getOrElse("0 0").split(' ')
    say(s"blender $id: $dir ($n frames, ${last(0)} s wall, ${last.lift(1).flatMap(_.toLongOption).getOrElse(0L) / 1024} MiB peak)")
    0
