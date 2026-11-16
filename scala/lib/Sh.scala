package piabrota.lib

import java.lang.ProcessBuilder.Redirect

/** Other programs, the way a shell script calls them. Every function takes the command as
  * `os.Shellable`s (strings, paths, sequences), never as one string to split, so no argument is
  * ever split or globbed. `env` adds to the environment (a null value removes a name); `cwd`
  * defaults to the current directory.
  *
  * Built on `java.lang.ProcessBuilder`, not `os.proc(...).call`: on Scala Native os-lib's pumper
  * threads cost about 40 ms a child, ProcessBuilder about 4 ms, and the timers start many children.
  */
object Sh:
  /** Runs the command with this process's stdin, stdout and stderr; returns its exit code. */
  def run(cmd: os.Shellable*)(using opts: Opts = Opts()): Int =
    System.out.flush()
    val pb = builder(cmd, opts).inheritIO()
    pb.start().waitFor()

  /** True if the command exits 0. Its output is dropped (`cmd >/dev/null 2>&1`). */
  def ok(cmd: os.Shellable*)(using opts: Opts = Opts()): Boolean =
    try
      val p = builder(cmd, opts).redirectOutput(Redirect.DISCARD).redirectError(Redirect.DISCARD).start()
      feed(p, opts.stdin)
      p.waitFor() == 0
    catch case _: java.io.IOException => false

  /** The command's stdout without the trailing newlines (`$(cmd)`); dies with its stderr if it
    * fails.
    */
  def out(cmd: os.Shellable*)(using opts: Opts = Opts()): String =
    val r = call(cmd*)
    if r.exitCode != 0 then
      die(s"${commandName(cmd)}: exit ${r.exitCode}${stderrTail(r)}", r.exitCode)
    r.out.text().stripTrailing()

  /** The command's stdout, or None if it fails or is not installed (`$(cmd 2>/dev/null)`). */
  def outOpt(cmd: os.Shellable*)(using opts: Opts = Opts()): Option[String] =
    try
      val r = call(cmd*)
      Option.when(r.exitCode == 0)(r.out.text().stripTrailing())
    catch case _: java.io.IOException => None

  /** The full result, for a caller that needs the code, stdout and stderr together. A program that
    * is not installed throws `java.io.IOException`, as os-lib does.
    */
  def call(cmd: os.Shellable*)(using opts: Opts = Opts()): os.CommandResult =
    // stderr goes to a file, so neither pipe can fill up while the other is read, with no thread.
    val errFile = java.io.File.createTempFile("piabrota-stderr", "")
    try
      val p = builder(cmd, opts).redirectError(errFile).start()
      feed(p, opts.stdin)
      val stdout = p.getInputStream.readAllBytes()
      val code = p.waitFor()
      val stderr = java.nio.file.Files.readAllBytes(errFile.toPath)
      os.CommandResult(args(cmd), code, Seq(Left(geny.Bytes(stdout)), Right(geny.Bytes(stderr))))
    finally errFile.delete()

  /** Where a program is on the PATH (`command -v name`). */
  def which(name: String): Option[os.Path] =
    sys.env.getOrElse("PATH", "").split(':').iterator.filter(_.nonEmpty)
      .map(dir => os.Path(dir, os.pwd) / name)
      .find(p => os.isFile(p) && p.toIO.canExecute)

  /** What a child reads: text, bytes, or a file (`< file`). */
  type Input = String | Array[Byte] | os.Path

  /** Options for one call: `Sh.out("git", "log")(using Sh.Opts(cwd = repo))`. `stdin` is text,
    * bytes or a file; it is empty by default, never this process's own stdin (except in `run`).
    */
  final case class Opts(cwd: os.Path = os.pwd, env: Map[String, String] = Map.empty,
      stdin: Sh.Input = "")

  /** `Opts.stdin` for a direct `os.proc(...).call(stdin = ...)`. */
  def input(stdin: Input): os.ProcessInput = stdin match
    case s: String      => s
    case b: Array[Byte] => b
    case p: os.Path     => p

  private def args(cmd: Seq[os.Shellable]): Seq[String] = cmd.flatMap(_.value)

  private def builder(cmd: Seq[os.Shellable], opts: Opts): ProcessBuilder =
    val pb = new ProcessBuilder(args(cmd)*).directory(opts.cwd.toIO)
    val environment = pb.environment()
    opts.env.foreach((k, v) => if v == null then environment.remove(k) else environment.put(k, v))
    pb

  /** Writes stdin and closes it. A large input goes from a thread, so a child that writes before it
    * reads cannot block on a full stdout pipe.
    */
  private def feed(p: Process, stdin: Input): Unit =
    val bytes = stdin match
      case s: String      => s.getBytes(java.nio.charset.StandardCharsets.UTF_8)
      case b: Array[Byte] => b
      case f: os.Path     => os.read.bytes(f)
    def write(): Unit =
      val in = p.getOutputStream
      try in.write(bytes)
      catch case _: java.io.IOException => () // the child exited without reading it all, as `|` allows
      finally
        try in.close() catch case _: java.io.IOException => ()
    if bytes.length <= 16384 then write()
    else
      val t = new Thread(() => write())
      t.setDaemon(true)
      t.start()

  private def commandName(cmd: Seq[os.Shellable]): String = args(cmd).headOption.getOrElse("command")

  private def stderrTail(r: os.CommandResult): String =
    val err = r.err.text().strip()
    if err.isEmpty then "" else s": $err"
