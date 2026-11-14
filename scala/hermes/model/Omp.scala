package piabrota.hermes

import Proc.{SIGHUP, SIGINT}

/** omp-tasks, the folder of omp-run's tasks (OMP_TASKS), read once at the start. */
final case class OmpConfig(tasks: os.Path)

object OmpConfig:
  def read(env: String => Option[String]): OmpConfig =
    OmpConfig(os.Path(env("OMP_TASKS").getOrElse("/var/lib/hermes/workspace/omp-tasks"), os.pwd))

/** The name of a task: a plain file name in omp-tasks, not hidden and not an option. */
object TaskName:
  def valid(name: String): Boolean =
    !(name.isEmpty || name.contains('/') || name.startsWith(".") || name.startsWith("-"))

/** The files of one run in omp-tasks. */
final case class TaskFiles(tasks: os.Path, name: String):
  val task = tasks / s"$name.md"
  val pid = tasks / s"$name.pid"
  val stop = tasks / s"$name.stop"
  val progress = tasks / s"$name.progress"

/** A signal that stopped omp-run, as it names it. */
enum StopSignal:
  case TERM, INT, HUP

object StopSignal:
  /** Every signal omp-run takes, but INT and HUP, is a TERM. */
  def of(sig: Int): StopSignal = if sig == SIGINT then INT else if sig == SIGHUP then HUP else TERM

/** How a run of omp ended, as the conversation reads it: a line, if one, and the exit code. */
object OmpEnd:
  // The shell's code for a command killed by SIGTERM, which bash -lic reports as a failure.
  val Signalled = 143
  val TimedOut = 124
  val Killed = 137

  /** `stopFile`: omp-run --stop asked for the stop. `signal`: a signal stopped omp-run. */
  def of(name: String, stopFile: Boolean, signal: Option[StopSignal], status: Int): (Option[String], Int) =
    if stopFile then (Some(s"omp-run: stopped on request (omp-run --stop $name)"), 0)
    else signal match
      case Some(sig) =>
        (Some(s"omp-run: stopped by SIG$sig, not by omp-run --stop: a restart of the unit, a deploy or a kill of the background process"),
          Signalled)
      case None =>
        val line =
          if status == TimedOut then Some("omp-run: stopped by the time limit (--max-time, or the wrapper's ceiling)")
          else if status == Killed then Some("omp-run: omp was killed (SIGKILL: out of memory, or 30 s after the time limit)")
          else if status > 128 then Some(s"omp-run: omp was stopped by signal ${status - 128}")
          else if status != 0 then Some(s"omp-run: omp exited with $status")
          else None
        (line, status)

/** One line of `omp --mode json`, as omp-stream reads it. */
enum OmpEvent:
  /** A line that is not a JSON object: a stderr line of omp. */
  case Stderr(line: String)
  case Session(cwd: String)
  /** `described`: the intent, else what the call works on; may be empty. */
  case ToolStart(tool: String, described: String)
  case ToolEnd(tool: String, isError: Boolean, ms: Option[Long], lines: List[String])
  case TextEnd(content: String)
  case AssistantEnd(cost: Double)
  case TurnEnd
  case AgentEnd
  /** A blank line, or an event that prints nothing. */
  case Ignored

object OmpEvent:
  def parse(raw: String): OmpEvent =
    if raw.forall(_.isWhitespace) then Ignored
    else
      scala.util.Try(ujson.read(raw)).toOption.flatMap(_.objOpt) match
        case None    => Stderr(raw)
        case Some(e) => event(ujson.Obj.from(e))

  private def event(e: ujson.Value): OmpEvent =
    def field(path: String*): Option[ujson.Value] = at(e, path*)
    def str(path: String*): Option[String] = field(path*).flatMap(_.strOpt)
    def toolName = field("toolName").filter(truthy).map(text).getOrElse("tool")
    str("type").getOrElse("") match
      case "session" => Session(field("cwd").filter(truthy).map(text).getOrElse("?"))
      case "tool_execution_start" =>
        ToolStart(toolName, str("intent").map(oneline).filter(_.nonEmpty)
          .orElse(field("args").map(argSummary).map(oneline).filter(_.nonEmpty))
          .getOrElse(""))
      case "tool_execution_end" =>
        val ms = field("result", "details", "wallTimeMs").flatMap(_.numOpt).map(roundHalfUp)
        val text = field("result", "content").map(elements).getOrElse(Nil).collect {
          case o: ujson.Obj if o.value.get("type").contains(ujson.Str("text")) =>
            o.value.get("text").flatMap(_.strOpt)
        }.flatten.mkString("\n").replaceAll("\\s+$", "")
        ToolEnd(toolName, field("isError").contains(ujson.True), ms,
          if text.isEmpty then Nil else text.split("\n", -1).toList)
      case "message_update" if str("assistantMessageEvent", "type").contains("text_end") =>
        TextEnd(field("assistantMessageEvent", "content").filter(truthy)
          .map(v => v.strOpt.getOrElse(ujson.write(v))).getOrElse(""))
      case "message_end" if str("message", "role").contains("assistant") =>
        AssistantEnd(field("message", "usage", "cost", "total").flatMap(_.numOpt).getOrElse(0.0))
      case "turn_end"  => TurnEnd
      case "agent_end" => AgentEnd
      case _           => Ignored

  /** The value at a path of object keys, if every step is an object that has the key. */
  private def at(v: ujson.Value, path: String*): Option[ujson.Value] =
    path.foldLeft(Option(v))((cur, key) => cur.flatMap(_.objOpt).flatMap(_.get(key)))
      .filter(_ != ujson.Null)

  /** jq's truth: everything but null and false. */
  private def truthy(v: ujson.Value): Boolean = v != ujson.Null && v != ujson.False

  /** A value inside a string, as jq's `"\(.)"` writes it: a string as is, the rest as JSON. */
  private def text(v: ujson.Value): String = v.strOpt.getOrElse(ujson.write(v))

  /** The items of an array, or the values of an object (jq's `.[]?`). */
  private def elements(v: ujson.Value): List[ujson.Value] = v match
    case a: ujson.Arr => a.value.toList
    case o: ujson.Obj => o.value.values.toList
    case _            => Nil

  /** What a tool call works on: its command, else its path, else its first string argument. */
  private def argSummary(args: ujson.Value): String = args match
    case o: ujson.Obj =>
      o.value.get("command").flatMap(_.strOpt)
        .orElse(o.value.get("path").flatMap(_.strOpt))
        .orElse(o.value.values.flatMap(_.strOpt).headOption)
        .getOrElse("")
    case _ => ""

  private def oneline(s: String): String = s.replaceAll("\\s+", " ")

  /** jq's `round`: half away from zero. */
  def roundHalfUp(x: Double): Long = if x < 0 then -math.round(-x) else math.round(x)

/** The counts of a run so far: its turns and its cost in dollars. */
final case class Tally(turns: Int, cost: Double)

object Tally:
  val zero: Tally = Tally(0, 0.0)
