package piabrota.scripts

import piabrota.lib.TestKit

class ContextSizeTest extends munit.FunSuite:
  test("levels"):
    assertEquals(ContextSize.level(30000)._1, ContextLevel.Ok)
    assertEquals(ContextSize.level(30001), (ContextLevel.Warn, "30001 / 32000 (margin 2000)"))
    assertEquals(ContextSize.level(32001), (ContextLevel.Fail, "32001 / 32000: Hermes drops the middle"))

  test("counts characters, not bytes"):
    val root = os.temp.dir(prefix = "context")
    os.write(root / "AGENTS.md", "é" * 31000) // 62000 bytes
    val r = TestKit.piabrota(Seq("context-size"), cwd = root, env = Map("GITHUB_ACTIONS" -> ""))
    assertEquals(r.exitCode, 0)
    assertEquals(r.out.text(), "WARN  AGENTS.md  31000 / 32000 (margin 2000)\n")

  test("a file over the limit fails, with an annotation on a runner"):
    val root = os.temp.dir(prefix = "context")
    os.write(root / "hermes" / "SOUL.md", "x" * 32001, createFolders = true)
    val r = TestKit.piabrota(Seq("context-size"), cwd = root, env = Map("GITHUB_ACTIONS" -> "true"))
    assertEquals(r.exitCode, 1)
    assertEquals(r.out.text(),
      "FAIL  hermes/SOUL.md  32001 / 32000: Hermes drops the middle\n" +
        "::error file=hermes/SOUL.md::hermes/SOUL.md 32001 / 32000: Hermes drops the middle\n")
