package piabrota.reels

import piabrota.lib.{Exit, env}

/** `reel`, the toolkit of the Reels Fabric (docs/REELS.md): ffmpeg, resvg and jq, nothing else, and
  * no network. The screenplay.json of a project is the one source: every command that makes a
  * picture or a sound refuses to run when the screenplay is not approved, or changed after its
  * approval. The data (profile, styles, jq rules, examples, fonts) is in REELS_SHARE.
  */
object Reel:
  val usage: String =
    """reel: the Reels Fabric toolkit. One screenplay.json a reel, 15 or 30 seconds, 1080x1920.
      |
      |Creative director and producer-editor (no approval needed):
      |  reel new <slug> <15|30> [--example]   a project folder and an empty screenplay
      |  reel lint <slug|file.json>            the rules of the screenplay (and of the shotlist, if there is one)
      |  reel screenplay-view <slug|file>      the screenplay as an A/V script
      |  reel timing-report <slug|file>        the table read: reading speed and hold time of each beat
      |  reel approve <slug> [--by <name>]     write screenplay.approved (SHA-256) when the lint passes
      |
      |Studio seats (refuse when the screenplay is not approved, or changed after approval):
      |  reel shotlist <slug> [--force]        the default direction/shotlist.json, to refine
      |  reel still <slug> <beat> [--at <s>] [-o <file>]   one frame of a beat (default: direction/storyboard/<beat>.png)
      |  reel blender <slug> <beat>            render a 3d shot (Cycles, CPU) from blender/<beat>.py to frames/<beat>/
      |  reel scene <slug> <beat>              render the clip of one beat to build/scenes/
      |  reel music <slug>                     the procedural music bed to build/audio/music.wav
      |  reel mix <slug>                       music and sfx, loudness normalised, to build/audio/mix.wav
      |  reel render <slug>                    scenes, audio, assembly: out/<slug>/reel.mp4
      |  reel qa <slug>                        facts, loudness, frames, safe area: out/<slug>/qa.json and qa/
      |  reel contact-sheet <slug>             out/<slug>/qa/contact-sheet.png
      |  reel publish <slug> [--replace]       copy reel.mp4 and review/ to the outbox (needs a passing QA)
      |
      |Folders: REELS_HOME (projects/<slug>/, out/<slug>/), REELS_OUTBOX. See docs/REELS.md.""".stripMargin

  /** What each command runs. */
  private def run(cmd: Cmd): (Toolkit, List[String]) => Int = cmd match
    case Cmd.New          => Screenplays.create
    case Cmd.Lint         => Screenplays.lint
    case Cmd.View         => Screenplays.screenplayView
    case Cmd.Timing       => Screenplays.timingReport
    case Cmd.Approve      => Screenplays.approve
    case Cmd.Shotlist     => Screenplays.shotlist
    case Cmd.Still        => Scene.still
    case Cmd.Scene        => Scene.scene
    case Cmd.Music        => Audio.music
    case Cmd.Blender      => Blender.blender
    case Cmd.Mix          => Audio.mix
    case Cmd.Render       => Render.render
    case Cmd.Qa           => Qa.qa
    case Cmd.ContactSheet => Qa.contactSheet
    case Cmd.Publish      => Qa.publish

  /** The edge: the environment and the profile are read here, once, and passed on. */
  def main(args: List[String]): Int =
    val share = env(EnvVar.Share).getOrElse("")
    if share.isEmpty || !os.isFile(os.Path(share, os.pwd) / Name.Profile) then
      fail(s"cannot find the toolkit data (${EnvVar.Share}=$share)")
    needTools(baseTools)
    val tk = Toolkit.open(Config.read(os.Path(share, os.pwd), env))
    try
      args match
        case Nil =>
          println(usage)
          2
        case ("help" | "-h" | "--help") :: _ =>
          println(usage)
          0
        case name :: rest =>
          Cmd.parse(name) match
            case Some(cmd) =>
              needTools(cmd.tools)
              run(cmd)(tk, rest)
            case None =>
              System.err.println(usage)
              fail(s"unknown command: $name")
    catch
      case e: Exit => throw e
      case e: (java.io.IOException | os.SubprocessException) => fail(e.getMessage)
    finally Toolkit.close(tk)
