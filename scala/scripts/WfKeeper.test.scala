package piabrota.scripts

import piabrota.lib.TestKit

/** openrig-wf-keeper against a fake `rig` that answers from fixture files in $FAKE. */
class WfKeeperTest extends munit.FunSuite:
  private val fakeRig = """#!/bin/sh
case "$*" in
  status) cat "$FAKE/status"; exit 0 ;;
  "ps --json") cat "$FAKE/ps.json" ;;
  "ps --nodes --rig wave-forecaster-dev --json") cat "$FAKE/nodes.json" ;;
  "up wave-forecaster-dev --existing") echo existing >>"$FAKE/calls"; exit "$(cat "$FAKE/existing.rc")" ;;
  "up /etc/openrig/specs/rigs/wave-forecaster-dev/rig.yaml") echo spec >>"$FAKE/calls"; exit "$(cat "$FAKE/spec.rc")" ;;
  *) echo "fake rig: unexpected call: $*" >&2; exit 99 ;;
esac
"""
  private val work = os.temp.dir(prefix = "keeper")
  private val fake = work / "fake"
  private val state = work / "state"
  private val attempts = state / "attempts"
  os.makeDir(fake)
  os.makeDir(state)
  private val fakes = TestKit.fakes("rig" -> fakeRig)

  private def port(status: String, attention: Int, running: Int) =
    s"""[{"name":"wave-forecaster-dev","status":"$status","attentionCount":$attention,"isArchived":false,"runningCount":$running}]"""
  private val stoppedNodes =
    """[{"logicalId":"port.porter","lifecycleState":"stopped","intentionallyStopped":false},{"logicalId":"port.auditor","lifecycleState":"stopped"}]"""

  private def run(rigs: String, nodes: String, existingRc: Int, specRc: Int, att: Option[String] = None,
      daemon: Boolean = true): (Int, String, String) =
    os.write.over(fake / "calls", "")
    os.write.over(fake / "status", if daemon then "Daemon running on port 7433\n" else "Daemon not running.\n")
    os.write.over(fake / "ps.json", rigs)
    os.write.over(fake / "nodes.json", nodes)
    os.write.over(fake / "existing.rc", s"$existingRc\n")
    os.write.over(fake / "spec.rc", s"$specRc\n")
    att match
      case None    => os.remove(attempts)
      case Some(t) => os.write.over(attempts, t)
    val r = TestKit.piabrota(Seq("openrig-wf-keeper"), env = Map("FAKE" -> fake.toString, "STATE_DIRECTORY" -> state.toString),
      fakes = Some(fakes))
    (r.exitCode, os.read(fake / "calls").split("\\s+").filter(_.nonEmpty).mkString(" "), r.out.text() + r.err.text())

  private val now = java.time.Instant.now().getEpochSecond
  private val (old, recent) = (now - 7200, now - 600)

  // name, rigs, nodes, existing rc, spec rc, attempts, exit, calls, a line of the output
  private val cases = List(
    ("daemon down", "[]", "[]", 0, 0, None, 0, "", "daemon not running"),
    ("running", port("running", 0, 2), "[]", 0, 0, None, 0, "", "runs"),
    ("running, attention", port("running", 2, 2), "[]", 0, 0, None, 0, "", "<4>"),
    ("partial", port("partial", 0, 1),
      """[{"logicalId":"port.auditor","lifecycleState":"stopped"},{"logicalId":"port.porter","lifecycleState":"running"}]""",
      0, 0, None, 0, "", "port.auditor=stopped"),
    ("stopped, snapshot", port("stopped", 0, 0), stoppedNodes, 0, 1, None, 0, "existing", "restored"),
    ("stopped, existing fails", port("stopped", 0, 0), stoppedNodes, 1, 0, None, 0, "existing spec", "started from"),
    ("stopped, both fail", port("stopped", 0, 0), stoppedNodes, 1, 1, None, 1, "existing spec", "<3>"),
    ("stopped on purpose", port("stopped", 0, 0),
      """[{"logicalId":"a","intentionallyStopped":true},{"logicalId":"b","intentionallyStopped":true}]""",
      0, 0, None, 0, "", "on purpose"),
    ("no rig of that name", "[]", "[]", 1, 0, None, 0, "spec", "started from"),
    ("archived rig is ignored", """[{"name":"wave-forecaster-dev","status":"running","isArchived":true,"runningCount":2}]""",
      "[]", 1, 0, None, 0, "spec", "started from"),
    ("another rig runs",
      """[{"name":"piabrota-dev","status":"running","isArchived":false,"runningCount":2},{"name":"wave-forecaster-dev","status":"stopped","isArchived":false,"runningCount":0}]""",
      stoppedNodes, 0, 0, None, 0, "", "another rig runs: piabrota-dev, skipped"),
    ("3 attempts in the last hour", port("stopped", 0, 0), stoppedNodes, 0, 0, Some(s"$recent\n" * 3), 1, "", "<3>"),
    ("old attempts are dropped", port("stopped", 0, 0), stoppedNodes, 0, 0, Some(s"$old\n" * 3), 0, "existing", "restored"),
  )

  for (name, rigs, nodes, erc, src, att, wantExit, wantCalls, wantOut) <- cases do
    test(name):
      val (code, calls, out) = run(rigs, nodes, erc, src, att, daemon = name != "daemon down")
      assertEquals((code, calls), (wantExit, wantCalls), out)
      assert(out.contains(wantOut), out)

  test("an envelope with .entries is read as the list"):
    val (code, _, out) = run(s"""{"entries":${port("running", 0, 2)}}""", "[]", 0, 0)
    assertEquals(code, 0, out)
    assert(out.contains("wave-forecaster-dev runs"), out)

  test("the attempts file keeps the recent lines and adds one; the old ones go"):
    run(port("stopped", 0, 0), stoppedNodes, 0, 0, Some(s"$old\n$recent\n"))
    val lines = os.read(attempts).split("\\s+").filter(_.nonEmpty).toList
    assertEquals(lines.size, 2)
    assert(!lines.contains(old.toString))
