package piabrota.metrics

import Awk.*

/** The first word of each line of the probe file (`<STATE_DIR>/<name>.probe`). */
enum ProbeKey(val key: String):
  case Ts extends ProbeKey("ts")
  case Domain extends ProbeKey("domain")
  case Repo extends ProbeKey("repo")
  case Asked extends ProbeKey("asked")
  case Visits extends ProbeKey("visits")

object ProbeKey:
  val byKey: Map[String, ProbeKey] = values.map(k => k.key -> k).toMap

/** A line of the sites file that Nix wrote: a site of this host and the address the probe asks. */
final case class Site(domain: String, url: String)

object Site:
  val Name = "[a-z0-9.-]+".r
  val Max = 24

  /** The good lines, 24 at most: a lowercase name and an http(s) address. */
  def parse(text: Option[String]): List[Site] =
    lines(text).toList.map(fields).collect {
      case f if Name.matches(nth(f, 1)) && (nth(f, 2).startsWith("http://") || nth(f, 2).startsWith("https://")) =>
        Site(f(0), f(1))
    }.take(Max)

/** The commit count and when GitHub gave it, as the probe file holds them. */
final case class CommitCount(commits: String, ts: String)

/** A site's views and distinct addresses of the last 24 h. */
final case class SiteVisits(site: String, views: Long, visitors: Long)

/** What one probe run writes: its time, the HTTP code of each site ("000" when nothing answered),
  * the commit count, when GitHub was last asked (only with a repository), the visits.
  */
final case class ProbeFile(ts: Long, answers: List[(Site, String)], commits: Option[CommitCount], asked: Option[Long],
    visits: List[SiteVisits]):
  import ProbeKey.*

  def render: String =
    (Vector(s"${Ts.key} $ts") ++
      answers.map((site, code) => s"${Domain.key} ${site.domain} $code") ++
      commits.map(c => s"${Repo.key} ${c.commits} ${c.ts}") ++
      asked.map(a => s"${Asked.key} $a") ++
      visits.map(v => s"${Visits.key} ${v.site} ${v.views} ${v.visitors}")).map(_ + "\n").mkString

object ProbeFile:
  import ProbeKey.*

  /** From the last file: its count ("repo <commits> <ts>"), kept when GitHub is not asked or does
    * not answer, and when GitHub was last asked ("asked <ts>"), so a GitHub that fails is not
    * asked every run.
    */
  def lastAnswer(text: Option[String]): (Option[CommitCount], Long) =
    lines(text).map(fields).foldLeft((Option.empty[CommitCount], 0L)) { case ((count, asked), f) =>
      val (n, ts) = (nth(f, 2), nth(f, 3))
      byKey.get(nth(f, 1)) match
        case Some(Repo) if isDigits(n + ts) => (Some(CommitCount(n, ts)), asked)
        case Some(Asked) if isDigits(n)     => (count, n.toLongOption.getOrElse(0L))
        case _                              => (count, asked)
    }

/** The probe file as the collector reads it: each line checked again, since it is only a file. */
final case class ProbeReport(ts: Option[String], sites: List[SiteStatus], commits: Option[CommitCount])

object ProbeReport:
  import ProbeKey.*

  private def short(s: String) = isDigits(s) && s.length <= 9

  /** The last "ts", the first 24 good "domain" lines, each with its first "visits", the last
    * good "repo".
    */
  def parse(text: Option[String]): ProbeReport =
    val rows = lines(text).toList.map(fields).flatMap(f => f.headOption.flatMap(byKey.get).map(_ -> f.toList.tail))
    val visits = rows.collect {
      case (Visits, List(site, v, p)) if short(v) && short(p) => site -> SiteVisits(site, v.toLong, p.toLong)
    }.distinctBy(_._1).toMap
    val sites = rows.collect {
      case (Domain, List(site @ Site.Name(), code)) if site.length <= 64 && code.length == 3 && isDigits(code) =>
        SiteStatus(site, code.toInt, visits.get(site))
    }.take(Site.Max)
    ProbeReport(
      rows.collect { case (Ts, List(t)) if isDigits(t) => t }.lastOption,
      sites,
      rows.collect { case (Repo, List(n, t)) if short(n) && isDigits(t) => CommitCount(n, t) }.lastOption,
    )

/** The first word of each line of the visits state (`<STATE_DIR>/<name>.visits`). */
enum VisitsKey(val key: String):
  case Pos extends VisitsKey("pos")
  case Hour extends VisitsKey("h")
  case Address extends VisitsKey("u")

/** Where the last run stopped in nginx's log: its inode and the offset after the last whole line. */
final case class LogPosition(inode: String, offset: Long)

object LogPosition:
  val Start: LogPosition = LogPosition("0", 0L)

/** The visits state: where the log was read to, the views by the hour and site, and the last time
  * of each address of a site, in the order they were first seen.
  */
final case class VisitsState(pos: LogPosition, hours: Iterable[((Long, String), Long)],
    seen: Iterable[((String, String), Long)]):
  import VisitsKey.*

  def render: String =
    (Vector(s"${Pos.key} ${pos.inode} ${pos.offset}") ++
      hours.map { case ((hour, site), n) => s"${Hour.key} $hour $site $n" } ++
      seen.map { case ((site, addr), t) => s"${Address.key} $site $addr $t" }).mkString("", "\n", "\n")

  /** "visits <site> <views> <visitors>" for each site of `known`. */
  def visits(known: List[String]): List[SiteVisits] = known.map { site =>
    SiteVisits(site, hours.collect { case ((_, s), n) if s == site => n }.sum, seen.count(_._1._1 == site).toLong)
  }

object VisitsState:
  import VisitsKey.*

  val DaySeconds = 86400L
  val HourSeconds = 3600L
  val MaxAddresses = 50000
  private val Stamp = "[0-9]+(\\.[0-9]+)?".r
  private val AddressText = "[0-9A-Fa-f.:]+".r

  /** The first line of the state: "pos <inode> <offset>". */
  def position(state: Option[String]): LogPosition =
    lines(state).headOption.map(fields) match
      case Some(Array(Pos.key, i, o, _*)) if isDigits(i) && isDigits(o) => LogPosition(i, o.toLong)
      case _                                                            => LogPosition.Start

  /** The state's hours and addresses still inside the 24 h before `now`, with the new log lines
    * added: an address is kept when it was seen before or there are fewer than 50000.
    */
  def tally(state: Option[String], logLines: List[String], known: List[String], now: Long, pos: LogPosition): VisitsState =
    val from = now - DaySeconds
    val hours = collection.mutable.LinkedHashMap[(Long, String), Long]().withDefaultValue(0L)
    val seen = collection.mutable.LinkedHashMap[(String, String), Long]()
    def visit(site: String, addr: String, ts: Long): Unit =
      seen((site, addr)) = math.max(seen.getOrElse((site, addr), 0L), ts)
    lines(state).map(fields).foreach {
      case Array(Hour.key, hour, site, n) if isDigits(n) && isDigits(hour) && num(hour) + HourSeconds > from && known.contains(site) =>
        hours((hour.toLong, site)) += n.toLong
      case Array(Address.key, site, addr, t) if isDigits(t) && known.contains(site) && AddressText.matches(addr) && num(t) > from =>
        visit(site, addr, t.toLong)
      case _ => ()
    }
    logLines.map(fields).foreach {
      case Array(stamp @ Stamp(_), site, addr) if known.contains(site) && AddressText.matches(addr) && addr.length <= 45 =>
        val ts = num(stamp).toLong
        if ts > from && ts <= now + 60 then
          hours((ts - ts % HourSeconds, site)) += 1
          if seen.contains((site, addr)) || seen.size < MaxAddresses then visit(site, addr, ts)
      case _ => ()
    }
    VisitsState(pos, hours.toVector, seen.toVector)
