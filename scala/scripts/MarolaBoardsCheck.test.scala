package piabrota.scripts

import piabrota.lib.TestKit

/** marola-boards-check against a stub curl: rio is fresh, bahia is a day old, gone has no board. */
class MarolaBoardsCheckTest extends munit.FunSuite:
  private def iso(hoursAgo: Long) = java.time.Instant.now().minusSeconds(hoursAgo * 3600 + 60).toString

  private val curl = s"""#!/bin/sh
case "$$2" in
  */data/areas.json) echo '{"areas":[{"id":"rio"},{"id":"bahia"},{"id":"gone"}]}' ;;
  */data/rio/latest.json) echo '{"generated_at":"${iso(2)}"}' ;;
  */data/bahia/latest.json) echo '{"generated_at":"${iso(30)}"}' ;;
  *) echo "curl: (22) The requested URL returned error: 404" >&2; exit 22 ;;
esac
"""

  test("a row per area; an old or missing board fails"):
    val r = TestKit.piabrota(Seq("marola-boards-check", "https://example.test"), fakes = Some(TestKit.fakes("curl" -> curl)))
    val out = r.out.text()
    assertEquals(r.exitCode, 1, out + r.err.text())
    assert(out.linesIterator.exists(l => l.startsWith("| rio | ") && l.endsWith("(2 h ago) | ✓ |")), out)
    assert(out.linesIterator.exists(l => l.startsWith("| bahia | ") && l.endsWith("(30 h ago) | ✗ older than 12 h |")), out)
    assert(out.contains("| gone | no latest.json | ✗ |"), out)
    assert(r.err.text().contains("marola boards are stale on https://example.test"), r.err.text())

  test("every board fresh: exit 0"):
    val r = TestKit.piabrota(Seq("marola-boards-check", "https://example.test"), env = Map("MAX_AGE_HOURS" -> "48"),
      fakes = Some(TestKit.fakes("curl" -> curl.replace("""{"id":"gone"}""", """{"id":"rio"}"""))))
    assertEquals(r.exitCode, 0, r.out.text() + r.err.text())
