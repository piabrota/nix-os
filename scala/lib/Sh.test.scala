package piabrota.lib

class ShTest extends munit.FunSuite:
  test("out trims the trailing newline"):
    assertEquals(Sh.out("printf", "a\\n\\n"), "a")
  test("ok is the exit code"):
    assert(Sh.ok("true"))
    assert(!Sh.ok("false"))
  test("outOpt is None for a missing program"):
    assertEquals(Sh.outOpt("no-such-program-here"), None)
  test("out dies with the exit code"):
    val e = intercept[Exit](Sh.out("sh", "-c", "echo boom >&2; exit 3"))
    assertEquals(e.code, 3)
    assert(e.message.contains("boom"))
