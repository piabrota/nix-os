package piabrota.design

import piabrota.lib.TestKit

class DarkGateTest extends munit.FunSuite:
  private val archify = s"""<html class="archify-theme"><script>new ${Archify.readsTheme}</script></html>"""

  test("a shell pattern: * is any text, / included; ? one character; the rest as it is"):
    assert(DarkGate.pattern("dist/figures/*.html").matches("dist/figures/a/b.html"))
    assert(DarkGate.pattern("a?c.html").matches("abc.html"))
    assert(!DarkGate.pattern("a.c").matches("abc"))
    assert(!DarkGate.pattern("dist/figures/*.html").matches("dist/other/x.html"))

  test("proof-dark-gate: archify pages in their place pass; others fail with the page's path"):
    val dir = os.temp.dir(prefix = "dark")
    os.write(dir / "dist" / "figures" / "a.html", archify, createFolders = true)
    os.write(dir / "dist" / "plain.html", "<html></html>")
    val ok = TestKit.piabrota(Seq("proof-dark-gate", "dist", "dist/figures/*.html"), cwd = dir)
    assertEquals((ok.exitCode, ok.err.text()), (0, ""))

    os.write(dir / "dist" / "stray.html", archify)
    val stray = TestKit.piabrota(Seq("proof-dark-gate", "dist", "dist/figures/*.html"), cwd = dir)
    assertEquals((stray.exitCode, stray.err.text()), (1, "dist/stray.html: an archify page outside proof.nix's dark location\n"))
    val two = TestKit.piabrota(Seq("proof-dark-gate", "dist", "dist/figures/*.html", "dist/stray.html"), cwd = dir)
    assertEquals(two.exitCode, 0, two.err.text())

    os.write.over(dir / "dist" / "figures" / "a.html", "<html class=\"archify-theme\"></html>")
    val old = TestKit.piabrota(Seq("proof-dark-gate", "dist", "dist/figures/*.html", "dist/stray.html"), cwd = dir)
    assertEquals((old.exitCode, old.err.text()), (1, "dist/figures/a.html: archify no longer reads ?theme= from the address\n"))
