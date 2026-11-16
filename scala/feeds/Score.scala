package piabrota.feeds

import java.time.{Duration, Instant}
import scala.math.Ordering.Double.TotalOrdering

/** The score of an item and the choice of what goes in the feed and in the digest (docs/FEEDS.md,
  * "Read the score").
  */
object Score:
  val InterestCap = 8.0

  /** Title match: 3 * weight / 5 * 2. Summary match: 1 * weight / 5 * 2. Else 0. */
  def interestPoints(interest: Interest, item: Item): Double =
    if interest.terms.in(item.title) then 3.0 * interest.weight / 5 * 2
    else if interest.terms.in(item.summary) then 1.0 * interest.weight / 5 * 2
    else 0.0

  /** The summed interest points, capped, and the names of the interests that matched. */
  def interestScore(item: Item, interests: List[Interest]): InterestScore =
    val hits = interests.map(i => i.name -> interestPoints(i, item)).filter(_._2 > 0)
    InterestScore(math.min(InterestCap, hits.map(_._2).sum), hits.map(_._1))

  /** +2 under 24 hours, then a straight line down to 0 at max_age_days. None without a date. */
  def recencyBonus(item: Item, src: Source, now: Instant): Double =
    val ageDays = Duration.between(item.date, now).toNanos / 86400e9
    val span = src.maxAgeDays - 1
    if !item.dated then 0.0
    else if ageDays <= 1 then 2.0
    else if span > 0 then math.max(0.0, 2.0 * (1 - (ageDays - 1) / span))
    else 0.0

  /** Up to +3 for a popular repository. */
  def starsBonus(stars: Int): Double = math.min(3.0, math.log10(stars + 1.0) / 1.5)

  /** A dated item older than the source limit. */
  def tooOld(item: Item, src: Source, now: Instant): Boolean =
    item.dated && Duration.between(item.date, now).compareTo(Duration.ofDays(src.maxAgeDays)) > 0

  /** The title has a term of the source's exclude_terms, as a whole word or phrase. */
  def isExcluded(item: Item, src: Source): Boolean = src.excluded.in(item.title)

  /** The item with its score, or None when a rule drops it. */
  def scoreItem(item: Item, src: Source, cfg: Config, now: Instant): Option[Item] =
    val interest = interestScore(item, cfg.interests)
    val dropped = cfg.negative.in(item.title) || cfg.negative.in(item.summary) ||
      tooOld(item, src, now) || isExcluded(item, src) || (src.requiresMatch && interest.matched.isEmpty)
    Option.unless(dropped) {
      val total = src.weight + interest.points + recencyBonus(item, src, now) + starsBonus(item.stars)
      item.copy(score = round1(total), matched = interest.matched)
    }

  /** Python's `round(x, 1)`: half to even, on the exact value of the double. */
  def round1(x: Double): Double =
    new java.math.BigDecimal(x).setScale(1, java.math.RoundingMode.HALF_EVEN).doubleValue

  /** Score the items of one source; keep those at min_score or more, and the pinned ones. */
  def selectItems(src: Source, items: List[Item], cfg: Config, now: Instant): List[Item] =
    val scored = items.flatMap(scoreItem(_, src, cfg, now))
    // A pinned source keeps its newest pinned_keep items whatever their score.
    val pinned =
      if src.pinned then scored.sortBy(_.date)(using Ordering[Instant].reverse).take(src.pinnedKeep).map(_.link).toSet
      else Set.empty[String]
    scored.map(i => i.copy(pinned = pinned(i.link))).filter(i => i.score >= cfg.output.minScore || i.pinned)

  /** One item for each key: the highest score, then the newest. An empty key never merges. */
  def bestBy(items: List[Item], key: Item => String): List[Item] =
    val best = items.zipWithIndex.foldLeft(Vector.empty[(String, Item)]) { case (kept, (item, position)) =>
      val name = Some(key(item)).filter(_.nonEmpty).getOrElse(s"#$position")
      kept.indexWhere(_._1 == name) match
        case -1 => kept :+ (name -> item)
        case i =>
          val current = kept(i)._2
          val better = item.score > current.score || item.score == current.score && item.date.isAfter(current.date)
          if better then kept.updated(i, name -> item) else kept
    }
    best.map(_._2).toList

  /** By normalised link first, then by normalised title. */
  def dedupe(items: List[Item]): List[Item] =
    bestBy(bestBy(items, i => Links.normalise(i.link)), i => Links.normaliseTitle(i.title))

  /** Best score first, then newest. */
  def rank(items: List[Item]): List[Item] = items.sortBy(i => (-i.score, -seconds(i.date)))

  private def seconds(moment: Instant): Double = moment.getEpochSecond + moment.getNano / 1e9

  /** The order inside a group for the feed, best last: pinned, then score, then date. */
  private val shareOrder: Ordering[Item] = Ordering.by(i => (i.pinned, i.score, seconds(i.date)))

  /** The order inside a group for the digest, best last: score, then date. */
  private val bestOrder: Ordering[Item] = Ordering.by(i => (i.score, seconds(i.date)))

  /** The best `share` items of each group, and all the others; both best first. */
  def splitShares(items: List[Item], share: Int, order: Ordering[Item]): (List[Item], List[Item]) =
    val sorted = items.sortBy(identity)(using order.reverse)
    val counts = sorted.scanLeft(Map.empty[String, Int])((seen, i) => seen.updated(i.group, seen.getOrElse(i.group, 0) + 1))
    val marked = sorted.zip(counts).map((item, seen) => (item, seen.getOrElse(item.group, 0) < share))
    (marked.collect { case (i, true) => i }, marked.collect { case (i, false) => i })

  /** Each group gets max_per_group places first; the room that is left goes to the best of the rest. */
  def selectForFeed(items: List[Item], output: Output): List[Item] =
    val (first, rest) = splitShares(items, output.maxPerGroup, shareOrder)
    val chosen = first ++ rank(rest).take(math.max(0, output.maxItems - first.length))
    rank(chosen.sortBy(identity)(using shareOrder.reverse).take(output.maxItems))

  /** At most digest_per_group items of each group, best first, cut at digest_items. */
  def selectForDigest(items: List[Item], output: Output): List[Item] =
    rank(splitShares(items, output.digestPerGroup, bestOrder)._1).take(output.digestItems)
