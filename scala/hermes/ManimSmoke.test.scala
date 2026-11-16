package piabrota.hermes

import piabrota.lib.{Sh, TestKit}

/** manim-smoke with a fake manim that writes the video, fails, or writes nothing. */
class ManimSmokeTest extends munit.FunSuite:
  private val scene = os.temp("from manim import *\n", suffix = ".py")

  private def smoke(manim: String): os.CommandResult =
    TestKit.piabrota(Seq("manim-smoke", scene.toString), fakes = Some(TestKit.fakes("manim" -> manim)))

  test("a render that writes Smoke.mp4 prints its path, its size and ok"):
    val r = smoke("#!/bin/sh\nmkdir -p \"$4/videos/smoke/480p15\" && printf 12345 >\"$4/videos/smoke/480p15/Smoke.mp4\"\n")
    assertEquals(r.exitCode, 0, r.out.text())
    val lines = r.out.text().linesIterator.toList
    assert(lines.head.endsWith("/media/videos/smoke/480p15/Smoke.mp4 5 bytes"), lines.head)
    assertEquals(lines(1), "ok")

  test("a failed render prints the end of its log and exits 1"):
    val r = smoke("#!/bin/sh\necho one\necho boom >&2\nexit 3\n")
    assertEquals((r.exitCode, r.out.text()), (1, "one\nboom\n"))

  test("a render with no video exits 1"):
    val r = smoke("#!/bin/sh\necho rendered\n")
    assertEquals((r.exitCode, r.out.text()), (1, "Smoke.mp4 is missing or empty\nrendered\n"))

  test("no manim on the PATH exits 2"):
    assume(Sh.which("manim").isEmpty, "this machine has a manim")
    val r = TestKit.piabrota(Seq("manim-smoke", scene.toString))
    assertEquals((r.exitCode, r.out.text()), (2, "manim: not found on PATH\n"))
