package piabrota.hermes

import piabrota.lib.{Sh, die, env}
import SmokeScene.{LogLines, Video}

/** `manim-smoke [scene.py]`: renders the hermes-manim skill's smoke scene (a title, an equation
  * and a circle) to a temporary folder and checks the video. Prints the path and size of Smoke.mp4
  * and `ok`. Exit 1: the render failed. Exit 2: no manim. No network, no secret. The scene is
  * MANIM_SMOKE_SCENE (hermes.nix sets it to the skill's scripts/smoke.py) unless one is given.
  */
object ManimSmoke:
  def run(args: List[String]): Int =
    val cfg = ManimConfig.read(env)
    val scene = args match
      case Nil         => cfg.defaultScene.getOrElse(die("manim-smoke: no scene: give one, or set MANIM_SMOKE_SCENE", 2))
      case List(scene) => scene
      case _           => die("usage: manim-smoke [scene.py]", 2)
    if Sh.which("manim").isEmpty then
      println("manim: not found on PATH")
      return 2

    val dir = os.temp.dir(os.Path(cfg.tmpDir), prefix = "hermes-manim.", deleteOnExit = false)
    try render(os.Path(scene, os.pwd), dir)
    finally os.remove.all(dir)

  private def render(scene: os.Path, dir: os.Path): Int =
    val log = dir / "out.log"
    val media = dir / "media"
    val manim = os.proc("manim", "-ql", "--disable_caching", "--media_dir", media, scene, SmokeScene.Scene)
      .call(stdout = log, mergeErrIntoOut = true, check = false)
    if manim.exitCode != 0 then
      print(Util.tailFile(os.read(log), LogLines))
      return 1
    val mp4 = (if os.isDir(media) then os.walk(media) else Nil).find(_.last == Video)
    mp4.filter(p => os.isFile(p) && os.size(p) > 0) match
      case Some(p) =>
        println(s"$p ${os.size(p)} bytes")
        println("ok")
        0
      case None =>
        println(s"$Video is missing or empty")
        print(Util.tailFile(os.read(log), LogLines))
        1
