package piabrota.hermes

import piabrota.lib.TestKit
import scala.concurrent.duration.*

/** gateway-wrapper with a stub gateway. Its plan, in STUB_PLAN, says what each start does:
  * `exit:N` exits N at once, `sleep:S:N` sleeps S seconds and exits N, `run` runs until TERM and
  * logs USR1 (and "ready" once its traps are set). The last word repeats for every later start.
  * About a minute in all.
  */
class GatewayWrapperTest extends munit.FunSuite:
  override val munitTimeout = 90.seconds

  private val stub = """#!/bin/sh
now() { date +%s.%N; }
echo "$(now) start $$" >>"$STUB_LOG"
n=$(grep -c ' start ' "$STUB_LOG")
set -- $STUB_PLAN
[ "$n" -gt "$#" ] && n=$#
eval "step=\${$n}"
case $step in
exit:*) echo "$(now) exit $$" >>"$STUB_LOG"; exit "${step#exit:}" ;;
sleep:*)
    rest=${step#sleep:}
    sleep "${rest%%:*}"
    echo "$(now) exit $$" >>"$STUB_LOG"
    exit "${rest#*:}"
    ;;
run)
    sleeper=
    trap 'echo "$(now) usr1 $$" >>"$STUB_LOG"' USR1
    trap 'echo "$(now) term $$" >>"$STUB_LOG"; [ -n "$sleeper" ] && kill "$sleeper"; exit 0' TERM INT
    sleep 1000 &
    sleeper=$!
    echo "$(now) ready $$" >>"$STUB_LOG"
    while kill -0 "$sleeper" 2>/dev/null; do wait "$sleeper"; done
    ;;
esac
"""

  /** One wrapper under test, with its own home, stub log and stderr file. */
  private final class Case(plan: String, extraEnv: Map[String, String] = Map.empty,
      withForeign: Boolean = false):
    val dir = os.temp.dir(prefix = "gateway-wrapper")
    val home = dir / "home"
    os.makeDir(home)
    val log = dir / "stub.log"
    os.write(log, "")
    val err = dir / "err"
    private val fakes = TestKit.fakes("gateway" -> stub)
    private val env = Map(
      "HERMES_HOME" -> home.toString, "GATEWAY_WRAPPER_FAST_EXIT_SECS" -> "2",
      "GATEWAY_WRAPPER_POLL_SECS" -> "1", "STUB_LOG" -> log.toString, "STUB_PLAN" -> plan,
    ) ++ extraEnv
    // A foreign gateway: a sleeper named in gateway.pid before the wrapper starts.
    private val foreignProc = Option.when(withForeign)(os.proc("sleep", "1000").spawn())
    val foreign: Int = foreignProc.fold(0)(_.wrapped.pid().toInt)
    if withForeign then
      os.write(home / "gateway.pid", s"""{"pid": $foreign, "kind": "hermes-gateway"}""" + "\n")

    val proc: os.SubProcess = os.proc(TestKit.bin, "gateway-wrapper", fakes / "gateway")
      .spawn(env = env, stdout = os.Inherit, stderr = err)
    def pid: Int = proc.wrapped.pid().toInt

    def starts: Int = os.read.lines(log).count(_.contains(" start "))
    def hasLog(word: String): Boolean = os.read(log).contains(word)
    def hasErr(text: String): Boolean = os.exists(err) && os.read(err).contains(text)
    def alive: Boolean = proc.isAlive()
    def signal(sig: Int): Unit = Proc.kill(pid, sig)
    def exitCode(): Int = { proc.waitFor(30000); proc.exitCode() }
    def stop(): Int = { signal(Proc.SIGTERM); exitCode() }

    /** Seconds from the first line with word `a` to the next line with word `b`. */
    def gap(a: String, b: String): Double =
      val lines = os.read.lines(log).map(_.split(' '))
      val i = lines.indexWhere(_(1) == a)
      val j = lines.indexWhere(_(1) == b, i + 1)
      lines(j)(0).toDouble - lines(i)(0).toDouble

    def endForeign(): Unit = foreignProc.foreach(p => { p.destroy(); p.waitFor(5000) })
    def foreignAlive: Boolean = foreignProc.exists(_.isAlive())

  private def waitFor(seconds: Double)(cond: => Boolean): Boolean =
    val end = System.nanoTime() + (seconds * 1e9).toLong
    while !cond && System.nanoTime() < end do Thread.sleep(100)
    cond

  test("a: exit 75 restarts the gateway at once, the wrapper stays up and signals reach the new gateway"):
    val c = Case("exit:75 run")
    assert(waitFor(5)(c.starts >= 2))
    assert(c.gap("exit", "start") < 1, os.read(c.log))
    assert(c.alive)
    assert(waitFor(2)(c.hasErr("gateway exited 75 (reload): starting it again")))
    assert(waitFor(3)(c.hasLog(" ready ")))
    c.signal(Proc.SIGUSR1)
    assert(waitFor(3)(c.hasLog(" usr1 ")))
    assertEquals(c.stop(), 0)

  test("b: 6 exits of 75 within 60 s: exit 1"):
    val c = Case("exit:75")
    assertEquals(c.exitCode(), 1)
    assertEquals(c.starts, 6)
    assert(c.hasErr("gateway exited 75 6 times in 60 s: giving up"))

  test("c: another exit status is the wrapper's"):
    val c = Case("exit:7")
    assertEquals(c.exitCode(), 7)
    assertEquals(c.starts, 1)

  test("d: exit 0 after the fast-exit limit, no other gateway"):
    val c = Case("sleep:3:0")
    assertEquals(c.exitCode(), 0)
    assertEquals(c.starts, 1)

  for body <- List("none", """{"pid": 999999999}""", "not json", """{"pid": "x"}""") do
    test(s"d2: fast exit 0 with the pid file '$body': exit 0, no restart"):
      val dir = os.temp.dir()
      // The pid file has to be there before the wrapper starts.
      val home = dir / "home"
      if body != "none" then os.write(home / "gateway.pid", body + "\n", createFolders = true)
      val log = dir / "log"
      val r = TestKit.piabrota(Seq("gateway-wrapper", (TestKit.fakes("gateway" -> stub) / "gateway").toString),
        env = Map("HERMES_HOME" -> home.toString, "GATEWAY_WRAPPER_FAST_EXIT_SECS" -> "2",
          "STUB_LOG" -> log.toString, "STUB_PLAN" -> "exit:0"))
      assertEquals(r.exitCode, 0)
      assertEquals(os.read.lines(log).count(_.contains(" start ")), 1)

  // The real gateway exits 75 when another gateway serves the host (the box, 2026-11-05). Older
  // versions may exit 0. Both are the same case.
  for code <- List(75, 0) do
    test(s"e$code: a fast exit $code while another gateway lives waits for it, with no restart storm"):
      val c = Case(s"exit:$code run", Map("GATEWAY_WRAPPER_POLL_SECS" -> "5"), withForeign = true)
      assert(waitFor(3)(
        c.hasErr(s"another gateway (pid ${c.foreign}) serves this host (the gateway exited $code): waiting for it to exit")))
      Thread.sleep(6000)
      assert(c.alive)
      assertEquals(c.starts, 1)
      assert(!c.hasErr("starting it again"))
      c.endForeign()
      assert(waitFor(6.5)(c.starts == 2))
      assert(c.hasErr("has exited: starting our own"))
      assert(c.alive)
      c.stop()

  test("e-storm: the gateway exits 75 at once on every start while another gateway lives"):
    val c = Case("exit:75", withForeign = true)
    Thread.sleep(5000)
    assert(c.alive)
    assertEquals(c.starts, 1)
    c.stop()
    c.endForeign()

  test("e2: the start after the wait is not a reload (limit 1 reload)"):
    val c = Case("exit:75 exit:75 run", Map("GATEWAY_WRAPPER_MAX_RELOADS" -> "1"), withForeign = true)
    assert(waitFor(3)(c.hasErr("waiting for it to exit")))
    c.endForeign()
    assert(waitFor(8)(c.starts >= 2))
    Thread.sleep(1000)
    assert(c.alive)
    assertEquals(c.starts, 3)
    c.stop()

  test("e3: a real reload (the gateway ran 3 s) restarts at once, with another live process in gateway.pid"):
    val c = Case("sleep:3:75 run", Map("GATEWAY_WRAPPER_FAST_EXIT_SECS" -> "1"), withForeign = true)
    assert(waitFor(8)(c.starts >= 2))
    assert(c.gap("start", "exit") > 2.5)
    assert(c.gap("exit", "start") < 1)
    assert(waitFor(2)(c.hasErr("gateway exited 75 (reload): starting it again")))
    assert(!c.hasErr("serves this host"))
    assert(c.alive)
    c.stop()
    c.endForeign()

  test("f: TERM while it waits for the other gateway ends it at once with 0; USR1 does not"):
    val c = Case("exit:0 run", withForeign = true)
    assert(waitFor(3)(c.hasErr("waiting for it to exit")))
    c.signal(Proc.SIGUSR1)
    Thread.sleep(500)
    assert(c.alive)
    val t0 = System.nanoTime()
    assertEquals(c.stop(), 0)
    assert((System.nanoTime() - t0) / 1e9 < 1)
    assert(c.foreignAlive)
    assertEquals(c.starts, 1)
    c.endForeign()

  test("g: SIGUSR1 reaches the gateway"):
    val c = Case("run")
    assert(waitFor(3)(c.hasLog(" ready ")))
    c.signal(Proc.SIGUSR1)
    assert(waitFor(3)(c.hasLog(" usr1 ")))
    assert(c.alive)
    c.stop()

  test("h: TERM reaches the gateway and the wrapper exits 0"):
    val c = Case("run")
    assert(waitFor(3)(c.hasLog(" ready ")))
    assertEquals(c.stop(), 0)
    assert(c.hasLog(" term "))

  test("readPid takes a number or a string of digits, and nothing else"):
    val f = os.temp()
    def pid(text: String) = { os.write.over(f, text); GatewayWrapper.readPid(f) }
    assertEquals(pid("""{"pid": 42}"""), Some(42L))
    assertEquals(pid("""{"pid": "42"}"""), Some(42L))
    assertEquals(pid("""{"pid": 1.5}"""), None)
    assertEquals(pid("""{"pid": "x"}"""), None)
    assertEquals(pid("not json"), None)
    assertEquals(GatewayWrapper.readPid(f / os.up / "missing"), None)
