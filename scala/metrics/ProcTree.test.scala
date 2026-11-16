package piabrota.metrics

import piabrota.lib.TestKit

/** A fixture tree for /proc, /sys/fs/cgroup and /etc/passwd, and the runs of the collector against
  * it: the old metrics/test/collect_test.py's `Suite`.
  */
final class ProcTree:
  val work: os.Path = os.temp.dir(prefix = "metrics")
  val proc: os.Path = work / "proc"
  val cg: os.Path = work / "cg"
  val out: os.Path = work / "out"
  val st: os.Path = work / "st"
  os.makeDir.all(proc)
  os.makeDir.all(out)
  os.makeDir.all(st)
  os.write(work / "passwd", "root:x:0:0::/root:/bin/sh\nalice:x:1000:100::/home/alice:/bin/sh\n")
  /** Inventory, probe file, repository, profile, NixOS version. */
  var opts: Map[String, String] = Map.empty
  var cgroupRoot: os.Path = cg
  var err: String = ""

  /** `piabrota metrics-collect` on the tree; true when it exits 0. */
  def run(extra: Map[String, String] = Map.empty): Boolean =
    val none = (work / "none").toString
    val env = Map(
      "METRICS_NAME" -> "piabrota2",
      "METRICS_LABEL" -> "piabrota2 (KVM 4)",
      "OUT_DIR" -> out.toString,
      "STATE_DIR" -> st.toString,
      "METRICS_INVENTORY" -> opts.getOrElse("inv", ""),
      "METRICS_PROBE" -> opts.getOrElse("probe", ""),
      "METRICS_REPO" -> opts.getOrElse("repo", ""),
      "SYSTEM_PROFILE" -> opts.getOrElse("profile", none),
      "NIXOS_VERSION_FILE" -> opts.getOrElse("nver", none),
      "PROC_ROOT" -> proc.toString,
      "CGROUP_ROOT" -> cgroupRoot.toString,
      "PASSWD_FILE" -> (work / "passwd").toString,
    ) ++ extra
    val r = TestKit.piabrota(Seq("metrics-collect"), env)
    err = r.err.text()
    r.exitCode == 0

  def raw: String = os.read(out / "piabrota2.json")
  def data: ujson.Value = ujson.read(raw)
  def valid: Boolean =
    try { ujson.read(raw); true }
    catch case _: ujson.ParseException => false

  def procAdd(pid: Int, comm: String, utime: Int, stime: Int, start: Int, rss: Int, uid: Int): Unit =
    val d = proc / pid.toString
    os.makeDir.all(d)
    os.write.over(d / "stat",
      s"$pid ($comm) S 1 $pid $pid 0 -1 4194560 100 0 0 0 $utime $stime 0 0 20 0 1 0 $start 1000000 " +
        s"$rss 18446744073709551615 1 1 0 0 0 0 0 0 0 0 0 0 17 0 0 0 0 0 0\n")
    os.write.over(d / "statm", s"5000 $rss 100 10 0 100 0\n")
    os.write.over(d / "status", s"Name:\tx\nUid:\t$uid\t$uid\t$uid\t$uid\n")

  /** The uptime, then user system idle iowait for all, cpu0 and cpu1 (nice is 0). */
  def sysAdd(uptime: String, cpu: Int*): Unit =
    os.write.over(proc / "uptime", s"$uptime 5000.00\n")
    os.write.over(proc / "loadavg", "0.50 0.25 0.10 1/100 999\n")
    os.write.over(proc / "meminfo",
      "MemTotal:        8000000 kB\nMemFree:          100000 kB\nMemAvailable:    3000000 kB\n" +
        "SwapTotal:       1000000 kB\nSwapFree:         400000 kB\n")
    val rows = List("cpu ", "cpu0", "cpu1").zip(cpu.grouped(4).toList).map { (n, c) =>
      s"$n ${c(0)} 0 ${c(1)} ${c(2)} ${c(3)} 0 0 0 0 0\n"
    }
    os.write.over(proc / "stat", rows.mkString + "intr 1\n")

  /** The counters of one sample, after sysAdd. The network is PID 1's; sda1 and lo do not count. */
  def ioAdd(ctxt: Int, forks: Int, rx: Int, tx: Int, sread: Int, swrite: Int): Unit =
    os.write.append(proc / "stat", s"ctxt $ctxt\nprocesses $forks\nprocs_running 3\nprocs_blocked 1\n")
    os.write.over(proc / "meminfo",
      "MemTotal:        8000000 kB\nMemFree:          100000 kB\nMemAvailable:    3000000 kB\n" +
        "Buffers:           10000 kB\nCached:          2000000 kB\nSwapTotal:       1000000 kB\n" +
        "SwapFree:         400000 kB\nShmem:             50000 kB\nDirty:               300 kB\n")
    os.write.over(proc / "loadavg", "0.50 0.25 0.10 2/345 999\n")
    os.write.over(proc / "1" / "net" / "dev",
      "Inter-|   Receive                            |  Transmit\n" +
        " face |bytes packets errs drop fifo frame compressed multicast|bytes packets errs drop fifo colls carrier compressed\n" +
        "    lo: 99999 9 0 0 0 0 0 0 99999 9 0 0 0 0 0 0\n" +
        s"  eth0: $rx 10 0 0 0 0 0 0 $tx 10 0 0 0 0 0 0\n", createFolders = true)
    os.write.over(proc / "1" / "net" / "sockstat",
      "sockets: used 40\nTCP: inuse 7 orphan 0 tw 3 alloc 9 mem 2\nUDP: inuse 4 mem 1\n")
    os.write.over(proc / "diskstats",
      s"   8       0 sda 100 0 $sread 50 200 0 $swrite 60 0 70 110\n" +
        s"   8       1 sda1 100 0 $sread 50 200 0 $swrite 60 0 70 110\n" +
        "   7       0 loop0 1 0 999 1 0 0 999 0 0 1 1\n")
    os.write.over(proc / "sys" / "fs" / "file-nr", "1234\t0\t9223372036854775807\n", createFolders = true)
    os.write.over(proc / "pressure" / "cpu",
      "some avg10=1.50 avg60=1.00 avg300=0.50 total=100\nfull avg10=0.00 avg60=0.00 avg300=0.00 total=0\n",
      createFolders = true)
    os.write.over(proc / "pressure" / "memory",
      "some avg10=0.25 avg60=0.10 avg300=0.00 total=10\nfull avg10=0.10 avg60=0.00 avg300=0.00 total=5\n")
    os.write.over(proc / "pressure" / "io",
      "some avg10=4.00 avg60=2.00 avg300=1.00 total=900\nfull avg10=3.00 avg60=1.00 avg300=0.50 total=800\n")

  def cgAdd(unit: String, max: String, cur: Int, peak: Option[Int] = None): Unit =
    val d = cg / "system.slice" / unit
    os.makeDir.all(d)
    os.write.over(d / "memory.max", s"$max\n")
    os.write.over(d / "memory.current", s"$cur\n")
    peak.foreach(p => os.write.over(d / "memory.peak", s"$p\n"))

object ProcTree:
  val Later: Seq[Int] = Seq(1500, 600, 9300, 600, 800, 300, 4600, 300, 700, 300, 4700, 300)
  val Hostile = "a\"b\\c</scr<img>"

  /** Sample 1 at uptime 1000 s: cpu0 and cpu1 each 500/250 user/system, 4000 idle, 250 iowait; four
    * processes, two that cannot be read, units with and without a limit.
    */
  def firstSample(t: ProcTree): Unit =
    t.sysAdd("1000.00", 1000, 500, 8000, 500, 500, 250, 4000, 250, 500, 250, 4000, 250)
    t.ioAdd(10000, 500, 1000000, 500000, 2000, 4000)
    t.procAdd(100, "alpha", 100, 50, 10, 1000, 1000)
    t.procAdd(200, "my proc (x)", 10, 0, 20, 3000, 0)
    t.procAdd(300, Hostile, 5, 0, 30, 500, 4242)
    t.procAdd(500, "nl\nx", 1, 0, 40, 100, 1000)
    os.makeDir(t.proc / "400") // a process that ended while it was read: no files
    os.makeDir(t.proc / "600")
    os.write(t.proc / "600" / "stat", "") // an empty stat
    os.makeDir(t.proc / "self")
    t.cgAdd("a.service", "1000", 500, Some(700))
    t.cgAdd("b.service", "max", 900)
    t.cgAdd("c.service", "2000", 1900)
    os.makeDir(t.cg / "system.slice" / "d.service") // no memory.max at all
    os.makeDir(t.cg / "system.slice" / "sub.slice") // not a service

  /** Sample 2, 10 s later, with a process that started in the window. */
  def secondSample(t: ProcTree): Unit =
    t.sysAdd("1010.00", Later*)
    t.ioAdd(15000, 520, 2000000, 600000, 2200, 6000)
    t.procAdd(100, "alpha", 200, 100, 10, 1000, 1000)
    t.procAdd(200, "my proc (x)", 310, 0, 20, 3000, 0)
    t.procAdd(300, Hostile, 5, 0, 30, 500, 4242)
    t.procAdd(500, "nl\nx", 1, 0, 40, 100, 1000)
    t.procAdd(700, "newbie", 50, 0, 100550, 50, 1000) // started at 1005.5 s
    t.cgAdd("c.service", "2000", 1950, Some(1990))
