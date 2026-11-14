package piabrota.pirsig

/** What the server reads from its environment, once, when Hermes starts it: HERMES_HOME (Hermes
  * passes it to every stdio MCP server), PIRSIG_REPO and PIRSIG_BASE (the server's env in
  * hermes.nix).
  */
final case class Config(home: os.Path, repo: String, base: String)

object Config:
  val DefaultRepo = "piabrota/pirsig"
  val DefaultBase = "main"

  def from(lookup: String => Option[String], userHome: os.Path, cwd: os.Path): Config =
    Config(
      home = lookup("HERMES_HOME").map(os.Path(_, cwd)).getOrElse(userHome / ".hermes"),
      repo = lookup("PIRSIG_REPO").getOrElse(DefaultRepo),
      base = lookup("PIRSIG_BASE").getOrElse(DefaultBase),
    )

/** What this server tells a client about itself. */
object Server:
  val Name = "pirsig"
  val Version = "0.1.0"
  val JsonRpc = "2.0"
  /** What this server says when the client asks for none. It uses only tools, which no version
    * since this one has changed, so it answers with the client's own version.
    */
  val DefaultProtocol = "2025-06-18"

/** A request's id, echoed as the client sent it: a number, a string or null. */
final case class RequestId(json: ujson.Value)

enum Method(val name: String):
  case Initialize extends Method("initialize")
  case Ping extends Method("ping")
  case ListTools extends Method("tools/list")
  case CallTool extends Method("tools/call")

/** What a client asks, with the parameters this server reads. */
enum Request:
  case Initialize(protocolVersion: Option[String])
  case Ping
  case ListTools
  case CallTool(name: String, arguments: ujson.Obj)
  case Unknown(method: String)

object Request:
  def parse(method: Option[String], params: ujson.Value): Request =
    Method.values.find(m => method.contains(m.name)) match
      case Some(Method.Initialize) => Initialize(Json.string(params, "protocolVersion"))
      case Some(Method.Ping)       => Ping
      case Some(Method.ListTools)  => ListTools
      case Some(Method.CallTool) =>
        CallTool(Json.string(params, "name").getOrElse(""), Json.obj(Json.get(params, "arguments")))
      case None => Unknown(method.getOrElse(""))

/** One line of stdin. */
enum Incoming:
  case Unreadable
  /** No id: a notification, or JSON that is no object. It gets no answer. */
  case Notification
  case Call(id: RequestId, request: Request)

object Incoming:
  def parse(line: String): Incoming =
    Json.read(line) match
      case Left(_) => Unreadable
      case Right(message) =>
        message.objOpt.flatMap(_.get("id")) match
          case None => Notification
          case Some(id) =>
            Call(RequestId(id), Request.parse(Json.string(message, "method"), Json.get(message, "params")))

enum ErrorCode(val code: Int):
  case ParseError extends ErrorCode(-32700)
  case MethodNotFound extends ErrorCode(-32601)
  case InvalidParams extends ErrorCode(-32602)

/** What a tool call answers: the tool's JSON as text, and whether the tool itself failed. */
final case class ToolResult(text: String, isError: Boolean)

/** The result of a request that succeeded. */
enum Reply:
  case Initialized(protocolVersion: String)
  case Pong
  case Tools(tools: List[Tool])
  case Called(result: ToolResult)

  def render: ujson.Value = this match
    case Initialized(version) =>
      ujson.Obj(
        "protocolVersion" -> version,
        "capabilities" -> ujson.Obj("tools" -> ujson.Obj()),
        "serverInfo" -> ujson.Obj("name" -> Server.Name, "version" -> Server.Version),
      )
    case Pong         => ujson.Obj()
    case Tools(tools) => ujson.Obj("tools" -> ujson.Arr.from(tools.map(_.describe)))
    case Called(r) =>
      ujson.Obj("content" -> ujson.Arr(ujson.Obj("type" -> "text", "text" -> r.text)), "isError" -> r.isError)

/** One line of stdout. */
enum Response:
  case Result(id: RequestId, reply: Reply)
  case Error(id: RequestId, code: ErrorCode, message: String)

  def render: ujson.Value = this match
    case Result(id, reply) => ujson.Obj("jsonrpc" -> Server.JsonRpc, "id" -> id.json, "result" -> reply.render)
    case Error(id, code, message) =>
      ujson.Obj("jsonrpc" -> Server.JsonRpc, "id" -> id.json,
        "error" -> ujson.Obj("code" -> code.code, "message" -> message))

enum ToolName(val label: String):
  case NoteSearch extends ToolName("pirsig_note_search")
  case NotesSubmit extends ToolName("pirsig_notes_submit")
  case VideoFetch extends ToolName("pirsig_video_fetch")
  case VideoCheck extends ToolName("pirsig_video_check")
  case VideoSubmit extends ToolName("pirsig_video_submit")

  /** The name Hermes gives the tool, which the model sees. */
  def mcp: String = s"mcp__${Server.Name}__$label"

/** A JSON Schema of a tool's input, as far as these tools need one. */
enum Schema:
  case Text(description: Option[String] = None, oneOf: List[String] = Nil)
  case Integer(description: Option[String] = None)
  case ListOf(items: Schema, description: Option[String] = None)
  case Record(properties: List[Property])

  def render: ujson.Obj = this match
    case Text(description, oneOf) =>
      typed("string", described(description) ++
        Option.when(oneOf.nonEmpty)("enum" -> ujson.Arr.from(oneOf.map(ujson.Str(_)))))
    case Integer(description) => typed("integer", described(description))
    case ListOf(items, description) => typed("array", described(description) :+ ("items" -> items.render))
    case Record(properties) =>
      typed("object", Seq(
        "properties" -> ujson.Obj.from(properties.map(p => p.name -> p.schema.render)),
        "required" -> ujson.Arr.from(properties.filter(_.required).map(p => ujson.Str(p.name))),
      ))

  private def typed(name: String, fields: Seq[(String, ujson.Value)]): ujson.Obj =
    ujson.Obj.from(("type" -> ujson.Str(name)) +: fields)

  private def described(description: Option[String]): Seq[(String, ujson.Value)] =
    description.map(d => "description" -> ujson.Str(d)).toSeq

final case class Property(name: String, schema: Schema, required: Boolean = false)

/** One tool of the server: its name, description and input schema, and what it answers. */
final case class Tool(name: ToolName, description: String, input: Schema, call: (Config, ujson.Obj) => Answer):
  def describe: ujson.Obj =
    ujson.Obj("name" -> name.label, "description" -> description, "inputSchema" -> input.render)

object Messages:
  /** The tools that open a pull request start its body with the owner's request. */
  val NoRequest = "say in `request` what the owner asked for"

/** A tool's answer, the JSON text the Python plugin returned. */
enum Answer:
  case Done(json: ujson.Obj)
  /** `"error": message`, then the problems if there is a list of them. */
  case Failed(message: String, problems: Option[Seq[String]] = None)

  def render: String = this match
    case Done(json) => Py.dumps(json)
    case Failed(message, problems) =>
      Py.dumps(ujson.Obj.from(("error" -> ujson.Str(message)) +: problems.map("problems" -> Json.strings(_)).toSeq))
