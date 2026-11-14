package piabrota.scripts

import piabrota.lib.{Sh, die, env}

/** `piabrota restart-services [GROUP] [--yes] [--dry-run]`: restarts the services of a piabrota box
  * by hand. For the OWNER only: an agent never runs it (docs/DEPLOY.md, "Restarting the services by
  * hand"). Run as root on the box (`just remote-restart`).
  *
  * GROUP: all (the default), metrics, web, pgx, room, loco, rig, hermes, or `list` (print the plan
  * and change nothing). --dry-run prints the plan and the exact commands and changes nothing; --yes
  * does not ask `Proceed? [y/N]`. A group acts only on the units the box has (`systemctl cat`), so
  * one command serves both hosts; a group the box lacks gives one `skip` line, not an error.
  *
  * `RestartAllow` is the allow list: no unit it does not name is ever touched, so sshd, the network,
  * systemd-*, acme-*, nix-daemon, deploy, qemu-guest-agent and cloud-init are never restarted.
  * `all` runs the groups in the order of `ServiceGroup`; hermes-agent, which holds the agent's own
  * session, is last, so a failure on the way is reported while the owner's session still lives.
  *
  * The prompt reads RESTART_TTY (default /dev/tty), never stdin. It prints no environment and no
  * journal line (a line can hold a secret): it prints the journalctl command instead.
  * Exit 0: every unit is as wanted. 1: a unit is not, or a stray gateway runs. 2: usage, no root for
  * a real run, or the prompt was refused or has no terminal.
  * For tests only: RESTART_PROC (default /proc), RESTART_TMUX_DIR (default /run/openrig),
  * RESTART_WAIT_STEP (2 s) and RESTART_WAIT_TRIES (30: 60 s) of the hermes wait.
  */
object RestartServices:
  private val usage =
    s"usage: piabrota restart-services [all|list|${ServiceGroup.values.map(_.render).mkString("|")}] [--yes] [--dry-run]"
  private val agent = Units.hermesAgent
  private val backend = Units.hermesBackend

  def run(args: List[String]): Int =
    RestartArgs.parse(args) match
      case Left(error) =>
        error.lines(usage).foreach(System.err.println)
        error.code
      case Right(chosen) =>
        val config = RestartConfig(
          proc = os.Path(env("RESTART_PROC").getOrElse("/proc"), os.pwd),
          tty = os.Path(env("RESTART_TTY").getOrElse("/dev/tty"), os.pwd),
          tmuxDir = os.Path(env("RESTART_TMUX_DIR").getOrElse("/run/openrig"), os.pwd),
          waitStep = env("RESTART_WAIT_STEP").flatMap(_.toIntOption).getOrElse(2),
          waitTries = env("RESTART_WAIT_TRIES").flatMap(_.toIntOption).getOrElse(30))
        restart(chosen, config)

  private def restart(chosen: RestartArgs, config: RestartConfig): Int =
    val planned = chosen.selection.groups.map(g => g -> group(g, config.tmuxDir))
    planned.foreach((g, p) => if p.steps.isEmpty then println(s"skip: ${g.render}: not on this box"))
    val plan = planned.flatMap(_._2.steps)
    val seatNote = planned.flatMap(_._2.note).lastOption

    println("\nplan:")
    plan.foreach(s => println(f"  ${s.verb.render}%-8s ${s.unit}%-26s ${s.why}"))
    seatNote.foreach(n => println(s"  note: $n"))
    if plan.isEmpty then { println("nothing to do on this box"); 0 }
    else if chosen.selection == Selection.Listing then 0
    else if chosen.dry then
      println("\ncommands (dry run, nothing changed):")
      plan.foreach { s =>
        println(s"  systemctl ${s.verb.render} ${s.unit}")
        if s.unit == agent then println(s"  (wait up to ${config.waitSeconds} s until $agent is active, then go on)")
      }
      0
    else if !Util.isRoot() then
      System.err.println("restart-services: run it as root (sudo)")
      2
    else if !chosen.yes && !canRead(config.tty) then
      System.err.println("restart-services: no terminal to ask on and no --yes: refusing")
      2
    else if !chosen.yes && !confirmed(config.tty) then
      println("aborted: nothing restarted")
      2
    else apply(plan, config)

  private def group(name: ServiceGroup, tmuxDir: os.Path): RestartGroup =
    def add(verb: Verb, unit: String, want: Want, why: String): Option[RestartStep] =
      if !RestartAllow.allowed(unit) then die(s"internal error: $unit is not on the allow list", 2)
      Option.when(Sh.ok("systemctl", "cat", unit))(RestartStep(verb, unit, want, why))
    val fresh = "none: runs once now, the page gets fresh data"
    name match
      // No metrics daemon: two timers fire oneshot services. Restart the timers, then run each oneshot once.
      case ServiceGroup.Metrics =>
        RestartGroup(List(
          add(Verb.Restart, "metrics-collect.timer", Want.Active, "none"),
          add(Verb.Restart, "metrics-pull.timer", Want.Active, "none"),
          add(Verb.Start, "metrics-collect.service", Want.Oneshot, fresh),
          add(Verb.Start, "metrics-pull.service", Want.Oneshot, fresh),
        ).flatten)
      // nginx.service has ExecReload = `nginx -t` then `kill -HUP` on NixOS, so a reload tests the
      // config first and keeps the old workers when the test fails: no second test here.
      case ServiceGroup.Web =>
        RestartGroup(add(Verb.Reload, "nginx.service", Want.Active, "no connection dropped; the unit tests the config first").toList)
      case ServiceGroup.Pgx =>
        RestartGroup(add(Verb.Restart, "pgx.service", Want.Active, "drops the open database connections").toList)
      case ServiceGroup.Room =>
        RestartGroup(add(Verb.Restart, "room-listeners.service", Want.Active, "the live listeners count restarts from zero").toList)
      case ServiceGroup.Loco =>
        val listed = Sh.outOpt("systemctl", "list-units", "loco-*.service", "--all", "--no-legend", "--plain").getOrElse("")
        val units = listed.linesIterator.flatMap(_.trim.split("\\s+").headOption).filter(_.nonEmpty).toList
        RestartGroup(units.filter(RestartAllow.allowed).flatMap(u => add(Verb.Restart, u, Want.Active, "the app is down for a few seconds")))
      case ServiceGroup.Rig =>
        val steps = add(Verb.Restart, Units.openrig, Want.Active, "ends every live seat").toList
        val seats = if steps.isEmpty then 0 else liveSeats(tmuxDir)
        RestartGroup(steps, Option.when(seats > 0)(s"$seats live tmux session(s) of OpenRig: they end with this restart"))
      // hermes-agent first, hermes-backend only after the agent is active: a dashboard that starts
      // while no gateway runs can start a second gateway of its own (the loop of 2026-11-05).
      case ServiceGroup.Hermes =>
        RestartGroup(List(
          add(Verb.Restart, agent, Want.Active, "ends running agent tasks, a coding run the agent started included"),
          add(Verb.Restart, backend, Want.Active, "closes the dashboard for a few seconds"),
        ).flatten)

  /** The tmux sessions of OpenRig (one per seat), read-only; rig is not called (it can start a daemon). */
  private def liveSeats(tmuxDir: os.Path): Int =
    if !os.isDir(tmuxDir) then 0
    else
      os.list(tmuxDir).filter(_.last.startsWith("tmux-")).map(_ / "default").filter(os.exists).map { sock =>
        Sh.outOpt("tmux", "-S", sock, "list-sessions").map(_.linesIterator.size).getOrElse(0)
      }.sum

  private def canRead(tty: os.Path): Boolean =
    scala.util.Using(java.io.FileInputStream(tty.toIO))(_ => ()).isSuccess

  private def confirmed(tty: os.Path): Boolean =
    print("\nProceed? [y/N] ")
    System.out.flush()
    val answer = scala.util.Using(scala.io.Source.fromFile(tty.toIO))(_.getLines().nextOption()).toOption.flatten
    Set("y", "Y", "yes", "YES", "Yes").contains(answer.getOrElse("").trim)

  private def isActive(unit: String): String =
    Sh.call("systemctl", "is-active", unit).out.text().stripTrailing()

  private def apply(plan: List[RestartStep], config: RestartConfig): Int =
    println()
    // The steps done, and whether hermes-agent came back (else hermes-backend stays as it is).
    val (touched, agentDown) = plan.foldLeft((Vector.empty[RestartStep], false)) { case ((done, down), s) =>
      if s.unit == backend && down then
        println(s"skip: ${s.unit}: $agent is not active")
        (done :+ s, down)
      else
        println(s"${s.verb.render} ${s.unit}")
        System.out.flush()
        val code = os.proc("systemctl", s.verb.render, s.unit).call(stdin = "", stdout = os.Inherit,
          stderr = os.Inherit, check = false).exitCode
        if code != 0 then println(s"systemctl ${s.verb.render} ${s.unit} failed")
        val stillDown =
          if s.unit != agent then down
          else if waitActive(s.unit, config) then { println(s"$agent is active"); false }
          else
            println(s"$agent is not active after ${config.waitSeconds} s: $backend stays as it is")
            true
        (done :+ s, stillDown)
    }

    val gatewayOk = !plan.exists(_.unit == agent) || agentDown || gatewayCheck(config.proc)

    println(f"\n${"unit"}%-28s ${"active"}%-10s ${"NRestarts"}%-9s ActiveEnterTimestamp")
    val bad = touched.filter { s =>
      val state = isActive(s.unit)
      def show(prop: String) = Sh.outOpt("systemctl", "show", "-p", prop, "--value", s.unit).filter(_.nonEmpty)
      val shown = if state.isEmpty then "unknown" else state
      println(f"${s.unit}%-28s $shown%-10s ${show("NRestarts").getOrElse("-")}%-9s ${show("ActiveEnterTimestamp").getOrElse("-")}")
      !s.want.met(state)
    }
    bad.foreach(s => println(s"FAIL ${s.unit} is not as wanted: read: journalctl -u ${s.unit} -n 50"))
    if bad.isEmpty && gatewayOk then { println("\nrestart-services: every unit is as wanted"); 0 }
    else 1

  /** `active` within the wait of the config. */
  private def waitActive(unit: String, config: RestartConfig): Boolean =
    (0 until config.waitTries).exists { _ =>
      isActive(unit) == UnitState.active || { Thread.sleep(config.waitStep * 1000L); false }
    } || isActive(unit) == UnitState.active

  /** The processes of /proc, with their argv and cgroup ("" when unreadable). */
  def processes(proc: os.Path): List[Proc] =
    def read(p: os.Path) = scala.util.Try(os.read(p)).getOrElse("")
    (if os.isDir(proc) then os.list(proc).toList else Nil).filter(d => d.last.headOption.exists(_.isDigit)).map { d =>
      Proc(d.last, read(d / "cmdline").replace('\u0000', '\n').split('\n').toList, read(d / "cgroup"))
    }

  /** Gateways are found in /proc by argv, not by `pgrep -f`: pgrep would also match the command lines
    * of sudo and ssh that hold this command. The unit's wrapper has the same argv as the gateway, so
    * every match must sit in the cgroup of hermes-agent.service.
    */
  def gatewayCheck(proc: os.Path): Boolean =
    val gateways = processes(proc).filter(_.isGateway)
    val stray = gateways.filterNot(_.inUnit(agent))
    stray.foreach { p =>
      println(s"WARN stray gateway pid ${p.pid} in ${p.cgroupPath.getOrElse("unknown cgroup")}: run: sudo systemctl restart hermes-backend")
    }
    if gateways.isEmpty then
      println("WARN no gateway process found: read: journalctl -u hermes-agent -n 50")
      false
    else if stray.nonEmpty then false
    else
      println(s"ok    gateway: ${gateways.size} process(es) (the wrapper and the gateway), all in $agent")
      true
