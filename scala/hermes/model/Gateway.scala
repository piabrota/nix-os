package piabrota.hermes

import Proc.{SIGINT, SIGTERM, SIGUSR1}

/** What gateway-wrapper reads from the environment, once, at its start. Seconds, except
  * `maxReloads`.
  */
final case class GatewayConfig(home: os.Path, fastExit: Long, poll: Long, maxReloads: Int, reloadWindow: Long)

object GatewayConfig:
  /** The config, or the message for a variable that is not a number. */
  def read(env: String => Option[String]): Either[String, GatewayConfig] =
    def number(name: String, default: Long): Either[String, Long] =
      env(name) match
        case None    => Right(default)
        case Some(v) => v.toLongOption.toRight(s"gateway-wrapper: $name is not a number: $v")
    for
      fastExit <- number("GATEWAY_WRAPPER_FAST_EXIT_SECS", 20)
      poll <- number("GATEWAY_WRAPPER_POLL_SECS", 5)
      maxReloads <- number("GATEWAY_WRAPPER_MAX_RELOADS", 5)
      reloadWindow <- number("GATEWAY_WRAPPER_RELOAD_WINDOW", 60)
    yield GatewayConfig(
      home = os.Path(env("HERMES_HOME").getOrElse("/var/lib/hermes/.hermes"), os.pwd),
      fastExit = fastExit, poll = poll, maxReloads = maxReloads.toInt, reloadWindow = reloadWindow)

/** What a signal to the wrapper asks for. */
enum Request:
  case Reload
  case Stop

object Request:
  def of(sig: Int): Option[Request] =
    if sig == SIGUSR1 then Some(Reload)
    else if sig == SIGTERM || sig == SIGINT then Some(Stop)
    else None

/** One run of the gateway: its exit status, when it started and ended (seconds), and whether a
  * stop came while it ran.
  */
final case class GatewayRun(status: Int, started: Long, ended: Long, stopping: Boolean):
  /** It exited 75 or 0 at once: another gateway may serve the host (Hermes uses 75 now). */
  def fastExit(cfg: GatewayConfig): Boolean =
    (status == 0 || status == GatewayRun.Reload) && ended - started < cfg.fastExit

object GatewayRun:
  /** The exit status of a gateway after a reload. */
  val Reload = 75

/** What the wrapper does after the gateway has exited. */
enum Next:
  /** Another gateway (this pid) serves the host: wait for it to end, then start again. */
  case WaitFor(other: Long, status: Int)
  /** A reload: start again at once, with these end times of the recent reloads. */
  case Restart(reloads: List[Long])
  /** Too many reloads in the window. */
  case GiveUp(count: Int)
  case Exit(code: Int)

object Next:
  /** The decision after a run. `foreign` is the other live gateway of gateway.pid, if a fast exit
    * made the wrapper look; `reloads` holds the end times of the recent reloads.
    */
  def after(run: GatewayRun, foreign: Option[Long], reloads: List[Long], cfg: GatewayConfig): Next =
    if run.stopping then Exit(if run.status == GatewayRun.Reload then 0 else run.status)
    // This test comes before the reload branch: a real reload exits 75 after a long run, and a
    // foreign gateway makes the new one exit at once.
    else foreign match
      case Some(other) => WaitFor(other, run.status)
      case None if run.status == GatewayRun.Reload =>
        val recent = reloads.filter(t => run.ended - t < cfg.reloadWindow) :+ run.ended
        if recent.length > cfg.maxReloads then GiveUp(recent.length) else Restart(recent)
      case None => Exit(run.status)

/** gateway.pid of $HERMES_HOME: JSON with the pid of the gateway that serves the host. */
object GatewayPid:
  val File = "gateway.pid"

  /** The pid, or None when the text is not JSON or has no plain pid. */
  def parse(text: String): Option[Long] =
    scala.util.Try(ujson.read(text)).toOption.flatMap(_.objOpt).flatMap(_.get("pid")).flatMap {
      case ujson.Num(n) if n == n.floor && n > 0 => Some(n.toLong)
      case ujson.Str(s) if s.nonEmpty && s.forall(_.isDigit) => s.toLongOption
      case _ => None
    }
