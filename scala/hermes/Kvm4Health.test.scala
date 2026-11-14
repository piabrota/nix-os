package piabrota.hermes

import piabrota.lib.{Sh, TestKit}

/** kvm4-health with a stub journalctl and systemctl. The other thresholds are set so that this
  * machine's own memory, load and disk cannot warn: the exit status then belongs to the stubs alone.
  */
class Kvm4HealthTest extends munit.FunSuite:
  // journalctl prints JOURNAL_USAGE for --disk-usage, as journald does, and no kernel lines.
  private val journalctl = """#!/bin/sh
for arg in "$@"; do
  if [ "$arg" = --disk-usage ]; then
    echo "Archived and active journals take up $JOURNAL_USAGE in the file system."
  fi
done
exit 0
"""
  // No unit is loaded and none has failed, as on piabrota (KVM 1).
  private val fakes = TestKit.fakes("journalctl" -> journalctl, "systemctl" -> "#!/bin/sh\nexit 0\n")
  private val quiet = Map(
    "KH_MEMAVAIL_WARN" -> "0", "KH_MEMAVAIL_CRIT" -> "0", "KH_SWAP_WARN" -> "101",
    "KH_PSI_MEM_WARN" -> "100000", "KH_PSI_IO_WARN" -> "100000", "KH_LOAD_WARN" -> "100000",
    "KH_DISK_WARN" -> "101", "KH_DISK_CRIT" -> "101", "KH_DISK_GROWTH_GIB" -> "100000",
  )

  private def health(usage: String, args: Seq[String] = Nil, home: os.Path = os.temp.dir()): os.CommandResult =
    TestKit.piabrota("kvm4-health" +: args,
      env = quiet ++ Map("HERMES_HOME" -> home.toString, "JOURNAL_USAGE" -> usage), fakes = Some(fakes))

  private def journalLine(r: os.CommandResult): String =
    r.out.text().linesIterator.find(_.matches("^(ok|WARN|CRIT) +journal.*")).getOrElse("").replaceAll(" +", " ")

  for (usage, line, code) <- List(
      // A journal that journald keeps within its own 200 MiB cap is healthy.
      ("182.3M", "ok journal 182.3MiB", 0),
      ("200.0M", "ok journal 200.0MiB", 0),
      // A journal above the cap is the finding.
      ("230.1M", "WARN journal 230.1MiB", 1),
      ("1.2G", "WARN journal 1.2G (journald keeps 200 MiB)", 1),
    )
  do
    test(s"a journal of $usage"):
      val r = health(usage)
      assertEquals(journalLine(r), line, r.out.text())
      assertEquals(r.exitCode, code, r.out.text())

  test("on a box with none of the Hermes units the units section has no unit line and no finding"):
    val r = health("100.0M")
    val lines = r.out.text().linesIterator.toList
    val units = lines.dropWhile(_ != "== units").takeWhile(_ != "== disk")
    assert(!units.exists(_.matches("^(ok|WARN|CRIT) +(hermes|pgx|openrig|user-).*")), units.mkString("\n"))
    assertEquals(lines.count(l => l.startsWith("ok ") && l.contains("no failed unit")), 1)
    assert(lines.head.startsWith(s"kvm4-health on ${Sh.out("uname", "-n")} at "), lines.head)
    assertEquals(lines.last, "kvm4-health: healthy")

  test("--alert speaks once for a finding, then is quiet, then says healthy again; --record keeps a sample"):
    val home = os.temp.dir()
    val first = health("1.2G", Seq("--alert", "--record"), home)
    assertEquals(first.exitCode, 0)
    assertEquals(first.out.text().linesIterator.toList,
      List(s"kvm4-health: 1 finding(s) on ${Sh.out("uname", "-n")}", "WARN  journal 1.2G (journald keeps 200 MiB)",
        "Ask for /kvm4-health for the full report."))
    assertEquals(health("1.2G", Seq("--alert"), home).out.text(), "")
    assertEquals(health("100.0M", Seq("--alert"), home).out.text(), s"kvm4 is healthy again (${Sh.out("uname", "-n")}).\n")
    assertEquals(health("100.0M", Seq("--alert"), home).out.text(), "")
    val samples = os.read.lines(home / "plugin-data" / "kvm4-health" / "samples.tsv")
    assertEquals(samples.length, 1)
    assertEquals(samples.head.split('\t').length, 5)

  test("an unknown argument is a usage error"):
    val r = TestKit.piabrota(Seq("kvm4-health", "--nope"))
    assertEquals(r.exitCode, 2)
    assertEquals(r.err.text(), "usage: kvm4-health [--alert] [--record]\n")

  test("cfmt rounds as C's printf does"):
    assertEquals(Util.cfmt(0.5, 0), "0")
    assertEquals(Util.cfmt(1.5, 0), "2")
    assertEquals(Util.cfmt(2.5, 0), "2")
    assertEquals(Util.cfmt(-0.3, 0), "-0")
    assertEquals(Util.cfmt(1.25, 1), "1.2")
    assertEquals(Util.cfmt(1073741824.0 * 1.5 / 1073741824, 1), "1.5")
