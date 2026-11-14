package piabrota.feeds

import java.time.{DateTimeException, Instant, LocalDate, LocalDateTime, ZoneOffset}

/** Dates of feeds: ISO 8601 (Atom, GitHub) or RFC 822 (RSS), as the Python script read them with
  * `datetime.fromisoformat` and `email.utils.parsedate_to_datetime`. A time with no offset is UTC.
  * There is no time zone database (scala/README.md), so only offsets and the zone abbreviations of
  * RFC 822 are known.
  */
object Dates:
  /** The text as a moment; None when it is neither form. */
  def parse(text: String): Option[Instant] =
    val t = Text.strip(text)
    iso(t).orElse(rfc822(t))

  /** 2026-11-04T10:00:00Z */
  def isoZ(moment: Instant): String =
    val t = moment.atOffset(ZoneOffset.UTC)
    f"${t.getYear}%04d-${t.getMonthValue}%02d-${t.getDayOfMonth}%02dT${t.getHour}%02d:${t.getMinute}%02d:${t.getSecond}%02dZ"

  def utcDate(moment: Instant): LocalDate = moment.atOffset(ZoneOffset.UTC).toLocalDate

  private val Iso =
    """(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2})(?::(\d{2})(?::(\d{2})(?:[.,](\d{1,9}))?)?)?(Z|[+-]\d{2}(?::?\d{2})?)?)?""".r

  private def iso(t: String): Option[Instant] = t match
    case Iso(y, mo, d, h, mi, s, frac, zone) =>
      val nanos = Option(frac).fold(0)(f => f.padTo(9, '0').toInt)
      moment(y.toInt, mo.toInt, d.toInt, num(h), num(mi), num(s), nanos, isoOffset(zone))
    case _ => None

  private def num(group: String): Int = Option(group).fold(0)(_.toInt)

  private def isoOffset(zone: String): Int = zone match
    case null | "Z" => 0
    case z =>
      val digits = z.drop(1).replace(":", "")
      val seconds = digits.take(2).toInt * 3600 + digits.drop(2).toIntOption.getOrElse(0) * 60
      if z.startsWith("-") then -seconds else seconds

  private val dayNames = Set("mon", "tue", "wed", "thu", "fri", "sat", "sun")
  private val monthNames = Vector("jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct",
    "nov", "dec", "january", "february", "march", "april", "may", "june", "july", "august",
    "september", "october", "november", "december")
  private val zones = Map("UT" -> 0, "UTC" -> 0, "GMT" -> 0, "Z" -> 0, "AST" -> -400, "ADT" -> -300,
    "EST" -> -500, "EDT" -> -400, "CST" -> -600, "CDT" -> -500, "MST" -> -700, "MDT" -> -600,
    "PST" -> -800, "PDT" -> -700)

  /** `Wed, 04 Nov 2026 06:00:00 -0300`, read the way Python's `email.utils` reads it. */
  private def rfc822(t: String): Option[Instant] =
    val words = t.split("\\s+").toList.filter(_.nonEmpty) match
      case first :: rest if first.endsWith(",") || dayNames(first.toLowerCase) => rest
      case first :: rest => first.drop(first.lastIndexOf(',') + 1) :: rest
      case Nil           => Nil
    // A time and an offset written together, as 06:00:00-0300.
    val fields = words match
      case List(d, m, y, timeAndZone) =>
        val i = Some(timeAndZone.indexOf('+')).filter(_ >= 0).getOrElse(timeAndZone.indexOf('-'))
        if i > 0 then List(d, m, y, timeAndZone.take(i), timeAndZone.drop(i)) else List(d, m, y, timeAndZone, "")
      case more => more.take(5)
    fields match
      case List(d0, m0, y0, time0, zone0) =>
        val (d, m) =
          if monthNames.contains(m0.toLowerCase) then (d0, m0.toLowerCase) else (m0, d0.toLowerCase)
        val (y, time) = if y0.indexOf(':') > 0 then (time0, y0) else (y0, time0)
        for
          month <- Some(monthNames.indexOf(m)).filter(_ >= 0).map(i => i % 12 + 1)
          parts = time.stripSuffix(",").split(':').toList
          (hh, mm, ss) <- parts match
            case List(h, mi)    => Some((h, mi, "0"))
            case List(h, mi, s) => Some((h, mi, s))
            case _              => None
          year <- y.stripSuffix(",").toIntOption
          day <- d.stripSuffix(",").toIntOption
          hour <- hh.toIntOption
          minute <- mm.toIntOption
          second <- ss.toIntOption
          fullYear = if year >= 100 then year else if year > 68 then year + 1900 else year + 2000
          instant <- moment(fullYear, month, day, hour, minute, second, 0, rfcOffset(zone0))
        yield instant
      case _ => None

  /** -0300 is -3 hours; an unknown zone is UTC. */
  private def rfcOffset(zone: String): Int =
    zones.get(zone.toUpperCase).orElse(zone.toIntOption) match
      case Some(hhmm) =>
        val seconds = math.abs(hhmm) / 100 * 3600 + math.abs(hhmm) % 100 * 60
        if hhmm < 0 then -seconds else seconds
      case None => 0

  private def moment(y: Int, mo: Int, d: Int, h: Int, mi: Int, s: Int, nanos: Int, offsetSeconds: Int): Option[Instant] =
    try Some(LocalDateTime.of(y, mo, d, h, mi, s, nanos).toInstant(ZoneOffset.ofTotalSeconds(offsetSeconds)))
    catch case _: DateTimeException => None
