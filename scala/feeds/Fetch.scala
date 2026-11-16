package piabrota.feeds

import scala.collection.concurrent.TrieMap

/** A GET: the URL and the extra headers in, the body or the error out. Tests pass their own. */
type Fetch = (String, Seq[(String, String)]) => Either[FetchError, Array[Byte]]

object Fetch:
  val RetryWait = 2.0
  val GithubGap = 7.0

  /** Call `get`. After a retryable error, wait RetryWait seconds and call it once more. */
  def withRetry(get: () => Either[FetchError, Array[Byte]], sleep: Double => Unit): Either[FetchError, Array[Byte]] =
    get() match
      case Left(e) if e.retryable =>
        sleep(RetryWait)
        get()
      case answer => answer

  /** Seconds between two requests to the host: GitHub's anonymous limit is 10 a minute. */
  def hostGap(host: String): Double = if host == GithubApi.Host then GithubGap else 0.0

  def sleepSeconds(seconds: Double): Unit = Thread.sleep((seconds * 1000).toLong)
  def monotonicSeconds(): Double = System.nanoTime() / 1e9

/** The HTTP client of a run: one request per host at a time, a gap between GitHub queries, one retry. */
final class Fetcher(
    open: Fetch = Curl.get,
    sleep: Double => Unit = Fetch.sleepSeconds,
    clock: () => Double = () => Fetch.monotonicSeconds(),
) extends Fetch:
  private val locks = TrieMap.empty[String, Object]
  private val last = TrieMap.empty[String, Double]

  def apply(url: String, headers: Seq[(String, String)]): Either[FetchError, Array[Byte]] =
    val host = Links.host(url)
    locks.getOrElseUpdate(host, new Object).synchronized {
      val wait = last.get(host).fold(0.0)(_ + Fetch.hostGap(host) - clock())
      if wait > 0 then sleep(wait)
      try Fetch.withRetry(() => open(url, headers), sleep)
      finally last(host) = clock()
    }

/** HTTP through curl: Scala Native has no java.net.http. The headers go on stdin (`-H @-`), so a
  * token is never on a command line. Only the first MaxBytes of a body are read, as the Python
  * script read them: a podcast feed of 5 MB has its newest items at the start.
  */
object Curl:
  val UserAgent = "Mozilla/5.0 (compatible; piabrota-feed/1.0; +https://github.com/piabrota/nix-os)"
  val Timeout = 20
  val MaxBytes = 1500000

  def get(url: String, headers: Seq[(String, String)]): Either[FetchError, Array[Byte]] =
    // --speed-time stops a transfer that stalls for Timeout seconds, as the Python socket timeout did.
    val cmd = Seq("curl", "--silent", "--show-error", "--fail", "--location", "--max-redirs", "10",
      "--connect-timeout", Timeout.toString, "--speed-limit", "1", "--speed-time", Timeout.toString,
      "--user-agent", UserAgent, "--header", "@-", "--url", url)
    val headerLines = headers.map((k, v) => s"$k: $v\n").mkString
    try
      val p = os.proc(cmd).spawn(stdin = headerLines, stdout = os.Pipe, stderr = os.Pipe)
      val body = p.stdout.readNBytes(MaxBytes)
      if body.length >= MaxBytes then
        p.destroy()
        Right(body)
      else
        p.waitFor()
        val err = Text.strip(new String(p.stderr.readAllBytes()))
        p.exitCode() match
          case 0  => Right(body)
          case 22 => Left(FetchError.Http(HttpCode.findFirstMatchIn(err).fold(0)(_.group(1).toInt)))
          case 28 => Left(FetchError.Timeout)
          case n  => Left(FetchError.Failed(if err.nonEmpty then err else s"curl: exit $n"))
    catch case e: java.io.IOException => Left(FetchError.Failed(s"curl: ${e.getMessage}"))

  private val HttpCode = "error: (\\d{3})".r
