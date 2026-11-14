package piabrota.hermes

import piabrota.lib.{Sh, TestKit}
import scala.concurrent.duration.*

/** omp-run with a fake omp: a normal run, a stop with --stop, SIGTERM to omp-run (Hermes's own kill)
  * and to its process group, SIGTERM to omp only, and a missing task file.
  */
class OmpRunTest extends munit.FunSuite:
  override val munitTimeout = 60.seconds

  private val fakeOmp = """#!/bin/sh
cat >/dev/null
echo '{"type":"session","cwd":"/work"}'
[ "${FAKE_SLEEP:-0}" = 0 ] || exec sleep "$FAKE_SLEEP"
echo '{"type":"agent_end"}'
"""

  /** A task directory with the task t, its progress file and the programs on a PATH. */
  private final class Setup:
    val tasks = os.temp.dir(prefix = "omp-tasks")
    os.write(tasks / "t.md", "task\n")
    os.write(tasks / "t.progress", "step 1 done\n")
    val bin = TestKit.fakes(
      "omp" -> fakeOmp,
      "omp-stream" -> s"#!/bin/sh\nexec ${TestKit.bin} omp-stream\n",
      "omp-run" -> s"#!/bin/sh\nexec ${TestKit.bin} omp-run \"$$@\"\n",
    )
    val path = s"$bin:${sys.env.getOrElse("PATH", "")}"
    val out = tasks / "out"
    def env(sleep: Int) = Map("OMP_TASKS" -> tasks.toString, "PATH" -> path, "FAKE_SLEEP" -> sleep.toString)

    /** omp-run t in the background; returns once omp runs. `cmd` wraps it, as Hermes's bash -lic does. */
    def start(sleep: Int, cmd: Seq[String] = Seq(TestKit.bin.toString, "omp-run", "t")): os.SubProcess =
      val p = os.proc(cmd).spawn(env = env(sleep), stdin = "", stdout = out, stderr = os.Path(out.toString + ".err"))
      val end = System.nanoTime() + 5e9.toLong
      while !(os.exists(tasks / "t.pid") && os.read(tasks / "t.pid").nonEmpty) && System.nanoTime() < end do
        Thread.sleep(100)
      Thread.sleep(300)
      p

    def stop(): os.CommandResult =
      os.proc(TestKit.bin, "omp-run", "--stop", "t").call(env = env(0), check = false, stderr = os.Pipe)

    /** The run ended with `code`, printed each text, and left no pid file. */
    def expect(p: os.SubProcess, code: Int, texts: String*): Unit =
      p.waitFor(50000)
      val text = os.read(out)
      texts.foreach(t => assert(text.contains(t), s"no line '$t' in:\n$text"))
      assert(!text.contains("tcsetattr"), text)
      assert(!os.exists(tasks / "t.pid"))
      assertEquals(p.exitCode(), code, text)

  test("a normal run prints omp's lines and the progress file, and exits 0"):
    val s = Setup()
    s.expect(s.start(0), 0, "omp: start in /work", "omp: done, 0 turns", "omp-run: progress file", "step 1 done")

  test("--stop ends the run with 0"):
    val s = Setup()
    val p = s.start(30)
    val r = s.stop()
    assert(r.out.text().contains("omp-run: stopped t"), r.out.text())
    s.expect(p, 0, "omp: start in /work", "stopped on request", "step 1 done")

  test("SIGTERM to omp-run ends it with 143, by a code"):
    val s = Setup()
    val p = s.start(30)
    Proc.kill(p.wrapped.pid().toInt, Proc.SIGTERM)
    s.expect(p, 143, "omp: start in /work", "stopped by SIGTERM, not by omp-run --stop", "step 1 done")

  test("SIGTERM to the process group of bash -lic, as Hermes kills a background task"):
    assume(Sh.which("setsid").isDefined && Sh.which("bash").isDefined, "needs setsid and bash")
    val s = Setup()
    val p = s.start(30, Seq("setsid", "bash", "-lic", "set +m; omp-run t"))
    Proc.kill(-p.wrapped.pid().toInt, Proc.SIGTERM)
    s.expect(p, 143, "omp: start in /work", "stopped by SIGTERM, not by omp-run --stop", "step 1 done")

  test("SIGTERM to omp only: omp was stopped by signal 15"):
    val s = Setup()
    val p = s.start(30)
    Proc.kill(os.read(s.tasks / "t.pid").trim.toInt, Proc.SIGTERM)
    s.expect(p, 143, "omp was stopped by signal 15")

  test("a missing task file"):
    val s = Setup()
    os.remove(s.tasks / "t.md")
    val r = TestKit.piabrota(Seq("omp-run", "t"), env = s.env(0))
    assertEquals(r.exitCode, 1)
    assert(r.out.text().startsWith("omp-run: no task file"), r.out.text())

  test("--stop with no run, a bad name, no arguments"):
    val s = Setup()
    val r = TestKit.piabrota(Seq("omp-run", "--stop", "t"), env = s.env(0))
    assertEquals((r.exitCode, r.out.text()), (1, "omp-run: no run named t\n"))
    assertEquals(TestKit.piabrota(Seq("omp-run", "../x"), env = s.env(0)).exitCode, 2)
    assertEquals(TestKit.piabrota(Seq("omp-run"), env = s.env(0)).exitCode, 2)
