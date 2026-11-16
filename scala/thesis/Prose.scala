package piabrota.thesis

import scala.collection.mutable.ArrayBuffer

/** Where a sentence stands: a paragraph, a list item, a block quote, a heading, a caption or a
  * footnote (footnotes are skipped).
  */
enum SentenceKind:
  case Paragraph, ListItem, Quote, Heading, Caption, Footnote

/** One sentence of a section: para is the same number for the sentences of one paragraph; line is
  * where it starts; words counts the words that are not marks.
  */
final case class Sentence(kind: SentenceKind, para: Int, line: Int, words: Int, text: String):
  def isProse: Boolean = kind match
    case SentenceKind.Paragraph | SentenceKind.ListItem | SentenceKind.Quote => true
    case _                                                                => false

/** The prose of one pandoc-markdown section, one sentence a row. Marks in the text: §C§ a citation
  * [@key], §N§ a narrative @key, §U§ a URL, §D§ a DOI, §F§ a footnote, MATH inline math, CODE a
  * code span; a cross-reference becomes "Figura 1". Skipped: code fences, display math, tables,
  * comments and the **[AUTHOR ...]** and **[ANALYSIS]** markers.
  */
object Prose:
  val Alpha = """\p{L}"""
  val Alnum = """\p{L}\p{N}"""

  def sentences(text: String, abbreviations: Set[String]): Vector[Sentence] =
    val s = new Scanner(abbreviations)
    lines(text).zipWithIndex.foreach((line, i) => s.line(line.stripSuffix("\r"), i + 1))
    s.flush()
    s.out.toVector

  /** The lines of a file as awk reads them: no empty last line after the final newline. */
  def lines(text: String): Vector[String] =
    if text.isEmpty then Vector.empty else text.stripSuffix("\n").split("\n", -1).toVector

  /** The words of the prose (paragraphs, lists, quotes): `words_of`. */
  def words(rows: Seq[Sentence]): Int = rows.filter(_.isProse).map(_.words).sum

  private val Fence = """^ {0,3}(```|~~~)""".r
  private val MathFence = """^ *\$\$ *$""".r
  private val MathLine = """^ *\$\$.*\$\$""".r
  private val Comment = """^ *<!--""".r
  private val Blank = """^[ \t]*$""".r
  private val TableRow = """^ *(\||[+][-=+]+[+])""".r
  private val FootnoteDef = """^ *\[\^[^\]]+\]:""".r
  private val Image = """^ *!\[""".r
  private val HeadingLine = """^ {0,3}#+ """.r
  private val QuoteLine = """^ {0,3}>""".r
  private val ListLine = """^ *([-*+]|[0-9]+[.)]) +""".r

  def matches(re: scala.util.matching.Regex, s: String): Boolean = re.findFirstIn(s).isDefined

  /** How often term stands in low as a whole word: no letter right before or after it. */
  def wordHit(low: String, term: String): Int =
    if term.isEmpty then 0
    else
      Iterator.iterate(low.indexOf(term))(i => low.indexOf(term, i + term.length)).takeWhile(_ >= 0).count { pos =>
        val before = if pos == 0 then ' ' else low.charAt(pos - 1)
        val after = if pos + term.length < low.length then low.charAt(pos + term.length) else ' '
        !before.isLetter && !after.isLetter
      }

  /** awk's gsub(/^[^[:alnum:]§]+|[^[:alnum:]§]+$/, "") and tolower. */
  def cleanWord(t: String): String =
    t.replaceAll(s"^[^$Alnum§]+|[^$Alnum§]+$$", "").toLowerCase

  private final class Scanner(abbr: Set[String]):
    import SentenceKind.*
    val out = ArrayBuffer[Sentence]()
    private val words = ArrayBuffer[(String, Int)]()
    private var para = 0
    private var kind: SentenceKind = Paragraph
    private var fence = false
    private var mathBlock = false

    def line(line: String, ln: Int): Unit =
      if matches(Fence, line) then { flush(); fence = !fence }
      else if fence then ()
      else if matches(MathFence, line) then { flush(); mathBlock = !mathBlock }
      else if mathBlock then ()
      else if matches(MathLine, line) || matches(Comment, line) then flush()
      else if matches(Blank, line) then { flush(); kind = Paragraph }
      else if matches(TableRow, line) then flush()
      else if matches(FootnoteDef, line) then { flush(); kind = Footnote }
      else if line.startsWith(": ") then single(Caption, line.drop(2), ln)
      else if matches(Image, line) then
        single(Caption, line.replaceFirst("""^ *!\[""", "").replaceFirst("""\]\(.*$""", ""), ln)
      else if matches(HeadingLine, line) then single(Heading, line.replaceFirst("""^ *#+ +""", ""), ln)
      else if matches(QuoteLine, line) then
        if kind != Quote then flush()
        kind = Quote
        add(line.replaceFirst("""^ *> ?""", ""), ln)
      else if matches(ListLine, line) then
        flush(); kind = ListItem
        add(line.replaceFirst("""^ *([-*+]|[0-9]+[.)]) +""", ""), ln)
      else if kind == Footnote then ()
      else
        if kind == Quote then { flush(); kind = Paragraph }
        add(line, ln)

    private def single(k: SentenceKind, text: String, ln: Int): Unit =
      flush(); kind = k; add(text, ln); flush(); kind = Paragraph

    private def add(text: String, ln: Int): Unit =
      clean(text).split("[ \t]+").foreach { part =>
        val stripped = part.replaceAll("^[*_]+|[*_]+$", "")
        val tok =
          if stripped.matches("^https?://.*") then "§U§"
          else if """10\.[0-9]{4,}/""".r.findFirstIn(stripped).isDefined then "§D§"
          else stripped
        if tok.nonEmpty then words += tok -> ln
      }

    def flush(): Unit =
      if words.nonEmpty then
        para += 1
        val sent = ArrayBuffer[String]()
        var nw = 0
        var start = words.head._2
        for (((tok, ln), i) <- words.zipWithIndex) do
          if sent.isEmpty then start = ln
          sent += tok
          if countsAsWord(tok) then nw += 1
          val end = i == words.length - 1 ||
            (tok.matches(""".*[.!?…]["”’)\]]*$""") && !isAbbr(tok) &&
              words(i + 1)._1.matches(s"""^["“‘(\\[]?([\\p{Lu}0-9]|§).*"""))
          if end then
            if nw > 0 || kind == Heading then out += Sentence(kind, para, start, nw, sent.mkString(" "))
            sent.clear()
            nw = 0
        words.clear()

    private def isAbbr(tok: String): Boolean =
      val t = tok.toLowerCase.replaceAll("""[.)"”’]+$""", "")
      abbr(t) || tok.matches(s"^[$Alpha]\\.$$") || tok.matches(s"^[$Alpha]{1,3}(\\.[$Alpha]{1,3})+\\.$$")

    private def countsAsWord(tok: String): Boolean =
      !tok.matches("^§[A-Z]§$") && s"[$Alnum]".r.findFirstIn(tok).isDefined

  /** The marks of prose.awk's `clean`. */
  def clean(text: String): String =
    val s = text.replace("\r", "")
      .replaceAll("""\*\*\[(AUTHOR|ANALYSIS)[^\]]*\]\*\*""", " ")
      .replaceAll("""!\[[^\]]*\]\([^)]*\)(\{[^}]*\})?""", " ")
      .replaceAll("""\[\^[^\]]*\]""", " §F§ ")
      .replaceAll("""\[@(fig|tbl|eq|sec|cap):[^\]]*\]""", " Figura 1 ")
      .replaceAll("""@(fig|tbl|eq|sec|cap):[A-Za-z0-9_-]+""", " Figura 1 ")
      .replaceAll("""\[[^\]\[]*@[^\]\[]*\]""", " §C§ ")
      .replaceAll("""(^|[ (])@[A-Za-z][A-Za-z0-9_:.-]*[A-Za-z0-9]""", " §N§")
    unlink(s)
      .replaceAll("""\{[#.][^}]*\}""", " ")
      .replaceAll("""\$[^$]+\$""", " MATH ")
      .replaceAll("`[^`]*`", " CODE ")
      .replaceAll("""<(https?://[^>]*)>""", " §U§ ")

  /** [text](url) becomes text. */
  private def unlink(s: String): String =
    """\[([^\]\[]*)\]\([^)]*\)""".r.replaceAllIn(s, m => scala.util.matching.Regex.quoteReplacement(m.group(1)))
