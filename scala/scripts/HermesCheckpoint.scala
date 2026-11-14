package piabrota.scripts

import piabrota.lib.{Sh, env}

/** `piabrota hermes-checkpoint NEW_UNIT_SHA256`: run as root on a host by deploy.yml, before the
  * switch. NEW_UNIT_SHA256 is the sha256 of hermes-agent.service in the system about to be
  * activated. When it differs from the unit that runs now, the switch reloads or restarts Hermes,
  * and a restart (a new package changes ExecStart) stops the gateway with SIGTERM and can cut a turn
  * in flight. So this asks Hermes for its own graceful restart first: SIGUSR1 (`systemctl reload`).
  * The gateway takes no new work, lets the turns, cron jobs and subagents in flight finish (at most
  * restart_after_turn_timeout, 600 s, hermes.nix), closes state.db and writes its planned-restart
  * marker; hermes/scripts/gateway-wrapper.sh starts it again. This waits for that new gateway, so
  * the switch that follows finds no work in flight.
  *
  * It never fails the deploy: every case it cannot handle prints a line and exits 0.
  * Test seams: HERMES_HOME, HC_UNIT (the unit file), HC_TIMEOUT and HC_POLL (seconds).
  */
object HermesCheckpoint:
  private val unit = Units.hermesAgent

  def run(args: List[String]): Int =
    val config = CheckpointConfig(
      home = os.Path(env("HERMES_HOME").getOrElse(CheckpointConfig.hermesHome), os.pwd),
      unitFile = os.Path(env("HC_UNIT").getOrElse(s"/etc/systemd/system/$unit"), os.pwd),
      timeout = env("HC_TIMEOUT").flatMap(_.toIntOption).getOrElse(660),
      poll = env("HC_POLL").flatMap(_.toIntOption).getOrElse(5))

    args.headOption.getOrElse("") match
      case n if !isSha256(n) =>
        System.err.println("usage: piabrota hermes-checkpoint NEW_UNIT_SHA256")
        2
      case _ if !os.exists(config.unitFile) =>
        println(s"no $unit on this host: nothing to prepare")
        0
      case n if piabrota.lib.Sha256.file(config.unitFile) == n =>
        println(s"$unit does not change in this deploy: Hermes stays up")
        0
      case _ if !Sh.ok("systemctl", "is-active", "--quiet", unit) =>
        println(s"$unit changes, but it is not active: nothing in flight")
        0
      case _ =>
        readPid(config.pidFile).filter(alive) match
          case None =>
            println(s"$unit changes, but no gateway runs: nothing in flight")
            0
          case Some(before) =>
            println(s"$unit changes in this deploy: asking the gateway (pid $before) to finish its work and restart")
            if Sh.run("systemctl", "reload", unit) != 0 then
              println(s"::warning::systemctl reload $unit failed; the switch goes on without a checkpoint")
            else checkpoint(config, before)
            0

  /** Lowercase hex, as sha256sum prints it. */
  def isSha256(n: String): Boolean = n.nonEmpty && n.forall(c => c.isDigit || ('a' to 'f').contains(c))

  private def checkpoint(config: CheckpointConfig, before: Long): Unit =
    val poll = config.poll
    val back = Iterator.from(1).map(_ * poll).takeWhile(_ - poll < config.timeout).flatMap { waited =>
      Thread.sleep(poll * 1000L)
      readPid(config.pidFile).filter(now => now != before && alive(now)).map(waited -> _)
    }.nextOption()
    back match
      case Some((waited, now)) =>
        println(s"checkpoint done after $waited s: the gateway (pid $now) is back, with no work in flight")
      case None =>
        println(s"::warning::the gateway did not restart within ${config.timeout} s; the switch goes on and may cut a turn")

  def readPid(file: os.Path): Option[Long] =
    if !os.isFile(file) then None else CheckpointConfig.pid(os.read(file))

  private def alive(pid: Long): Boolean = os.isDir(os.Path(s"/proc/$pid"))
