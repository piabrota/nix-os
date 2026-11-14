package piabrota.hermes

import piabrota.lib.{die, env, warn}
import Proc.{SIGCHLD, SIGHUP, SIGINT, SIGQUIT, SIGTERM}

/** `omp-run`: runs one omp task in the background of Hermes's terminal, and stops one.
  *
  *   omp-run <name> [omp flags]   runs `omp -p --mode json --no-title [flags] < omp-tasks/<name>.md`
  *                                through omp-stream, then prints how the run ended and the
  *                                progress file omp-tasks/<name>.progress
  *   omp-run --stop <name>        stops that run and waits until it has ended
  *
  * Hermes starts a background command as `bash -lic`, with no terminal. When a signal kills the last
  * command of that shell, bash prints "tcsetattr: Inappropriate ioctl for device" and the task ends
  * as a failure with exit 143. omp-run is never killed by a signal: it takes SIGTERM, SIGINT and
  * SIGHUP, passes SIGTERM to omp, lets omp-stream print the last lines and exits with a code. A stop
  * with --stop ends with 0, so it is not reported as a failure. omp-tasks is OMP_TASKS, by default
  * /var/lib/hermes/workspace/omp-tasks.
  */
object OmpRun:
  private val usage = "usage: omp-run <name> [omp flags] | omp-run --stop <name>"
  // The wrapper's timeout sends SIGKILL 30 seconds after SIGTERM: 45 seconds covers it.
  private val StopWaitSecs = 45

  def run(args: List[String]): Int =
    val cfg = OmpConfig.read(env)
    args match
      case "--stop" :: name :: Nil => stop(files(cfg, name))
      case "--stop" :: _           => die(usage, 2)
      case name :: flags           => start(files(cfg, name), flags)
      case Nil                     => die(usage, 2)

  private def files(cfg: OmpConfig, name: String): TaskFiles =
    if !TaskName.valid(name) then die(usage, 2)
    TaskFiles(cfg.tasks, name)

  /** The pid in the pid file, if it holds one. */
  private def readPid(f: TaskFiles): Option[Int] = if os.isFile(f.pid) then os.read(f.pid).trim.toIntOption else None

  /** The answer on stdout and the exit code, as the conversation reads them. */
  private def end(message: String, code: Int): Int = { println(message); code }

  private def stop(f: TaskFiles): Int =
    if !os.isFile(f.pid) then end(s"omp-run: no run named ${f.name}", 1)
    else
      os.write.over(f.stop, "")
      readPid(f).filter(Proc.kill(_, SIGTERM)) match
        case None =>
          os.remove(f.pid)
          os.remove(f.stop)
          end(s"omp-run: ${f.name} is not running", 1)
        case Some(pid) =>
          Iterator.range(0, StopWaitSecs).takeWhile(_ => Proc.alive(pid)).foreach(_ => Thread.sleep(1000))
          if Proc.alive(pid) then end(s"omp-run: ${f.name} still runs $StopWaitSecs s after SIGTERM (pid $pid)", 1)
          else end(s"omp-run: stopped ${f.name}", 0)

  private def start(f: TaskFiles, flags: List[String]): Int =
    if !(os.isFile(f.task) && f.task.toIO.canRead) then end(s"omp-run: no task file ${f.task}", 1)
    else
      readPid(f).filter(Proc.alive) match
        case Some(old) =>
          end(s"omp-run: ${f.name} already runs (pid $old); stop it with: omp-run --stop ${f.name}", 1)
        case None =>
          os.remove(f.stop)
          val (status, signal) = runOmp(f, flags)
          report(f, status, signal)

  /** Runs omp into omp-stream and waits for both. omp's exit status, and the last signal that
    * stopped it (TERM, INT or HUP).
    */
  private def runOmp(f: TaskFiles, flags: List[String]): (Int, Option[StopSignal]) =
    // From here a signal waits for the loops below instead of ending omp-run.
    Proc.block(SIGTERM, SIGINT, SIGHUP, SIGCHLD)
    val (readEnd, writeEnd) = Proc.pipe()
    // omp-stream ignores the signals, so it reads to the end of omp's output and prints the last lines.
    val stream = Proc.spawn(Seq("omp-stream"), ignore = Seq(SIGTERM, SIGINT, SIGHUP, SIGQUIT),
      io = Seq(Proc.Io.Dup(readEnd, 0), Proc.Io.Close(readEnd), Proc.Io.Close(writeEnd)))
    val omp = Proc.spawn(Seq("omp", "-p", "--mode", "json", "--no-title") ++ flags, ignore = Seq(SIGINT, SIGQUIT),
      io = Seq(Proc.Io.ReadFile(f.task.toString, 0), Proc.Io.Dup(writeEnd, 1), Proc.Io.Dup(writeEnd, 2),
        Proc.Io.Close(readEnd), Proc.Io.Close(writeEnd)))
    Proc.close(readEnd)
    Proc.close(writeEnd)
    stream.swap.foreach(why => warn(s"omp-run: omp-stream: $why"))
    omp.swap.foreach(why => warn(s"omp-run: omp: $why"))

    var signal = Option.empty[StopSignal]
    def onSignal(sig: Int): Unit =
      signal = Some(StopSignal.of(sig))
      omp.foreach(Proc.kill(_, SIGTERM))
    val status = omp match
      case Left(_) => 127
      case Right(pid) =>
        os.write.over(f.pid, s"$pid\n")
        waitFor(pid, onSignal)
    stream.foreach(waitFor(_, onSignal))
    os.remove(f.pid)
    (status, signal)

  /** Waits for a child to exit and hands each signal that comes meanwhile to `onSignal`. */
  private def waitFor(child: Int, onSignal: Int => Unit): Int =
    var status = Option.empty[Int]
    while status.isEmpty do
      Proc.nextSignal(Seq(SIGTERM, SIGINT, SIGHUP, SIGCHLD), 1000).filter(_ != SIGCHLD).foreach(onSignal)
      status = Proc.exited(child)
    status.get

  /** How the run ended, the progress file, and the exit code. */
  private def report(f: TaskFiles, status: Int, signal: Option[StopSignal]): Int =
    val stopFile = os.exists(f.stop)
    if stopFile then os.remove(f.stop)
    val (line, rc) = OmpEnd.of(f.name, stopFile, signal, status)
    line.foreach(println)
    if os.isFile(f.progress) && f.progress.toIO.canRead then
      println(s"omp-run: progress file ${f.progress}:")
      System.out.write(os.read.bytes(f.progress))
    rc
