package piabrota.metrics

/** The keys of a host file (metrics/SCHEMA.md) and of all.json, written once: the collector
  * writes them, the export, the preview and the pull read them.
  */
object Key:
  val V = "v"
  val Host = "host"
  val Label = "label"
  val Ts = "ts"
  val Interval = "interval"
  val Uptime = "uptime_s"
  val Vcpus = "vcpus"
  val Load = "load"
  val Cpu = "cpu"
  val TotalPct = "total_pct"
  val Cores = "cores"
  val Warming = "warming"
  val Mem = "mem"
  val Total = "total"
  val Used = "used"
  val Available = "available"
  val SwapTotal = "swap_total"
  val SwapUsed = "swap_used"
  val Disk = "disk"
  val RootTotal = "root_total"
  val RootUsed = "root_used"
  val MemDetail = "mem_detail"
  val Buffers = "buffers"
  val Cached = "cached"
  val Shmem = "shmem"
  val Dirty = "dirty"
  val Tasks = "tasks"
  val Threads = "threads"
  val Running = "running"
  val Blocked = "blocked"
  val ForksPerS = "forks_per_s"
  val CtxtPerS = "ctxt_per_s"
  val FdsOpen = "fds_open"
  val Net = "net"
  val Sockets = "sockets"
  val DiskIo = "disk_io"
  val Pressure = "pressure"
  val ProcsTotal = "procs_total"
  val ServicesRunning = "services_running"
  val Inventory = "inventory"
  val System = "system"
  val Nixos = "nixos"
  val Generation = "generation"
  val Domains = "domains"
  val Up = "up"
  val Views = "views"
  val Visitors = "visitors"
  val Sites = "list"
  val Name = "name"
  val Code = "code"
  val Repo = "repo"
  val Commits = "commits"
  val TopMem = "top_mem"
  val TopCpu = "top_cpu"
  val Units = "units"
  val Pid = "pid"
  val User = "user"
  val Rss = "rss"
  val CpuPct = "cpu_pct"
  val Unit = "unit"
  val Max = "max"
  val Peak = "peak"
  // all.json
  val Hosts = "hosts"
  val StaleAfter = "stale_after_s"
  val Age = "age_s"
  val Fresh = "fresh"
  val Data = "data"

/** The two counters of a direction: `<name>_bps` and `<name>_total` in "net" and "disk_io". */
enum Direction(val name: String):
  case Rx extends Direction("rx")
  case Tx extends Direction("tx")
  case Read extends Direction("read")
  case Write extends Direction("write")

  def perSecond: String = s"${name}_bps"
  def total: String = s"${name}_total"

object Direction:
  val net: List[Direction] = List(Rx, Tx)
  val disk: List[Direction] = List(Read, Write)

/** A host file's JSON, written the way the collector's awk wrote it: values already rendered. */
object JsonText:
  def obj(fields: Iterable[(String, String)]): String =
    fields.iterator.map((k, v) => s""""$k":$v""").mkString("{", ",", "}")

  def arr(items: Iterable[String]): String = items.mkString("[", ",", "]")

  /** A string as the collector writes it: [[Awk.esc]], so printable ASCII only. */
  def str(s: String): String = "\"" + Awk.esc(s) + "\""

/** The files in OUT_DIR: one `<host>.json` a host, and what the export makes of them. */
object OutFile:
  val Suffix = ".json"
  val AllJson = "all.json"
  val Prometheus = "metrics.prom"

  def host(name: String): String = name + Suffix

  /** Names that are not a host's: the export's own files. */
  val reserved: Set[String] = Set(AllJson, Prometheus).map(_.takeWhile(_ != '.'))

/** A host name names a file: lowercase letters, digits and dashes only. */
object HostName:
  def valid(name: String): Boolean = name.forall(c => (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-')

  /** The cheap check of a fetched host file, no parser: a JSON object that names `name`. */
  def claims(text: String, name: String): Boolean =
    text.startsWith("{") && text.contains(s""""${Key.Host}":"$name"""")

/** owner/name of a GitHub repository, and a branch: ASCII letters, digits and `._/-`. */
object RepoName:
  def valid(s: String): Boolean = s.forall(c => isAsciiAlnum(c) || "._/-".contains(c))

def isAsciiAlnum(c: Char): Boolean = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
