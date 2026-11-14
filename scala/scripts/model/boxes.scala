package piabrota.scripts

// What runs on a box: its units and their restarts, Hermes's gateway, the OpenRig rig keeper and
// the system's packages.

/** What `systemctl is-active` prints. */
object UnitState:
  val active = "active"
  val inactive = "inactive"

/** A systemctl verb of a restart plan. */
enum Verb:
  case Restart, Reload, Start

  def render: String = toString.toLowerCase

/** The state a unit must reach: active, or (a oneshot service) active or inactive, not failed. */
enum Want:
  case Active, Oneshot

  def met(state: String): Boolean = state == UnitState.active || (this == Oneshot && state == UnitState.inactive)

/** One step of a restart plan. */
final case class RestartStep(verb: Verb, unit: String, want: Want, why: String)

/** The steps of one group that this box has, and a note for the owner. */
final case class RestartGroup(steps: List[RestartStep], note: Option[String] = None)

/** The unit groups of restart-services, in the order `all` runs them: hermes-agent, which holds the
  * agent's own session, is last.
  */
enum ServiceGroup:
  case Metrics, Web, Pgx, Room, Loco, Rig, Hermes

  def render: String = toString.toLowerCase

object ServiceGroup:
  def parse(s: String): Option[ServiceGroup] = values.find(_.render == s)

/** What restart-services acts on. */
enum Selection:
  case All, Listing
  case One(group: ServiceGroup)

  def render: String = this match
    case All        => "all"
    case Listing    => "list"
    case One(group) => group.render

  def groups: List[ServiceGroup] = this match
    case One(group) => List(group)
    case _          => ServiceGroup.values.toList

object Selection:
  def parse(s: String): Option[Selection] = s match
    case "all"  => Some(All)
    case "list" => Some(Listing)
    case other  => ServiceGroup.parse(other).map(One(_))

/** restart-services's arguments. */
final case class RestartArgs(selection: Selection, yes: Boolean, dry: Boolean)

/** An argument restart-services refuses, or `--help`. */
enum RestartArgError:
  case Help
  case TwoGroups(first: String, second: String)
  case Unknown(arg: String)

  def code: Int = if this == Help then 0 else 2

  /** What goes to stderr. */
  def lines(usage: String): List[String] = this match
    case Help                     => List(usage)
    case TwoGroups(first, second) => List(s"restart-services: one group only (got $first and $second)", usage)
    case Unknown(arg)             => List(s"restart-services: unknown group or option: $arg", usage)

object RestartArgs:
  def parse(args: List[String]): Either[RestartArgError, RestartArgs] =
    args.foldLeft[Either[RestartArgError, (Option[Selection], Boolean, Boolean)]](Right((None, false, false))) {
      case (Left(e), _)                         => Left(e)
      case (Right((s, _, d)), "--yes" | "-y")    => Right((s, true, d))
      case (Right((s, y, _)), "--dry-run" | "-n") => Right((s, y, true))
      case (Right(_), "-h" | "--help")          => Left(RestartArgError.Help)
      case (Right((s, y, d)), a) =>
        (s, Selection.parse(a)) match
          case (Some(first), Some(_)) => Left(RestartArgError.TwoGroups(first.render, a))
          case (None, Some(chosen))   => Right((Some(chosen), y, d))
          case (_, None)              => Left(RestartArgError.Unknown(a))
    }.map((s, y, d) => RestartArgs(s.getOrElse(Selection.All), y, d))

/** restart-services's settings: /proc (RESTART_PROC), the prompt's terminal (RESTART_TTY), OpenRig's
  * tmux sockets (RESTART_TMUX_DIR), and the wait for hermes-agent (RESTART_WAIT_STEP seconds,
  * RESTART_WAIT_TRIES times).
  */
final case class RestartConfig(proc: os.Path, tty: os.Path, tmuxDir: os.Path, waitStep: Int, waitTries: Int):
  def waitSeconds: Int = waitTries * waitStep

/** The allow list of restart-services: no unit it does not name is ever touched. */
object RestartAllow:
  private val fixed = Set("metrics-collect.timer", "metrics-pull.timer", "metrics-collect.service",
    "metrics-pull.service", "nginx.service", "pgx.service", "room-listeners.service", Units.openrig,
    Units.hermesAgent, Units.hermesBackend)
  private val locoApp = "loco-[A-Za-z0-9_.-]+\\.service".r
  private val locoBackup = "loco-.*-backup\\.service".r

  /** A fixed name, or a loco app: loco-NAME.service, but not the nightly backup oneshot
    * loco-NAME-backup.service (loco.nix), which a restart would only run again.
    */
  def allowed(unit: String): Boolean = fixed(unit) || (!locoBackup.matches(unit) && locoApp.matches(unit))

/** A process of /proc: its pid, argv and cgroup file. */
final case class Proc(pid: String, argv: List[String], cgroup: String):
  /** Exactly the processes whose argv holds the two words `gateway` and `run` in a row. */
  def isGateway: Boolean = argv.zip(argv.drop(1)).contains(("gateway", "run"))

  def inUnit(unit: String): Boolean =
    val cg = cgroup.stripTrailing()
    cg.endsWith(s"/$unit") || cg.contains(s"/$unit/")

  /** The path of the cgroup's first line (`0::/system.slice/x.service`). */
  def cgroupPath: Option[String] =
    "^[0-9]*:[^:]*:(.*)$".r.findFirstMatchIn(Util.firstLine(cgroup)).map(_.group(1)).filter(_.nonEmpty)

/** hermes-checkpoint's settings: Hermes's home (HERMES_HOME), the unit file now (HC_UNIT), and the
  * wait for the new gateway (HC_TIMEOUT, HC_POLL seconds).
  */
final case class CheckpointConfig(home: os.Path, unitFile: os.Path, timeout: Int, poll: Int):
  def pidFile: os.Path = home / "gateway.pid"

object CheckpointConfig:
  val hermesHome = "/var/lib/hermes/.hermes"

  /** The pid in gateway.pid (JSON, `{"pid": 123, ...}`), the same read as gateway-wrapper.sh. */
  def pid(text: String): Option[Long] =
    """"pid"\s*:\s*([0-9]+)""".r.findFirstMatchIn(text).flatMap(_.group(1).toLongOption)

/** The status of a rig, as `rig ps --json` gives it; Missing when there is no such rig. */
enum RigStatus:
  case Running, Partial, Stopped, Missing
  case Other(raw: String)

  def render: String = this match
    case Other(raw) => raw
    case known      => known.toString.toLowerCase

object RigStatus:
  def parse(raw: Option[String]): RigStatus = raw match
    case None            => Missing
    case Some("running") => Running
    case Some("partial") => Partial
    case Some("stopped") => Stopped
    case Some("missing") => Missing
    case Some(other)     => Other(other)

/** A rig of `rig ps --json`, read with jq's `//`: a missing, null or false value is none. */
final case class Rig(name: Option[String], status: RigStatus, attention: Long, running: Double, archived: Boolean)

object Rig:
  def parse(v: ujson.Value): Rig =
    def number(key: String) = Jq.get(v, key).flatMap(_.numOpt).getOrElse(0.0)
    Rig(Jq.field(v, "name"), RigStatus.parse(Jq.field(v, "status")), number("attentionCount").toLong,
      number("runningCount"), Jq.isTrue(v, "isArchived"))

/** A seat of `rig ps --nodes --json`. */
final case class RigNode(logicalId: String, lifecycle: Option[String], intentionallyStopped: Boolean):
  def running: Boolean = lifecycle.contains("running")
  def render: String = s"$logicalId=${lifecycle.getOrElse("null")}"

object RigNode:
  def parse(v: ujson.Value): RigNode =
    RigNode(Jq.rawField(v, "logicalId"), v.objOpt.flatMap(_.get("lifecycleState")).map(Jq.raw),
      Jq.isTrue(v, "intentionallyStopped"))

/** A rig list or a node list: a bare array, or an envelope with it in `.entries`. */
object RigList:
  def parse(json: String): Option[List[ujson.Value]] =
    Jq.parse(json).flatMap {
      case o: ujson.Obj => o.value.get("entries").flatMap(_.arrOpt).map(_.toList)
      case a: ujson.Arr => Some(a.value.toList)
      case _            => None
    }

/** What openrig-wf-keeper does next. */
enum KeeperStep:
  /** Print the line and exit 0. */
  case Say(line: String)
  /** Ask for the rig's seats, then decide. */
  case Nodes(status: RigStatus)
  case Start(status: RigStatus)

/** openrig-wf-keeper's settings: its attempts file (STATE_DIRECTORY) and the clock. */
final case class KeeperConfig(attempts: os.Path, now: Long)

/** The keeper's rig and its back-off. */
object Keeper:
  val rigName = "wave-forecaster-dev"
  val spec = s"/etc/openrig/specs/rigs/$rigName/rig.yaml"
  val window = 3600L
  val maxAttempts = 3

  /** From the rigs that are not archived. */
  def decide(live: List[Rig]): KeeperStep =
    val ours = live.find(_.name.contains(rigName))
    val status = ours.fold(RigStatus.Missing)(_.status)
    live.find(r => !r.name.contains(rigName) && r.running > 0) match
      case Some(other) => KeeperStep.Say(s"another rig runs: ${other.name.getOrElse("null")}, skipped")
      case None =>
        status match
          case RigStatus.Running =>
            val attention = ours.fold(0L)(_.attention)
            if attention > 0 then
              KeeperStep.Say(Priority.Warning(s"$rigName runs, $attention seat(s) need attention: rig ps --nodes --rig $rigName"))
            else KeeperStep.Say(s"$rigName runs")
          case RigStatus.Partial | RigStatus.Stopped => KeeperStep.Nodes(status)
          case RigStatus.Missing                     => KeeperStep.Start(status)
          case other => KeeperStep.Say(Priority.Warning(s"$rigName has the status '${other.render}': nothing done"))

  /** From the seats of a partial or stopped rig. */
  def withNodes(status: RigStatus, nodes: List[RigNode]): KeeperStep = status match
    case RigStatus.Partial =>
      val down = nodes.filterNot(_.running).map(_.render)
      KeeperStep.Say(Priority.Warning(s"$rigName is partial, seats not running: ${down.mkString(", ")}. Nothing changed."))
    case _ if nodes.nonEmpty && nodes.forall(_.intentionallyStopped) =>
      KeeperStep.Say(s"$rigName was stopped on purpose (rig down): not started")
    case _ => KeeperStep.Start(status)

  /** The start times of the attempts file that are within the window of `now`. */
  def recent(lines: List[String], now: Long): List[String] =
    lines.filter(t => t.nonEmpty && t.forall(_.isDigit)).filter(t => now - t.toLong <= window)

/** A package of the system's closure, as freeze lists it. */
final case class FreezePkg(name: String, bytes: Long)

/** freeze's arguments. */
final case class FreezeArgs(bySize: Boolean, system: String)

object FreezeArgs:
  def parse(args: List[String]): FreezeArgs =
    val (bySize, rest) = args match
      case "--by-size" :: tail => (true, tail)
      case other               => (false, other)
    FreezeArgs(bySize, rest.headOption.filter(_.nonEmpty).getOrElse(BoxPaths.currentSystem))

/** What hermes-check expects on the box. Keep the plugin list in step with extraPlugins in
  * hermes.nix, and the skills with hermes/skills/. The pirsig tools are an MCP server, not a plugin
  * (docs/HERMES-PLUGINS.md); their two skills are checked with the others.
  */
object HermesLive:
  val community = List("custom-dangerous-patterns", "tripwire", "public-holidays", "inbox",
    "telegram-business", "workflow-record", "github-copilot", "error-ledger", "aux-ledger",
    "approval-ledger", "stop-ledger", "progress-squash", "gh-ref", "wiki-ref", "memory-rewind",
    "hermes-guide", "hermes-plugin-guard")
  val skills = List("hermes-omp", "kvm4-health", "hermes-manim", "hermes-cron", "evidence-ledger-research",
    "pirsig-smart-notes", "pirsig-video-indexer")
  val home = CheckpointConfig.hermesHome
  val bin = "/etc/profiles/per-user/hermes/bin"
  val user = "hermes"
  val ompVersion = "18.16.0"

/** One line of hermes-check's report. */
enum CheckLine:
  case Section(title: String)
  case Info(text: String)
  case Pass(text: String)
  case Fail(text: String)

  def render: String = this match
    case Section(title) => s"\n== $title"
    case Info(text)     => text
    case Pass(text)     => s"ok    $text"
    case Fail(text)     => s"FAIL  $text"

object CheckLine:
  def of(ok: Boolean, pass: => String, fail: => String): CheckLine = if ok then Pass(pass) else Fail(fail)
