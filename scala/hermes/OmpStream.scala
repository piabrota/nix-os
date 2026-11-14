package piabrota.hermes

import java.io.{BufferedReader, InputStreamReader}
import java.nio.charset.StandardCharsets.UTF_8

/** `omp-stream`: reads the JSON lines of `omp -p --mode json` on stdin and prints one plain line per
  * event, at once, so the output of omp reaches the conversation while omp works.
  *
  *   omp -p --mode json --no-title < task.md 2>&1 | omp-stream
  *
  * Prints: the start, each tool call and its result (the first 5 lines), each finished assistant
  * text, and the end with the turns and the cost. A line that is not JSON (a stderr line) prints as
  * `omp stderr: <line>`. Keys and tokens print as [redacted]. It reads stdin only: no file, no
  * network. The hermes-omp skill runs it through omp-run.
  */
object OmpStream:
  def run(args: List[String]): Int =
    val in = BufferedReader(InputStreamReader(System.in, UTF_8))
    // scanLeft on an iterator reads one line per step, so each event prints as it comes.
    Iterator.continually(in.readLine()).takeWhile(_ != null).map(OmpEvent.parse)
      .scanLeft((Tally.zero, List.empty[String]))((acc, e) => step(acc._1, e))
      .foreach { (_, lines) =>
        lines.foreach(line => System.out.print(redact(line) + "\n"))
        System.out.flush()
      }
    0

  /** The tally after an event, and the lines it prints. */
  def step(t: Tally, e: OmpEvent): (Tally, List[String]) = e match
    case OmpEvent.Stderr(raw)    => (t, List("omp stderr: " + cut(raw, 300)))
    case OmpEvent.Session(cwd)   => (t, List(s"omp: start in $cwd"))
    case OmpEvent.ToolStart(tool, described) =>
      (t, List(s"> $tool" + (if described.isEmpty then "" else ": " + cut(described, 200))))
    case OmpEvent.ToolEnd(tool, isError, ms, lines) =>
      val status = if isError then "ERROR" else "ok"
      (t, List(s"< $tool $status" + ms.fold("")(n => s" ($n ms)")) ++
        lines.take(5).map(l => "    " + cut(l, 160)) ++
        Option.when(lines.length > 5)(s"    ... ${lines.length - 5} more lines"))
    case OmpEvent.TextEnd(content)   => (t, List("omp says: " + cut(content, 1500)))
    case OmpEvent.AssistantEnd(cost) => (t.copy(cost = t.cost + cost), Nil)
    case OmpEvent.TurnEnd            => (t.copy(turns = t.turns + 1), Nil)
    case OmpEvent.AgentEnd           => (t, List(s"omp: done, ${t.turns} turns, cost $$${cost4(t.cost)}"))
    case OmpEvent.Ignored            => (t, Nil)

  /** The first `n` characters (code points, as jq counts). */
  def cut(s: String, n: Int): String =
    if s.codePointCount(0, s.length) <= n then s else s.substring(0, s.offsetByCodePoints(0, n))

  /** Dollars with 4 decimals. */
  def cost4(cost: Double): String =
    val c = OmpEvent.roundHalfUp(cost * 10000)
    f"${math.floorDiv(c, 10000L)}.${c % 10000}%04d"

  def redact(line: String): String =
    line.replaceAll("sk-ant-[A-Za-z0-9_-]+", "[redacted]")
      .replaceAll("gh[pousr]_[A-Za-z0-9]+", "[redacted]")
      .replaceAll("github_pat_[A-Za-z0-9_]+", "[redacted]")
