package piabrota.scripts

import scala.scalanative.posix.{stdlib, unistd}
import scala.scalanative.unsafe.*

import piabrota.lib.{Sh, die}

/** What several scripts of this area share: processes, files and the checkout. Candidates for
  * scala/lib.
  */
object Util:
  /** Replaces this process with `plan.cmd`, found on the PATH, as sh's `exec` does: same pid, so
    * the caller's signals and cgroup reach the program. The plan's `set` and `unset` change the
    * environment first.
    */
  def exec(plan: Exec): Nothing =
    System.out.flush()
    System.err.flush()
    Zone.acquire { implicit z =>
      plan.unset.foreach(name => stdlib.unsetenv(toCString(name)))
      plan.set.foreach((k, v) => stdlib.setenv(toCString(k), toCString(v), 1))
      val argv = alloc[CString](plan.cmd.size + 1)
      plan.cmd.zipWithIndex.foreach((arg, i) => argv(i) = toCString(arg))
      argv(plan.cmd.size) = null
      unistd.execvp(argv(0), argv)
    }
    die(s"${plan.cmd.headOption.getOrElse("exec")}: cannot run it", 127)

  /** `Sh.run` after flushing stdout, so the lines printed so far come before the program's own. */
  def run(cmd: os.Shellable*): Int =
    System.out.flush()
    Sh.run(cmd*)

  /** A step that must work: its failure stops the command with its exit code (`set -e`). */
  def step(cmd: os.Shellable*): Unit =
    val code = run(cmd*)
    if code != 0 then die("", code)

  /** Writes `text` beside `file`, gives it `owner` and `mode`, then renames it over `file`: a reader
    * never sees half a file. A chown that fails is reported and the write goes on, as in the shell
    * scripts these came from.
    */
  def put(file: os.Path, text: String, owner: Owner, mode: Mode, tmpName: String = ""): Unit =
    val tmp = file / os.up / (if tmpName.nonEmpty then tmpName else file.last + ".new")
    os.remove(tmp)
    os.write(tmp, text, perms = Mode.OwnerOnly.perms)
    Sh.run("chown", owner.render, tmp)
    os.perms.set(tmp, mode.perms)
    os.move(tmp, file, replaceExisting = true)

  /** A token file without its trailing newlines, as `$(cat file)` gives it. */
  def readToken(file: os.Path): String = os.read(file).reverse.dropWhile(_ == '\n').reverse

  /** A file that exists and that this process can read. */
  def readable(file: os.Path): Boolean = os.isFile(file) && file.toIO.canRead

  /** True when this process runs as root (`id -u` is 0). */
  def isRoot(): Boolean = Sh.outOpt("id", "-u").flatMap(_.toIntOption).contains(0)

  /** The keys and values of a `KEY=value` file; a later line wins. */
  def envFile(text: String): Map[String, String] =
    text.linesIterator.flatMap { line =>
      line.split("=", 2) match
        case Array(k, v) => Some(k -> v)
        case _           => None
    }.toMap

  /** The first line of a text, as `| head -n 1` gives it. */
  def firstLine(text: String): String = text.linesIterator.nextOption().getOrElse("")

  /** stdout and stderr of a command, merged (`2>&1`), with its exit code; "" if it cannot start. */
  def merged(cmd: String*): (Int, String) =
    try
      val r = os.proc(cmd).call(stdin = "", stdout = os.Pipe, stderr = os.Pipe, mergeErrIntoOut = true,
        check = false)
      (r.exitCode, r.out.text())
    catch case _: java.io.IOException => (127, "")


/** JSON values read the way the shell scripts read them with jq. */
object Jq:
  /** A value as `jq -r` prints it. */
  def raw(v: ujson.Value): String = v match
    case ujson.Str(s)                                            => s
    case ujson.Num(n) if n == math.rint(n) && math.abs(n) < 1e15 => n.toLong.toString
    case other                                                   => other.render()

  /** `jq -r .key`: "null" when the key is missing. */
  def rawField(v: ujson.Value, key: String): String = v.objOpt.flatMap(_.get(key)).map(raw).getOrElse("null")

  /** `.key // empty`: None when the key is missing, null or false. */
  def get(v: ujson.Value, key: String): Option[ujson.Value] =
    v.objOpt.flatMap(_.get(key)).filter(x => x != ujson.Null && x != ujson.False)

  /** `jq -er .key`: None when the key is missing, null or false. */
  def field(v: ujson.Value, key: String): Option[String] = get(v, key).map(raw)

  /** `.key == true`. */
  def isTrue(v: ujson.Value, key: String): Boolean = v.objOpt.flatMap(_.get(key)).contains(ujson.True)

  /** A text as JSON, or None. */
  def parse(text: String): Option[ujson.Value] = scala.util.Try(ujson.read(text)).toOption
