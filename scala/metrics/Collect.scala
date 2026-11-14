package piabrota.metrics

import java.io.{File, IOException}
import java.nio.file.Files

import Awk.*

/** `piabrota metrics-collect`: one run of the collector. A timer runs it every 10 s on both hosts
  * (metrics.nix). It reads /proc and the cgroup tree and writes one JSON file, atomically
  * (docs/METRICS.md, metrics/SCHEMA.md). No network, and no command line is read.
  *
  * Environment ([[CollectConfig]]):
  *   METRICS_NAME       file name and "host" key: piabrota or piabrota2 (required)
  *   METRICS_LABEL      the page's name for the host (default: the name)
  *   METRICS_INTERVAL   seconds between runs, written to the file (default 10)
  *   OUT_DIR            where <name>.json goes (default /run/metrics-web)
  *   STATE_DIR          where the previous sample is kept (default /run/metrics-state)
  *   METRICS_INVENTORY  a file of "<key> <count>" lines that Nix wrote: what this generation runs.
  *                      Optional; without it the file has no "inventory".
  *   METRICS_PROBE      the file metrics-probe writes: the sites' answers and visits, the commits.
  *                      Optional; without it the file has no "domains" and no "repo".
  *   METRICS_REPO       owner/name of the repository the commits are counted in (the "repo" name)
  *   SYSTEM_PROFILE     the system profile; its generation is the number of deploys (default
  *                      /nix/var/nix/profiles/system)
  *   NIXOS_VERSION_FILE default /run/current-system/nixos-version
  *   PROC_ROOT, CGROUP_ROOT, PASSWD_FILE, DF_PATH: the sources; the tests point them at a fixture.
  */
object Collect:
  def run(args: List[String]): Int =
    val config = CollectConfig.fromEnv()
    Host.umask022()
    Host.mkdirs(config.outDir)
    Host.mkdirs(config.stateDir)
    val (out, state) = (config.outFile, config.stateFile)
    val (tmpOut, tmpState) = (Host.temp(out), Host.temp(state))
    Host.cleaning(tmpOut, tmpState) {
      val prev = Previous.parse(read(state))
      val sample = Sampler.sample(Readings.of(config), prev, config, Host.sysConf, Host.now())
      Host.write(tmpState, sample.counters.render)
      Host.write(tmpOut, sample.json)
      // The state first: a crash between the two moves costs one sample, never a wrong number.
      Host.move(tmpState, state)
      Host.move(tmpOut, out)
    }
    0

/** What one run reads, as it was read: the files' texts and what the folders list. */
final case class Readings(stat: Array[String], uptime: Option[String], loadavg: Option[String],
    meminfo: Array[String], pressure: List[(Resource, Array[String])], fileNr: Option[String], netDev: Array[String],
    sockstat: Array[String], diskstats: Array[String], passwd: Array[String], procs: Vector[ProcFiles],
    unitDirs: Vector[String], units: Vector[UnitMemory], rootFs: Option[(Long, Long)], inventory: Option[Array[String]],
    nixosVersion: Option[String], profileLink: Option[String], probe: Option[String])

object Readings:
  /** The reads of one run: a file a process or a unit leaves on the way is a missing one. */
  def of(config: CollectConfig): Readings =
    val proc = config.procRoot
    val slice = s"${config.cgroupRoot}/system.slice"
    val unitDirs = Host.listing(slice)
      .filter(n => n.endsWith(".service") && !n.startsWith(".") && File(s"$slice/$n").isDirectory)
    Readings(
      stat = lines(read(s"$proc/stat")),
      uptime = read(s"$proc/uptime"),
      loadavg = read(s"$proc/loadavg"),
      meminfo = lines(read(s"$proc/meminfo")),
      pressure = Resource.values.toList.map(r => r -> lines(read(s"$proc/pressure/${r.file}"))),
      fileNr = read(s"$proc/sys/fs/file-nr"),
      // The network of PID 1, not this unit: the collector runs with PrivateNetwork, and /proc/net
      // is its own empty namespace.
      netDev = lines(read(s"$proc/1/net/dev")),
      sockstat = lines(read(s"$proc/1/net/sockstat")),
      diskstats = lines(read(s"$proc/diskstats")),
      passwd = lines(read(config.passwdFile)),
      procs = Host.listing(proc).filter(isDigits).flatMap(pid => procFiles(s"$proc/$pid", pid)),
      unitDirs = unitDirs,
      units = unitDirs.flatMap(unit => unitMemory(s"$slice/$unit", unit)),
      rootFs = Host.diskSpace(config.dfPath),
      inventory = config.inventory.map(file => lines(read(file))),
      nixosVersion = read(config.nixosVersionFile),
      profileLink =
        try Some(Files.readSymbolicLink(Host.path(config.systemProfile)).toString)
        catch case _: (IOException | UnsupportedOperationException) => None,
      probe = config.probe.flatMap(read),
    )

  /** One process; None when it ended between the listing and these reads, or cannot be read. */
  private def procFiles(dir: String, pid: String): Option[ProcFiles] =
    for
      st <- read(s"$dir/stat")
      sm <- read(s"$dir/statm")
      stat <- ProcStat.parse(st)
    yield ProcFiles(pid, stat, sm, read(s"$dir/status"))

  /** A unit has a cgroup under system.slice while it runs; only one with a MemoryMax is listed. */
  private def unitMemory(dir: String, unit: String): Option[UnitMemory] =
    UnitMemory.limit(read(s"$dir/memory.max"))
      .map(max => UnitMemory(unit, read(s"$dir/memory.current"), max, read(s"$dir/memory.peak")))


/** The decisions of a run: [[Readings]] and the previous counters to a [[Sample]]. */
object Sampler:
  private val CpuLine = "cpu[0-9]* .*".r
  private val PressureLine = "(some|full) avg10=[0-9.]+ .*".r
  private val WholeDisk = "[sv]d[a-z]+|xvd[a-z]+|nvme[0-9]+n[0-9]+".r
  private val InventoryKey = "[a-z][a-z_]*".r
  private val GenerationLink = "system-"
  private val TopProcs = 10
  private val TopUnits = 12

  def sample(r: Readings, prev: Previous, config: CollectConfig, sys: SysConf, ts: Long): Sample =
    val kernel = KernelStat.parse(r.stat)
    // The CPU lines of /proc/stat: "cpu" is the total, "cpu0".. are the vCPUs.
    val cpuRows = r.stat.collect { case l @ CpuLine() => fields(l) }
    val cpuNames = cpuRows.map(_(0)).toVector
    val cpuNow: Map[String, CpuTimes] = cpuRows.map { f =>
      f(0) -> CpuTimes((2 to 9).map(i => num(nth(f, i))).sum, num(nth(f, 5)) + num(nth(f, 6)))
    }.toMap

    val up = num(nth(fields(r.uptime.getOrElse("")), 1))
    val load = fields(r.loadavg.getOrElse(""))
    val threads =
      val t = nth(load, 4)
      num(t.substring(t.lastIndexOf('/') + 1))

    val elapsed = up - prev.uptime.getOrElse(0.0)
    val warming = prev.uptime.isEmpty || elapsed <= 0

    // A counter per second since the last run; 0 on a first run or when the counter went back.
    def rate(now: Double, before: Option[Double]): Double = before match
      case Some(b) if !warming && now >= b => (now - b) / elapsed
      case _                               => 0

    def traffic(now: InOut, before: Option[InOut]): Traffic =
      Traffic(InOut(rate(now.in, before.map(_.in)), rate(now.out, before.map(_.out))), now)

    val cpuBusy = cpuNames.map { n =>
      val c = cpuNow(n)
      val busy = prev.cpu.get(n) match
        case Some(p) if !warming && c.total > p.total => 100 * (1 - (c.idle - p.idle) / (c.total - p.total))
        case _                                         => 0.0
      n -> math.max(busy, 0)
    }

    // Pressure stall (PSI), the 10 s averages: "some" (and "full") of cpu, memory and io.
    val pressure = r.pressure.flatMap { (res, text) =>
      val kinds = text.toList.collect { case l @ PressureLine(_) =>
        val f = fields(l)
        f(0) -> num(f(1).stripPrefix("avg10="))
      }
      Option.when(kinds.nonEmpty)(Pressure(res, kinds))
    }

    // The sum over every interface but lo.
    val netRows = r.netDev.filter(_.contains(':')).map(l => fields(l.replaceFirst(":", " ")))
      .filter(f => f.length >= 17 && f(0) != "lo")
    val net = Option.when(netRows.nonEmpty)(InOut(netRows.map(f => num(f(1))).sum, netRows.map(f => num(f(9))).sum))

    val sockets = r.sockstat.toList.flatMap { l =>
      val f = fields(l)
      (2 until f.length by 2).flatMap { k =>
        SocketKind.values.find(s => s.proto == nth(f, 1) && s.field == nth(f, k)).map(_ -> num(nth(f, k + 1)))
      }
    }

    // Whole disks only (not partitions): sectors of 512 bytes read and written.
    val diskRows = r.diskstats.map(fields).filter(f => f.length >= 10 && WholeDisk.matches(f(2)))
    val diskIo = Option.when(diskRows.nonEmpty)(
      InOut(diskRows.map(f => num(f(5)) * 512).sum, diskRows.map(f => num(f(9)) * 512).sum))

    val users = r.passwd.map(_.split(":", -1)).filter(f => nth(f, 1).nonEmpty)
      .foldLeft(Map.empty[String, String])((m, f) => if m.contains(nth(f, 3)) then m else m + (nth(f, 3) -> f(0)))

    val procs = r.procs.map { p =>
      val uid = lines(p.status).find(_.startsWith("Uid:")).fold("")(l => nth(fields(l), 2))
      val dt = prev.procs.get(p.pid) match
        case Some(before) if before.start == p.stat.start        => p.stat.ticks - before.ticks
        case _ if p.stat.start > prev.uptime.getOrElse(0.0) * sys.clockTicks => p.stat.ticks
        case _                                                     => 0.0
      val cpu = if warming then 0.0 else math.max(dt, 0) / sys.clockTicks / elapsed * 100
      Proc(p.pid, p.stat.name, users.getOrElse(uid, if uid.isEmpty then "?" else uid),
        num(nth(fields(p.statm), 2)) * sys.pageSize, cpu, p.stat.start, p.stat.ticks)
    }

    val services = r.units.zipWithIndex.map { (u, i) =>
      Service(u.name, num(u.current.getOrElse("")), u.max, u.peak.filter(isDigits).map(num), i)
    }

    // The 10 biggest by `key`, the biggest first; ties go to the lower pid.
    def top(key: Proc => Double): Vector[Proc] =
      procs.sortWith((a, b) => key(a) > key(b) || (key(a) == key(b) && a.pidNumber < b.pidNumber)).take(TopProcs)

    val probe = r.probe.map(text => ProbeReport.parse(Some(text)))

    Sample(
      host = config.name,
      label = config.label,
      ts = ts,
      interval = config.interval,
      uptime = up,
      load = (1 to 3).map(i => num(nth(load, i))),
      cpuTotal = cpuBusy.filter(_._1 == CpuTimes.All).lastOption.fold(0.0)(_._2),
      cores = cpuBusy.filter(_._1 != CpuTimes.All).map(_._2),
      warming = warming,
      mem = Memory.parse(r.meminfo),
      disk = r.rootFs.fold(InOut(0, 0))((total, used) => InOut(total.toDouble, used.toDouble)),
      tasks = Tasks(threads, kernel.running, kernel.blocked, rate(kernel.processes, prev.kernel.map(_.forks)),
        rate(kernel.ctxt, prev.kernel.map(_.ctxt))),
      fdsOpen = r.fileNr.map(t => num(nth(fields(t), 1))).filter(_ >= 0),
      net = net.map(traffic(_, prev.net)),
      sockets = sockets,
      diskIo = diskIo.map(traffic(_, prev.disk)),
      pressure = pressure,
      procsTotal = procs.size,
      servicesRunning = r.unitDirs.size,
      inventory = r.inventory.map(inventory),
      system = SystemInfo(r.nixosVersion.flatMap(nixos), r.profileLink.flatMap(generation)),
      domains = probe.flatMap(p => p.ts.map(Domains(_, p.sites))),
      repo = probe.flatMap(_.commits).map(RepoCommits(config.repo, _)),
      topMem = top(_.rss),
      topCpu = top(_.cpu),
      units = services.sortWith((a, b) => a.ratio > b.ratio || (a.ratio == b.ratio && a.order < b.order)).take(TopUnits),
      counters = Counters(up, KernelCounters(kernel.ctxt, kernel.processes), net, diskIo,
        cpuNames.map(n => n -> cpuNow(n)), procs.map(p => p.pid -> ProcTicks(p.start, p.ticks))),
    )

  /** The counts of what this generation runs. Nix wrote the file, but each line is still checked:
    * a short lowercase key and a whole number, 24 lines at most, the first of a key wins.
    */
  def inventory(text: Array[String]): Vector[(String, String)] =
    text.map(fields).collect {
      case Array(k @ InventoryKey(), n) if k.length <= 24 && isDigits(n) && n.length <= 9 => (k, n)
    }.distinctBy(_._1).take(24).toVector

  /** The first line of the NixOS version file, when it looks like a version. */
  def nixos(text: String): Option[String] =
    Some(text.takeWhile(_ != '\n'))
      .filter(v => v.nonEmpty && v.length <= 64 && v.forall(c => isAsciiAlnum(c) || "._+-".contains(c)))

  /** The generation of the system profile's target, system-<n>-link: deploy-rs makes one on each
    * deploy that changes the system.
    */
  def generation(link: String): Option[String] =
    Some(link.substring(link.lastIndexOf('/') + 1).stripPrefix(GenerationLink).stripSuffix("-link"))
      .filter(g => isDigits(g) && g.length <= 9)
