package piabrota.metrics

/** The pure parts of the model: the files the commands read back, and the checks of their lines. */
class ModelTest extends munit.FunSuite:
  test("the state file: what a run writes, the next one reads"):
    val counters = Counters(1000.5, KernelCounters(10000, 500), Some(InOut(1e6, 5e5)), None,
      Vector("cpu" -> CpuTimes(9000, 4500), "cpu0" -> CpuTimes(4500, 2250)), Vector("100" -> ProcTicks(10, 150)))
    val text = counters.render
    assertEquals(text, "T 1000.5\nK 10000 500\nN 1000000 500000\nC cpu 9000 4500\nC cpu0 4500 2250\nP 100 10 150\n")
    assertEquals(Previous.parse(Some(text)), Previous(Some(1000.5), Map("cpu" -> CpuTimes(9000, 4500),
      "cpu0" -> CpuTimes(4500, 2250)), Map("100" -> ProcTicks(10, 150)), Some(KernelCounters(10000, 500)),
      Some(InOut(1e6, 5e5)), None))

  test("a garbled state line is left out"):
    assertEquals(Previous.parse(Some("garbage\nT\nK 1 2 3\nX 1\nD 1 2")), Previous(disk = Some(InOut(1, 2))))

  test("the name of a process is between the first ( and the last )"):
    val tail = (1 to 20).map(i => if i == 12 then "7" else if i == 13 then "3" else if i == 20 then "42" else "0")
    assertEquals(ProcStat.parse(s"1 (a (b)) c) ${tail.mkString(" ")}"), Some(ProcStat("a (b)) c", 10, 42)))
    assertEquals(ProcStat.parse("1 (x) S 1 2"), None)
    assertEquals(ProcStat.parse(""), None)

  test("the probe file as the probe writes it and the collector reads it"):
    val up = Site("up.example", "https://up.example/")
    val file = ProbeFile(1700000000, List(up -> "200", Site("down.example", "https://d/") -> "000"),
      Some(CommitCount("230", "1699999000")), Some(1700000000), List(SiteVisits("up.example", 3, 2)))
    val text = file.render
    assertEquals(text, "ts 1700000000\ndomain up.example 200\ndomain down.example 000\nrepo 230 1699999000\n" +
      "asked 1700000000\nvisits up.example 3 2\n")
    assertEquals(ProbeFile.lastAnswer(Some(text)), (Some(CommitCount("230", "1699999000")), 1700000000L))
    assertEquals(ProbeReport.parse(Some(text + "domain B 200\nrepo x 1\n")), ProbeReport(Some("1700000000"),
      List(SiteStatus("up.example", 200, Some(SiteVisits("up.example", 3, 2))), SiteStatus("down.example", 0, None)),
      Some(CommitCount("230", "1699999000"))))
    assert(SiteStatus("a", 401, None).up && !SiteStatus("a", 502, None).up && !SiteStatus("a", 0, None).up)

  test("the sites file keeps a lowercase name and an http(s) address, 24 at most"):
    assertEquals(Site.parse(Some("a.example https://a/\nB.example https://b/\nc.example ftp://c/\nd http://d/ x")),
      List(Site("a.example", "https://a/"), Site("d", "http://d/")))
    assertEquals(Site.parse(Some((0 until 30).map(i => s"s$i http://s/").mkString("\n"))).size, 24)

  test("the visits: the state's last 24 h and the new lines"):
    val now = 1700000000L
    val state = s"pos 7 120\nh ${now - 7200} up.example 4\nh ${now - 90000} up.example 9\nu up.example 192.0.2.1 ${now - 100}\n" +
      s"u gone.example 192.0.2.1 ${now - 100}\n"
    assertEquals(VisitsState.position(Some(state)), LogPosition("7", 120))
    assertEquals(VisitsState.position(Some("h 1 a 2")), LogPosition.Start)
    val kept = VisitsState.tally(Some(state), List(s"${now - 10}.5 up.example 192.0.2.2", s"${now + 100}.0 up.example 192.0.2.3",
      "garbage"), List("up.example", "auth.example"), now, LogPosition("7", 200))
    val hour = (now - 10) - (now - 10) % 3600
    assertEquals(kept.render, s"pos 7 200\nh ${now - 7200} up.example 4\nh $hour up.example 1\n" +
      s"u up.example 192.0.2.1 ${now - 100}\nu up.example 192.0.2.2 ${now - 10}\n")
    assertEquals(kept.visits(List("up.example", "auth.example")),
      List(SiteVisits("up.example", 5, 2), SiteVisits("auth.example", 0, 0)))

  test("the inventory, the NixOS version and the generation are checked"):
    assertEquals(Sampler.inventory(Array("apps 1", "Apps 2", "apps 3", "x 1.5", "k 1 2", "sites 7")),
      Vector("apps" -> "1", "sites" -> "7"))
    assertEquals(Sampler.nixos("26.05.20261101.abcdef0\nmore"), Some("26.05.20261101.abcdef0"))
    assertEquals(Sampler.nixos("not a \"version\""), None)
    assertEquals(Sampler.generation("/nix/var/nix/profiles/system-42-link"), Some("42"))
    assertEquals(Sampler.generation("system-x-link"), None)

  test("the commit count is the page of rel=\"last\""):
    assertEquals(Probe.lastPage("HTTP/2 200\r\nLink: <https://x/c?per_page=1&page=2>; rel=\"next\", " +
      "<https://x/c?per_page=1&page=230>; rel=\"last\"\r\n\r\n"), Some("230"))
    assertEquals(Probe.lastPage("HTTP/2 200\r\n\r\n"), None)

  test("a host file names its host; the export's own files are not hosts"):
    assert(HostName.claims("""{"v":1,"host":"piabrota"}""", "piabrota"))
    assert(!HostName.claims("""{"host":"piabrota2"}""", "piabrota") && !HostName.claims("""x"host":"a"""", "a"))
    assert(HostName.valid("piabrota2") && !HostName.valid("../x") && !HostName.valid("Upper"))
    assertEquals(OutFile.reserved, Set("all", "metrics"))

  test("the export's environment, and a Prometheus line"):
    assertEquals(ExportConfig("d", "30", "1").problem, None)
    assertEquals(ExportConfig("d", "x", "y").problem, Some("bad METRICS_STALE"))
    assertEquals(ExportConfig("d", "30", "").problem, Some("bad METRICS_NOW"))
    val m = Metric.of("site_up", MetricKind.Gauge, "h", Seq(Label.Host -> Json.Str("a\"b\\\n")), Json.num(1L))
    assertEquals(m.map(_.line), Some("""piabrota_site_up{host="a\"b\\\n"} 1"""))
    assertEquals(Metric.of("x", MetricKind.Counter, "h", Nil, Json.Str("1")), None)
    assertEquals(Metric.render(m.toVector), "# HELP piabrota_site_up h\n# TYPE piabrota_site_up gauge\n" + m.get.line)
