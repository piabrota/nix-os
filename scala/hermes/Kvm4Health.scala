package piabrota.hermes

import piabrota.lib.{Sh, die, env}
import Util.{awkNum, cfmt, count as num}
import Level.{Crit, Ok, Warn}

/** `kvm4-health [--alert] [--record]`: the health of kvm4 and of the Hermes units: memory, swap,
  * pressure, load, disk, the journal, and for each unit its memory now, its peak against its
  * MemoryMax, its tasks and its restarts (NRestarts, where a restart loop shows). Read-only on the
  * system: it reads /proc, `systemctl show`, `df`, `du` and the journal, and changes nothing.
  *
  *   kvm4-health            the full report; exit 1 when a line is WARN or CRIT
  *   kvm4-health --alert    only the findings, and only when they change or every 6 h; prints
  *                          nothing when healthy (a no_agent cron job: empty output is silent)
  *   kvm4-health --record   also appends one sample, for growth per day (only the hermes user,
  *                          in HERMES_HOME/plugin-data/kvm4-health)
  *
  * Thresholds are environment variables (KH_*, in `Limits`). The plan's figures: 4 vCPU, 16 GB RAM,
  * 200 GB disk (AGENTS.md, "Resource budget"); it reads the real ones. Hermes runs it from the
  * kvm4-health skill and from the watchdog cron job.
  */
object Kvm4Health:
  private val GiB = 1073741824L

  def run(args: List[String]): Int =
    val mode = HealthMode.parse(args).getOrElse(die("usage: kvm4-health [--alert] [--record]", 2))
    Report(HealthConfig.read(mode, env)).run()

  /** `[ "$a" -lt "$b" ]` and its kin: false when either side is not an integer. */
  private def cmp(a: String, b: String)(op: (Long, Long) => Boolean): Boolean =
    (a.trim.toLongOption, b.trim.toLongOption) match
      case (Some(x), Some(y)) => op(x, y)
      case _                  => false

  /** awk's `a > b` on numbers. */
  private def gt(a: String, b: String): Boolean = awkNum(a) > awkNum(b)

  /** Bytes as MiB or GiB. */
  private def human(bytes: Double): String =
    if bytes >= GiB then cfmt(bytes / GiB, 1) + " GiB" else cfmt(bytes / 1048576, 0) + " MiB"
  private def human(bytes: String): String = human(awkNum(bytes))

  /** a as a percentage of b, rounded; 0 when b is 0. */
  private def pct(a: Double, b: Double): String = if b > 0 then cfmt(100 * a / b, 0) else "0"

  /** GiB, from a threshold's text; 0 when it is not an integer. */
  private def gib(limit: String): Long = limit.toLongOption.getOrElse(0L) * GiB

  private final class Report(cfg: HealthConfig):
    import cfg.{home, limits, state}
    private val alert = cfg.mode.alert
    // The findings so far, in the order of the report.
    private var findings = Vector.empty[Finding]
    private val now = System.currentTimeMillis() / 1000
    private val cores = Sh.outOpt("nproc").getOrElse("1")
    private val hasJournal = Sh.which("journalctl").isDefined

    private def out(line: String): Unit = if !alert then println(line)
    private def flag(level: Level, key: String, text: String): Unit =
      val f = Finding(level, key, text)
      findings :+= f
      out(f.line)
    private def ok(text: String): Unit = out(Ok.line(text))
    private def section(name: String): Unit = { out(""); out(s"== $name") }
    private def findingsText: String = findings.map(_.line + "\n").mkString

    private def meminfo(key: String): String =
      readable(os.Path("/proc/meminfo")).flatMap(_.linesIterator.map(_.trim.split("\\s+"))
        .collectFirst { case Array(k, v, _*) if k == s"$key:" => cfmt(awkNum(v) * 1024, 0) }).getOrElse("")
    private def psi(resource: String): String =
      readable(os.Path(s"/proc/pressure/$resource")).flatMap(_.linesIterator.map(_.trim.split("\\s+"))
        .collectFirst { case f if f(0) == "some" && f.length >= 3 => f(2).replace("avg60=", "") }).getOrElse("")
    private def prop(unit: String, name: String): String =
      Sh.outOpt("systemctl", "show", unit, "-p", name, "--value").getOrElse("")
    private def readable(p: os.Path): Option[String] =
      Option.when(os.isFile(p) && p.toIO.canRead)(os.read(p))

    def run(): Int =
      val host = Sh.out("uname", "-n")
      out(s"kvm4-health on $host at ${Sh.out("date", "+%Y-%m-%d %H:%M %Z")}, $cores cores")
      memory()
      cpu()
      val agent = unitsSection()
      val rootUsed = disk()
      growth(agent, rootUsed)
      val samples = state / Sample.File
      if cfg.mode.record && scala.util.Try(os.makeDir.all(state)).isSuccess && state.toIO.canWrite then
        os.write.append(samples, Sample(now, agent, rootUsed).render)
        os.write.over(samples, Util.tailFile(os.read(samples), Sample.Keep))
      if !alert then
        if findings.isEmpty then { print("\nkvm4-health: healthy\n"); 0 }
        else { print(s"\nkvm4-health: ${findings.length} finding(s)\n"); 1 }
      else alertOnChange(host)

    private def memory(): Unit =
      section("memory")
      val total = meminfo("MemTotal")
      val avail = meminfo("MemAvailable")
      val p = pct(awkNum(avail), awkNum(total))
      val line = s"RAM available ${human(avail)} of ${human(total)} ($p %)"
      if cmp(p, limits.memAvailCrit)(_ < _) then flag(Crit, "mem-avail", line)
      else if cmp(p, limits.memAvailWarn)(_ < _) then flag(Warn, "mem-avail", line)
      else ok(line)
      val swapTotal = num(meminfo("SwapTotal"))
      val swapUsed = swapTotal - num(meminfo("SwapFree"))
      if swapTotal > 0 then
        val p = pct(swapUsed.toDouble, swapTotal.toDouble)
        val line = s"swap used ${human(swapUsed.toDouble)} of ${human(swapTotal.toDouble)} ($p %)"
        if cmp(p, limits.swapWarn)(_ >= _) then flag(Warn, "swap", line) else ok(line)
      val v = psi("memory")
      if v.nonEmpty then
        val line = s"memory pressure $v % (some, avg60)"
        if gt(v, limits.psiMemWarn) then flag(Warn, "psi-mem", line) else ok(line)
      if hasJournal then
        val kernel = Sh.call("journalctl", "-k", "--since", "-24h", "-o", "cat", "--no-pager").out.text()
        val n = kernel.linesIterator.count(l => l.toLowerCase.contains("out of memory") || l.toLowerCase.contains("oom-kill"))
        if n > 0 then flag(Warn, "oom", s"$n OOM kill lines in the kernel log in 24 h")
        else ok("no OOM kill in 24 h")

    private def cpu(): Unit =
      section("cpu")
      val load = readable(os.Path("/proc/loadavg")).getOrElse("").trim.split("\\s+")
      val Array(l1, l5, l15) = load.padTo(3, "").take(3): @unchecked
      val per = cfmt(awkNum(l15) / awkNum(cores), 2)
      val line = s"load $l1 $l5 $l15 (15 min: $per per core)"
      if gt(per, limits.loadWarn) then flag(Warn, "load", line) else ok(line)
      for r <- List("cpu", "io") do
        val v = psi(r)
        if v.nonEmpty then
          if r == "io" && gt(v, limits.psiIoWarn) then flag(Warn, "psi-io", s"I/O pressure $v % (some, avg60)")
          else ok(s"$r pressure $v % (some, avg60)")

    private def unitsSection(): AgentSample =
      section("units")
      // A unit that is not loaded is skipped: piabrota (KVM 1) has none of them. The slice of the
      // hermes user's cron workers exists only where that user does.
      val slice = Sh.outOpt("id", "-u", HealthUnits.HermesUser).map(uid => s"user-$uid.slice")
      val agents = for u <- HealthUnits.All ++ slice if prop(u, "LoadState") == "loaded" yield unit(u)
      val failed = Sh.outOpt("systemctl", "--failed", "--plain", "--no-legend").getOrElse("")
        .linesIterator.map(_.trim.split("\\s+").headOption.getOrElse("") + " ").mkString
      if failed.nonEmpty then flag(Warn, "failed", s"failed units: $failed") else ok("no failed unit")
      agents.flatten.lastOption.getOrElse(AgentSample())

    /** The lines of one loaded unit; hermes-agent's sample when it is that unit. */
    private def unit(u: String): Option[AgentSample] =
      val active = prop(u, "ActiveState")
      val cur = num(prop(u, "MemoryCurrent"))
      val peak = num(prop(u, "MemoryPeak"))
      val max = prop(u, "MemoryMax")
      val tasks = num(prop(u, "TasksCurrent"))
      val restarts = num(prop(u, "NRestarts"))
      val agent = Option.when(u == HealthUnits.Agent)(AgentSample(cur.toString, num(prop(u, "CPUUsageNSec")).toString,
        num(prop(u, "ActiveEnterTimestampMonotonic")).toString))
      val cronWorkers = u.startsWith("user-")
      val name = if cronWorkers then s"$u (cron workers)" else u
      if cmp(restarts.toString, limits.restartsCrit)(_ > _) then
        flag(Crit, s"restarts-crit-$u", s"$u restarted $restarts times since it started")
      else if cmp(restarts.toString, limits.restartsWarn)(_ > _) then
        flag(Warn, s"restarts-$u", s"$u restarted $restarts times since it started")
      if active != "active" then
        if !cronWorkers then flag(Warn, s"down-$u", s"$name is $active")
      else if max.isEmpty || max == "infinity" then
        val line = s"$name: ${human(cur.toDouble)} now, peak ${human(peak.toDouble)}, no MemoryMax, $tasks tasks, $restarts restarts"
        if cur > gib(limits.unitNoMaxGib) then flag(Warn, s"mem-$u", line) else ok(line)
      else
        val pc = pct(cur.toDouble, awkNum(max))
        val pp = pct(peak.toDouble, awkNum(max))
        val line = s"$name: ${human(cur.toDouble)} now ($pc %), peak ${human(peak.toDouble)} ($pp %) of ${human(max)}, $tasks tasks, $restarts restarts"
        if cmp(pc, limits.unitMemWarn)(_ >= _) then flag(Warn, s"mem-$u", line)
        else if cmp(pp, limits.unitPeakWarn)(_ >= _) then flag(Warn, s"peak-$u", s"$line (the peak was near the limit)")
        else ok(line)
      agent

    /** The disk section; the bytes used on /. */
    private def disk(): Long =
      section("disk")
      val fields = Sh.out("df", "-P", "-B1", "/").linesIterator.drop(1).nextOption().getOrElse("").trim.split("\\s+")
      if fields.length < 4 then die("kvm4-health: df -P -B1 / gave no sizes")
      val Array(size, used, avail) = fields.slice(1, 4).map(_.toLongOption.getOrElse(0L)): @unchecked
      val p = pct(used.toDouble, size.toDouble)
      val line = s"/ used ${human(used.toDouble)} of ${human(size.toDouble)} ($p %), ${human(avail.toDouble)} free"
      if cmp(p, limits.diskCrit)(_ >= _) then flag(Crit, "disk", line)
      else if cmp(p, limits.diskWarn)(_ >= _) then flag(Warn, "disk", line)
      else ok(line)
      if hasJournal then
        val usage = Sh.outOpt("journalctl", "--disk-usage").getOrElse("")
        "[0-9.]+[KMGT]".r.findFirstIn(usage).foreach { j =>
          if j.endsWith("G") || j.endsWith("T") then flag(Warn, "journal", s"journal $j (journald keeps 200 MiB)")
          else if j.endsWith("M") then
            if gt(j.stripSuffix("M"), limits.journalMib) then flag(Warn, "journal", s"journal ${j}iB")
            else ok(s"journal ${j}iB")
          else ok(s"journal $j")
        }
      if !alert && os.exists(home) && home.toIO.canRead then
        def size(dir: os.Path, label: String): Unit =
          val k = Sh.outOpt("du", "-sxk", dir.toString).flatMap(_.split("\\s+").headOption).getOrElse("")
          out(f"      $label%-16s ${human(num(k) * 1024.0)}")
        for d <- List("state.db", "sessions", "logs", "plugin-data", "cache", "skills")
          if os.exists(home / d) do size(home / d, d)
        for d <- List("/var/lib/hermes/workspace", "/var/lib/pgx").map(os.Path(_))
          if os.exists(d) && d.toIO.canRead do size(d, d.last)
      used

    /** Growth: against the oldest sample of the last 24 h (one sample every 30 min from the cron job). */
    private def growth(agent: AgentSample, rootUsed: Long): Unit =
      readable(state / Sample.File).foreach { text =>
        section("growth")
        val lines = text.linesIterator.toList
        val first = lines.find(l => awkNum(l.split("\t", -1)(0)) >= now - 86400).map(fields)
        first.filter(f => f.length >= 5 && f(0).toLongOption.exists(now - _ >= 21600)) match
          case Some(f) =>
            val age = now - f(0).toLong
            val rate = cfmt((rootUsed - awkNum(f(3))) * 86400 / age / GiB, 2)
            val line = s"/ grows $rate GiB a day (over ${age / 3600} h)"
            if gt(rate, limits.diskGrowthGib) then flag(Warn, "disk-growth", line) else ok(line)
            if f(1) == agent.start && agent.start != "0" then
              val grew = agent.mem.toLong - f(2).toLongOption.getOrElse(0L)
              val line = s"hermes-agent grew ${human(grew.toDouble)} in ${age / 3600} h with no restart"
              if grew > gib(limits.agentGrowthGib) then flag(Warn, "agent-growth", s"$line (a leak, or a cache that does not shrink)")
              else ok(line)
          case None => ok("less than 6 h of samples: no rate yet")
        lines.lastOption.map(fields).foreach { f =>
          if f.length >= 5 && agent.start != "0" && f(1) == agent.start && f(0).toLongOption.exists(now - _ > 0) then
            val c = cfmt((awkNum(agent.cpu) - awkNum(f(4))) / 1e9 / (now - f(0).toLong) * 100, 0)
            val line = s"hermes-agent used $c % of one core since the last sample"
            if cmp(c, limits.agentCpuWarn)(_ >= _) then flag(Warn, "agent-cpu", line) else ok(line)
        }
      }

    /** The fields of one sample, split on blanks as `set -- $line` splits them. */
    private def fields(line: String): Array[String] = line.trim.split("\\s+").filter(_.nonEmpty)

    /** --alert: speak when the set of findings changes, again after KH_REPEAT_HOURS, and once on recovery. */
    private def alertOnChange(host: String): Int =
      val last = state / AlertState.File
      val sig = Finding.signature(findings)
      val prev = readable(last).map(AlertState.parse).getOrElse(AlertState.none)
      def remember(s: String): Unit = if state.toIO.canWrite then os.write.over(last, AlertState(now, s).render)
      if findings.isEmpty then
        if prev.signature.exists(_ != ' ') then
          print(s"kvm4 is healthy again ($host).\n")
          remember("")
        0
      else if sig == prev.signature && now - prev.time < limits.repeatHours.toLongOption.getOrElse(0L) * 3600 then 0
      else
        print(s"kvm4-health: ${findings.length} finding(s) on $host\n$findingsText")
        print("Ask for /kvm4-health for the full report.\n")
        remember(sig)
        0
