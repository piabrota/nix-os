package piabrota.scripts

import piabrota.lib.TestKit

/** marola-boards-mirror against a stub curl that serves $SITE, and loco-backup with a stub sqlite3. */
class MarolaBoardsTest extends munit.FunSuite:
  private val curl = """#!/bin/sh
# curl -fsS --max-time N URL -o FILE
f="$SITE/${4#https://src.test/}"
[ -f "$f" ] || { echo "curl: (22) 404" >&2; exit 22; }
cp "$f" "$6"
"""
  private val work = os.temp.dir(prefix = "boards")
  private val site = work / "site"
  private val out = work / "out"
  os.makeDir.all(out)
  os.write(work / "areas.json", """{"areas":[{"id":"rio"},{"id":"bad"},{"id":"gone"},{"id":"half"}]}""")
  os.write(site / "rio" / "latest.json", """{"days":[{"file":"2026-11-14.json"}]}""", createFolders = true)
  os.write(site / "rio" / "2026-11-14.json", "{}")
  os.write(site / "bad" / "latest.json", """{"days":[{"file":"../../etc/passwd"}]}""", createFolders = true)
  os.write(site / "half" / "latest.json", """{"days":[{"file":"2026-11-13.json"}]}""", createFolders = true)
  os.write(out / "half" / "old.json", "kept", createFolders = true)
  os.write(out / "rio" / "stale.json", "gone", createFolders = true)

  test("each area is replaced whole, or kept as it was"):
    val r = TestKit.piabrota(Seq("marola-boards-mirror", "https://src.test", out.toString, (work / "areas.json").toString),
      env = Map("SITE" -> site.toString), fakes = Some(TestKit.fakes("curl" -> curl)))
    val err = r.err.text()
    assertEquals(r.exitCode, 0, err)
    assertEquals(os.list(out / "rio").map(_.last).toList, List("2026-11-14.json", "latest.json"))
    assertEquals(os.perms(out / "rio").toString, "rwxr-xr-x")
    assert(err.contains("marola-boards: rio updated"), err)
    assert(err.contains("marola-boards: bad: refused file name ../../etc/passwd"), err)
    assert(err.contains("marola-boards: no latest.json for gone"), err)
    assert(err.contains("marola-boards: half kept as it was"), err)
    assertEquals(os.read(out / "half" / "old.json"), "kept")
    assertEquals(os.list(out).map(_.last).filter(_.startsWith(".")).toList, Nil)

  test("loco-backup: a dated copy, and the old ones go"):
    val state = work / "loco"
    os.write(state / "db.sqlite", "db", createFolders = true)
    os.write(state / "backup" / "db-2000-01-01.sqlite", "old", createFolders = true)
    os.proc("touch", "-d", "2000-01-01", state / "backup" / "db-2000-01-01.sqlite").call()
    val sqlite3 = "#!/bin/sh\necho \"$*\" > \"$LOG\"\n"
    val log = work / "sqlite.log"
    val r = TestKit.piabrota(Seq("loco-backup", state.toString), env = Map("LOG" -> log.toString),
      fakes = Some(TestKit.fakes("sqlite3" -> sqlite3)))
    assertEquals(r.exitCode, 0, r.err.text())
    val today = os.proc("date", "+%F").call().out.text().trim
    assertEquals(os.read(log).trim, s"$state/db.sqlite .backup '$state/backup/db-$today.sqlite'")
    assert(!os.exists(state / "backup" / "db-2000-01-01.sqlite"))
