package piabrota.hermes

import piabrota.lib.{die, env, warn}
import Proc.{SIGCHLD, SIGINT, SIGQUIT, SIGTERM, SIGUSR1}
import scala.annotation.tailrec

/** `gateway-wrapper COMMAND [ARGUMENT...]`: the main process of the unit hermes-agent (hermes.nix).
  * COMMAND is the gateway, for example `hermes gateway run --external-supervisor`.
  *
  *   - It passes SIGUSR1 (a reload) and SIGTERM or SIGINT (a stop) to the gateway.
  *   - The gateway exits 75 after a reload. The wrapper starts it again at once and stays up, so
  *     the unit never leaves "active" and `RestartSec` is not part of a reload. More than
  *     GATEWAY_WRAPPER_MAX_RELOADS exits of 75 in GATEWAY_WRAPPER_RELOAD_WINDOW seconds: exit 1,
  *     and systemd then restarts the unit and counts it.
  *   - A gateway that exits 75 or 0 within GATEWAY_WRAPPER_FAST_EXIT_SECS seconds of its start,
  *     while $HERMES_HOME/gateway.pid names another live process, means that another gateway
  *     serves the host. The dashboard's Chat tab starts one when it finds none for a few seconds.
  *     The wrapper checks this before it counts a reload. It does not exit then (Restart=always
  *     would loop and count). It waits for that process to end, and then starts the gateway again.
  *     A real reload runs longer than the limit, so it is not this case.
  *   - Any other exit status is the status of the wrapper.
  */
object GatewayWrapper:
  private val handled = Seq(SIGUSR1, SIGTERM, SIGINT, SIGCHLD)

  def run(args: List[String]): Int =
    if args.isEmpty then die("usage: gateway-wrapper COMMAND [ARGUMENT...]", 2)
    Proc.block(handled*)
    GatewayConfig.read(env) match
      case Right(cfg) => supervise(args, cfg, reloads = Nil)
      case Left(why)  => die(why, 2)

  private def now(): Long = System.currentTimeMillis() / 1000

  /** One call per start of the gateway. `reloads` holds the end times of the recent 75s. */
  @tailrec private def supervise(command: List[String], cfg: GatewayConfig, reloads: List[Long]): Int =
    // A stop that came while no gateway ran ends the wrapper before the next start.
    if stopRequested() then 0
    else
      val child = Proc.spawn(command, ignore = Seq(SIGINT, SIGQUIT)) match
        case Right(pid) => pid
        case Left(why)  => die(s"gateway-wrapper: ${command.head}: $why", 127)
      val started = now()
      val (status, stopping) = waitFor(child)
      val exit = GatewayRun(status, started, now(), stopping)
      val foreign = if !exit.stopping && exit.fastExit(cfg) then otherGateway(cfg.home, child) else None
      Next.after(exit, foreign, reloads, cfg) match
        case Next.WaitFor(other, code) =>
          warn(s"another gateway (pid $other) serves this host (the gateway exited $code): waiting for it to exit")
          if !waitForExit(other, cfg.poll) then 0
          else
            warn(s"the other gateway (pid $other) has exited: starting our own")
            // This start is not a reload: it does not count for the limit.
            supervise(command, cfg, reloads)
        case Next.Restart(recent) =>
          warn(s"gateway exited ${GatewayRun.Reload} (reload): starting it again")
          supervise(command, cfg, recent)
        case Next.GiveUp(count) =>
          warn(s"gateway exited ${GatewayRun.Reload} $count times in ${cfg.reloadWindow} s: giving up")
          1
        case Next.Exit(code) => code

  /** Takes the signals that waited while no gateway ran: true if one was a stop. Every one is
    * taken, so a fold and not `exists`.
    */
  private def stopRequested(): Boolean =
    Iterator.continually(Proc.nextSignal(handled, 0)).takeWhile(_.isDefined).flatten
      .foldLeft(false)((stop, sig) => stop || Request.of(sig).contains(Request.Stop))

  /** Waits for the gateway to exit and passes the signals on to it. Its exit status, and whether a
    * stop came.
    */
  private def waitFor(child: Int): (Int, Boolean) =
    var stopping = false
    var status = Option.empty[Int]
    while status.isEmpty do
      Proc.nextSignal(handled, 1000).flatMap(Request.of) match
        case Some(Request.Reload) => Proc.kill(child, SIGUSR1)
        case Some(Request.Stop)   => stopping = true; Proc.kill(child, SIGTERM)
        case None                 => ()
      status = Proc.exited(child)
    (status.get, stopping)

  /** Polls every `poll` seconds until the process is gone. False if a stop came first. */
  private def waitForExit(pid: Long, poll: Long): Boolean =
    var stopped = false
    while !stopped && running(pid) do
      if Proc.nextSignal(handled, poll * 1000).flatMap(Request.of).contains(Request.Stop) then stopped = true
    !stopped

  private def running(pid: Long): Boolean = os.isDir(os.Path(s"/proc/$pid"))

  /** The pid in gateway.pid when it is another live process than the gateway that just ended. */
  private def otherGateway(home: os.Path, gone: Int): Option[Long] =
    readPid(home / GatewayPid.File).filter(pid => pid != gone && running(pid))

  /** The pid of gateway.pid, or None when the file is missing, is not JSON or has no plain pid. */
  def readPid(file: os.Path): Option[Long] =
    scala.util.Try(os.read(file)).toOption.flatMap(GatewayPid.parse)
