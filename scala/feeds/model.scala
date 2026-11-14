package piabrota.feeds

import java.time.{Instant, LocalDate}
import java.time.temporal.ChronoUnit

/** The [output] table of feeds.toml. */
final case class Output(
    maxItems: Int = 80,
    maxPerGroup: Int = 14,
    maxAgeDays: Int = 21,
    minScore: Double = 4.0,
    digestItems: Int = 18,
    digestPerGroup: Int = 3,
    digestMinScore: Double = 6.0,
    digestMaxChars: Int = 1900,
    pinnedKeep: Int = 3,
)

final case class Group(id: String, title: String)

final case class Interest(name: String, weight: Int, terms: Terms)

/** What a source is, and so how it is asked and read. `key` is its name in feeds.toml. */
enum SourceKind(val key: String):
  case Feed extends SourceKind("feed")
  case GithubSearch extends SourceKind("github_search")
  case AppleChart extends SourceKind("apple_chart")

object SourceKind:
  def parse(key: String): Option[SourceKind] = values.find(_.key == key)

/** One [[source]]. */
final case class Source(
    id: String,
    group: String,
    kind: SourceKind,
    weight: Int,
    maxAgeDays: Int,
    pinnedKeep: Int,
    url: String = "",
    query: String = "",
    limit: Int = Source.DefaultLimit,
    pinned: Boolean = false,
    requiresMatch: Boolean = false,
    genres: List[String] = Nil,
    excludeTerms: List[String] = Nil,
):
  lazy val excluded: Terms = Terms(excludeTerms)

object Source:
  val DefaultLimit = 20

/** feeds.toml. */
final case class Config(
    title: String,
    output: Output,
    negative: Terms,
    groups: List[Group],
    interests: List[Interest],
    sources: List[Source],
)

object Config:
  /** Reads and checks the configuration file; the message of a Left is the whole error. */
  def load(path: os.Path): Either[String, Config] =
    if !os.isFile(path) then Left(s"$path: no such file")
    else parse(os.read(path), path.toString)

  def parse(text: String, file: String): Either[String, Config] =
    Toml.parse(text, file).flatMap(fromToml(_, file))

  def fromToml(raw: Toml.Table, file: String): Either[String, Config] = ConfigReader.fromToml(raw, file)

/** The keys and table names of feeds.toml. */
enum ConfigKey(val name: String):
  case Title extends ConfigKey("title")
  case Output extends ConfigKey("output")
  case Negative extends ConfigKey("negative")
  case Group extends ConfigKey("group")
  case Interest extends ConfigKey("interest")
  case Source extends ConfigKey("source")
  case Id extends ConfigKey("id")
  case Name extends ConfigKey("name")
  case Kind extends ConfigKey("kind")
  case Weight extends ConfigKey("weight")
  case Terms extends ConfigKey("terms")
  case MaxItems extends ConfigKey("max_items")
  case MaxPerGroup extends ConfigKey("max_per_group")
  case MaxAgeDays extends ConfigKey("max_age_days")
  case MinScore extends ConfigKey("min_score")
  case DigestItems extends ConfigKey("digest_items")
  case DigestPerGroup extends ConfigKey("digest_per_group")
  case DigestMinScore extends ConfigKey("digest_min_score")
  case DigestMaxChars extends ConfigKey("digest_max_chars")
  case PinnedKeep extends ConfigKey("pinned_keep")
  case Url extends ConfigKey("url")
  case Query extends ConfigKey("query")
  case Limit extends ConfigKey("limit")
  case Pinned extends ConfigKey("pinned")
  case RequiresMatch extends ConfigKey("requires_match")
  case Genres extends ConfigKey("genres")
  case ExcludeTerms extends ConfigKey("exclude_terms")

object ConfigKey:
  /** The only keys [output] may have. */
  val output: Set[ConfigKey] = Set(MaxItems, MaxPerGroup, MaxAgeDays, MinScore, DigestItems, DigestPerGroup,
    DigestMinScore, DigestMaxChars, PinnedKeep)

  /** The only keys a [[source]] may have. */
  val source: Set[ConfigKey] = Set(Id, Group, Kind, Weight, MaxAgeDays, PinnedKeep, Url, Query, Limit, Pinned,
    RequiresMatch, Genres, ExcludeTerms)

final case class Item(
    title: String,
    link: String,
    summary: String,
    date: Instant,
    dated: Boolean,
    source: String,
    group: String,
    stars: Int = 0,
    score: Double = 0.0,
    matched: List[String] = Nil,
    pinned: Boolean = false,
)

/** The summed interest points of an item and the names of the interests that matched. */
final case class InterestScore(points: Double, matched: List[String])

/** What happened to one source in a run. `text` is the status health.json shows. */
enum Status:
  case Ok, Error, Skipped
  def text: String = toString.toLowerCase

final case class SourceResult(id: String, status: Status, items: List[Item] = Nil, error: Option[String] = None)

final case class Report(
    cfg: Config,
    sources: List[Source],
    results: List[SourceResult],
    items: List[Item],
    errors: List[String],
    now: Instant,
)

/** Why a request gave no body. `describe` is the text health.json shows. */
enum FetchError:
  case Http(code: Int)
  case Timeout
  case Failed(message: String)

  def describe: String = (this match
    case Http(code)      => s"HTTP $code"
    case Timeout         => "timeout"
    case Failed(message) => message
  ).take(200)

  /** A timeout or an HTTP 5xx. Never a 4xx. */
  def retryable: Boolean = this match
    case Http(code) => code >= 500
    case Timeout    => true
    case Failed(_)  => false

/** A GET: the URL and the extra headers. */
final case class Request(url: String, headers: Seq[(String, String)] = Nil)

/** GitHub's repository search: the host, the request and the fields of an answer. */
object GithubApi:
  val Host = "api.github.com"
  val SearchUrl = s"https://$Host/search/repositories?"
  val Accept = "Accept" -> "application/vnd.github+json"
  def authorization(token: String): (String, String) = "Authorization" -> s"Bearer $token"

  val Items = "items"
  val FullName = "full_name"
  val HtmlUrl = "html_url"
  val Description = "description"
  val PushedAt = "pushed_at"
  val CreatedAt = "created_at"
  val Stars = "stargazers_count"

/** The fields of an Apple podcast chart. */
object AppleChart:
  val Feed = "feed"
  val Results = "results"
  val Genres = "genres"
  val Name = "name"
  val Url = "url"
  val Artist = "artistName"

/** The files of a run: feeds.toml and state.json in the feeds home, the others in the output folder. */
enum FeedFile(val name: String):
  case FeedsToml extends FeedFile("feeds.toml")
  case State extends FeedFile("state.json")
  case Atom extends FeedFile("feed.atom")
  case Digest extends FeedFile("digest.md")
  case Opml extends FeedFile("sources.opml")
  case Health extends FeedFile("health.json")

/** The keys of health.json. */
object HealthJson:
  val Generated = "generated"
  val Sources = "sources"
  val Status = "status"
  val Error = "error"
  val Items = "items"
  val Newest = "newest"

/** What the environment gives a run, read once by `FeedBuild.run`. */
final case class Environment(feedsHome: os.Path, githubToken: Option[String])

object Environment:
  val HermesHome = "HERMES_HOME"
  val GithubToken = "GITHUB_TOKEN"
  val OutDir = "out"

  /** $HERMES_HOME/feeds, ~/.hermes/feeds without it. */
  def from(lookup: String => Option[String]): Environment =
    val hermes = lookup(HermesHome).fold(os.home / ".hermes")(h => os.Path(expandHome(h), os.pwd))
    Environment(hermes / "feeds", lookup(GithubToken))

  def expandHome(p: String): String =
    if p == "~" || p.startsWith("~/") then os.home.toString + p.drop(1) else p

/** The command line of feed-build. */
final case class Args(
    config: Option[os.Path] = None,
    out: Option[os.Path] = None,
    state: Option[os.Path] = None,
    dryRun: Boolean = false,
    noState: Boolean = false,
    opmlOnly: Boolean = false,
    maxSeconds: Double = 150.0,
    sources: List[String] = Nil,
)

/** Where a run reads and writes: the command line first, then the feeds home. */
final case class Paths(config: os.Path, out: os.Path, state: os.Path)

object Paths:
  def of(args: Args, environment: Environment): Paths =
    val home = environment.feedsHome
    Paths(args.config.getOrElse(home / FeedFile.FeedsToml.name), args.out.getOrElse(home / Environment.OutDir),
      args.state.getOrElse(home / FeedFile.State.name))

/** state.json: the id of each printed item and the date it was first printed (yyyy-mm-dd, UTC). */
final case class State(seen: Map[String, String]):
  def contains(id: String): Boolean = seen.contains(id)

  /** Without the entries first seen more than SeenDays days ago, and the damaged ones. */
  def pruned(now: Instant): State =
    val today = Dates.utcDate(now)
    State(seen.filter { (_, first) =>
      scala.util.Try(LocalDate.parse(first.take(10))).toOption.exists(d => ChronoUnit.DAYS.between(d, today) <= State.SeenDays)
    })

  def withSeen(ids: List[String], today: LocalDate): State = State(seen ++ ids.map(_ -> today.toString))

  def render: String =
    val sorted = ujson.Obj.from(seen.toList.sortBy(_._1).map((k, v) => k -> ujson.Str(v)))
    ujson.write(ujson.Obj(State.Seen -> sorted), indent = 2)

object State:
  val SeenDays = 60
  val Seen = "seen"
  val empty: State = State(Map.empty)

  /** A damaged state only means nothing was seen: the next run prints again. */
  def parse(text: String): State =
    scala.util.Try(ujson.read(text).obj(Seen).obj).toOption.fold(empty) { seen =>
      State(seen.collect { case (k, ujson.Str(v)) => k -> v }.toMap)
    }
