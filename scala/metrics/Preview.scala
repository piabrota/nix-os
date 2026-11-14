package piabrota.metrics

import java.io.{File, InputStream, IOException}
import java.net.{InetAddress, ServerSocket, Socket}
import java.nio.charset.StandardCharsets.{ISO_8859_1, UTF_8}
import java.nio.file.Files

import piabrota.lib.{die, env}

/** `piabrota metrics-preview`: serve metrics/index.html with one fixture case, to open it in a
  * browser (`just metrics-preview`).
  *
  *   piabrota metrics-preview [healthy|stale|missing|hostile] [port]
  *   piabrota metrics-preview --check
  *
  * The "ts" in a fixture is seconds from now; the server adds the time of each request, so a healthy
  * host stays live and a stale one stays stale. Stop with Ctrl-C. `--check` serves the healthy case
  * on a free port, fetches the page and the data as the browser does, and prints "N checks, M
  * failed". METRICS_DIR is the folder of index.html and test/fixtures (default: metrics).
  */
object Preview:
  def run(args: List[String]): Int =
    val dir = env("METRICS_DIR").getOrElse(Fixture.Dir)
    args match
      case "--check" :: _ => check(dir)
      case _ =>
        val cases = Host.listing(s"$dir/${Fixture.Folder}").filter(c => File(s"$dir/${Fixture.Folder}/$c").isDirectory)
        val name = args.headOption.getOrElse(Fixture.Default)
        val port = args.lift(1).fold(Fixture.DefaultPort)(p => p.toIntOption.getOrElse(die(s"bad port: $p", 2)))
        if !cases.contains(name) then die(s"no such case: $name (${cases.mkString(", ")})", 2)
        val server = Server(dir, name, port)
        println(s"case $name: http://${Fixture.Loopback}:${server.port}/ (Ctrl-C stops)")
        server.serve()
        0

  /** One small HTTP/1.0 server on 127.0.0.1: GET only, one thread a connection, closed after the
    * answer, as Python's http.server answered the old preview.
    */
  private final class Server(dir: String, fixture: String, wantedPort: Int):
    private val socket = ServerSocket(wantedPort, 50, InetAddress.getByName(Fixture.Loopback))
    val port: Int = socket.getLocalPort

    def serve(): Unit =
      while true do
        val client = socket.accept()
        val t = Thread(() => answer(client))
        t.setDaemon(true)
        t.start()

    private def answer(client: Socket): Unit =
      try
        val request = readHead(client.getInputStream)
        val response = request.split(" ") match
          case Array("GET", target, _*) => respond(target.takeWhile(_ != '?'))
          case _                        => Response.error(Status.NotImplemented)
        val out = client.getOutputStream
        out.write(response.head.getBytes(ISO_8859_1))
        out.write(response.body)
        out.flush()
      catch case _: IOException => ()
      finally client.close()

    private def respond(path: String): Response =
      val notFound = Response.error(Status.NotFound)
      val file = path.stripPrefix(Fixture.DataPath)
      if path == "/" || path == s"/${Fixture.Page}" then
        Response(Status.Ok, ContentType.Html, Files.readAllBytes(Host.path(s"$dir/${Fixture.Page}")))
      else if path.startsWith(Fixture.DataPath) && !file.contains('/') && path.endsWith(OutFile.Suffix) then
        val f = File(s"$dir/${Fixture.Folder}/$fixture${Fixture.DataPath}$file")
        if !f.isFile then notFound
        else live(String(Files.readAllBytes(f.toPath), UTF_8), Host.now()) match
          case Some(data) => Response(Status.Ok, ContentType.Json, data.getBytes(UTF_8))
          case None       => notFound
      else notFound

  /** A fixture with its times moved to now. Infinity is written as the largest double, as jq
    * writes it, so the page gets valid JSON.
    */
  def live(raw: String, now: Long): Option[String] =
    def later(j: Json): Json = j match
      case Json.Num(_, v) => Json.num(v + now)
      case other          => other
    Json.parse(raw).map {
      case Json.Obj(fields) =>
        val domains = fields.get(Key.Domains).map {
          case Json.Obj(d) => Json.Obj(d.updatedWith(Key.Ts)(_.map(later)))
          case other       => other
        }
        Json.write(Json.Obj(fields.updatedWith(Key.Ts)(_.map(later)) ++ domains.map(Key.Domains -> _)))
      case other => Json.write(other)
    }

  /** The request line; the headers (8 KiB at most) are read and ignored. */
  private def readHead(in: InputStream): String =
    val head = new StringBuilder
    def ended = head.length >= 4 && head.substring(head.length - 4) == "\r\n\r\n"
    var c = 0
    while c >= 0 && !ended && head.length < 8192 do
      c = in.read()
      if c >= 0 then head += c.toChar
    head.toString.takeWhile(c => c != '\r' && c != '\n')

  private def check(dir: String): Int =
    val server = Server(dir, Fixture.Default, 0)
    val t = Thread(() => server.serve())
    t.setDaemon(true)
    t.start()
    val now = Host.now()
    def host(path: String): Json = get(server.port, path)._2.flatMap(b => Json.parse(String(b, UTF_8))).getOrElse(Json.Null)
    val host2 = host("/data/piabrota2.json")
    val results = List(
      "GET / gives the page" ->
        get(server.port, "/")._2.exists(_.sameElements(Files.readAllBytes(Host.path(s"$dir/${Fixture.Page}")))),
      "GET /data/piabrota2.json is fresh JSON" -> (host2(Key.Host) == Json.Str("piabrota2") && (host2(Key.Ts) match
        case Json.Num(_, ts) => ts >= now - 10
        case _               => false)),
      "GET /data/piabrota.json" -> (host("/data/piabrota.json")(Key.Host) == Json.Str("piabrota")),
      "a missing host is a 404" -> (get(server.port, "/data/nope.json")._1 == Status.NotFound.code),
      "a path out of data/ is a 404" -> (get(server.port, "/data/../index.html")._1 == Status.NotFound.code),
    )
    val failed = results.filterNot(_._2).map(_._1)
    failed.foreach(name => println(s"FAIL $name"))
    println(s"${results.size} checks, ${failed.size} failed")
    if failed.isEmpty then 0 else 1

  /** One GET, as the browser sends it: the status, and the body of a 200. */
  private def get(port: Int, path: String): (Int, Option[Array[Byte]]) =
    val s = Socket(Fixture.Loopback, port)
    try
      s.getOutputStream.write(s"GET $path HTTP/1.0\r\nHost: ${Fixture.Loopback}\r\n\r\n".getBytes(ISO_8859_1))
      s.getOutputStream.flush()
      val reply = s.getInputStream.readAllBytes()
      val text = String(reply, ISO_8859_1)
      val status = text.takeWhile(_ != '\r').split(" ").lift(1).flatMap(_.toIntOption).getOrElse(0)
      val bodyAt = text.indexOf("\r\n\r\n")
      (status, Option.when(status == Status.Ok.code && bodyAt >= 0)(reply.drop(bodyAt + 4)))
    finally s.close()
