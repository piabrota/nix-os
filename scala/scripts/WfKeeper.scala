package piabrota.scripts

import piabrota.lib.{Sh, die, env}
import Keeper.{rigName, spec}

/** `piabrota openrig-wf-keeper` (openrig.nix, the unit openrig-wf-keeper): keeps the port rig
  * wave-forecaster-dev up. Every `rig` call goes to the daemon at OPENRIG_URL (the `rig` wrapper
  * sets it). It never starts a daemon, sends no task and answers no prompt. The rig's output is not
  * printed: it is not needed, and `rig ps --full` shows tokens. The only state is
  * $STATE_DIRECTORY/attempts: the epoch second of each start, one per line, at most
  * `Keeper.maxAttempts` an hour. A line starting with <3> or <4> is logged by journald as an error
  * or a warning.
  */
object WfKeeper:
  private def rigJson(args: String*): Option[List[ujson.Value]] = Sh.outOpt("rig" +: args).flatMap(RigList.parse)

  private def nodes(): Option[List[RigNode]] =
    rigJson("ps", "--nodes", "--rig", rigName, "--json").map(_.map(RigNode.parse))

  private def done(message: String): Int = { println(message); 0 }

  def run(@annotation.unused args: List[String]): Int =
    val config = KeeperConfig(
      os.Path(env("STATE_DIRECTORY").getOrElse(die("STATE_DIRECTORY is not set", 1)), os.pwd) / "attempts",
      java.time.Instant.now().getEpochSecond)
    val (code, status) = Util.merged("rig", "status")
    if code != 0 then done("rig status failed, the daemon does not answer: nothing done")
    else if !status.contains("Daemon running") then done("daemon not running: nothing done")
    else rigJson("ps", "--json") match
      case None       => done(Priority.Warning("rig ps failed: nothing done"))
      case Some(rigs) => act(Keeper.decide(rigs.map(Rig.parse).filterNot(_.archived)), config)

  private def act(next: KeeperStep, config: KeeperConfig): Int = next match
    case KeeperStep.Say(line) => done(line)
    case KeeperStep.Start(status) => start(status, config)
    case KeeperStep.Nodes(status) =>
      nodes() match
        case Some(seats) => act(Keeper.withNodes(status, seats), config)
        case None if status == RigStatus.Partial =>
          done(Priority.Warning(s"$rigName is partial and rig ps --nodes failed: nothing done"))
        case None => done(Priority.Warning("rig ps --nodes failed: nothing done"))

  /** Back-off: keep the attempts of the last hour, and stop at maxAttempts of them. */
  private def start(status: RigStatus, config: KeeperConfig): Int =
    val state = status.render
    val kept = Keeper.recent(if os.isFile(config.attempts) then os.read.lines(config.attempts).toList else Nil, config.now)
    if kept.size >= Keeper.maxAttempts then
      println(Priority.Error(s"$rigName is $state and ${kept.size} start attempts failed or ended in the last hour: not trying. Read: journalctl -u openrig; rig ps --nodes --rig $rigName"))
      1
    else
      os.write.over(config.attempts, (kept :+ config.now.toString).map(_ + "\n").mkString)
      println(s"$rigName is $state: starting it")
      if status == RigStatus.Stopped && Sh.ok("rig", "up", rigName, "--existing") then
        done(s"$rigName restored from its snapshot (--existing)")
      else
        val code = Sh.call("rig", "up", spec).exitCode
        if code == 0 then done(s"$rigName started from $spec")
        else
          println(Priority.Error(s"$rigName did not start: rig up exited with $code. Read: rig up $rigName --existing"))
          1
