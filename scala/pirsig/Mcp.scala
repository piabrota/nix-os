package piabrota.pirsig

import java.io.{BufferedReader, InputStreamReader}
import java.nio.charset.StandardCharsets.UTF_8

import scala.util.control.NonFatal

import piabrota.lib.{die, env}

/** `piabrota pirsig-mcp`: the tools of the owner's two former Hermes plugins, pirsig-notes and
  * pirsig-videos, as one MCP server over stdio (docs/HERMES-PLUGINS.md). Hermes starts it
  * (`mcpServers.pirsig` in hermes.nix) and names its tools `mcp__pirsig__<name>`.
  *
  * JSON-RPC 2.0, one message per line on stdin and stdout; stderr is Hermes's log. Calls run one
  * at a time, so two submissions never share the brain's checkout.
  */
object Mcp:
  val tools: List[Tool] =
    List(Notes.search, Notes.submit, Videos.fetch, Videos.check, Videos.submit)

  def run(args: List[String]): Int = args match
    case Nil =>
      val config = Config.from(env, os.Path(sys.props("user.home")), os.pwd)
      val in = BufferedReader(InputStreamReader(System.in, UTF_8))
      Iterator.continually(in.readLine()).takeWhile(_ != null).filter(_.trim.nonEmpty)
        .flatMap(handle(config, _)).foreach(send)
      0
    case _ => die("usage: piabrota pirsig-mcp", 2)

  private def send(message: ujson.Value): Unit =
    System.out.write((ujson.write(message) + "\n").getBytes(UTF_8))
    System.out.flush()

  /** The answer to one line, or None for a notification. */
  def handle(config: Config, line: String): Option[ujson.Value] =
    Incoming.parse(line) match
      case Incoming.Unreadable       => Some(Response.Error(RequestId(ujson.Null), ErrorCode.ParseError, "Parse error").render)
      case Incoming.Notification     => None
      case Incoming.Call(id, request) => Some(respond(config, id, request).render)

  def respond(config: Config, id: RequestId, request: Request): Response = request match
    case Request.Initialize(version) =>
      Response.Result(id, Reply.Initialized(version.getOrElse(Server.DefaultProtocol)))
    case Request.Ping      => Response.Result(id, Reply.Pong)
    case Request.ListTools => Response.Result(id, Reply.Tools(tools))
    case Request.CallTool(name, arguments) =>
      tools.find(_.name.label == name) match
        case None       => Response.Error(id, ErrorCode.InvalidParams, s"Unknown tool: $name")
        case Some(tool) => Response.Result(id, Reply.Called(call(config, tool, arguments)))
    case Request.Unknown(method) => Response.Error(id, ErrorCode.MethodNotFound, s"Method not found: $method")

  private def call(config: Config, tool: Tool, arguments: ujson.Obj): ToolResult =
    // A bug in one tool must not end the server, which serves the other tools too: its stack
    // goes to Hermes's log and the model gets the error.
    try ToolResult(tool.call(config, arguments).render, isError = false)
    catch case NonFatal(e) =>
      e.printStackTrace()
      ToolResult(s"${tool.name.label} failed: $e", isError = true)
