package piabrota.scripts

/** The pure parts of the area's model: parse, render and decide. */
class ModelTest extends munit.FunSuite:
  test("a repository slug, as sh's ${s%%/*} and ${s#*/} cut it"):
    assertEquals(RepoSlug.parse("marola-dev/marola-front"), RepoSlug("marola-dev", "marola-front"))
    assertEquals(RepoSlug.parse("x"), RepoSlug("x", "x"))
    assertEquals(RepoSlug("piabrota", "room").seatTokenName, "piabrota--room")
    assertEquals(RepoSlug("piabrota", "room").gitUrl, "https://github.com/piabrota/room.git")

  test("commit counts"):
    assertEquals(CommitCount.of(List("h0ffmann", "x[bot]", "claude", "claudette", "-")), CommitCount(3, 2))
    assertEquals(CommitCount(1, 2).render, "commits = { human = 1; agent = 2; };")

  test("a stack's merges"):
    assertEquals(StackMerge.Conflict(StackPr("3"), List("x", "y")).render, "#3  CONFLICT in:\n      x\n      y")
    assertEquals(StackPr("3").refspec, "pull/3/head:refs/pr-stack/3")

  test("the App's JWT and installations"):
    val unsigned = Jwt.unsigned("123", 1000)
    assert(unsigned.startsWith("eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9."), unsigned)
    val payload = String(java.util.Base64.getUrlDecoder.decode(unsigned.split('.')(1)), "UTF-8")
    assertEquals(payload, """{"iat":940,"exp":1540,"iss":"123"}""")
    assertEquals(AppCredential.parse("GH_APP_ID=7\nGH_APP_PRIVATE_KEY_B64=a2V5\n").pem.toList, "key".getBytes.toList)
    assertEquals(AppCredential.parse("GH_APP_PRIVATE_KEY_B64=!!!").pem.length, 0)
    val list = Installation.parseList(ujson.read("""[{"id":1,"account":{"login":"a"}},{"id":2,"account":{"login":"b"}}]"""))
    assertEquals(Installation.on(list, "b"), Some("2"))
    assertEquals(Installation.on(list, "c"), None)
    assertEquals(Installation.parseList(ujson.read("{}")), Nil)

  test("token requests and permissions"):
    assertEquals(TokenRequest.readOnly("room").render, """{"repositories":["room"],"permissions":{"contents":"read"}}""")
    assertEquals(TokenRequest(Some(Nil), Permissions.pullRequests).render, """{"repositories":[],"permissions":{"pull_requests":"write"}}""")
    val parsed = Permissions.parse("""{"contents":"write","issues":"write"}""")
    assertEquals(parsed.map(p => TokenRequest(None, p).render), Right("""{"permissions":{"contents":"write","issues":"write"}}"""))
    assert(Permissions.parse("""{"contents":1}""").isLeft)

  test("the bot's identity"):
    val bot = BotIdentity("piabrota-hermes", "42")
    assertEquals(bot.gitconfig, "[user]\n  name = piabrota-hermes[bot]\n  email = 42+piabrota-hermes[bot]@users.noreply.github.com\n")
    assert(bot.hasUserId && !BotIdentity("x", "").hasUserId && !BotIdentity("x", "null").hasUserId)

  test("the settings files of the token units"):
    val ok = ujson.read("""{"repository":"piabrota/room","tokens":"/t","home":"/h","profile":"p"}""")
    assertEquals(TylerTokenConfig.parse(ok).map(_.profileDir), Right(os.Path("/h/profiles/p")))
    assertEquals(TylerTokenConfig.parse(ujson.read("""{"repository":"x"}""")), Left("no tokens"))
    assertEquals(MarolaTokenConfig.parse(ujson.read("""{"owner":"o","names":[1]}""")).left.toOption,
      Some("names holds a value that is not a string"))

  test("the credential helpers' requests"):
    assertEquals(CredentialRequest.path(Iterator("protocol=https", "path=a/b", "", "path=c/d")), "a/b")
    assertEquals(CredentialRequest.path(Iterator("path")), "")
    assert(!CredentialRequest.plain("..") && !CredentialRequest.plain("a/b") && CredentialRequest.plain("a"))
    val hermes = HermesCredentialConfig(os.root, Set("marola-dev/marola-front"))
    assertEquals(hermes.tokenName("marola-dev/Marola-Front.git"), "marola-pr-bot")
    assertEquals(hermes.tokenName("marola-dev/marola-site"), "marola-dev")
    assertEquals(SeatCredential.tokenName("marola-dev/marola-front.git"), Some("marola-dev--marola-front"))
    assertEquals(SeatCredential.tokenName(""), None)

  private val omp = OmpSettings("/c", "/a", "35m", "/omp", "/timeout", "/choom")

  test("omp: the ceiling, choom and the token"):
    val e = OmpSettings.exec(omp, ClaudeTokens(None, Some("sk-ant-oat-h"), None), List("-p"))
    assertEquals(e.cmd, List("/timeout", "--signal=TERM", "--kill-after=30s", "35m", "/choom", "-n", "500", "--",
      "/omp", "--append-system-prompt", "/a", "-p"))
    assertEquals(e.set("ANTHROPIC_OAUTH_TOKEN"), "sk-ant-oat-h")
    assertEquals(e.unset, OmpSettings.names)
    val seat = OmpSettings.exec(omp.copy(ceiling = "none"), ClaudeTokens(None, None, Some("sk-ant-oat-s")), Nil)
    assertEquals(seat.cmd.head, "/choom")
    assertEquals((seat.set("ANTHROPIC_OAUTH_TOKEN"), seat.unset.head), ("sk-ant-oat-s", "ANTHROPIC_API_KEY"))

  test("seat-claude: the subscription token moves, an API key does not"):
    val s = SeatClaudeSettings("/claude", "/choom")
    assertEquals(SeatClaudeSettings.exec(s, ClaudeTokens(None, None, Some("sk-ant-oat-s")), Nil).set,
      Map("CLAUDE_CODE_OAUTH_TOKEN" -> "sk-ant-oat-s"))
    val api = SeatClaudeSettings.exec(s, ClaudeTokens(None, None, Some("sk-ant-api-x")), List("--help"))
    assertEquals((api.set, api.cmd.last), (Map.empty[String, String], "--help"))
    assert(api.unset.contains("ANTHROPIC_API_KEY"))

  test("marola-gh and openrig-claude-token"):
    assert(MarolaGh.allows(List("pr", "create", "--fill")))
    assert(!MarolaGh.allows(List("pr", "merge")) && !MarolaGh.allows(List("--repo", "x", "pr", "create")))
    assertEquals(SeatClaudeToken.render(List("CLAUDE_CODE_OAUTH_TOKEN=a", "CLAUDE_CODE_OAUTH_TOKEN=b")), "ANTHROPIC_API_KEY=b\n")
    assertEquals(SeatClaudeToken.render(Nil), "")

  test("restart-services: the arguments"):
    assertEquals(RestartArgs.parse(Nil), Right(RestartArgs(Selection.All, false, false)))
    assertEquals(RestartArgs.parse(List("web", "-y", "-n")), Right(RestartArgs(Selection.One(ServiceGroup.Web), true, true)))
    assertEquals(RestartArgs.parse(List("list", "pgx")), Left(RestartArgError.TwoGroups("list", "pgx")))
    assertEquals(RestartArgs.parse(List("--force", "-h")), Left(RestartArgError.Unknown("--force")))
    assertEquals(RestartArgs.parse(List("-h", "--force")).left.map(_.code), Left(0))
    assertEquals(Selection.All.groups.map(_.render), List("metrics", "web", "pgx", "room", "loco", "rig", "hermes"))

  test("restart-services: the allow list, the wanted state and the gateways"):
    assert(RestartAllow.allowed("loco-notes.service") && !RestartAllow.allowed("loco-notes-backup.service"))
    assert(!RestartAllow.allowed("loco-evil;rm.service") && !RestartAllow.allowed("sshd.service"))
    assert(Want.Oneshot.met("inactive") && !Want.Active.met("inactive") && !Want.Oneshot.met("failed"))
    val gw = Proc("100", List("hermes", "gateway", "run"), "0::/system.slice/hermes-agent.service\n")
    assert(gw.isGateway && gw.inUnit(Units.hermesAgent))
    assertEquals(gw.cgroupPath, Some("/system.slice/hermes-agent.service"))
    assert(!Proc("1", List("sh", "-c", "echo gateway run"), "").isGateway)

  test("hermes-checkpoint: the hash and the pid file"):
    assert(HermesCheckpoint.isSha256("0" * 64) && !HermesCheckpoint.isSha256("") && !HermesCheckpoint.isSha256("ABC"))
    assertEquals(CheckpointConfig.pid("""{"pid": 123, "kind": "hermes-gateway"}"""), Some(123L))
    assertEquals(CheckpointConfig.pid("{}"), None)

  private def rig(name: String, status: RigStatus, attention: Long = 0, running: Double = 0) =
    Rig(Some(name), status, attention, running, archived = false)

  test("the rig keeper decides"):
    import Keeper.rigName
    assertEquals(Keeper.decide(Nil), KeeperStep.Start(RigStatus.Missing))
    assertEquals(Keeper.decide(List(rig(rigName, RigStatus.Running))), KeeperStep.Say(s"$rigName runs"))
    assertEquals(Keeper.decide(List(rig(rigName, RigStatus.Running, attention = 2))),
      KeeperStep.Say(s"<4>$rigName runs, 2 seat(s) need attention: rig ps --nodes --rig $rigName"))
    assertEquals(Keeper.decide(List(rig("other", RigStatus.Running, running = 1), rig(rigName, RigStatus.Stopped))),
      KeeperStep.Say("another rig runs: other, skipped"))
    assertEquals(Keeper.decide(List(rig(rigName, RigStatus.Other("odd")))),
      KeeperStep.Say(s"<4>$rigName has the status 'odd': nothing done"))
    val stopped = List(RigNode("a", Some("stopped"), true), RigNode("b", None, true))
    assertEquals(Keeper.withNodes(RigStatus.Stopped, stopped), KeeperStep.Say(s"$rigName was stopped on purpose (rig down): not started"))
    assertEquals(Keeper.withNodes(RigStatus.Stopped, Nil), KeeperStep.Start(RigStatus.Stopped))
    assertEquals(Keeper.withNodes(RigStatus.Partial, RigNode("p", Some("running"), false) :: stopped),
      KeeperStep.Say(s"<4>$rigName is partial, seats not running: a=stopped, b=null. Nothing changed."))
    assertEquals(Keeper.recent(List("100", "", "x", "3500", "4000"), now = 4000), List("3500", "4000"))
    assertEquals(Rig.parse(ujson.read("""{"name":"r","status":null,"runningCount":2,"isArchived":true}""")),
      Rig(Some("r"), RigStatus.Missing, 0, 2.0, true))

  test("marola's boards"):
    assertEquals(Boards.areas("""{"areas":[{"id":"rio"},{"id":7}]}"""), List("rio", "7"))
    assertEquals(Boards.days("""{"days":[{"file":"2026-11-14.json"},{}]}"""), List("2026-11-14.json", "null"))
    assertEquals(Boards.days("nope"), Nil)
    assert(Boards.isDayFile("2026-11-14.json") && !Boards.isDayFile("../x.json"))
    assertEquals(Boards.generatedAt("""{"generated_at":null}"""), None)
    assertEquals(Boards.generatedAt("""{"generated_at":"2026-11-14T00:00:00Z"}"""), Some("2026-11-14T00:00:00Z"))
    assertEquals(BoardRow.Dated("rio", "t", 7200, 43200).render, "| rio | t (2 h ago) | ✓ |")
    assertEquals(BoardRow.Dated("rio", "t", 50000, 43200).render, "| rio | t (13 h ago) | ✗ older than 12 h |")
    assert(!BoardRow.Missing("gone").fresh)

  test("the dummy video's captions, join and verdict"):
    assertEquals(VideoDummy.cue(1, "Scene 2: script"), "2\n00:00:05,500 --> 00:00:10,500\nScene 2: script\n")
    assertEquals(VideoDummy.graph(2), "[0:v][1:v]xfade=transition=fade:duration=0.5:offset=5.5[v1];" +
      "[2:a][3:a]acrossfade=d=0.5[a1];[a1]loudnorm=I=-16:TP=-1.5:LRA=11,aresample=48000[aout]")
    val good = VideoReport("f.mp4", 200000, 27.5, 1280, 720, "h264", "aac", Map('v' -> 1, 'a' -> 1, 's' -> 1), 1.0, 10)
    assertEquals(good.problem, None)
    assertEquals(good.copy(streams = good.streams + ('a' -> 2)).problem, Some("2 audio streams, expected 1"))
    assertEquals(good.copy(bytes = 100).problem, Some("file is 100 bytes, 100 KB or less"))

  test("freeze's arguments"):
    assertEquals(FreezeArgs.parse(List("--by-size")), FreezeArgs(true, "/run/current-system"))
    assertEquals(FreezeArgs.parse(List("/nix/store/x")), FreezeArgs(false, "/nix/store/x"))
