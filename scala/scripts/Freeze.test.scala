package piabrota.scripts

class FreezeTest extends munit.FunSuite:
  private val pathInfo = """/nix/store/aaaa-bash-interactive-5.3p9	2097152
/nix/store/bbbb-etc	512
/nix/store/cccc-Zlib-1.3	2048
/nix/store/dddd-acl-2.3.2	1073741824
"""

  test("name==version, sorted by name without case, the total last"):
    assertEquals(Freeze.report(pathInfo, bySize = false), List(
      f"${"acl==2.3.2"}%-56s ${"1.00 GiB"}%12s",
      f"${"bash-interactive==5.3p9"}%-56s ${"2.0 MiB"}%12s",
      f"${"Zlib==1.3"}%-56s ${"2.0 KiB"}%12s",
      "# 3 packages, 4 store paths, 1.00 GiB",
    ))

  test("--by-size puts the largest first"):
    assertEquals(Freeze.report(pathInfo, bySize = true).map(_.takeWhile(_ != ' ')),
      List("acl==2.3.2", "bash-interactive==5.3p9", "Zlib==1.3", "#"))

  test("a path with no version is no package"):
    assertEquals(Freeze.nameVersion("/nix/store/abc-unit-nginx.service"), None)
    assertEquals(Freeze.human(1023), "1023 B")
