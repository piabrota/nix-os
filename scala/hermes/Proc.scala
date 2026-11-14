package piabrota.hermes

import scala.scalanative.posix.{fcntl, signal, unistd}
import scala.scalanative.posix.spawn as ps
import scala.scalanative.posix.signal.sigset_t
import scala.scalanative.posix.sys.wait.*
import scala.scalanative.posix.time.timespec
import scala.scalanative.posix.timeOps.timespecOps
import scala.scalanative.unsafe.*
import scala.scalanative.unsigned.*

/** Child processes and signals, for the commands that supervise a child the way a shell script does
  * with `cmd &`, `trap` and `wait`. The signals a command handles are blocked once, at its start,
  * and read one at a time with `nextSignal`: no handler runs in the middle of other code.
  */
object Proc:
  // Values, not the extern defs, so that they can be matched on.
  val SIGCHLD: Int = signal.SIGCHLD
  val SIGHUP: Int = signal.SIGHUP
  val SIGINT: Int = signal.SIGINT
  val SIGQUIT: Int = signal.SIGQUIT
  val SIGTERM: Int = signal.SIGTERM
  val SIGUSR1: Int = signal.SIGUSR1

  /** What a child gets on its file descriptors before it starts. */
  enum Io:
    case Dup(from: Int, to: Int)
    case ReadFile(path: String, to: Int)
    case Close(fd: Int)

  /** Blocks these signals, so that they wait for `nextSignal`. Call it first: a thread started
    * later inherits the mask.
    */
  def block(signals: Int*): Unit =
    val set = stackalloc[sigset_t]()
    signal.sigemptyset(set)
    signals.foreach(signal.sigaddset(set, _))
    signal.sigprocmask(signal.SIG_BLOCK, set, null)

  /** The next of these (blocked) signals within `millis`, or None when the time runs out. */
  def nextSignal(signals: Seq[Int], millis: Long): Option[Int] =
    val set = stackalloc[sigset_t]()
    signal.sigemptyset(set)
    signals.foreach(signal.sigaddset(set, _))
    val ts = stackalloc[timespec]()
    ts.tv_sec = (millis / 1000).toSize
    ts.tv_nsec = (millis % 1000 * 1000000).toSize
    val sig = signal.sigtimedwait(set, null, ts)
    Option.when(sig > 0)(sig)

  /** Starts `argv` (looked up on the PATH) with this process's environment, an empty signal mask
    * and `ignore` ignored, as `cmd &` gives SIGINT and SIGQUIT to a child of a shell script. The
    * pid, or the reason it could not start.
    */
  def spawn(argv: Seq[String], ignore: Seq[Int] = Nil, io: Seq[Io] = Nil): Either[String, Int] =
    Zone.acquire { implicit z =>
      val args = alloc[CString](argv.length + 1)
      argv.zipWithIndex.foreach((a, i) => args(i) = toCString(a))
      args(argv.length) = null

      val actions = alloc[ps.posix_spawn_file_actions_t]()
      ps.posix_spawn_file_actions_init(actions)
      io.foreach {
        case Io.Dup(from, to)       => ps.posix_spawn_file_actions_adddup2(actions, from, to)
        case Io.ReadFile(path, to)  =>
          ps.posix_spawn_file_actions_addopen(actions, to, toCString(path), fcntl.O_RDONLY, 0.toUInt)
        case Io.Close(fd)           => ps.posix_spawn_file_actions_addclose(actions, fd)
      }
      val attr = alloc[ps.posix_spawnattr_t]()
      ps.posix_spawnattr_init(attr)
      val empty = alloc[sigset_t]()
      signal.sigemptyset(empty)
      ps.posix_spawnattr_setsigmask(attr, empty)
      ps.posix_spawnattr_setflags(attr, ps.POSIX_SPAWN_SETSIGMASK.toShort)

      // The child keeps an ignored signal through exec, so it is ignored here for the moment of the
      // spawn. Setting SIG_IGN drops a pending signal: one that waits is raised again after.
      val pending = stackalloc[sigset_t]()
      signal.sigpending(pending)
      val waiting = ignore.filter(signal.sigismember(pending, _) == 1)
      val old = ignore.map(s => s -> signal.signal(s, signal.SIG_IGN))
      val pid = stackalloc[CInt]()
      val rc = ps.posix_spawnp(pid, args(0), actions, attr, args, unistd.environ)
      old.foreach((s, handler) => signal.signal(s, handler))
      waiting.foreach(signal.raise)

      ps.posix_spawnattr_destroy(attr)
      ps.posix_spawn_file_actions_destroy(actions)
      if rc == 0 then Right(!pid) else Left(fromCString(scala.scalanative.libc.string.strerror(rc)))
    }

  /** The exit status of the child if it has ended, in the shell's form: 128 + n for signal n. */
  def exited(pid: Int): Option[Int] =
    val status = stackalloc[CInt]()
    if waitpid(pid, status, WNOHANG) != pid then None
    else if WIFSIGNALED(!status) then Some(128 + WTERMSIG(!status))
    else Some(WEXITSTATUS(!status))

  /** Sends a signal; false when there is no such process (`kill -SIG pid 2>/dev/null`). */
  def kill(pid: Int, sig: Int): Boolean = signal.kill(pid, sig) == 0

  /** True while a process with this pid exists (`kill -0 pid`). */
  def alive(pid: Int): Boolean = signal.kill(pid, 0) == 0

  /** A pipe: (read end, write end). */
  def pipe(): (Int, Int) =
    val fds = stackalloc[CInt](2)
    if unistd.pipe(fds) != 0 then piabrota.lib.die("pipe failed")
    (fds(0), fds(1))

  def close(fd: Int): Unit = unistd.close(fd)
