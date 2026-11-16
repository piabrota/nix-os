package piabrota.pirsig

class ModelTest extends munit.FunSuite:
  val config = Config(os.temp.dir(), Config.DefaultRepo, Config.DefaultBase)

  test("the config: HERMES_HOME relative to the working directory, and the defaults"):
    val env = Map("HERMES_HOME" -> "h", "PIRSIG_BASE" -> "dev")
    assertEquals(Config.from(env.get, os.root / "home" / "u", os.root / "w"),
      Config(os.root / "w" / "h", "piabrota/pirsig", "dev"))
    assertEquals(Config.from(_ => None, os.root / "home" / "u", os.root / "w").home, os.root / "home" / "u" / ".hermes")

  test("incoming lines"):
    assertEquals(Incoming.parse("{not json"), Incoming.Unreadable)
    assertEquals(Incoming.parse("""{"method": "notifications/initialized"}"""), Incoming.Notification)
    assertEquals(Incoming.parse("[1]"), Incoming.Notification)
    assertEquals(Incoming.parse("""{"id": "a", "method": "initialize"}"""),
      Incoming.Call(RequestId(ujson.Str("a")), Request.Initialize(None)))
    assertEquals(Incoming.parse("""{"id": 1, "method": "tools/call", "params": {"name": "x", "arguments": 3}}"""),
      Incoming.Call(RequestId(ujson.Num(1)), Request.CallTool("x", ujson.Obj())))
    assertEquals(Incoming.parse("""{"id": 1, "method": 5}"""), Incoming.Call(RequestId(ujson.Num(1)), Request.Unknown("")))

  test("responses"):
    val id = RequestId(ujson.Num(2))
    assertEquals(Mcp.respond(config, id, Request.Initialize(None)).render("result")("protocolVersion").str,
      Server.DefaultProtocol)
    assertEquals(Mcp.respond(config, id, Request.Unknown("x")),
      Response.Error(id, ErrorCode.MethodNotFound, "Method not found: x"))
    assertEquals(Mcp.respond(config, id, Request.CallTool(ToolName.VideoCheck.label, ujson.Obj("name" -> "..")))
      .render("result")("content")(0)("text").str, """{"error": "not a video folder name: '..'"}""")

  test("a schema renders type, description, enum and items in that order"):
    val s = Schema.Record(List(Property("a", Schema.Text(Some("d"), List("x")), required = true),
      Property("b", Schema.ListOf(Schema.Integer()))))
    assertEquals(ujson.write(s.render), """{"type":"object","properties":{"a":{"type":"string","description":"d",""" +
      """"enum":["x"]},"b":{"type":"array","items":{"type":"integer"}}},"required":["a"]}""")

  test("answers"):
    assertEquals(Answer.Failed("no", Some(Seq("p"))).render, """{"error": "no", "problems": ["p"]}""")
    assertEquals(Answer.Failed("no").render, """{"error": "no"}""")

  test("tags keep their JSON type"):
    assertEquals(Tag.parse(ujson.Num(5)), Tag("5", quoted = false))
    assertEquals(Tag.parse(ujson.Num(5)).yaml, "5")
    assertEquals(Tag.parse(ujson.Str("pkm")).yaml, "\"pkm\"")
    assertEquals(Tag.parse(ujson.Str("Big")).repr, "'Big'")

  test("search input"):
    assertEquals(SearchInput.parse(ujson.Obj("query" -> " Ocean ", "limit" -> 50)), Right(SearchInput("ocean", 20)))
    assertEquals(SearchInput.parse(ujson.Obj("query" -> "x", "limit" -> "x")), Right(SearchInput("x", 10)))
    assertEquals(SearchInput.parse(ujson.Obj("query" -> " ")), Left("no query"))

  test("rank: a hit in the title counts three times"):
    def note(title: String, body: String) = BrainNote(title, title, "", "", Folder.Inbox, body)
    val notes = List(note("a", "ocean"), note("ocean", ""), note("b", "nothing"))
    assertEquals(Notes.rank(notes, "ocean").map(_.title), List("ocean", "a"))

  test("branch names"):
    val heads = "abc\trefs/heads/hermes/x\ndef\trefs/heads/hermes/x-2\n"
    assertEquals(Brain.remoteBranches(heads), Set("hermes/x", "hermes/x-2"))
    assertEquals(Brain.freeBranch("x", Brain.remoteBranches(heads)), "hermes/x-3")
    assertEquals(Brain.freeBranch("y", Set.empty), "hermes/y")

  test("video.json from yt-dlp's info"):
    val info = ujson.Obj("id" -> "abc", "webpage_url" -> "u", "title" -> "T", "duration" -> 95, "upload_date" -> "20261103")
    val record = VideoRecord.from(info, VideoRecord.date(info), Track("pt", CaptionsKind.Manual))
    assertEquals(record.date, "2026-11-03")
    assertEquals(Py.dumps(record.json), """{"id": "abc", "url": "u", "title": "T", "channel": null, """ +
      """"date": "2026-11-03", "duration": 95, "language": null, "captions": "pt", "captions_kind": "manual", """ +
      """"description": null, "hub": null, "resource": null}""")
    assertEquals(intercept[BadData](VideoRecord.from(ujson.Obj(), "", Track("pt", CaptionsKind.Manual))).message, "'id'")
