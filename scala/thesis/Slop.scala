package piabrota.thesis

import scala.collection.mutable
import Prose.{Alpha, cleanWord, wordHit}
import Text.{fixed, g6}
import Signal.*

/** The phrase lists of gate 2, lower case. */
final case class SlopLists(phrases: List[String], transitions: List[String], summaries: List[String], hedges: List[String])

/** One row of the report: the columns as slop.awk printed them. */
final case class SignalRow(signal: Signal, value: String, warn: String, max: String, points: String)

/** An offending span: the signal, the line and what was found. */
final case class Span(signal: Signal, line: Int, text: String)

/** The score of one section: the rows in the order of the report, the spans in the order they were
  * found, and the sum of the points.
  */
final case class SlopScore(words: Int, tooShort: Boolean, signals: Vector[SignalRow], spans: Vector[Span], total: Double):
  /** printf "%.0f" of the sum. */
  def total0: String = fixed(total, 0)

/** Surface patterns that models overuse, in one pt-BR section. No external detector, no model: it
  * measures patterns, not authorship, and cannot promise any detector's result. A signal scores
  * weight * clamp((value - warn) / (max - warn), 0, 1); the score is the sum, from 0 to 100.
  */
object SlopScore:
  /** A signal's value (None: not measured, "n/a") and its spans. */
  private final case class Measure(signal: Signal, value: Option[Double], spans: Vector[Span] = Vector.empty)

  def measure(rows: Vector[Sentence], raw: String, title: String, params: SlopParams, lists: SlopLists): SlopScore =
    val sents = rows.filter(_.isProse)
    val words = sents.map(_.words).sum
    if words < params.minWords then SlopScore(words, tooShort = true, Vector.empty, Vector.empty, 0.0)
    else
      val measures = Measures(sents, words, raw, title, params, lists).all
      val scored = measures.map { m =>
        m.value match
          case None => (SignalRow(m.signal, "n/a", "-", "-", "0"), 0.0)
          case Some(v) =>
            val Band(w, a, b) = params.bands(m.signal)
            val pt = if b == a then 0.0 else w * ((v - a) / (b - a)).max(0).min(1)
            (SignalRow(m.signal, fixed(v, 3), g6(a), g6(b), fixed(pt, 1)), pt)
      }
      SlopScore(words, tooShort = false, scored.map(_._1), measures.flatMap(_.spans), scored.foldLeft(0.0)(_ + _._2))

  private final case class Measures(sents: Vector[Sentence], words: Int, raw: String, title: String, params: SlopParams,
      lists: SlopLists):
    private val per1000 = 1000.0 / words
    private val low = sents.map(s => s" ${s.text.toLowerCase} ")
    private val paras = sents.indices.filter(sents(_).kind == SentenceKind.Paragraph).groupBy(sents(_).para).toList
      .sortBy(_._2.head).map(_._2)

    def all: Vector[Measure] = Vector(phrases, dashes, tricolon, sameOpening, lowVariation, summaryEndings,
      repeatedNgrams, hedging, boldLeadins, restatedHeading, transitions)

    private def phrases: Measure =
      val hits = for i <- sents.indices.toVector; p <- lists.phrases; h = wordHit(low(i), p); if h > 0 yield (h, Span(Phrases, sents(i).line, p))
      Measure(Phrases, Some(hits.map(_._1).sum * per1000), hits.map(_._2))

    private def dashes: Measure =
      val lines = dashLines
      Measure(Dashes, Some(lines.length * per1000), lines.take(8).map(l => Span(Dashes, l, "dash")))

    private def tricolon: Measure =
      val k = params.tricolonItemMaxWords - 1
      val item = s"([$Alpha-]+ ){0,$k}[$Alpha-]+"
      val re = s"$item, $item,? (e|ou) $item".r
      val spans = sents.flatMap(s => re.findFirstIn(s.text).map(Span(Tricolon, s.line, _)))
      Measure(Tricolon, Some(spans.length.toDouble / sents.length), spans)

    /** Runs of same_opening_run or more sentences of one paragraph that begin with the same words. */
    private def sameOpening: Measure =
      val spans = mutable.ArrayBuffer[Span]()
      var run = 1
      (1 to sents.length).foreach { i =>
        val same = i < sents.length && sents(i).para == sents(i - 1).para && sents(i).kind == sents(i - 1).kind &&
          firstKey(sents(i).text) == firstKey(sents(i - 1).text) && firstKey(sents(i).text) != ""
        if same then run += 1
        else
          if run >= params.sameOpeningRun then
            spans += Span(SameOpening, sents(i - run).line, s"""$run sentences begin with "${firstKey(sents(i - 1).text)}"""")
          run = 1
      }
      Measure(SameOpening, Some(spans.length.toDouble), spans.toVector)

    private def lowVariation: Measure =
      Measure(LowVariation, Option.when(sents.length >= params.minSentencesForCv) {
        val mean = words.toDouble / sents.length
        val sd = math.sqrt(sents.map(s => math.pow(s.words - mean, 2)).sum / sents.length)
        sd / mean
      })

    private def summaryEndings: Measure =
      val eligible = paras.filter(_.length >= 3)
      val spans = eligible.toVector.flatMap { p =>
        val last = low(p.last).replaceFirst("""^ [„“"(]*""", "")
        Option.when(lists.summaries.exists(last.startsWith))(Span(SummaryEndings, sents(p.last).line, Text.take(sents(p.last).text, 70)))
      }
      Measure(SummaryEndings, Some(if eligible.length >= 3 then spans.length.toDouble / eligible.length else 0), spans)

    private def repeatedNgrams: Measure =
      val n = params.ngramSize
      val grams = mutable.LinkedHashMap[String, (Int, Int)]()
      sents.foreach { s =>
        val window = mutable.ArrayBuffer[String]()
        s.text.split(" ").foreach { tk =>
          val w = cleanWord(tk)
          if w.isEmpty || w.startsWith("§") || w.exists(c => c >= '0' && c <= '9') || w == "math" || w == "code" then window.clear()
          else
            window += w
            if window.length >= n then
              val key = window.takeRight(n).mkString(" ")
              val (count, line) = grams.getOrElse(key, (0, s.line))
              grams(key) = (count + 1, line)
        }
      }
      val repeated = grams.filter(_._2._1 >= params.ngramMinRepeats)
      Measure(RepeatedNgrams, Some(repeated.size * per1000),
        repeated.toVector.map { case (key, (count, line)) => Span(RepeatedNgrams, line, s""""$key" x$count""") })

    private def hedging: Measure =
      Measure(Hedging, Some(sents.indices.map(i => lists.hedges.map(wordHit(low(i), _)).sum).sum * per1000))

    private def boldLeadins: Measure =
      val bold = proseLines.filter((line, _) => """^ *([-*+]|[0-9]+[.)]) +\*\*[^*]+\*\*""".r.findFirstIn(line).isDefined)
      Measure(BoldLeadins, Some(bold.length.toDouble), bold.take(5).map((line, ln) => Span(BoldLeadins, ln, Text.take(line, 70))))

    private def restatedHeading: Measure =
      val titleWords = title.toLowerCase.split(s"[^$Alpha]+").filter(w => w.codePointCount(0, w.length) >= 5)
      val firstIdx = paras.headOption.map(_.head)
      val first = firstIdx.map(low).getOrElse("")
      val share = if titleWords.length >= 2 then titleWords.count(wordHit(first, _) > 0).toDouble / titleWords.length else 0
      val opens = first.matches("^ (este|neste|o presente|nesse|neste) (capítulo|seção|trabalho|texto).*")
      val restated = (if opens then share.max(0.5) + 0.4 else share).min(1)
      val span = Option.when(restated >= params.bands(RestatedHeading).warn)(
        Span(RestatedHeading, firstIdx.map(sents(_).line).getOrElse(0), Text.take(firstIdx.map(sents(_).text).getOrElse(""), 80)))
      Measure(RestatedHeading, Some(restated), span.toVector)

    private def transitions: Measure =
      val spans = paras.toVector.flatMap { p =>
        val start = low(p.head).replaceFirst("""^ [„“"(]*""", "")
        lists.transitions.find(start.startsWith).map(t => Span(Transitions, sents(p.head).line, t))
      }
      Measure(Transitions, Some(if paras.length >= 4 then spans.length.toDouble / paras.length else 0), spans)

    private def firstKey(text: String): String =
      val tk = text.split(" ")
      val w1 = cleanWord(tk.headOption.getOrElse(""))
      if w1.matches("^(o|a|os|as|um|uma|de|da|do|em|no|na|por|para|com|que|e|se|ao|à|nos|nas)$") then
        s"$w1 ${cleanWord(tk.lift(1).getOrElse(""))}"
      else w1

    /** The lines of the raw text outside code fences, with their numbers. */
    private def proseLines: Vector[(String, Int)] =
      Prose.lines(raw).zipWithIndex.foldLeft((false, Vector.empty[(String, Int)])) { case ((fence, out), (l, i)) =>
        val line = l.stripSuffix("\r")
        if line.matches("^ {0,3}(```|~~~).*") then (!fence, out)
        else (fence, if fence then out else out :+ (line -> (i + 1)))
      }._2

    /** One line number for each em dash, ---, spaced en dash or spaced --, outside code, math and markers. */
    private def dashLines: Vector[Int] =
      proseLines.flatMap { (line, ln) =>
        val t = line.replaceAll("`[^`]*`", "").replaceAll("""\$[^$]*\$""", "")
          .replaceAll("""\*\*\[(AUTHOR|ANALYSIS)[^\]]*\]\*\*""", "")
        "—|---| – | -- ".r.findAllIn(t).map(_ => ln).toVector
      }

/** `thesis slop <slug> <id>`: gate 2, the score of surface patterns of model-written text. */
object Slop:
  def run(k: Kit, args: List[String]): Int = args match
    case List(slug, id) => check(k, Gate(k, slug, id))
    case _              => fail("usage: thesis slop <slug> <id>")

  private def check(k: Kit, g: Gate): Int =
    def low(xs: List[String]) = xs.filter(_.nonEmpty).map(_.toLowerCase)
    val pl = k.profile.lists
    val params = k.profile.slop
    val r = SlopScore.measure(g.prose, g.text, g.sec.title, params,
      SlopLists(low(pl.slopPhrases), low(pl.transitions), low(pl.summaryOpeners), low(pl.hedges)))
    val thr = Profile.show(params.threshold)
    val slugId = s"${g.p.slug}/${g.sec.id}"
    say(s"slop: $slugId: surface patterns of model-written text, local rules only")
    say("  This measures patterns, not authorship. No detector is reliable and this one is not a detector:")
    say("  it cannot promise any external tool's score. A person writes some of these patterns. To lower the")
    say("  score, rewrite from facts and add what only the author knows (**[AUTHOR: ...]** markers, never")
    say("  invented experience); paraphrasing the same sentences keeps the pattern.")
    if r.tooShort then
      say(s"  ${r.words} words: under ${Profile.show(params.minWords)}, too short to score. Score 0 (not scored).")
      say(s"slop: $slugId: score 0/100 (threshold $thr): PASS (not scored)")
      0
    else
      say("  signal             value   warn    max  points")
      r.signals.foreach(s => say(f"  ${s.signal.name}%-17s ${s.value}%6s ${s.warn}%6s ${s.max}%6s ${s.points}%7s"))
      say("  offending spans (line, signal):")
      r.spans.take(40).foreach(s => say(s"    line ${s.line} ${s.signal.name}: ${Text.take(s.text, 90)}"))
      val score = r.total0
      if score.toDouble >= params.threshold then
        say(s"slop: $slugId: score $score/100 (threshold $thr): FAIL")
        1
      else
        say(s"slop: $slugId: score $score/100 (threshold $thr): PASS")
        0
