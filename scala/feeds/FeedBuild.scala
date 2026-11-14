package piabrota.feeds

import java.time.Instant
import java.util.concurrent.Executors
import scala.concurrent.{Await, ExecutionContext, Future}
import scala.concurrent.duration.Duration
import scala.util.control.NonFatal
import piabrota.lib.{die, env}

/** `feed-build`: fetch the sources of feeds.toml, score every item, write feed.atom, digest.md,
  * sources.opml and health.json, and print the digest of the new items. A no_agent cron job of
  * Hermes runs it (hermes.nix, `scripts/feed-build.sh`) and posts what it prints. docs/FEEDS.md.
  * Exit 0 when one source worked; 1 when none did, or a write failed; 2 for a bad command line.
  */
object FeedBuild:
  val Workers = 4

  /** What one run needs: the deadline is in System.nanoTime. */
  final case class Run(fetch: Fetch, now: Instant, deadline: Long, githubToken: Option[String])

  def run(args: List[String]): Int = main(args, Environment.from(env), Fetcher(), Instant.now())

  /** The whole run, with the environment, the network and the clock given: tests pass their own. */
  def main(args: List[String], environment: Environment, fetch: Fetch, now: Instant): Int =
    parseArgs(args) match
      case Left(Help) =>
        print(HelpText)
        0
      case Left(error) => die(s"$Usage\nfeed-build: error: $error", 2)
      case Right(a) =>
        build(a, environment, fetch, now)
        0

  private val Help = "--help"

  val Usage: String =
    "usage: feed-build [-h] [--config CONFIG] [--out OUT] [--state STATE] [--dry-run] [--no-state]\n" +
      "                  [--opml-only] [--max-seconds MAX_SECONDS] [--source SOURCE [SOURCE ...]]"

  private val HelpText = s"""$Usage
    |
    |Build the personal feed (docs/FEEDS.md).
    |
    |options:
    |  -h, --help            show this help message and exit
    |  --config CONFIG       feeds.toml (default $$HERMES_HOME/feeds/feeds.toml)
    |  --out OUT             output folder (default $$HERMES_HOME/feeds/out)
    |  --state STATE         state file (default $$HERMES_HOME/feeds/state.json)
    |  --dry-run             print the digest, write nothing
    |  --no-state            write the outputs, ignore the state
    |  --opml-only           write sources.opml and stop
    |  --max-seconds MAX_SECONDS
    |                        deadline for fetching
    |  --source SOURCE [SOURCE ...]
    |                        only these ids
    |""".stripMargin

  /** The command line, as argparse read it; Left is the error, or Help. */
  def parseArgs(args: List[String]): Either[String, Args] =
    def loop(rest: List[String], a: Args): Either[String, Args] = rest match
      case Nil                                     => Right(a)
      case ("-h" | "--help") :: _                  => Left(Help)
      case opt :: tail if opt.startsWith("--") && opt.contains('=') =>
        val (name, value) = opt.splitAt(opt.indexOf('='))
        loop(name :: value.drop(1) :: tail, a)
      case "--dry-run" :: tail                     => loop(tail, a.copy(dryRun = true))
      case "--no-state" :: tail                    => loop(tail, a.copy(noState = true))
      case "--opml-only" :: tail                   => loop(tail, a.copy(opmlOnly = true))
      case "--source" :: tail =>
        val (ids, after) = tail.span(!_.startsWith("-"))
        if ids.isEmpty then Left("argument --source: expected at least one argument")
        else loop(after, a.copy(sources = a.sources ++ ids))
      case opt :: tail if Valued(opt) =>
        tail match
          case value :: rest if !value.startsWith("-") || value.toDoubleOption.isDefined =>
            withValue(opt, value, a).flatMap(loop(rest, _))
          case _ => Left(s"argument $opt: expected one argument")
      case other                                   => Left(s"unrecognized arguments: ${other.mkString(" ")}")
    loop(args, Args())

  private val Valued = Set("--config", "--out", "--state", "--max-seconds")

  private def withValue(opt: String, value: String, a: Args): Either[String, Args] =
    def path = os.Path(os.FilePath(value), os.pwd)
    opt match
      case "--config" => Right(a.copy(config = Some(path)))
      case "--out"    => Right(a.copy(out = Some(path)))
      case "--state"  => Right(a.copy(state = Some(path)))
      case _ =>
        value.toDoubleOption.map(n => a.copy(maxSeconds = n))
          .toRight(s"argument --max-seconds: invalid float value: '$value'")

  /** The run: dies with exit 1 when no source worked, the configuration is bad or a write failed. */
  def build(args: Args, environment: Environment, fetch: Fetch, now: Instant): Unit =
    val paths = Paths.of(args, environment)
    val cfg = Config.load(paths.config).fold(message => die(s"error: $message"), identity)
    val sources = chosen(cfg.sources, args.sources)
    if args.opmlOnly then Outputs.writeAtomic(paths.out / FeedFile.Opml.name, Outputs.opml(cfg, sources))
    else
      val run = Run(fetch, now, System.nanoTime() + (args.maxSeconds * 1e9).toLong, environment.githubToken)
      val report = makeReport(cfg, sources, collect(sources, run), now)
      if report.results.exists(_.status == Status.Ok) then publish(report, args, paths)
      else
        // No source worked: the old feed stays, health.json says why.
        if !args.dryRun then Outputs.writeAtomic(paths.out / FeedFile.Health.name, Outputs.health(report))
        val failed = if report.errors.isEmpty then "" else s" (errors: ${report.errors.mkString(", ")})"
        die(s"error: no source ran$failed")

  /** The sources named by --source, all of them without it. */
  def chosen(sources: List[Source], ids: List[String]): List[Source] =
    sources.filter(s => ids.isEmpty || ids.contains(s.id))

  /** Write the outputs, print the new items above the digest threshold, update the state. */
  private def publish(report: Report, args: Args, paths: Paths): Unit =
    val stateful = !(args.noState || args.dryRun)
    val seen = if stateful then Outputs.loadState(paths.state).pruned(report.now) else State.empty
    val printed = Outputs.pickDigest(fresh(report, seen), report, report.cfg.output.digestMaxChars)
    if !args.dryRun then Outputs.writeAll(report, paths.out)
    // stdout is what the cron job posts: no new item, no output.
    if printed.nonEmpty then print(Outputs.renderDigest(printed, report.cfg, report.now, report.errors))
    if stateful then
      Outputs.saveState(paths.state, seen.withSeen(printed.map(i => Links.itemId(i.link)), Dates.utcDate(report.now)))

  /** The items at the digest threshold or above that the state has not seen. */
  def fresh(report: Report, seen: State): List[Item] =
    report.items.filter(i => i.score >= report.cfg.output.digestMinScore && !seen.contains(Links.itemId(i.link)))

  /** Score, dedupe and rank the items of all sources that worked. */
  def makeReport(cfg: Config, sources: List[Source], results: List[SourceResult], now: Instant): Report =
    val kept = sources.zip(results).flatMap((src, r) => Score.selectItems(src, r.items, cfg, now))
    val items = Score.selectForFeed(Score.dedupe(kept), cfg.output)
    Report(cfg, sources, results, items, results.filter(_.status == Status.Error).map(_.id), now)

  /** Run all sources on a small thread pool. The results follow the order of `sources`. */
  def collect(sources: List[Source], run: Run): List[SourceResult] =
    val pool = Executors.newFixedThreadPool(Workers)
    given ExecutionContext = ExecutionContext.fromExecutorService(pool)
    try
      val started = interleave(sources).map(src => src.id -> Future(runSource(src, run)))
      val done = started.map((id, f) => id -> Await.result(f, Duration.Inf)).toMap
      sources.map(s => done(s.id))
    finally pool.shutdown()

  /** Spread the sources of one host, so the workers do not all wait on one host's lock. */
  def interleave(sources: List[Source]): List[Source] =
    val byHost = sources.groupBy(hostOf)
    val hosts = sources.map(hostOf).distinct.map(byHost)
    (0 until hosts.map(_.length).maxOption.getOrElse(0)).toList.flatMap(i => hosts.flatMap(_.lift(i)))

  private def hostOf(src: Source): String =
    src.kind match
      case SourceKind.GithubSearch                 => GithubApi.Host
      case SourceKind.Feed | SourceKind.AppleChart => Links.host(src.url)

  /** Fetch and parse one source. It never throws: an error is recorded in its result. */
  def runSource(src: Source, run: Run): SourceResult =
    if System.nanoTime() >= run.deadline then SourceResult(src.id, Status.Skipped)
    else
      val request = requestFor(src, run.now, run.githubToken)
      // The edge of one source: a bad answer must not stop the other sources.
      try
        run.fetch(request.url, request.headers) match
          case Left(e)     => failed(src, e.describe)
          case Right(data) => SourceResult(src.id, Status.Ok, parse(src, data, run.now))
      catch case NonFatal(e) => failed(src, s"${e.getClass.getName.split('.').last}: ${e.getMessage}".take(200))

  private def failed(src: Source, error: String): SourceResult = SourceResult(src.id, Status.Error, error = Some(error))

  /** The items of a source's answer, read by its kind. */
  def parse(src: Source, data: Array[Byte], now: Instant): List[Item] = src.kind match
    case SourceKind.Feed         => Parse.feed(data, src, now)
    case SourceKind.GithubSearch => Parse.github(data, src, now)
    case SourceKind.AppleChart   => Parse.apple(data, src, now)

  /** The URL and the extra headers of a source. */
  def requestFor(src: Source, now: Instant, token: Option[String]): Request = src.kind match
    case SourceKind.GithubSearch                 => Request(githubUrl(src, now), githubHeaders(token))
    case SourceKind.Feed | SourceKind.AppleChart => Request(src.url)

  /** The Accept header, and a token only when GITHUB_TOKEN is set. */
  def githubHeaders(token: Option[String]): Seq[(String, String)] =
    GithubApi.Accept +: token.map(GithubApi.authorization).toSeq

  private val DaysAgo = "\\{d(\\d+)\\}".r

  /** Replace {d7}, {d14}, {d30} with the date that many days ago. */
  def githubQuery(query: String, now: Instant): String =
    DaysAgo.replaceAllIn(query, m => Dates.utcDate(now.minusSeconds(m.group(1).toLong * 86400)).toString)

  /** The repository search URL of a github_search source. */
  def githubUrl(src: Source, now: Instant): String =
    GithubApi.SearchUrl + Links.encode(List(
      "q" -> githubQuery(src.query, now), "sort" -> "stars", "order" -> "desc", "per_page" -> src.limit.toString))
