package piabrota.hermes

import piabrota.lib.TestKit

class OmpStreamTest extends munit.FunSuite:
  private def stream(input: String): String =
    val r = TestKit.piabrota(Seq("omp-stream"), stdin = input)
    assertEquals(r.exitCode, 0, r.err.text())
    r.out.text()

  test("a recorded run"):
    assertEquals(stream(OmpStreamFixture.run), OmpStreamFixture.expected)

  test("a line that is not JSON prints as a stderr line"):
    assertEquals(stream("Error: no such model\n"), "omp stderr: Error: no such model\n")

  test("a tool error, its time and its text"):
    val event = """{"type":"tool_execution_end","toolName":"bash","isError":true,"result":{"content":[{"type":"text","text":"boom\n"}],"details":{"wallTimeMs":12.4}}}"""
    assertEquals(stream(event + "\n"), "< bash ERROR (12 ms)\n    boom\n")

  test("keys and tokens are redacted"):
    val event = """{"type":"message_update","assistantMessageEvent":{"type":"text_end","content":"key sk-ant-oat01-ABC and ghp_abc123"}}"""
    assertEquals(stream(event + "\n"), "omp says: key [redacted] and [redacted]\n")

  test("a tool result keeps 5 lines and counts the rest; blank lines print nothing"):
    val text = (1 to 8).map(i => s"line $i").mkString("\\n")
    val event = s"""{"type":"tool_execution_end","toolName":"read","result":{"content":[{"type":"text","text":"$text"}]}}"""
    assertEquals(stream("   \n" + event + "\n"),
      "< read ok\n" + (1 to 5).map(i => s"    line $i\n").mkString + "    ... 3 more lines\n")

  test("a tool call shows its command when it has no intent"):
    val event = """{"type":"tool_execution_start","toolName":"bash","args":{"command":"ls\n  -la"}}"""
    assertEquals(stream(event + "\n"), "> bash: ls -la\n")

  test("cost4 and cut"):
    assertEquals(OmpStream.cost4(0.0448), "0.0448")
    assertEquals(OmpStream.cost4(12.5), "12.5000")
    assertEquals(OmpStream.cut("ação", 2), "aç")
