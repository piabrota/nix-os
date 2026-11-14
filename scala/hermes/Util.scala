package piabrota.hermes

import piabrota.lib.Exit

/** Small helpers the commands of hermes/ share. */
object Util:
  /** `x` with `decimals` digits, as C's printf("%.Nf") writes it: the exact binary value, ties to
    * even, and "-0" for a small negative number. awk's printf is that printf.
    */
  def cfmt(x: Double, decimals: Int): String =
    val s = java.math.BigDecimal(x).setScale(decimals, java.math.RoundingMode.HALF_EVEN).toPlainString
    if (x < 0 || (x == 0 && 1 / x < 0)) && !s.startsWith("-") then "-" + s else s

  private val numericPrefix = """^\s*[-+]?(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?""".r

  /** A string as awk reads it as a number: its leading number, else 0. */
  def awkNum(s: String): Double =
    numericPrefix.findFirstIn(s).map(_.trim.toDouble).getOrElse(0.0)

  /** A count, or 0 when the text is not one (the script's `num`). */
  def count(s: String): Long =
    if s.nonEmpty && s.forall(_.isDigit) then s.toLongOption.getOrElse(0L) else 0L

  /** The last `n` lines of a text, as `printf '%s\n' "$text" | tail -n N` prints them. */
  def lastLines(text: String, n: Int): String =
    text.replaceAll("\n+$", "").split("\n", -1).takeRight(n).map(_ + "\n").mkString

  /** The lines of a text, each with its newline (the last one may have none), as perl reads them. */
  def linesKeep(text: String): List[String] =
    if text.isEmpty then Nil
    else
      val ends = text.indices.filter(text(_) == '\n').map(_ + 1)
      val cuts = (0 +: ends) ++ Option.when(!text.endsWith("\n"))(text.length)
      cuts.sliding(2).collect { case Seq(a, b) => text.substring(a, b) }.toList

  /** The last `n` lines of a file, as `tail -n N file` prints them. */
  def tailFile(text: String, n: Int): String =
    val body = text.stripSuffix("\n")
    if text.isEmpty then ""
    else body.split("\n", -1).takeRight(n).mkString("\n") + (if text.endsWith("\n") then "\n" else "")

/** The steps of a cron job, as the old scripts' ERR trap had them: a failed command ends the job
  * with one line on stdout, `<prefix> failed: <step>`, and exit 1. `step` names what runs now.
  */
final class Steps(prefix: String):
  var step = "start"

  /** `<prefix> failed: <what>` on stdout, exit 1. */
  def fail(what: String): Nothing =
    println(s"$prefix failed: $what")
    throw Exit(1)

  /** Ends the job with this exit code and nothing more. */
  def quit(code: Int = 0): Nothing = throw Exit(code)

  /** Runs a command with this process's stdout and stderr; fails the step if it fails. */
  def run(cmd: os.Shellable*)(using opts: piabrota.lib.Sh.Opts): Unit =
    if piabrota.lib.Sh.run(cmd*) != 0 then fail(step)

  /** Runs a command with its output dropped (`>/dev/null 2>&1`); fails the step if it fails. */
  def quiet(cmd: os.Shellable*)(using opts: piabrota.lib.Sh.Opts): Unit =
    if !piabrota.lib.Sh.ok(cmd*) then fail(step)

  /** The command's stdout without the trailing newlines (`$(cmd)`), its stderr on ours; fails the
    * step if it fails.
    */
  def out(cmd: os.Shellable*)(using opts: piabrota.lib.Sh.Opts): String =
    val r = os.proc(cmd*).call(cwd = opts.cwd, env = opts.env, stdin = piabrota.lib.Sh.input(opts.stdin), stdout = os.Pipe,
      stderr = os.Inherit, check = false)
    if r.exitCode != 0 then fail(step)
    r.out.text().replaceAll("\n+$", "")

  /** The exit code of a command whose stdout is dropped and whose stderr is ours. */
  def code(cmd: os.Shellable*)(using opts: piabrota.lib.Sh.Opts): Int =
    os.proc(cmd*).call(cwd = opts.cwd, env = opts.env, stdin = piabrota.lib.Sh.input(opts.stdin), stdout = os.Pipe,
      stderr = os.Inherit, check = false).exitCode
