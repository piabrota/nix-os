package piabrota.feeds

import java.nio.charset.StandardCharsets.UTF_8

import piabrota.lib.Sha256

/** Links, split and joined the way Python's `urllib.parse` does: an item's id is a hash of its
  * normalised link, and the state file holds those ids, so a link must normalise as it always did.
  */
object Links:
  final case class Parts(scheme: String, netloc: String, path: String, query: String, fragment: String)

  /** `urlsplit`. */
  def split(url: String): Parts =
    val colon = url.indexOf(':')
    val (scheme, afterScheme) =
      if colon > 0 && url.head.isLetter && url.take(colon).forall(c => c.isLetterOrDigit && c < 128 || "+-.".contains(c))
      then (url.take(colon).toLowerCase, url.drop(colon + 1))
      else ("", url)
    val (netloc, rest) =
      if afterScheme.startsWith("//") then
        val body = afterScheme.drop(2)
        val end = body.indexWhere(c => c == '/' || c == '?' || c == '#') match
          case -1 => body.length
          case i  => i
        (body.take(end), body.drop(end))
      else ("", afterScheme)
    val (beforeFragment, fragment) = cut(rest, '#')
    val (path, query) = cut(beforeFragment, '?')
    Parts(scheme, netloc, path, query, fragment)

  private def cut(s: String, at: Char): (String, String) = s.indexOf(at) match
    case -1 => (s, "")
    case i  => (s.take(i), s.drop(i + 1))

  /** The host of a URL, lower case, without user or port (`urlsplit(url).hostname`). */
  def host(url: String): String =
    val netloc = split(url).netloc
    val hostPort = netloc.drop(netloc.lastIndexOf('@') + 1)
    val host =
      if hostPort.startsWith("[") then hostPort.drop(1).takeWhile(_ != ']')
      else hostPort.takeWhile(_ != ':')
    host.toLowerCase

  /** Lower-case scheme and host, no utm_* keys, no fragment, no trailing slash. */
  def normalise(link: String): String =
    val parts = split(Text.strip(link))
    val query = encode(queryPairs(parts.query).filterNot(_._1.toLowerCase.startsWith("utm_")))
    val path = parts.path.reverse.dropWhile(_ == '/').reverse
    val withHost =
      if parts.netloc.nonEmpty || NetlocSchemes(parts.scheme) then
        "//" + parts.netloc.toLowerCase + (if path.nonEmpty && !path.startsWith("/") then "/" + path else path)
      else path
    val withScheme = if parts.scheme.nonEmpty then parts.scheme + ":" + withHost else withHost
    if query.nonEmpty then withScheme + "?" + query else withScheme

  private val NetlocSchemes = Set("ftp", "http", "gopher", "nntp", "telnet", "imap", "wais", "file",
    "mms", "https", "shttp", "snews", "prospero", "rtsp", "rtsps", "rtspu", "rsync", "svn", "svn+ssh",
    "sftp", "nfs", "git", "git+ssh", "ws", "wss", "itms-services")

  /** The first 16 hex characters of the SHA-256 of the normalised link. */
  def itemId(link: String): String = Sha256.hex(normalise(link).getBytes(UTF_8)).take(16)

  /** Lower-case words only, for the second dedupe pass (`re.sub(r"\W+", " ", title.lower())`). */
  def normaliseTitle(title: String): String =
    val low = title.toLowerCase(java.util.Locale.ROOT)
    val spaced = StringBuilder()
    low.codePoints.forEach(c => if Text.isWord(c) then spaced.appendAll(Character.toChars(c)) else spaced += ' ')
    spaced.result().split(' ').filter(_.nonEmpty).mkString(" ")

  /** `parse_qsl(query, keep_blank_values=True)`. */
  def queryPairs(query: String): List[(String, String)] =
    query.split('&').toList.filter(_.nonEmpty).map { field =>
      field.indexOf('=') match
        case -1 => unquotePlus(field) -> ""
        case i  => unquotePlus(field.take(i)) -> unquotePlus(field.drop(i + 1))
    }

  /** `urlencode(pairs)`. */
  def encode(pairs: Seq[(String, String)]): String =
    pairs.map((k, v) => s"${quotePlus(k)}=${quotePlus(v)}").mkString("&")

  /** `quote_plus`: every byte but letters, digits and `_.-~` as %XX, a space as +. */
  def quotePlus(s: String): String =
    s.getBytes(UTF_8).map { b =>
      val c = (b & 0xff).toChar
      if c < 128 && (c.isLetterOrDigit || "_.-~".contains(c)) then c.toString
      else if c == ' ' then "+"
      else f"%%${b & 0xff}%02X"
    }.mkString

  /** `unquote_plus`: + is a space, %XX a byte, the bytes UTF-8 (a bad sequence becomes U+FFFD). */
  def unquotePlus(s: String): String =
    val in = s.replace('+', ' ')
    val bytes = java.io.ByteArrayOutputStream()
    var i = 0
    while i < in.length do
      val hex = in.slice(i + 1, i + 3)
      if in(i) == '%' && hex.length == 2 && hex.forall(c => Character.digit(c, 16) >= 0) then
        bytes.write(Integer.parseInt(hex, 16))
        i += 3
      else
        bytes.write(in.substring(i, i + 1).getBytes(UTF_8))
        i += 1
    new String(bytes.toByteArray, UTF_8)
