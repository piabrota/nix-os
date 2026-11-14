package piabrota.pirsig

import piabrota.lib.TestKit

/** The server as Hermes drives it: JSON-RPC lines on stdin, answers on stdout. */
class McpTest extends munit.FunSuite:
  def session(lines: String*): List[ujson.Value] =
    val r = TestKit.piabrota(Seq("pirsig-mcp"), stdin = lines.mkString("", "\n", "\n"))
    assertEquals(r.exitCode, 0, r.err.text())
    r.out.lines().toList.map(ujson.read(_))

  def request(id: Int, method: String, params: ujson.Obj = ujson.Obj()): String =
    ujson.write(ujson.Obj("jsonrpc" -> "2.0", "id" -> id, "method" -> method, "params" -> params))

  test("initialize, the initialized notification, ping and tools/list"):
    val answers = session(
      request(1, "initialize", ujson.Obj("protocolVersion" -> "2025-11-25", "capabilities" -> ujson.Obj(),
        "clientInfo" -> ujson.Obj("name" -> "hermes", "version" -> "0.23.1"))),
      """{"jsonrpc": "2.0", "method": "notifications/initialized"}""",
      "",
      request(2, "ping"),
      request(3, "tools/list"),
    )
    assertEquals(answers.map(_("id").num), List(1.0, 2.0, 3.0))
    val init = answers(0)("result")
    assertEquals(init("protocolVersion").str, "2025-11-25")
    assertEquals(init("capabilities"), ujson.Obj("tools" -> ujson.Obj()))
    assertEquals(init("serverInfo")("name").str, "pirsig")
    assertEquals(answers(1)("result"), ujson.Obj())
    val tools = answers(2)("result")("tools").arr
    assertEquals(tools.map(_("name").str).toList, List("pirsig_note_search", "pirsig_notes_submit",
      "pirsig_video_fetch", "pirsig_video_check", "pirsig_video_submit"))
    for t <- tools do
      assertEquals(t("inputSchema")("type").str, "object")
      assert(t("description").str.nonEmpty)
    assertEquals(tools(1)("inputSchema")("properties")("notes")("items")("required"),
      ujson.Arr("title", "type", "status", "body"))
    assertEquals(tools(4)("inputSchema")("required"), ujson.Arr("name", "request"))

  test("errors: a bad line, an unknown method, an unknown tool"):
    val answers = session("{not json", request(7, "resources/list"),
      request(8, "tools/call", ujson.Obj("name" -> "nothing", "arguments" -> ujson.Obj())))
    assertEquals(answers(0), ujson.Obj("jsonrpc" -> "2.0", "id" -> ujson.Null,
      "error" -> ujson.Obj("code" -> -32700, "message" -> "Parse error")))
    assertEquals(answers(1)("error")("code").num, -32601.0)
    assertEquals(answers(2)("error"), ujson.Obj("code" -> -32602, "message" -> "Unknown tool: nothing"))

  test("a tool's answer is the plugin's JSON as text, with Python's separators"):
    val answers = session(request(4, "tools/call",
      ujson.Obj("name" -> "pirsig_video_fetch", "arguments" -> ujson.Obj("url" -> "ftp://x"))))
    assertEquals(answers(0)("result"), ujson.Obj(
      "content" -> ujson.Arr(ujson.Obj("type" -> "text", "text" -> """{"error": "give an https YouTube URL"}""")),
      "isError" -> false))

  test("an argument is a usage error"):
    val r = TestKit.piabrota(Seq("pirsig-mcp", "x"))
    assertEquals(r.exitCode, 2)
    assertEquals(r.err.text().trim, "usage: piabrota pirsig-mcp")
