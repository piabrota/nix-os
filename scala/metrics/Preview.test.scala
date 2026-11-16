package piabrota.metrics

import piabrota.lib.TestKit

/** The preview server (the old metrics/test/preview.py --check) and the pull with a fake curl. */
class PreviewTest extends munit.FunSuite:
  test("--check serves the page and the healthy case"):
    val r = TestKit.piabrota(Seq("metrics-preview", "--check"), Map("METRICS_DIR" -> Fixtures.tree().toString))
    assertEquals(r.out.text(), "5 checks, 0 failed\n", r.err.text())
    assertEquals(r.exitCode, 0)

  test("an unknown case exits 2"):
    val r = TestKit.piabrota(Seq("metrics-preview", "nope"), Map("METRICS_DIR" -> Fixtures.tree().toString))
    assertEquals(r.exitCode, 2)
    assertEquals(r.err.text().trim, "no such case: nope (healthy, hostile, missing, stale)")

  test("live moves the times to now and keeps the JSON valid"):
    val raw = Fixtures.cases("hostile")("piabrota2.json")
    val live = Preview.live(raw, 1000).flatMap(Json.parse).get
    assertEquals(live("ts"), Json.num(998L))
    assert(!Json.write(live).contains("Infinity"))
    val healthy = Preview.live(Fixtures.cases("healthy")("piabrota2.json"), 1000).flatMap(Json.parse).get
    assertEquals(healthy("domains")("ts"), Json.num(960L))

class PullTest extends munit.FunSuite:
  /** A curl that writes `body` to the -o file, or fails when it is empty. */
  private def fakes(body: String) = TestKit.fakes("curl" -> s"""#!/bin/sh
while [ $$# -gt 0 ]; do [ "$$1" = -o ] && out=$$2; shift; done
[ -n '$body' ] || exit 22
printf '%s' '$body' > "$$out"
""")

  private def pull(dir: os.Path, body: String) =
    TestKit.piabrota(Seq("metrics-pull"), Map("METRICS_PULL_URL" -> "http://edge/x.json", "METRICS_PULL_NAME" -> "piabrota",
      "OUT_DIR" -> dir.toString), fakes = Some(fakes(body)))

  test("a good file is kept; a failed fetch or another host's file leaves it"):
    val dir = os.temp.dir(prefix = "pull")
    val good = """{"v":1,"host":"piabrota","ts":1}"""
    val r = pull(dir, good)
    assertEquals((r.exitCode, r.err.text()), (0, ""))
    assertEquals(os.read(dir / "piabrota.json"), good)
    val failed = pull(dir, "")
    assertEquals(failed.exitCode, 0)
    assertEquals(failed.err.text().trim, "pull: fetch of http://edge/x.json failed; the old file stays")
    val other = pull(dir, """{"host":"piabrota2"}""")
    assertEquals(other.exitCode, 0)
    assertEquals(other.err.text().trim, "pull: http://edge/x.json did not return the file of piabrota; the old file stays")
    assertEquals(os.read(dir / "piabrota.json"), good)
    assertEquals(os.list(dir).map(_.last), Seq("piabrota.json"), "no temp file left")

  test("a bad name exits 2"):
    val r = TestKit.piabrota(Seq("metrics-pull"), Map("METRICS_PULL_URL" -> "x", "METRICS_PULL_NAME" -> "A"))
    assertEquals(r.exitCode, 2)
    assertEquals(r.err.text().trim, "pull: bad METRICS_PULL_NAME")
