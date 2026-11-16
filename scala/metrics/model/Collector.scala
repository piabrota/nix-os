package piabrota.metrics

import Awk.*

/** Two counters that go together: received and sent, read and written. */
final case class InOut(in: Double, out: Double)

/** A CPU line of /proc/stat: all its ticks, and the idle and iowait ones. */
final case class CpuTimes(total: Double, idle: Double)

object CpuTimes:
  /** The name of the line of all the vCPUs; "cpu0".. are each one. */
  val All = "cpu"

/** A process's start (ticks after boot) and the CPU ticks it used. */
final case class ProcTicks(start: Double, ticks: Double)

/** The kernel's counters of /proc/stat that a rate is made of. */
final case class KernelCounters(ctxt: Double, forks: Double)

/** The lines of the state file, one letter each. */
enum StateTag(val tag: String):
  case Uptime extends StateTag("T")
  case Kernel extends StateTag("K")
  case Net extends StateTag("N")
  case Disk extends StateTag("D")
  case Cpu extends StateTag("C")
  case Process extends StateTag("P")

object StateTag:
  val byTag: Map[String, StateTag] = values.map(t => t.tag -> t).toMap

/** The previous run's counters, from the state file: what it holds, a garbled line left out. CPU
  * by name, processes by pid.
  */
final case class Previous(uptime: Option[Double] = None, cpu: Map[String, CpuTimes] = Map.empty,
    procs: Map[String, ProcTicks] = Map.empty, kernel: Option[KernelCounters] = None, net: Option[InOut] = None,
    disk: Option[InOut] = None)

object Previous:
  import StateTag.*

  def parse(text: Option[String]): Previous =
    lines(text).map(fields).foldLeft(Previous()) { (p, f) =>
      f.headOption.flatMap(byTag.get).fold(p) { tag =>
        (tag, f.toList.tail) match
          case (Uptime, List(up))           => p.copy(uptime = Some(num(up)))
          case (Cpu, List(n, tot, idl))     => p.copy(cpu = p.cpu + (n -> CpuTimes(num(tot), num(idl))))
          case (Process, List(pid, st, ut)) => p.copy(procs = p.procs + (pid -> ProcTicks(num(st), num(ut))))
          case (Kernel, List(ctxt, forks))  => p.copy(kernel = Some(KernelCounters(num(ctxt), num(forks))))
          case (Net, List(rx, tx))          => p.copy(net = Some(InOut(num(rx), num(tx))))
          case (Disk, List(rd, wr))         => p.copy(disk = Some(InOut(num(rd), num(wr))))
          case _                            => p
      }
    }

/** This run's counters, which the next run reads as its [[Previous]]. */
final case class Counters(uptime: Double, kernel: KernelCounters, net: Option[InOut], disk: Option[InOut],
    cpu: Vector[(String, CpuTimes)], procs: Vector[(String, ProcTicks)]):
  import StateTag.*

  def render: String =
    val rows = Vector(s"${Uptime.tag} ${plain(uptime)}", s"${Kernel.tag} ${plain(kernel.ctxt)} ${plain(kernel.forks)}") ++
      net.map(n => s"${Net.tag} ${fixed(n.in, 0)} ${fixed(n.out, 0)}") ++
      disk.map(d => s"${Disk.tag} ${fixed(d.in, 0)} ${fixed(d.out, 0)}") ++
      cpu.map((n, c) => s"${Cpu.tag} $n ${plain(c.total)} ${plain(c.idle)}") ++
      procs.map((pid, p) => s"${Process.tag} $pid ${plain(p.start)} ${plain(p.ticks)}")
    rows.mkString("", "\n", "\n")

/** What `getconf CLK_TCK` and `getconf PAGESIZE` give. */
final case class SysConf(clockTicks: Double, pageSize: Double)

/** /proc/<pid>/stat: the name, between the first ( and the LAST ) since it can hold spaces,
  * parentheses or a newline; the CPU ticks (utime + stime) and the start.
  */
final case class ProcStat(name: String, ticks: Double, start: Double)

object ProcStat:
  def parse(st: String): Option[ProcStat] =
    val (open, close) = (st.indexOf('('), st.lastIndexOf(')'))
    Option.when(open >= 0 && close >= 0)(fields(st.drop(close + 2))).filter(_.length >= 20).map { r =>
      ProcStat(if close > open then st.substring(open + 1, close) else "", num(nth(r, 12)) + num(nth(r, 13)), num(nth(r, 20)))
    }

/** A process as it was read: its stat, its statm and its status. */
final case class ProcFiles(pid: String, stat: ProcStat, statm: String, status: Option[String])

/** A process: what the two lists show, and its start and CPU ticks for the next run. */
final case class Proc(pid: String, name: String, user: String, rss: Double, cpu: Double, start: Double, ticks: Double):
  def pidNumber: Double = pid.toDouble

  def render: String = JsonText.obj(Seq(Key.Pid -> fixed(pidNumber, 0), Key.Name -> JsonText.str(name),
    Key.User -> JsonText.str(user), Key.Rss -> fixed(rss, 0), Key.CpuPct -> fixed(cpu, 1)))

/** A unit with a MemoryMax, as read from its cgroup. */
final case class UnitMemory(name: String, current: Option[String], max: Double, peak: Option[String])

object UnitMemory:
  /** memory.max when it is a limit: "max" and 0 are none. */
  def limit(text: Option[String]): Option[Double] = text.filter(isDigits).map(num).filter(_ != 0)

/** A unit with a MemoryMax; `order` is its place in the listing, for ties. */
final case class Service(name: String, mem: Double, max: Double, peak: Option[Double], order: Int):
  def ratio: Double = mem / max

  def render: String = JsonText.obj(Seq(Key.Unit -> JsonText.str(name), Key.Mem -> fixed(mem, 0),
    Key.Max -> fixed(max, 0)) ++ peak.map(p => Key.Peak -> fixed(p, 0)))

/** The pressure files of /proc/pressure, by name. */
enum Resource(val file: String):
  case Cpu extends Resource("cpu")
  case Memory extends Resource("memory")
  case Io extends Resource("io")

/** The 10 s averages of one resource: "some" (and "full"). */
final case class Pressure(resource: Resource, avg10: List[(String, Double)])

/** The counts of /proc/net/sockstat that the page shows: `key` in the file, `field` on the
  * `proto` line.
  */
enum SocketKind(val key: String, val proto: String, val field: String):
  case Tcp extends SocketKind("tcp", "TCP:", "inuse")
  case TcpTimeWait extends SocketKind("tcp_tw", "TCP:", "tw")
  case Udp extends SocketKind("udp", "UDP:", "inuse")

/** The lines of /proc/meminfo that the page shows, in bytes. */
final case class Memory(total: Double, available: Double, swapTotal: Double, swapFree: Double, buffers: Double,
    cached: Double, shmem: Double, dirty: Double)

object Memory:
  def parse(meminfo: Array[String]): Memory =
    val kb = meminfo.map(fields).map(f => nth(f, 1) -> num(nth(f, 2)) * 1024).toMap.withDefaultValue(0.0)
    Memory(kb("MemTotal:"), kb("MemAvailable:"), kb("SwapTotal:"), kb("SwapFree:"), kb("Buffers:"), kb("Cached:"),
      kb("Shmem:"), kb("Dirty:"))

/** The kernel lines of /proc/stat. */
final case class KernelStat(ctxt: Double, processes: Double, running: Double, blocked: Double)

object KernelStat:
  private val Line = "(ctxt|processes|procs_running|procs_blocked) .*".r

  def parse(stat: Array[String]): KernelStat =
    val m = stat.collect { case l @ Line(_) =>
      val f = fields(l)
      f(0) -> num(nth(f, 2))
    }.toMap.withDefaultValue(0.0)
    KernelStat(m("ctxt"), m("processes"), m("procs_running"), m("procs_blocked"))

/** A rate and the counter it came from, for the net and the disks. */
final case class Traffic(rate: InOut, total: InOut):
  def render(in: Direction, out: Direction): String = JsonText.obj(Seq(in.perSecond -> fixed(rate.in, 0),
    out.perSecond -> fixed(rate.out, 0), in.total -> fixed(total.in, 0), out.total -> fixed(total.out, 0)))

/** The tasks the kernel schedules. */
final case class Tasks(threads: Double, running: Double, blocked: Double, forksPerS: Double, ctxtPerS: Double)

/** The NixOS version and the generation of the system profile. */
final case class SystemInfo(nixos: Option[String], generation: Option[String]):
  def render: String =
    JsonText.obj(nixos.map(v => Key.Nixos -> JsonText.str(v)) ++ generation.map(g => Key.Generation -> g.toLong.toString))

/** A site the probe asked, and its visits when the probe counted them. */
final case class SiteStatus(name: String, code: Int, visits: Option[SiteVisits]):
  /** An answer below 500 is up. */
  def up: Boolean = code >= 100 && code < 500

/** The sites of the probe file, at the probe's time. */
final case class Domains(ts: String, sites: List[SiteStatus]):
  def render: String =
    val seen = sites.flatMap(_.visits)
    val sums = if seen.isEmpty then Nil else List(Key.Views -> seen.map(_.views).sum.toString,
      Key.Visitors -> seen.map(_.visitors).sum.toString)
    val list = sites.map { s =>
      JsonText.obj(List(Key.Name -> s""""${s.name}"""", Key.Code -> s.code.toString, Key.Up -> s.up.toString) ++
        s.visits.toList.flatMap(v => List(Key.Views -> v.views.toString, Key.Visitors -> v.visitors.toString)))
    }
    JsonText.obj(List(Key.Ts -> fixed(num(ts), 0), Key.Up -> sites.count(_.up).toString,
      Key.Total -> sites.size.toString) ++ sums :+ (Key.Sites -> JsonText.arr(list)))

/** The commit count of the probe file, with the repository's name when it is known. */
final case class RepoCommits(name: Option[String], count: CommitCount):
  def render: String = JsonText.obj(name.map(r => Key.Name -> JsonText.str(r)).toList ++
    List(Key.Commits -> int(num(count.commits)), Key.Ts -> fixed(num(count.ts), 0)))

/** One sample of a host: what its JSON file says (metrics/SCHEMA.md), and the counters the next
  * run compares with.
  */
final case class Sample(host: String, label: String, ts: Long, interval: Double, uptime: Double, load: Seq[Double],
    cpuTotal: Double, cores: Vector[Double], warming: Boolean, mem: Memory, disk: InOut, tasks: Tasks,
    fdsOpen: Option[Double], net: Option[Traffic], sockets: List[(SocketKind, Double)], diskIo: Option[Traffic],
    pressure: List[Pressure], procsTotal: Int, servicesRunning: Int, inventory: Option[Vector[(String, String)]],
    system: SystemInfo, domains: Option[Domains], repo: Option[RepoCommits], topMem: Vector[Proc],
    topCpu: Vector[Proc], units: Vector[Service], counters: Counters):
  import JsonText.{arr, obj, str}

  def json: String =
    val cpu = obj(Seq(Key.TotalPct -> fixed(cpuTotal, 1), Key.Cores -> arr(cores.map(fixed(_, 1)))) ++
      Option.when(warming)(Key.Warming -> "true"))
    val memory = obj(Seq(Key.Total -> fixed(mem.total, 0), Key.Used -> fixed(mem.total - mem.available, 0),
      Key.Available -> fixed(mem.available, 0), Key.SwapTotal -> fixed(mem.swapTotal, 0),
      Key.SwapUsed -> fixed(mem.swapTotal - mem.swapFree, 0)))
    val memDetail = obj(Seq(Key.Buffers -> fixed(mem.buffers, 0), Key.Cached -> fixed(mem.cached, 0),
      Key.Shmem -> fixed(mem.shmem, 0), Key.Dirty -> fixed(mem.dirty, 0)))
    val taskJson = obj(Seq(Key.Threads -> int(tasks.threads), Key.Running -> int(tasks.running),
      Key.Blocked -> int(tasks.blocked), Key.ForksPerS -> fixed(tasks.forksPerS, 1), Key.CtxtPerS -> fixed(tasks.ctxtPerS, 0)))
    val pressureJson = pressure.map(p => p.resource.file -> obj(p.avg10.map((k, v) => k -> fixed(v, 2))))
    val fields = Vector(
      Key.V -> "1", Key.Host -> str(host), Key.Label -> str(label), Key.Ts -> ts.toString,
      Key.Interval -> fixed(interval, 0), Key.Uptime -> fixed(uptime, 0), Key.Vcpus -> cores.size.toString,
      Key.Load -> arr(load.map(fixed(_, 2))), Key.Cpu -> cpu, Key.Mem -> memory,
      Key.Disk -> obj(Seq(Key.RootTotal -> fixed(disk.in, 0), Key.RootUsed -> fixed(disk.out, 0))),
      Key.MemDetail -> memDetail, Key.Tasks -> taskJson,
    ) ++ fdsOpen.map(n => Key.FdsOpen -> int(n)) ++
      net.map(t => Key.Net -> t.render(Direction.Rx, Direction.Tx)) ++
      Option.when(sockets.nonEmpty)(Key.Sockets -> obj(sockets.map((k, n) => k.key -> int(n)))) ++
      diskIo.map(t => Key.DiskIo -> t.render(Direction.Read, Direction.Write)) ++
      Option.when(pressure.nonEmpty)(Key.Pressure -> obj(pressureJson)) ++
      Vector(Key.ProcsTotal -> procsTotal.toString, Key.ServicesRunning -> servicesRunning.toString) ++
      inventory.map(inv => Key.Inventory -> obj(inv.map((k, n) => k -> int(num(n))))) ++
      Vector(Key.System -> system.render) ++
      domains.map(d => Key.Domains -> d.render) ++
      repo.map(r => Key.Repo -> r.render) ++
      Vector(Key.TopMem -> arr(topMem.map(_.render)), Key.TopCpu -> arr(topCpu.map(_.render)),
        Key.Units -> arr(units.map(_.render)))
    obj(fields) + "\n"
