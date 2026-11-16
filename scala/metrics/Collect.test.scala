package piabrota.metrics

import piabrota.lib.TestKit
import ProcTree.{firstSample, secondSample, Hostile, Later}

/** The collector against a fixture /proc (the old metrics/test/collect_test.py). */
class CollectTest extends munit.FunSuite:
  override def beforeAll(): Unit =
    assume(Host.clockTicks == 100 && Host.pageSize == 4096, "the fixtures assume CLK_TCK 100 and a 4096 byte page")

  private def nums(v: ujson.Value*): Seq[Double] = v.map(_.num)

  test("first run: nothing to compare with"):
    val t = ProcTree()
    firstSample(t)
    assert(t.run(), t.err)
    assert(t.valid)
    val d = t.data
    assertEquals(d("cpu")("warming").bool, true)
    assertEquals(nums(d("cpu")("total_pct"), d("cpu")("cores")(0)), Seq(0.0, 0.0))
    assertEquals(d("top_cpu").arr.map(_("cpu_pct").num).sum, 0.0)
    val rates = nums(d("tasks")("forks_per_s"), d("tasks")("ctxt_per_s"), d("net")("rx_bps"), d("net")("tx_bps"),
      d("disk_io")("read_bps"), d("disk_io")("write_bps"))
    assertEquals(rates, Seq.fill(6)(0.0))
    assert(os.size(t.st / "piabrota2.state") > 0)
    assertEquals((os.walk(t.out) ++ os.walk(t.st)).filter(_.last.endsWith(".tmp")).map(_.last), Seq.empty[String])
    assertEquals(os.perms(t.out / "piabrota2.json").toString, "rw-r--r--")

  test("second run, 10 s later: every number"):
    val t = ProcTree()
    firstSample(t)
    assert(t.run())
    secondSample(t)
    assert(t.run(), t.err)
    assert(t.valid)
    val d = t.data
    assertEquals(d("v").num, 1.0)
    assertEquals(d("host").str, "piabrota2")
    assertEquals(d("label").str, "piabrota2 (KVM 4)")
    assertEquals(d("interval").num, 10.0)
    assert(d("ts").num > 1700000000)
    assertEquals(d("uptime_s").num, 1010.0)
    assertEquals(d("vcpus").num, 2.0)
    assertEquals(d("load").arr.map(_.num).toSeq, Seq(0.5, 0.25, 0.1))
    assert(!d("cpu").obj.contains("warming"))
    assertEquals(d("cpu")("total_pct").num, 30.0)
    assertEquals(d("cpu")("cores").arr.map(_.num).toSeq, Seq(35.0, 25.0))
    assertEquals(nums(d("mem")("total"), d("mem")("used"), d("mem")("available")), Seq(8192000000.0, 5120000000.0, 3072000000.0))
    assertEquals(nums(d("mem")("swap_total"), d("mem")("swap_used")), Seq(1024000000.0, 614400000.0))
    assert(d("disk")("root_total").num > 0 && d("disk")("root_used").num > 0)
    assertEquals(d("mem_detail"), ujson.Obj("buffers" -> 10240000, "cached" -> 2048000000.0, "shmem" -> 51200000, "dirty" -> 307200))
    assertEquals(d("tasks"), ujson.Obj("threads" -> 345, "running" -> 3, "blocked" -> 1, "forks_per_s" -> 2, "ctxt_per_s" -> 500))
    assertEquals(d("fds_open").num, 1234.0)
    assertEquals(d("net"), ujson.Obj("rx_bps" -> 100000, "tx_bps" -> 10000, "rx_total" -> 2000000, "tx_total" -> 600000))
    assertEquals(d("sockets"), ujson.Obj("tcp" -> 7, "tcp_tw" -> 3, "udp" -> 4))
    assertEquals(d("disk_io"), ujson.Obj("read_bps" -> 10240, "write_bps" -> 102400, "read_total" -> 1126400, "write_total" -> 3072000))
    assertEquals(d("pressure"), ujson.Obj("cpu" -> ujson.Obj("some" -> 1.5, "full" -> 0), "memory" -> ujson.Obj("some" -> 0.25, "full" -> 0.1),
      "io" -> ujson.Obj("some" -> 4, "full" -> 3)))
    assertEquals(d("procs_total").num, 5.0, "procs_total skips the ones that ended")
    assertEquals(d("top_mem").arr.map(_("pid").num.toInt).toSeq, Seq(200, 100, 300, 500, 700))
    assertEquals(d("top_cpu").arr.map(_("pid").num.toInt).toSeq, Seq(200, 100, 700, 300, 500), "ties by pid")
    assertEquals(nums(d("top_cpu")(0)("cpu_pct"), d("top_cpu")(1)("cpu_pct")), Seq(30.0, 15.0))
    assertEquals(d("top_cpu")(2)("cpu_pct").num, 5.0, "a process that started in the window")
    assertEquals(d("top_mem")(0)("rss").num, 12288000.0)
    assertEquals(Seq(d("top_mem")(0)("user").str, d("top_mem")(1)("user").str), Seq("root", "alice"))
    assertEquals(d("top_mem")(2)("user").str, "4242", "an unknown uid stays a number")
    assertEquals(d("top_mem")(0)("name").str, "my proc (x)")
    assertEquals(d("top_mem")(2)("name").str, Hostile)
    assertEquals(d("top_mem")(3)("name").str, "nl?x")
    assertEquals(d("units").arr.map(_("unit").str).toSeq, Seq("c.service", "a.service"))
    assertEquals(d("units")(1), ujson.Obj("unit" -> "a.service", "mem" -> 500, "max" -> 1000, "peak" -> 700))
    assertEquals(d("units")(0), ujson.Obj("unit" -> "c.service", "mem" -> 1950, "max" -> 2000, "peak" -> 1990))
    assert(t.raw.length < 8192)
    assert(!t.raw.contains("/bin/") && !t.raw.contains("cmdline"))
    assertEquals(d("services_running").num, 4.0)
    assert(!d.obj.contains("inventory"))

  test("the inventory keeps the good lines, 24 at most"):
    val t = ProcTree()
    firstSample(t)
    val inv = t.work / "inventory"
    t.opts = Map("inv" -> inv.toString)
    // To drop: a quote, a capital, a negative, a fraction, three fields, a key too long, a number
    // too long, a repeated key, an empty line.
    os.write(inv, "apps 1\nsites 7\nskills 120\n" +
      s"x\"y 1\nApps 2\nrigs -1\nmcp 1.5\nplugins 1 2\n${"a" * 25} 1\ntimers 1234567890\napps 9\n\n")
    assert(t.run())
    assert(t.valid)
    assertEquals(t.data("inventory"), ujson.Obj("apps" -> 1, "sites" -> 7, "skills" -> 120))
    os.write.over(inv, (0 until 30).map(i => s"k${i.toString.map(c => ('a' + (c - '0')).toChar)} 1\n").mkString)
    assert(t.run())
    assertEquals(t.data("inventory").obj.size, 24)
    os.write.over(inv, "")
    assert(t.run())
    assertEquals(t.data("inventory"), ujson.Obj())
    t.opts = Map("inv" -> (t.work / "nope").toString)
    assert(t.run())
    assertEquals(t.data("inventory"), ujson.Obj(), "a missing inventory file is an empty object")

  test("the system, the probe file and the repository"):
    val t = ProcTree()
    firstSample(t)
    assert(t.run())
    assertEquals(t.data("system"), ujson.Obj())
    assert(!t.data.obj.contains("domains") && !t.data.obj.contains("repo"))
    os.symlink(t.work / "system", os.RelPath("system-42-link"))
    os.write(t.work / "nixos-version", "26.05.20261101.abcdef0")
    val probe = t.work / "probe"
    t.opts = Map("profile" -> (t.work / "system").toString, "nver" -> (t.work / "nixos-version").toString,
      "probe" -> probe.toString, "repo" -> "piabrota/nix-os")
    os.write(probe, "ts 1700000000\ndomain www.piabrota.art 200\ndomain metrics.piabrota.art 401\n" +
      "domain down.piabrota.art 000\ndomain bad.piabrota.art 502\ndomain B\"x 200\ndomain long 2000\n" +
      "repo 230 1699999000\nrepo x 1\n")
    assert(t.run())
    assert(t.valid)
    val d = t.data
    assertEquals(d("system"), ujson.Obj("nixos" -> "26.05.20261101.abcdef0", "generation" -> 42))
    assertEquals(d("domains")("list").arr.map(x => (x("name").str, x("code").num.toInt, x("up").bool)).toSeq,
      Seq(("www.piabrota.art", 200, true), ("metrics.piabrota.art", 401, true), ("down.piabrota.art", 0, false),
        ("bad.piabrota.art", 502, false)))
    assertEquals(nums(d("domains")("ts"), d("domains")("up"), d("domains")("total")), Seq(1700000000.0, 2.0, 4.0))
    assertEquals(d("repo"), ujson.Obj("name" -> "piabrota/nix-os", "commits" -> 230, "ts" -> 1699999000))
    assertEquals(d("uptime_s").num, 1000.0, "the sites leave the uptime as it was")

    os.write.over(t.work / "nixos-version", "not a \"version\"")
    os.remove(t.work / "system")
    os.symlink(t.work / "system", os.RelPath("system-x-link"))
    os.write.over(probe, (0 until 30).map(i => s"domain d$i.example 200\n").mkString + "ts 1700000000\n")
    assert(t.run())
    assertEquals(t.data("system"), ujson.Obj(), "a bad version and a bad generation are left out")
    assertEquals(t.data("domains")("total").num, 24.0)
    assert(!t.data.obj.contains("repo"))
    t.opts = t.opts + ("probe" -> (t.work / "nope").toString)
    assert(t.run())
    assert(!t.data.obj.contains("domains"))

  test("the caps: 10 processes in each list, 12 units"):
    val t = ProcTree()
    firstSample(t)
    assert(t.run())
    (1000 until 1030).foreach { i =>
      t.procAdd(i, s"p$i", 1, 0, 50, i - 900, 1000)
      t.cgAdd(s"u$i.service", "100", i - 900)
    }
    t.sysAdd("1020.00", Later*)
    assert(t.run())
    assertEquals(Seq(t.data("top_mem").arr.size, t.data("top_cpu").arr.size), Seq(10, 10))
    assertEquals(t.data("units").arr.size, 12)
    assert(os.size(t.out / "piabrota2.json") < 8192)

  test("a process that cannot be read, and a missing cgroup tree"):
    val t = ProcTree()
    firstSample(t)
    assert(t.run())
    if sys.props.get("user.name").forall(_ != "root") && !os.read.lines(os.Path("/proc/self/status")).exists(_.matches("Uid:\\s+0\\s.*")) then
      t.procAdd(800, "locked", 1, 0, 60, 100, 1000)
      os.perms.set(t.proc / "800" / "stat", "---------")
      t.sysAdd("1030.00", Later*)
      assert(t.run())
      assert(!t.data("top_mem").arr.exists(_("pid").num == 800))
      assertEquals(t.err, "")
      os.perms.set(t.proc / "800" / "stat", "rw-r--r--")
    t.sysAdd("1040.00", Later*)
    t.cgroupRoot = t.work / "none"
    assert(t.run())
    assertEquals(t.data("units"), ujson.Arr())
    assert(t.valid)
    assertEquals(t.err, "")

  test("a clock that went back or a garbled state counts as a first run"):
    val t = ProcTree()
    firstSample(t)
    os.write(t.st / "piabrota2.state", "garbage\nT notanumber\n")
    assert(t.run())
    assert(t.valid)
    t.sysAdd("10.00", Later*)
    os.write.over(t.st / "piabrota2.state", "T 5000\n")
    assert(t.run())
    assertEquals(t.data("cpu")("warming").bool, true)

  test("a bad or missing name is refused"):
    val r = TestKit.piabrota(Seq("metrics-collect"), Map("METRICS_NAME" -> "../x"))
    assertEquals(r.exitCode, 2)
    assertEquals(r.err.text().trim, "collect: bad METRICS_NAME")
    assertEquals(TestKit.piabrota(Seq("metrics-collect")).exitCode, 1)

  // The old suite proved its escaper checks could fail by breaking the awk; these unit tests
  // pin the escaper and the number formats instead.
  test("the escaper: printable ASCII, a backslash and a quote escaped"):
    assertEquals(Awk.esc("a\"b\\c\né"), "a\\\"b\\\\c??")
    assert(ujson.read("\"" + Awk.esc(Hostile) + "\"").str == Hostile)

  test("printf's numbers: half to even, as C rounds"):
    assertEquals(Awk.fixed(0.5, 0), "0")
    assertEquals(Awk.fixed(1.5, 0), "2")
    assertEquals(Awk.fixed(0.25, 1), "0.2")
    assertEquals(Awk.fixed(-3.0, 0), "-3")
    assertEquals(Awk.fixed(30.0, 1), "30.0")
    assertEquals(Awk.int(345.9), "345")
    assertEquals(Awk.num("  12abc"), 12.0)
    assertEquals(Awk.num("1.23457e+06"), 1234570.0)
    assertEquals(Awk.num("x"), 0.0)
