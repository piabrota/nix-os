package piabrota.metrics

import java.io.{IOException, RandomAccessFile}
import java.nio.charset.StandardCharsets.ISO_8859_1
import java.nio.file.Files

import piabrota.lib.Sh
import Awk.*

/** `piabrota metrics-probe`: one run of the probe. A timer runs it every 60 s (metrics.nix). It asks
  * each site of this host for a response, counts each site's visits of the last 24 h from nginx's
  * log, and reads the commit count of the repository from GitHub at most once in PROBE_REPO_EVERY
  * seconds. It writes one file, atomically, that metrics-collect puts in the JSON
  * (metrics/SCHEMA.md, "domains" and "repo").
  *
  * Environment ([[ProbeConfig]]):
  *   METRICS_NAME      the host's name (required): the file is <STATE_DIR>/<name>.probe
  *   PROBE_SITES       a file of "<domain> <url>" lines that Nix wrote (metrics.nix)
  *   PROBE_REPO        owner/name on GitHub; empty: no commit count
  *   PROBE_BRANCH      the branch whose commits are counted (default main)
  *   PROBE_REPO_EVERY  seconds between two reads of GitHub (default 600: 6 an hour of the 60 that
  *                     GitHub gives an address without a token)
  *   PROBE_VISITS_LOG  the pages nginx logged, "<msec> <server_name> <address>" a line (metrics.nix);
  *                     empty or unreadable: no visits. What was read, and the last 24 h, are kept in
  *                     <STATE_DIR>/<name>.visits
  *   PROBE_NOW         the time, Unix seconds (default now; the tests set it)
  *   STATE_DIR         default /run/metrics-state
  *   GITHUB_API        default https://api.github.com; the tests point it at nothing
  */
object Probe:
  private val UserAgent = "piabrota-metrics-probe"
  private val LastPage = """.*[?&]page=([0-9]+)>; rel="last".*""".r
  private val NoAnswer = "000"

  def run(args: List[String]): Int =
    val config = ProbeConfig.fromEnv()
    Host.umask022()
    Host.mkdirs(config.stateDir)
    val (out, visitsState) = (config.outFile, config.visitsFile)
    val (tmp, visitsTmp) = (Host.temp(out), Host.temp(visitsState))
    val now = config.now
    Host.cleaning(tmp, visitsTmp) {
      val sites = Site.parse(read(config.sitesFile))
      val visits = config.visitsLog.fold(List.empty[SiteVisits])(log => Visits(log, visitsState, visitsTmp, sites, now))
      val (oldCount, asked) = ProbeFile.lastAnswer(read(out))
      val answers = sites.map(site => site -> answer(site.url))
      val ask = config.repo.isDefined && config.repoEvery.toLongOption.exists(now - asked >= _)
      val count =
        if !ask then oldCount
        else config.repo.flatMap(commits(config.githubApi, _, config.branch)).map(CommitCount(_, now.toString)).orElse(oldCount)
      val file = ProbeFile(now, answers, count, config.repo.map(_ => if ask then now else asked), visits)
      Host.write(tmp, file.render)
      Host.move(tmp, out)
    }
    0

  /** The site's HTTP code, 000 when nothing answers. No redirect is followed: a 301 is an answer. */
  private def answer(url: String): String =
    val code =
      try Sh.call("curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "--connect-timeout", "3",
        "--max-time", "6", "-A", UserAgent, url).out.text()
      catch case _: IOException => ""
    if code.length == 3 && isDigits(code) then code else NoAnswer

  /** The commit count of the branch: with one commit a page, the page number of rel="last". */
  private def commits(api: String, repo: String, branch: String): Option[String] =
    val headers =
      try Sh.call("curl", "-s", "-o", "/dev/null", "-D", "-", "--max-time", "10", "-A", UserAgent,
        "-H", "Accept: application/vnd.github+json", s"$api/repos/$repo/commits?per_page=1&sha=$branch").out.text()
      catch case _: IOException => ""
    lastPage(headers)

  /** The page number of the `rel="last"` link of the headers, when it is a short number. */
  def lastPage(headers: String): Option[String] =
    val last = headers.replace("\r", "").split("\n").filter(_.toLowerCase.startsWith("link:"))
      .collect { case LastPage(n) => n }.mkString("\n")
    Option.when(last.nonEmpty && last.length <= 9)(last)

  /** The visits (docs/METRICS.md, "Visits"): what nginx added to `log` since the last run, at most
    * 16 MiB, and the views by the hour and the last time of each address, for 24 h, kept in
    * `state` ([[VisitsState]]). A new file (logrotate) is read from its start; a line that nginx has
    * not finished is read next run.
    */
  private object Visits:
    private val MaxRead = 16L * 1024 * 1024

    def apply(log: String, state: String, tmp: String, sites: List[Site], now: Long): List[SiteVisits] =
      inodeAndSize(log).fold(List.empty[SiteVisits]) { (ino, size) =>
        val known = sites.map(_.domain).distinct
        val stateText = read(state)
        val last = VisitsState.position(stateText)
        val start = if last.inode != ino || last.offset > size then 0L else last.offset
        // More than 16 MiB behind: read the last 16 MiB, and drop its first line, which is cut.
        val skip = size - start > MaxRead
        val off = if skip then size - MaxRead else start
        // The last piece counts only when the read ended on a newline, and it is "" then.
        val pieces = readRange(log, off, size).split("\n", -1).toList.init
        val used = pieces.map(_.length + 1).sum
        val kept = VisitsState.tally(stateText, if skip then pieces.drop(1) else pieces, known, now,
          LogPosition(ino, off + used))
        Host.write(tmp, kept.render)
        Host.move(tmp, state)
        kept.visits(known)
      }

    /** `stat -L -c '%i %s'`: the inode and the size of the log, if it can be read. */
    private def inodeAndSize(log: String): Option[(String, Long)] =
      if !Files.isReadable(Host.path(log)) then None
      else
        Sh.outOpt("stat", "-L", "-c", "%i %s", log).map(fields).collect {
          case Array(ino, size) if isDigits(ino) && isDigits(size) => (ino, size.toLong)
        }

    /** Bytes `from` to `to` of the log as text, one char a byte; less if it was cut meanwhile. */
    private def readRange(log: String, from: Long, to: Long): String =
      if to <= from then ""
      else
        try
          val file = RandomAccessFile(log, "r")
          try
            file.seek(from)
            val buf = new Array[Byte]((to - from).toInt)
            var got = 0
            var n = 0
            while got < buf.length && n >= 0 do
              n = file.read(buf, got, buf.length - got)
              if n > 0 then got += n
            String(buf, 0, got, ISO_8859_1)
          finally file.close()
        catch case _: IOException => ""
