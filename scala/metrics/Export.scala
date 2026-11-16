package piabrota.metrics

import java.io.File
import java.nio.charset.StandardCharsets.UTF_8
import java.nio.file.Files
import scala.collection.immutable.VectorMap

import Json.{Arr, Null, Num, Obj, Str}
import MetricKind.{Counter, Gauge}

/** `piabrota metrics-export`: every host file of OUT_DIR as one all.json and as metrics.prom, the
  * Prometheus text format 0.0.4 (docs/METRICS.md, "For machines"). A timer runs it where the page
  * is (metrics.nix); no network. A file that is not a JSON object, is over 64 KiB or whose "host" is
  * not its name is left out. In a host file any key may be missing or of the wrong type; a number
  * that is not finite is left out of metrics.prom.
  *
  * Environment ([[ExportConfig]]):
  *   OUT_DIR        where the host files are, and the two files go (default /run/metrics-web)
  *   METRICS_STALE  seconds after which a host is not fresh (default 30)
  *   METRICS_NOW    Unix seconds to use as now; the tests set it
  */
object Export:
  private val MaxHostFile = 65536L
  private val MaxHostName = 32

  def run(args: List[String]): Int =
    Host.umask022()
    val config = ExportConfig.fromEnv()
    val dir = config.outDir
    val hosts = hostFiles(dir)
    val (all, prom) = (s"$dir/${OutFile.AllJson}", s"$dir/${OutFile.Prometheus}")
    val (tmpAll, tmpProm) = (s"$dir/.${OutFile.AllJson}.${Host.pid}.tmp", s"$dir/.${OutFile.Prometheus}.${Host.pid}.tmp")
    Host.cleaning(tmpAll, tmpProm) {
      val files = Exported(hosts, config.now.toDouble, Num(config.stale, config.stale.toDouble))
      Files.write(Host.path(tmpAll), (files.allJson + "\n").getBytes(UTF_8))
      Files.write(Host.path(tmpProm), (files.prometheus + "\n").getBytes(UTF_8))
      Host.move(tmpAll, all)
      Host.move(tmpProm, prom)
    }
    0

  /** The host files, by name, in the order of the shell's glob. */
  private def hostFiles(dir: String): VectorMap[String, Json] =
    VectorMap.from(Host.listing(dir).filter(n => n.endsWith(OutFile.Suffix) && !n.startsWith(".")).flatMap { file =>
      val name = file.stripSuffix(OutFile.Suffix)
      val f = File(s"$dir/$file")
      val ok = !OutFile.reserved.contains(name) && name.length <= MaxHostName && HostName.valid(name) &&
        f.isFile && f.length <= MaxHostFile
      val data = if ok then Json.parse(String(Files.readAllBytes(f.toPath), UTF_8)) else None
      data.collect { case d: Obj if d(Key.Host) == Str(name) => name -> d }
    })

  /** What one run writes, from the host files (export.jq, before it became this). */
  private final class Exported(hosts: VectorMap[String, Json], now: Double, stale: Num):
    private def age(d: Json): Option[Double] = d(Key.Ts) match
      case Num(_, ts) if ts.isFinite => Some(math.floor(math.max(0, now - ts)))
      case _                         => None

    private def fresh(d: Json): Boolean = age(d).exists(_ <= stale.value)

    def allJson: String =
      val hostsJson = hosts.map { (name, d) =>
        name -> Obj(VectorMap(Key.Age -> age(d).map(Json.num(_)).getOrElse(Null), Key.Fresh -> Json.Bool(fresh(d)),
          Key.Data -> d))
      }
      Json.write(Obj(VectorMap(Key.V -> Json.num(1L), Key.Ts -> Json.num(math.floor(now)), Key.StaleAfter -> stale,
        Key.Hosts -> Obj(hostsJson))))

    def prometheus: String =
      Metric.render(hosts.toVector.flatMap((name, d) => series(name, d)) ++ Vector(
        gauge("hosts", "Host files read", Nil, Json.num(hosts.size.toLong)),
        gauge("export_timestamp_seconds", "Unix time this file was written", Nil, Json.num(math.floor(now))),
      ).flatten)

    private def gauge(name: String, help: String, labels: Seq[(Label, Json)], value: Json): Option[Metric] =
      Metric.of(name, Gauge, help, labels, value)

    /** The fields of an object, none for anything else (`if type == "object" then . else {} end`). */
    private def fieldsOf(j: Json): VectorMap[String, Json] = j match
      case Obj(f) => f
      case _      => VectorMap.empty

    private def obj(d: Json, key: String): VectorMap[String, Json] = fieldsOf(d(key))

    /** `.[key]` as an array, [] when it is not one. */
    private def arr(d: Json, key: String): Vector[Json] = d(key) match
      case Arr(items) => items
      case _          => Vector.empty

    /** jq's `.[key] // "?"`. */
    private def orUnknown(d: Json, key: String): Json = d(key) match
      case Null | Json.Bool(false) => Str("?")
      case v                       => v

    private def flag(j: Json): Json = j match
      case Json.Bool(b) => Json.num(if b then 1L else 0L)
      case _            => Null

    private def series(host: String, d: Json): Vector[Metric] =
      val h = Seq(Label.Host -> Str(host))
      def by(label: Label, value: String) = h :+ (label -> Str(value))
      val cpuHelp = "Busy share of the vCPUs over the last interval"
      val cpu = Obj(obj(d, Key.Cpu))
      val net = Obj(obj(d, Key.Net))
      val diskIo = Obj(obj(d, Key.DiskIo))
      val disk = Obj(obj(d, Key.Disk))
      val tasks = Obj(obj(d, Key.Tasks))
      val system = Obj(obj(d, Key.System))
      val domains = Obj(obj(d, Key.Domains))
      val repo = Obj(obj(d, Key.Repo))
      val ageNum = age(d).map(Json.num(_)).getOrElse(Null)
      // A rate and a counter for each direction: <name>_bytes_per_second and <name>_bytes_total.
      def traffic(section: Json, directions: List[Direction], name: String, what: String, scope: String) =
        directions.flatMap(x => Vector(
          gauge(s"${name}_bytes_per_second", s"$what bytes per second, $scope", by(Label.Direction, x.name),
            section(x.perSecond)),
          Metric.of(s"${name}_bytes_total", Counter, s"$what bytes since boot, $scope", by(Label.Direction, x.name),
            section(x.total)),
        ).flatten)
      Vector(
        gauge("host_fresh", "1 when the host's file is newer than the stale limit", h, Json.num(if fresh(d) then 1L else 0L)),
        gauge("sample_age_seconds", "Seconds since the host's last sample", h, ageNum),
        gauge("sample_timestamp_seconds", "Unix time of the host's last sample", h, d(Key.Ts)),
        gauge("uptime_seconds", "Seconds since boot", h, d(Key.Uptime)),
        gauge("vcpus", "Number of vCPUs", h, d(Key.Vcpus)),
      ).flatten ++
        arr(d, Key.Load).take(3).zip(Seq("1m", "5m", "15m")).flatMap((v, w) => gauge("load", "Load average", by(Label.Window, w), v)) ++
        gauge("cpu_busy_percent", cpuHelp, by(Label.Cpu, Key.Total), cpu(Key.TotalPct)) ++
        arr(cpu, Key.Cores).zipWithIndex.flatMap((v, i) => gauge("cpu_busy_percent", cpuHelp, by(Label.Cpu, i.toString), v)) ++
        (obj(d, Key.Mem) ++ obj(d, Key.MemDetail)).flatMap((k, v) =>
          gauge("memory_bytes", "Memory and swap, from /proc/meminfo", by(Label.Kind, k), v)) ++
        List(Key.Total -> Key.RootTotal, Key.Used -> Key.RootUsed).flatMap((kind, key) =>
          gauge("root_filesystem_bytes", "The filesystem of /", by(Label.Kind, kind), disk(key))) ++
        gauge("threads", "Threads and processes the kernel schedules", h, tasks(Key.Threads)) ++
        List(Key.Running, Key.Blocked).flatMap(s => gauge("tasks", "Tasks running or blocked", by(Label.State, s), tasks(s))) ++
        Vector(
          gauge("forks_per_second", "New processes per second", h, tasks(Key.ForksPerS)),
          gauge("context_switches_per_second", "Context switches per second", h, tasks(Key.CtxtPerS)),
          gauge("open_files", "Open file handles", h, d(Key.FdsOpen)),
          gauge("processes", "Processes, kernel threads included", h, d(Key.ProcsTotal)),
          gauge("services_running", "Services with a cgroup under system.slice", h, d(Key.ServicesRunning)),
        ).flatten ++
        traffic(net, Direction.net, "network", "Network", "every interface but lo") ++
        obj(d, Key.Sockets).flatMap((k, v) =>
          gauge("sockets", "Sockets: tcp in use, tcp in TIME-WAIT, udp in use", by(Label.Kind, k), v)) ++
        traffic(diskIo, Direction.disk, "disk", "Disk", "whole disks") ++
        obj(d, Key.Pressure).toVector.flatMap((r, kinds) =>
          fieldsOf(kinds).flatMap((k, v) =>
            gauge("pressure_percent", "Pressure stall, avg10", h ++ Seq(Label.Resource -> Str(r), Label.Kind -> Str(k)), v))) ++
        obj(d, Key.Inventory).flatMap((k, v) =>
          gauge("inventory", "What the deployed configuration declares", by(Label.Item, k), v)) ++
        gauge("deploy_generation", "Generation of the system profile: one per deploy", h, system(Key.Generation)) ++
        (system(Key.Nixos) match
          case Str(v) => gauge("nixos_info", "The NixOS version, as a label", by(Label.Version, v), Json.num(1L))
          case _      => None) ++
        List(Key.Total, Key.Up).flatMap(s => gauge("sites", "Sites of the host: total and up", by(Label.State, s), domains(s))) ++
        gauge("probe_timestamp_seconds", "Unix time of the last probe", h, domains(Key.Ts)) ++
        arr(domains, Key.Sites).collect { case s: Obj => s }.flatMap { s =>
          val l = h :+ (Label.Site -> orUnknown(s, Key.Name))
          Vector(
            gauge("site_up", "1 when the site answered below HTTP 500", l, flag(s(Key.Up))),
            gauge("site_http_code", "The site's HTTP code, 0 for no answer", l, s(Key.Code)),
            gauge("site_views_24h", "Pages browsers got from the site in the last 24 h", l, s(Key.Views)),
            gauge("site_visitors_24h", "Distinct addresses that got a page in the last 24 h", l, s(Key.Visitors)),
          ).flatten
        } ++
        (repo(Key.Name) match
          case Str(name) => gauge("repo_commits", "Commits on the counted branch", by(Label.Repo, name), repo(Key.Commits))
          case _         => None) ++
        arr(d, Key.Units).collect { case u: Obj => u }.flatMap { u =>
          val l = h :+ (Label.Unit -> orUnknown(u, Key.Unit))
          Vector(
            gauge("unit_memory_bytes", "memory.current of a unit with a MemoryMax", l, u(Key.Mem)),
            gauge("unit_memory_max_bytes", "MemoryMax of the unit", l, u(Key.Max)),
            gauge("unit_memory_peak_bytes", "memory.peak of the unit", l, u(Key.Peak)),
          ).flatten
        }
