package piabrota.scripts

import piabrota.lib.{Sh, TestKit}

/** hermes-checkpoint with a stub systemctl and a fixture gateway.pid. A live pid is 1 (the init of
  * the sandbox or the box) or this test's own; nothing is signalled.
  */
class HermesCheckpointTest extends munit.FunSuite:
  // STUB_ACTIVE=0 makes is-active fail; STUB_RELOAD_FAIL=1 makes reload fail; a reload writes
  // STUB_NEW_PID into gateway.pid, as the restarted gateway does.
  private val systemctl = """#!/bin/sh
echo "systemctl $*" >>"$LOG"
case $1 in
  is-active) [ "${STUB_ACTIVE:-1}" = 1 ]; exit ;;
  reload)
    [ "${STUB_RELOAD_FAIL:-0}" = 1 ] && exit 1
    [ -n "${STUB_NEW_PID:-}" ] && printf '{"pid": %s, "kind": "hermes-gateway"}\n' "$STUB_NEW_PID" >"$HERMES_HOME/gateway.pid"
    exit 0 ;;
esac
exit 0
"""
  private val work = os.temp.dir(prefix = "hc")
  private val home = work / "home"
  private val log = work / "calls.log"
  private val unit = work / "hermes-agent.service"
  os.makeDir(home)
  os.write(unit, "[Service]\n")
  private val fakes = TestKit.fakes("systemctl" -> systemctl)
  private val same = Sh.out("sha256sum", unit).takeWhile(_ != ' ')
  private val other = "0" * 64
  private val self = os.readLink(os.Path("/proc/self")).toString

  private def pidfile(pid: String) = os.write.over(home / "gateway.pid", s"""{"pid": $pid, "kind": "hermes-gateway"}\n""")

  private def check(name: String, args: Seq[String], status: Int, pattern: String, reloaded: Boolean,
      extra: Map[String, String] = Map.empty): Unit =
    os.write.over(log, "")
    val env = Map("LOG" -> log.toString, "HERMES_HOME" -> home.toString, "HC_UNIT" -> unit.toString,
      "HC_POLL" -> "1", "HC_TIMEOUT" -> "3") ++ extra
    val r = TestKit.piabrota("hermes-checkpoint" +: args, env = env, fakes = Some(fakes))
    val out = r.out.text() + r.err.text()
    assertEquals(r.exitCode, status, s"$name: $out")
    assert(out.contains(pattern), s"$name: $out")
    assertEquals(os.read.lines(log).exists(_.startsWith("systemctl reload")), reloaded, s"$name: reload")

  test("no argument is a usage error")(check("none", Nil, 2, "usage", false))
  test("a bad hash is a usage error")(check("bad", Seq("not-a-hash"), 2, "usage", false))
  test("a host without Hermes is left alone"):
    check("missing", Seq(other), 0, "no hermes-agent.service", false, Map("HC_UNIT" -> (work / "missing").toString))
  test("an unchanged unit is left alone"):
    pidfile("1")
    check("same", Seq(same), 0, "does not change", false)
  test("an inactive unit is left alone"):
    pidfile("1")
    check("inactive", Seq(other), 0, "not active", false, Map("STUB_ACTIVE" -> "0"))
  test("no gateway.pid: nothing in flight"):
    os.remove(home / "gateway.pid")
    check("no pid", Seq(other), 0, "no gateway runs", false)
  test("a dead pid: nothing in flight"):
    pidfile("999999999")
    check("dead", Seq(other), 0, "no gateway runs", false)
  test("a changed unit is reloaded and waited for"):
    pidfile("1")
    check("reload", Seq(other), 0, "checkpoint done", true, Map("STUB_NEW_PID" -> self))
  test("a gateway that never comes back times out, exit 0"):
    pidfile("1")
    check("timeout", Seq(other), 0, "did not restart within 3 s", true)
  test("a failed reload warns, exit 0"):
    pidfile("1")
    check("reload fails", Seq(other), 0, "reload hermes-agent.service failed", true, Map("STUB_RELOAD_FAIL" -> "1"))
