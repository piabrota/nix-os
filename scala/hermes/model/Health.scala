package piabrota.hermes

/** The two flags of kvm4-health. */
final case class HealthMode(alert: Boolean, record: Boolean)

object HealthMode:
  val Alert = "--alert"
  val Record = "--record"

  /** The flags, or None for an argument that is neither. */
  def parse(args: List[String]): Option[HealthMode] =
    Option.when(args.forall(a => a == Alert || a == Record))(HealthMode(args.contains(Alert), args.contains(Record)))

/** The thresholds, as the text of their variables: the checks compare them as the script's `[ -lt ]`
  * and awk did, so a value that is not a number keeps its old effect. An empty variable takes the
  * default (`${X:=default}`).
  */
final case class Limits(
    unitMemWarn: String, // % of a unit's MemoryMax in use now
    unitPeakWarn: String, // % of a unit's MemoryMax reached since it started
    unitNoMaxGib: String, // GiB in use by a unit that has no MemoryMax
    memAvailWarn: String, // % of RAM available, under it: WARN
    memAvailCrit: String, // under it: CRIT
    swapWarn: String, // % of swap (zram) in use
    psiMemWarn: String, // memory pressure, `some` avg60, %
    psiIoWarn: String, // I/O pressure, `some` avg60, %
    loadWarn: String, // 15-minute load per core
    diskWarn: String, // % of / used
    diskCrit: String,
    diskGrowthGib: String, // GiB a day that / grows by
    agentGrowthGib: String, // GiB that hermes-agent grew by in 24 h, with no restart
    restartsWarn: String, // restarts of a unit since it started, above it: WARN
    restartsCrit: String, // above it: CRIT (a restart loop)
    agentCpuWarn: String, // % of one core, hermes-agent's average since the last sample
    journalMib: String, // MiB of journal, above it: WARN
    repeatHours: String, // --alert repeats the same findings after this many hours
)

object Limits:
  def read(env: String => Option[String]): Limits =
    def kh(name: String, default: String) = env(s"KH_$name").getOrElse(default)
    Limits(
      unitMemWarn = kh("UNIT_MEM_WARN", "80"),
      unitPeakWarn = kh("UNIT_PEAK_WARN", "90"),
      unitNoMaxGib = kh("UNIT_NOMAX_GIB", "4"),
      memAvailWarn = kh("MEMAVAIL_WARN", "15"),
      memAvailCrit = kh("MEMAVAIL_CRIT", "5"),
      swapWarn = kh("SWAP_WARN", "50"),
      psiMemWarn = kh("PSI_MEM_WARN", "10"),
      psiIoWarn = kh("PSI_IO_WARN", "20"),
      loadWarn = kh("LOAD_WARN", "1.5"),
      diskWarn = kh("DISK_WARN", "80"),
      diskCrit = kh("DISK_CRIT", "90"),
      diskGrowthGib = kh("DISK_GROWTH_GIB", "5"),
      agentGrowthGib = kh("AGENT_GROWTH_GIB", "1"),
      restartsWarn = kh("RESTARTS_WARN", "3"),
      restartsCrit = kh("RESTARTS_CRIT", "50"),
      agentCpuWarn = kh("AGENT_CPU_WARN", "200"),
      // journald keeps at most 200 MiB (SystemMaxUse in tools.nix), and a journal that has filled up
      // to its own cap is normal. Only a journal above the cap is a finding, so the limit sits above it.
      journalMib = kh("JOURNAL_MIB", "220"),
      repeatHours = kh("REPEAT_HOURS", "6"),
    )

/** What kvm4-health reads from the environment, once, at its start. */
final case class HealthConfig(home: os.Path, mode: HealthMode, limits: Limits):
  /** Where --record and --alert keep their state. */
  def state: os.Path = home / "plugin-data" / "kvm4-health"

object HealthConfig:
  def read(mode: HealthMode, env: String => Option[String]): HealthConfig =
    HealthConfig(os.Path(env("HERMES_HOME").getOrElse("/var/lib/hermes/.hermes"), os.pwd), mode, Limits.read(env))

/** The level of one line of the report. */
enum Level(val render: String):
  case Ok extends Level("ok")
  case Warn extends Level("WARN")
  case Crit extends Level("CRIT")

  /** A line of the report at this level. */
  def line(text: String): String = f"$render%-5s $text"

/** A WARN or CRIT line; `key` names it in the signature that --alert compares. */
final case class Finding(level: Level, key: String, text: String):
  def line: String = level.line(text)

object Finding:
  /** The keys of the findings, sorted and without a repeat, each followed by a blank, after one. */
  def signature(findings: Seq[Finding]): String =
    (" " +: findings.map(_.key).distinct.sorted.map(_ + " ")).mkString

/** The units whose health the report shows, and the one it follows for growth. */
object HealthUnits:
  val Agent = "hermes-agent"
  val All = List(Agent, "hermes-backend", "pgx", "openrig")
  val HermesUser = "hermes"

/** What the growth section needs of hermes-agent: its memory, CPU time and start, as text. */
final case class AgentSample(mem: String = "0", cpu: String = "0", start: String = "0")

/** One line of samples.tsv: the time, hermes-agent's start, memory and CPU time, and / used. */
final case class Sample(time: Long, agent: AgentSample, rootUsed: Long):
  def render: String = s"$time\t${agent.start}\t${agent.mem}\t$rootUsed\t${agent.cpu}\n"

object Sample:
  val File = "samples.tsv"
  // Two weeks at one sample every 30 min.
  val Keep = 700

/** last-alert: when --alert last spoke, and the signature of what it said. */
final case class AlertState(time: Long, signature: String):
  def render: String = s"$time\n$signature\n"

object AlertState:
  val File = "last-alert"
  val none: AlertState = AlertState(0L, "")

  def parse(text: String): AlertState =
    val l = text.split("\n", -1)
    AlertState(Util.count(l(0)), if l.length > 1 then l(1) else "")
