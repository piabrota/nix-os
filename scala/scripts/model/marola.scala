package piabrota.scripts

// marola.dev's boards, tiles and backups on the box, and the check of the boards from outside.

/** The files and keys of a marola site's boards: `areas.json` names the areas, each area's
  * `latest.json` names its day files and when it was generated.
  */
object Boards:
  val areasFile = "areas.json"
  val latestFile = "latest.json"
  val dayFile = "[0-9]{4}-[0-9]{2}-[0-9]{2}\\.json".r

  /** The ids of an areas.json. */
  def areas(json: String): List[String] = ujson.read(json)("areas").arr.map(a => Jq.raw(a("id"))).toList

  /** The day files a latest.json names, as `jq -r '.days[].file'` prints them; Nil if it cannot be read. */
  def days(json: String): List[String] =
    scala.util.Try(ujson.read(json)("days").arr.map(d => Jq.rawField(d, "file")).toList).getOrElse(Nil)

  /** A file name from the network: only <date>.json, never a path. */
  def isDayFile(name: String): Boolean = dayFile.matches(name)

  /** `.generated_at` of a latest.json, as `jq -er` gives it: None when missing, null or false. */
  def generatedAt(json: String): Option[String] =
    Jq.parse(json).flatMap(Jq.get(_, "generated_at")).map {
      case ujson.Str(s) => s
      case other        => other.render()
    }

/** marola-boards-check's settings: the site, MAX_AGE_HOURS in seconds, and the clock. */
final case class BoardsCheckConfig(base: String, maxAge: Long, now: Long)

object BoardsCheckConfig:
  val defaultBase = "https://marola.piabrota.art"
  val defaultMaxHours = 12L

/** One row of marola-boards-check's table: an area's board, its time and age, or none. */
enum BoardRow:
  case Missing(area: String)
  case Dated(area: String, generated: String, age: Long, maxAge: Long)

  def fresh: Boolean = this match
    case Missing(_)                  => false
    case Dated(_, _, age, maxAge)    => age <= maxAge

  def render: String = this match
    case Missing(area) => s"| $area | no latest.json | ✗ |"
    case Dated(area, generated, age, maxAge) =>
      val mark = if fresh then "✓" else s"✗ older than ${maxAge / 3600} h"
      s"| $area | $generated (${age / 3600} h ago) | $mark |"

/** marola-boards-build's settings: the unit's credentials and runtime directories, from systemd. */
final case class BoardsBuildConfig(credentials: Option[os.Path], runtime: Option[os.Path]):
  def ghcrToken: Option[os.Path] = credentials.map(_ / "ghcr-token").filter(os.isFile)

/** The places on the box. */
object MarolaPaths:
  val boardsBuild: os.Path = os.Path("/var/lib/marola-boards-build")
  val tilesWork: os.Path = os.Path("/var/lib/marola-tiles")
  val backups: os.Path = os.Path("/var/backups/marola")
  val tiles = "marola.pmtiles"
  /** tile-join picks its output format from the suffix, so the new file must end in .pmtiles. */
  val newTiles = "marola.new.pmtiles"
  val stamp = ".stamp"
  val registry = "ghcr.io"
