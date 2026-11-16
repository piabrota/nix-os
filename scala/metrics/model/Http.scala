package piabrota.metrics

import java.nio.charset.StandardCharsets.UTF_8

/** The answers of the preview's HTTP/1.0 server. */
enum Status(val code: Int, val reason: String):
  case Ok extends Status(200, "OK")
  case NotFound extends Status(404, "Not Found")
  case NotImplemented extends Status(501, "Not Implemented")

object ContentType:
  val Text = "text/plain"
  val Html = "text/html"
  val Json = "application/json"

final case class Response(status: Status, contentType: String, body: Array[Byte]):
  def head: String =
    s"HTTP/1.0 ${status.code} ${status.reason}\r\nContent-Type: $contentType\r\nContent-Length: ${body.length}\r\n\r\n"

object Response:
  /** "404 Not Found\n" as text, for an error status. */
  def error(status: Status): Response = Response(status, ContentType.Text, s"${status.code} ${status.reason}\n".getBytes(UTF_8))

/** The page's fixtures (metrics/test/fixtures/<case>/data/<host>.json) and where the preview
  * serves them.
  */
object Fixture:
  val Dir = "metrics"
  val Default = "healthy"
  val Folder = "test/fixtures"
  val Page = "index.html"
  val DataPath = "/data/"
  val DefaultPort = 8080
  val Loopback = "127.0.0.1"
