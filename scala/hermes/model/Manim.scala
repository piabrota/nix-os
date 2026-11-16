package piabrota.hermes

/** What manim-smoke reads from the environment, once: the default scene (MANIM_SMOKE_SCENE) and
  * the folder for temporary files.
  */
final case class ManimConfig(defaultScene: Option[String], tmpDir: String)

object ManimConfig:
  def read(env: String => Option[String]): ManimConfig =
    ManimConfig(env("MANIM_SMOKE_SCENE"), env("TMPDIR").getOrElse("/tmp"))

/** The smoke scene of the hermes-manim skill and the video it renders. */
object SmokeScene:
  val Scene = "Smoke"
  val Video = s"$Scene.mp4"
  /** The lines of the render's log shown when it fails. */
  val LogLines = 20
