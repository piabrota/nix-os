package piabrota.hermes

class HermesModelTest extends munit.FunSuite:
  private def envOf(vars: (String, String)*): String => Option[String] = vars.toMap.get

  test("GatewayConfig: defaults, a value, and a variable that is not a number"):
    val cfg = GatewayConfig.read(envOf("HERMES_HOME" -> "/h", "GATEWAY_WRAPPER_POLL_SECS" -> "1"))
    assertEquals(cfg, Right(GatewayConfig(os.Path("/h"), 20, 1, 5, 60)))
    assertEquals(GatewayConfig.read(envOf("GATEWAY_WRAPPER_MAX_RELOADS" -> "x")),
      Left("gateway-wrapper: GATEWAY_WRAPPER_MAX_RELOADS is not a number: x"))

  test("Request: USR1 reloads, TERM and INT stop, CHLD asks nothing"):
    assertEquals(Request.of(Proc.SIGUSR1), Some(Request.Reload))
    assertEquals(List(Proc.SIGTERM, Proc.SIGINT).map(Request.of), List(Some(Request.Stop), Some(Request.Stop)))
    assertEquals(Request.of(Proc.SIGCHLD), None)

  test("Next.after: a stop, a foreign gateway, reloads up to the limit, another status"):
    val cfg = GatewayConfig(os.Path("/h"), fastExit = 20, poll = 5, maxReloads = 2, reloadWindow = 60)
    assertEquals(Next.after(GatewayRun(75, 0, 100, stopping = true), None, Nil, cfg), Next.Exit(0))
    assertEquals(Next.after(GatewayRun(7, 0, 100, stopping = true), None, Nil, cfg), Next.Exit(7))
    assertEquals(Next.after(GatewayRun(0, 99, 100, false), Some(42L), Nil, cfg), Next.WaitFor(42L, 0))
    // A reload older than the window leaves the count.
    assertEquals(Next.after(GatewayRun(75, 0, 100, false), None, List(10L, 90L), cfg), Next.Restart(List(90L, 100L)))
    assertEquals(Next.after(GatewayRun(75, 0, 100, false), None, List(80L, 90L), cfg), Next.GiveUp(3))
    assertEquals(Next.after(GatewayRun(0, 0, 100, false), None, Nil, cfg), Next.Exit(0))

  test("GatewayRun.fastExit: 0 or 75 within the limit"):
    val cfg = GatewayConfig(os.Path("/h"), fastExit = 2, poll = 1, maxReloads = 5, reloadWindow = 60)
    assert(GatewayRun(75, 10, 11, false).fastExit(cfg))
    assert(GatewayRun(0, 10, 11, false).fastExit(cfg))
    assert(!GatewayRun(1, 10, 11, false).fastExit(cfg))
    assert(!GatewayRun(75, 10, 12, false).fastExit(cfg))

  test("GatewayPid.parse"):
    assertEquals(GatewayPid.parse("""{"pid": 42, "kind": "hermes-gateway"}"""), Some(42L))
    assertEquals(GatewayPid.parse("""{"pid": "7"}"""), Some(7L))
    assertEquals(GatewayPid.parse("""{"pid": -1}"""), None)
    assertEquals(GatewayPid.parse("[1]"), None)

  test("CronEnv, OpenPr and Branches"):
    assertEquals(CronEnv.read("/bin", envOf("DRY_RUN" -> "1")),
      CronEnv("/bin:/run/current-system/sw/bin", dryRun = true, outPatch = None, tmpDir = "/tmp"))
    assertEquals(CronEnv.read("", envOf("DRY_RUN" -> "yes")).dryRun, false)
    val prs = OpenPr.parseList("""[{"headRefName":"x","url":"u1"},{"headRefName":"hermes/grid-refresh-2","url":"u2"}]""")
    assertEquals(GridFiles.branches.ownsAny(prs), Some(OpenPr("hermes/grid-refresh-2", "u2")))
    assertEquals(OpenPr.parseList("""[{"headRefName":"b"}]"""), List(OpenPr("b", "")))
    assertEquals(SkillsRepo.branches.dated("20261114"), "hermes/skills-export-20261114")
    assertEquals(SkillsRepo.branches.dry, "hermes/skills-export-dry")

  test("RunJson.parse and refuse"):
    val old = RunJson.parse("""{"hours":["2026-11-14T00:00"],"nodes":10,"triangles":20,"sst":{"date":"2026-11-13"}}""").get
    assertEquals((old.hours, old.first, old.nodes, old.sstDate, old.fetched), (1, "2026-11-14T00:00", "10", "2026-11-13", "not stated"))
    assertEquals(RunJson.parse("[]"), None)
    assertEquals(RunJson.refuse(old, old, meshChanged = false), None)
    assertEquals(RunJson.refuse(old.copy(hasSst = false), old, false), Some("the sea temperature is missing (Copernicus Marine)"))
    assertEquals(RunJson.refuse(old.copy(hours = 2), old, false), Some("run.json has 2 hours, the committed one has 1"))
    assertEquals(RunJson.refuse(old.copy(nodes = "11"), old, false),
      Some("run.json has other nodes or triangles, but mesh.bin did not change"))
    assertEquals(RunJson.refuse(old.copy(nodes = "11"), old, true), None)

  test("Sizes: refuse and describe"):
    assertEquals(Sizes("frames.bin", Some(4), Some(4)).refuse, None)
    assertEquals(Sizes("frames.bin", Some(4), None).refuse, Some("frames.bin is missing"))
    assertEquals(Sizes("sst.bin", Some(4), Some(5)).refuse, Some("sst.bin has 5 bytes, the committed one has 4"))
    assertEquals(Sizes("sst.bin", None, Some(5)).refuse, None)
    assertEquals(Sizes("mesh.bin", Some(1), None).describe,
      "- `mesh.bin`: 1 bytes before, no file after. **changed: check the Natural Earth source**\n")
    assertEquals(GridFiles.changed(" M public/grid/run.json"), "run.json")

  test("Origin: the owner's skills, and their names in the README"):
    assertEquals(List(Origin.MadeHere, Origin.Plugin("pirsig-brain"), Origin.NixOs("skills")).map(_.isOwn), List(true, true, true))
    assertEquals(List(Origin.Bundled, Origin.Hub, Origin.Plugin("other"), Origin.NixOs("x")).map(_.isOwn),
      List(false, false, false, false))
    assertEquals(Origin.Plugin("pirsig-brain").render, "Plugin pirsig-brain")
    assertEquals(Origin.NixOs("skills").render, "Added by nix-os (skills)")

  test("Found.of keeps the first skill of a name"):
    val a = Skill("a", os.Path("/1/a"), Origin.MadeHere)
    val b = Skill("b", os.Path("/1/b"), Origin.MadeHere)
    assertEquals(Found.of(List(a, b, a.copy(dir = os.Path("/2/a")))), Found(List(a, b), List("a")))

  test("TaskName, StopSignal and OmpEnd"):
    assert(TaskName.valid("t"))
    assertEquals(List("", "a/b", ".x", "-x").map(TaskName.valid), List(false, false, false, false))
    assertEquals(List(Proc.SIGINT, Proc.SIGHUP, Proc.SIGTERM).map(StopSignal.of), List(StopSignal.INT, StopSignal.HUP, StopSignal.TERM))
    assertEquals(OmpEnd.of("t", stopFile = true, Some(StopSignal.TERM), 143),
      (Some("omp-run: stopped on request (omp-run --stop t)"), 0))
    assertEquals(OmpEnd.of("t", false, Some(StopSignal.HUP), 0)._2, 143)
    assert(OmpEnd.of("t", false, Some(StopSignal.HUP), 0)._1.exists(_.startsWith("omp-run: stopped by SIGHUP,")))
    assertEquals(OmpEnd.of("t", false, None, 0), (None, 0))
    assertEquals(OmpEnd.of("t", false, None, 143), (Some("omp-run: omp was stopped by signal 15"), 143))
    assertEquals(OmpEnd.of("t", false, None, 3), (Some("omp-run: omp exited with 3"), 3))

  test("OmpEvent.parse and OmpStream.step"):
    assertEquals(OmpEvent.parse("  "), OmpEvent.Ignored)
    assertEquals(OmpEvent.parse("oops"), OmpEvent.Stderr("oops"))
    assertEquals(OmpEvent.parse("""{"type":"session"}"""), OmpEvent.Session("?"))
    val (t1, _) = OmpStream.step(Tally.zero, OmpEvent.TurnEnd)
    val (t2, _) = OmpStream.step(t1, OmpEvent.AssistantEnd(0.5))
    assertEquals(OmpStream.step(t2, OmpEvent.AgentEnd), (Tally(1, 0.5), List("omp: done, 1 turns, cost $0.5000")))

  test("HealthMode, Level, Finding.signature and AlertState"):
    assertEquals(HealthMode.parse(List("--record", "--alert")), Some(HealthMode(alert = true, record = true)))
    assertEquals(HealthMode.parse(Nil), Some(HealthMode(false, false)))
    assertEquals(HealthMode.parse(List("--nope")), None)
    assertEquals(Level.Ok.line("x"), "ok    x")
    assertEquals(Level.Crit.line("x"), "CRIT  x")
    val fs = List(Finding(Level.Warn, "swap", "a"), Finding(Level.Warn, "disk", "b"), Finding(Level.Crit, "disk", "c"))
    assertEquals(Finding.signature(fs), " disk swap ")
    assertEquals(Finding.signature(Nil), " ")
    assertEquals(AlertState.parse(AlertState(12, " disk ").render), AlertState(12, " disk "))
    assertEquals(AlertState.parse("x"), AlertState(0, ""))
    assertEquals(Limits.read(envOf("KH_LOAD_WARN" -> "2")).loadWarn, "2")
    assertEquals(Limits.read(envOf()).journalMib, "220")
