package piabrota.metrics

import piabrota.lib.TestKit

/** The probe with a fake curl, its visits, and the collector reading its file (the old
  * metrics/test/collect_test.py's probe and visits parts).
  */
class ProbeTest extends munit.FunSuite:
  private val FakeCurl = """#!/bin/sh
for a; do url=$a; done
echo "$url" >> "$FAKE_LOG"
case $url in
  */commits\?*) [ -n "$FAKE_LINK" ] || exit 7; printf 'HTTP/2 200\r\nlink: %s\r\n\r\n' "$FAKE_LINK" ;;
  https://up.example/) printf 200 ;;
  http://auth.example/) printf 401 ;;
  *) printf 000; exit 7 ;;
esac
"""
  private val Now = 1700000000L
  private val Link = """<https://api.test/x?page=999>; rel="last""""

  /** A work folder, the fake curl, the sites file and the runs of the probe. */
  private final class Setup:
    val work: os.Path = os.temp.dir(prefix = "probe")
    val pst: os.Path = work / "pst"
    val log: os.Path = work / "curl.log"
    val sites: os.Path = work / "sites"
    val fakes: os.Path = TestKit.fakes("curl" -> FakeCurl)
    os.write(log, "")
    os.write(sites, "up.example https://up.example/\nauth.example http://auth.example/\ndown.example https://down.example/\n" +
      "Bad.example https://x/\nno-url.example ftp://x/\n")
    var err = ""

    def run(link: String, every: String = "600", extra: Map[String, String] = Map.empty): Boolean =
      val r = TestKit.piabrota(Seq("metrics-probe"), Map(
        "FAKE_LOG" -> log.toString, "FAKE_LINK" -> link, "METRICS_NAME" -> "piabrota2", "STATE_DIR" -> pst.toString,
        "PROBE_SITES" -> sites.toString, "PROBE_REPO" -> "piabrota/nix-os", "GITHUB_API" -> "https://api.test",
        "PROBE_REPO_EVERY" -> every) ++ extra, fakes = Some(fakes))
      err = r.err.text()
      r.exitCode == 0

    def line(key: String): Seq[String] =
      os.read.lines(pst / "piabrota2.probe").filter(_.startsWith(s"$key ")).map(_.drop(key.length + 1)).toSeq

  test("a code for each site, and the commit count from GitHub at most every PROBE_REPO_EVERY"):
    val s = Setup()
    val last = """<https://api.test/repositories/1/commits?per_page=1&sha=main&page=2>; rel="next", """ +
      """<https://api.test/repositories/1/commits?per_page=1&sha=main&page=230>; rel="last""""
    assert(s.run(last), s.err)
    assertEquals(s.line("domain"), Seq("up.example 200", "auth.example 401", "down.example 000"))
    assertEquals(s.line("repo").head.split(' ').head, "230")
    assertEquals(os.read.lines(s.log).count(_.endsWith("api.test/repos/piabrota/nix-os/commits?per_page=1&sha=main")), 1)
    assert(s.run(Link))
    assertEquals(os.read.lines(s.log).count(_.contains("api.test")), 1, "not asked again")
    assertEquals(s.line("repo").head.split(' ').head, "230")
    s.run("", every = "0")
    assertEquals(s.line("repo").head.split(' ').head, "230", "a GitHub that does not answer keeps the old count")
    assertEquals(s.line("asked").size, 1)
    s.run(Link, every = "0")
    assertEquals(s.line("repo").head.split(' ').head, "999")
    assertEquals(s.err, "")

  test("the visits: 24 h of views and addresses for each site"):
    val s = Setup()
    val vlog = s.work / "visits.log"
    val vst = s.pst / "piabrota2.visits"
    def run(at: Long = Now) = s.run(Link, extra = Map("PROBE_VISITS_LOG" -> vlog.toString, "PROBE_NOW" -> at.toString))
    s.run(Link)
    assertEquals(s.line("visits"), Seq(), "no log, no visits")
    val cut = s"${Now - 30}.000 up.example 198.51.100"
    os.write(vlog, s"${Now - 100}.123 up.example 192.0.2.1\n${Now - 90}.001 up.example 192.0.2.1\n" +
      s"${Now - 80}.500 up.example 2001:db8::1\n${Now - 70}.000 auth.example 192.0.2.1\n" +
      s"${Now - 60}.000 _ 192.0.2.9\n${Now - 50}.000 other.example 192.0.2.9\n" +
      s"${Now - 90000}.000 up.example 192.0.2.7\ngarbage line\n${Now - 40}.000 up.example 192.0.2.1\"x\n" + cut)
    assert(run(), s.err)
    assertEquals(s.line("visits"), Seq("up.example 3 2", "auth.example 1 1", "down.example 0 0"))
    assertEquals(os.read.lines(vst).head.split(' ')(2), (os.size(vlog) - cut.length).toString,
      "a line nginx has not finished is not read")
    os.write.append(vlog, s".7\n${Now - 20}.000 up.example 192.0.2.1\n")
    assert(run(Now + 60))
    assertEquals(s.line("visits").head, "up.example 5 3", "the next run reads it, and counts nothing twice")
    os.remove(vlog)
    os.write(vlog, s"${Now + 100}.000 auth.example 203.0.113.5\n")
    assert(run(Now + 120))
    assertEquals(s.line("visits").take(2), Seq("up.example 5 3", "auth.example 2 2"), "a new file is read from its start")
    val later = Now + 86400 + 3600 + 200
    os.write.append(vlog, s"${later - 10}.000 auth.example 203.0.113.6\n")
    assert(run(later))
    assertEquals(s.line("visits").take(2), Seq("up.example 0 0", "auth.example 1 1"), "an hour older than 24 h goes")
    os.remove(vst)
    os.write.over(vlog, s"${Now - 100}.000 up.example 192.0.2.1\n${Now - 90}.000 up.example 192.0.2.2\n" +
      s"${Now - 80}.000 up.example 192.0.2.2\n${Now - 70}.000 up.example 192.0.2.3\n${Now - 60}.000 auth.example 192.0.2.1\n")
    assert(run())
    assertEquals(s.line("visits").take(2), Seq("up.example 4 3", "auth.example 1 1"), "a run with no state reads it all")
    os.perms.set(vlog, "---------")
    if !java.nio.file.Files.isReadable(vlog.toNIO) then
      run()
      assertEquals(s.line("visits"), Seq(), "an unreadable log gives no visits")
    os.perms.set(vlog, "rw-r--r--")
    assert(run())
    assertEquals(s.err, "")

  test("the collector shows what the probe found, with the sums of the visits"):
    val s = Setup()
    val vlog = s.work / "visits.log"
    os.write(vlog, s"${Now - 100}.000 up.example 192.0.2.1\n${Now - 90}.000 up.example 192.0.2.2\n" +
      s"${Now - 80}.000 up.example 192.0.2.2\n${Now - 70}.000 up.example 192.0.2.3\n${Now - 60}.000 auth.example 192.0.2.1\n")
    assert(s.run(Link, every = "0", extra = Map("PROBE_VISITS_LOG" -> vlog.toString, "PROBE_NOW" -> Now.toString)))
    val t = ProcTree()
    ProcTree.firstSample(t)
    t.opts = Map("probe" -> (s.pst / "piabrota2.probe").toString, "repo" -> "piabrota/nix-os")
    assert(t.run(), t.err)
    val d = t.data
    assertEquals(Seq(d("domains")("up").num, d("domains")("total").num, d("repo")("commits").num), Seq(2.0, 3.0, 999.0))
    assertEquals(d("domains")("list").arr.map(x => (x("name").str, x.obj.get("views").map(_.num), x.obj.get("visitors").map(_.num))).toSeq,
      Seq(("up.example", Some(4.0), Some(3.0)), ("auth.example", Some(1.0), Some(1.0)), ("down.example", Some(0.0), Some(0.0))))
    assertEquals(Seq(d("domains")("views").num, d("domains")("visitors").num), Seq(5.0, 4.0))
    assertEquals(os.list(t.out).filter(_.last.contains("probe")).map(_.last), Seq.empty[String], "the probe file is not in the served folder")

  test("a bad name exits 2"):
    val r = TestKit.piabrota(Seq("metrics-probe"), Map("METRICS_NAME" -> "../x", "STATE_DIR" -> os.temp.dir().toString))
    assertEquals(r.exitCode, 2)
    assertEquals(r.err.text().trim, "probe: bad METRICS_NAME")
