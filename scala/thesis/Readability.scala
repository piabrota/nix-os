package piabrota.thesis

import Prose.{Alnum, Alpha, wordHit}
import Text.{awkGt, awkNum, fixed}

/** The word lists of gate 1: the forms of ser, the participles, the anglicisms, the glossary terms
  * of the project and the groups of terms that name one thing.
  */
final case class ReadabilityLists(ser: Set[String], irregular: Set[String], adjectiveLike: Set[String],
    anglicisms: List[String], glossary: Set[String], groups: List[List[String]])

/** The paragraph numbers: a mean and a share are kept as printed, rounded. */
final case class Paragraphs(count: Int, mean: String, max: Int, over: Int, oneSentence: Int, oneSentenceShare: String)

/** The ratios, computed only with enough sentences. */
final case class Ratios(sentenceMean: String, sentenceMedian: String, long: Int, longShare: String,
    paragraphs: Option[Paragraphs], passive: Int, passiveShare: String, flesch: String, syllablesPerWord: String)

final case class LongSentence(line: Int, words: Int, text: String)

final case class Anglicism(term: String, line: Int, hits: Int)

/** The numbers of gate 1 (pt-BR), from the sentences of Prose. A rounded value is kept as text, the
  * way readability.awk printed it, because the report reads the rounded values back.
  *   - passive: a form of ser, then within three tokens a participle (-ado, -ido, ... or an irregular
  *     one of the profile) that is not adjective-like. The passive with -se is NOT counted.
  *   - Flesch-style index for Portuguese: 248.835 - 1.015 * words/sentences - 84.6 * syllables/word
  *     (Martins et al. 1996, constants from memory); the syllable counter is approximate.
  */
final case class ReadabilityNumbers(sentences: Int, words: Int, ratios: Option[Ratios], worst: Vector[LongSentence],
    passives: Vector[Mark], anglicisms: Vector[Anglicism], anglicismsDistinct: Int, mixed: Vector[String])

object ReadabilityNumbers:
  def measure(rows: Vector[Sentence], limits: ReadabilityLimits, lists: ReadabilityLists): ReadabilityNumbers =
    val sents = rows.filter(_.isProse)
    val ns = sents.length
    val words = sents.map(_.words).sum
    if ns < limits.minSentences then ReadabilityNumbers(ns, words, None, Vector.empty, Vector.empty, Vector.empty, 0, Vector.empty)
    else
      val mean = words.toDouble / ns
      val long = sents.count(_.words > limits.sentenceLongWords)
      val passive = sents.filter(s => isPassive(lists, s.text))
      val syl = sents.map(s => s.text.split(" ").filter(t => !t.matches("^§[A-Z]§$") && s"[$Alnum]".r.findFirstIn(t).isDefined)
        .map(_.replaceAll(s"[^$Alpha]", "")).filter(_.nonEmpty).map(syllables).sum).sum
      val perWord = syl.toDouble / (if words > 0 then words else 1)
      val ratios = Ratios(fixed(mean, 1), fixed(median(sents.map(_.words.toDouble)), 1), long, fixed(long.toDouble / ns, 3),
        paragraphs(sents, limits), passive.length, fixed(passive.length.toDouble / ns, 3),
        fixed(248.835 - 1.015 * mean - 84.6 * perWord, 1), fixed(perWord, 2))
      // The longest first; of two as long, the earlier.
      val worst = sents.zipWithIndex.sortBy((s, i) => (-s.words, i)).take(limits.worstSentences)
        .map((s, _) => LongSentence(s.line, s.words, s.text))
      val lower = sents.map(s => s" ${s.text.toLowerCase} ")
      val anglicisms = lists.anglicisms.filterNot(a => lists.glossary(a.toLowerCase)).toVector.flatMap { a =>
        sents.indices.map(i => Anglicism(a, sents(i).line, wordHit(lower(i), a.toLowerCase))).filter(_.hits > 0)
      }
      val mixed = lists.groups.toVector.flatMap { group =>
        val hits = group.filter { term =>
          term.split('|').exists(v => !lists.glossary(v.toLowerCase) && lower.exists(l => wordHit(l, v.toLowerCase) > 0))
        }
        Option.when(hits.length > 1)(hits.map(_.split('|').head).mkString(", "))
      }
      ReadabilityNumbers(ns, words, Some(ratios), worst, passive.take(5).map(s => Mark(s.line, s.text)), anglicisms,
        anglicisms.map(_.term.toLowerCase).distinct.length, mixed)

  private def paragraphs(sents: Vector[Sentence], limits: ReadabilityLimits): Option[Paragraphs] =
    val paras = sents.filter(_.kind == SentenceKind.Paragraph).groupBy(_.para).values.toList
    Option.when(paras.nonEmpty) {
      val pw = paras.map(_.map(_.words).sum)
      val one = paras.count(_.length == 1)
      Paragraphs(paras.length, fixed(pw.sum.toDouble / paras.length, 1), pw.max, pw.count(_ > limits.paragraphWordsMax),
        one, fixed(one.toDouble / paras.length, 3))
    }

  private def isParticiple(lists: ReadabilityLists, t: String): Boolean =
    if t == "sido" || t == "ido" || lists.adjectiveLike(t) then false
    else lists.irregular(t) || t.length >= 5 && t.matches(".*(ado|ada|ados|adas|ido|ida|idos|idas)$")

  private def isPassive(lists: ReadabilityLists, text: String): Boolean =
    val tk = text.split(" ").map(Prose.cleanWord)
    tk.indices.exists(i => lists.ser(tk(i)) && (i + 1 to (i + 3).min(tk.length - 1)).exists(j => isParticiple(lists, tk(j))))

  def median(xs: Seq[Double]): Double =
    val s = xs.sorted
    if s.isEmpty then 0 else if s.length % 2 == 1 then s(s.length / 2) else (s(s.length / 2 - 1) + s(s.length / 2)) / 2

  private val vowels = "aeiouáéíóúâêôãõàü".toSet
  private val strong = "aeoáéóâêôãõ".toSet

  /** Vowel groups, with two strong vowels or an accented i or u split: approximate. */
  def syllables(w: String): Int =
    val low = w.toLowerCase
    low.indices.count { i =>
      val c = low(i)
      vowels(c) && (i == 0 || !vowels(low(i - 1)) || (strong(low(i - 1)) && strong(c)) || c == 'í' || c == 'ú')
    }.max(1)

/** `thesis readability <slug> <id>`: gate 1, human-readable pt-BR. Numbers first; a verdict only for
  * the hard limits of profile.json.
  */
object Readability:
  def run(k: Kit, args: List[String]): Int = args match
    case List(slug, id) => check(k, Gate(k, slug, id))
    case _              => fail("usage: thesis readability <slug> <id>")

  private def check(k: Kit, g: Gate): Int =
    val pl = k.profile.lists
    val lists = ReadabilityLists(
      ser = pl.serForms.map(_.toLowerCase).toSet,
      irregular = pl.irregularParticiples.map(_.toLowerCase).toSet,
      adjectiveLike = pl.adjectiveLikeParticiples.map(_.toLowerCase).toSet,
      anglicisms = pl.anglicisms.filter(_.nonEmpty),
      glossary = glossaryTerms(g.p).toSet,
      groups = k.profile.mixedTerms)
    val lim = k.profile.readability
    val r = ReadabilityNumbers.measure(g.prose, lim, lists)
    def show(d: Double): String = Profile.show(d)
    def pct1(v: String): String = fixed(awkNum(v) * 100, 1)
    def pct0(v: String): String = fixed(awkNum(v) * 100, 0)
    def pctInt(d: Double): String = (d * 100).toLong.toString
    val fails = new StringBuilder
    val slugId = s"${g.p.slug}/${g.sec.id}"

    say(s"readability: $slugId (pt-BR heuristics; approximate; numbers first, a verdict only for the hard limits)")
    say(s"  sentences ${r.sentences}, words ${r.words}")
    r.ratios match
      case None => say(s"  fewer than ${show(lim.minSentences)} sentences: the ratios are not computed")
      case Some(m) =>
        val mean = m.sentenceMean
        say(s"  sentence length: mean $mean, median ${m.sentenceMedian} words; over ${show(lim.sentenceLongWords)} words: ${m.long} (${pct1(m.longShare)} %)   [limits: mean ${show(lim.sentenceMeanMax)}, share ${pctInt(lim.sentenceLongShareMax)} %]")
        if awkGt(mean, show(lim.sentenceMeanMax)) then fails ++= s" mean sentence length $mean > ${show(lim.sentenceMeanMax)};"
        if awkGt(m.longShare, show(lim.sentenceLongShareMax)) then
          fails ++= s" ${m.long} sentences over ${show(lim.sentenceLongWords)} words;"
        m.paragraphs.foreach { pg =>
          say(s"  paragraphs: ${pg.count}, mean ${pg.mean} words, longest ${pg.max}; over ${show(lim.paragraphWordsMax)} words: ${pg.over}; one-sentence: ${pg.oneSentence} (${pct0(pg.oneSentenceShare)} %)   [limit ${pctInt(lim.oneSentenceParagraphShareMax)} %]")
          if pg.over != 0 then fails ++= s" ${pg.over} paragraph(s) over ${show(lim.paragraphWordsMax)} words;"
          if awkGt(pg.oneSentenceShare, show(lim.oneSentenceParagraphShareMax)) && pg.count >= 4 then
            fails ++= " too many one-sentence paragraphs;"
        }
        say(s"  passive (ser + participle; the -se passive is NOT counted): ${m.passive} of ${r.sentences} (${pct1(m.passiveShare)} %)   [limit ${pctInt(lim.passiveShareMax)} %]")
        if awkGt(m.passiveShare, show(lim.passiveShareMax)) then fails ++= " passive voice share over the limit;"
        say(s"  Flesch-style index for pt (Martins et al. 1996 constants; syllable count approximate): ${m.flesch}   [min ${show(lim.fleschPtMin)}]")
        if awkGt(show(lim.fleschPtMin), m.flesch) then fails ++= s" Flesch-style index ${m.flesch} < ${show(lim.fleschPtMin)};"

    val na = r.anglicismsDistinct
    say(s"  anglicisms not in notes/glossary.md: $na distinct")
    r.anglicisms.take(12).foreach(a => say(s"    line ${a.line}: ${a.term} (x${a.hits})"))
    if na >= lim.anglicismFailDistinct then fails ++= s" $na distinct anglicisms;"
    val nm = r.mixed.length
    say(s"  mixed terms: $nm group(s)")
    r.mixed.foreach(x => say(s"    one thing, several words: $x"))
    if nm != 0 then fails ++= s" mixed terms ($nm group(s));"

    val scan = LintScan(g.text, g.sec.role, pl.allowedChars, Nil)
    val uncited = scan.uncited("fig", "tbl", "eq")
    say(s"  figures, tables, equations not cited in the text: ${uncited.length}")
    uncited.foreach(l => say(s"    ${l.name} is never cited"))
    if uncited.nonEmpty then fails ++= s" ${uncited.length} label(s) never cited;"

    say("  longest sentences (line, words):")
    r.worst.foreach(w => say(s"    line ${w.line}, ${w.words} words: ${Text.take(w.text, 110)}"))
    say("  passive examples:")
    r.passives.foreach(m => say(s"    line ${m.line}: ${Text.take(m.text, 110)}"))
    if fails.nonEmpty then
      say(s"readability: $slugId: FAIL:$fails")
      1
    else
      say(s"readability: $slugId: PASS (the hard limits only; read the numbers)")
      0

  /** The terms of notes/glossary.md, lower case: the first cell of a table row, or the first words
    * of a list item before a dash or a colon.
    */
  def glossaryTerms(p: Project): List[String] =
    val file = p.notes / Names.GlossaryMd
    if !os.isFile(file) then Nil
    else
      Prose.lines(os.read(file)).flatMap { line =>
        if line.matches("^ *\\|.*") then
          val cells = line.split("\\|", -1)
          val t = if cells.length > 1 then cells(1).replaceAll("^[ \t]+|[ \t]+$", "") else ""
          Option.when(t.nonEmpty && !t.matches("^-+$") && t.toLowerCase != "termo")(t.toLowerCase)
        else if line.matches("^ *[-*] +.*") then
          val t = line.replaceFirst("^ *[-*] +", "").replaceFirst(" *([:—–]|--| - ).*$", "").replace("*", "")
          Option.when(t.nonEmpty)(t.toLowerCase)
        else None
      }.toList
