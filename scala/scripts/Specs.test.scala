package piabrota.scripts

import piabrota.lib.TestKit

class SpecsTest extends munit.FunSuite:
  test("specs prints the kernel and exits 0"):
    val r = TestKit.piabrota(Seq("specs"))
    assertEquals(r.exitCode, 0)
    assert(r.out.text().linesIterator.exists(_.startsWith("kernel       ")), r.out.text())
