package piabrota.feeds

import scala.util.matching.Regex

/** Text as the Python script saw it: its `\s`, `\w`, `strip` and `len` are Unicode, so these are too. */
object Text:
  val SummaryMax = 400

  /** Python's `str.isspace`: also the no-break space that `&nbsp;` becomes. */
  def isSpace(c: Char): Boolean = Character.isWhitespace(c) || Character.isSpaceChar(c) || c == '\u0085'

  /** Python's `\w`: letters, digits, other numbers and `_`. */
  def isWord(codePoint: Int): Boolean =
    Character.isLetterOrDigit(codePoint) || codePoint == '_' ||
      Character.getType(codePoint) == Character.OTHER_NUMBER ||
      Character.getType(codePoint) == Character.LETTER_NUMBER

  def strip(s: String): String = s.dropWhile(isSpace).reverse.dropWhile(isSpace).reverse

  /** Python's `len`: code points, not UTF-16 units. */
  def length(s: String): Int = s.codePointCount(0, s.length)

  /** Python's `s[:n]`. */
  def take(s: String, n: Int): String =
    if length(s) <= n then s else s.substring(0, s.offsetByCodePoints(0, n))

  private val BlockTag = "(?i)</?(?:p|br|div|li|ul|ol|h[1-6]|tr|td|table|blockquote|pre)\\b[^>]*>".r
  private val AnyTag = "</?[A-Za-z!][^>]*>".r
  private val Control = "[\\x00-\\x08\\x0b\\x0c\\x0e-\\x1f]".r

  /** No HTML tags, entities, control characters or extra white space. */
  def clean(text: String): String =
    val plain = Html.unescape(AnyTag.replaceAllIn(BlockTag.replaceAllIn(text, " "), ""))
    words(Control.replaceAllIn(plain, ""))

  /** Clean text, cut at SummaryMax characters. */
  def summarize(text: String): String = take(clean(text), SummaryMax).stripTrailing

  /** The words, one space between them. */
  def words(s: String): String = s.map(c => if isSpace(c) then ' ' else c).split(' ').filter(_.nonEmpty).mkString(" ")

/** Terms that match as whole words or phrases, ignoring case: "omp" matches "OMP, again" but not
  * "pomp". The Python script used a look-around regex, which RE2 has not, so each term is looked
  * for in turn; every caller only asks whether one matches.
  */
final class Terms(terms: Seq[String]):
  private val lowered = terms.map(_.toLowerCase(java.util.Locale.ROOT))

  def in(text: String): Boolean =
    val low = text.toLowerCase(java.util.Locale.ROOT)
    lowered.exists(term => occursAlone(low, term))

  private def occursAlone(text: String, term: String): Boolean =
    Iterator.iterate(text.indexOf(term))(i => text.indexOf(term, i + 1)).takeWhile(_ >= 0).exists { i =>
      val end = i + term.length
      (i == 0 || !Text.isWord(text.codePointBefore(i))) && (end == text.length || !Text.isWord(text.codePointAt(end)))
    }

/** Python's `html.unescape` for the entities a feed uses: every numeric reference, the HTML 4 names
  * and `&apos;`. A name it does not know stays as it is.
  */
object Html:
  private val Reference = "&(#[0-9]+;?|#[xX][0-9a-fA-F]+;?|[^\\t\\n\\f <&#;]{1,32};?)".r

  def unescape(s: String): String =
    if !s.contains('&') then s
    else Reference.replaceAllIn(s, m => Regex.quoteReplacement(decode(m.group(1))))

  private def decode(ref: String): String =
    if ref.startsWith("#") then numeric(ref.drop(1).stripSuffix(";"))
    else
      val whole = if ref.endsWith(";") then named.get(ref.dropRight(1)) else latin1.get(ref)
      whole.getOrElse {
        // As Python: the longest leading name that may go without ';', then the rest as it is.
        (ref.length - 1 to 2 by -1).map(ref.take).find(latin1.contains) match
          case Some(name) => named(name) + ref.drop(name.length)
          case None       => "&" + ref
      }

  private def numeric(digits: String): String =
    val n =
      if digits.startsWith("x") || digits.startsWith("X") then BigInt(digits.drop(1), 16) else BigInt(digits)
    if n > 0x10ffff || (n >= 0xd800 && n <= 0xdfff) then "�"
    else
      val c = n.toInt
      invalidCharRefs.get(c).getOrElse {
        if invalidCodePoint(c) then "" else new String(Character.toChars(c))
      }

  private val invalidCharRefs: Map[Int, String] = Map(
    0x00 -> "�", 0x0d -> "\r", 0x80 -> "€", 0x81 -> "\u0081", 0x82 -> "‚",
    0x83 -> "ƒ", 0x84 -> "„", 0x85 -> "…", 0x86 -> "†", 0x87 -> "‡",
    0x88 -> "ˆ", 0x89 -> "‰", 0x8a -> "Š", 0x8b -> "‹", 0x8c -> "Œ",
    0x8d -> "\u008d", 0x8e -> "Ž", 0x8f -> "\u008f", 0x90 -> "\u0090", 0x91 -> "‘",
    0x92 -> "’", 0x93 -> "“", 0x94 -> "”", 0x95 -> "•", 0x96 -> "–",
    0x97 -> "—", 0x98 -> "˜", 0x99 -> "™", 0x9a -> "š", 0x9b -> "›",
    0x9c -> "œ", 0x9d -> "\u009d", 0x9e -> "ž", 0x9f -> "Ÿ",
  )

  private def invalidCodePoint(c: Int): Boolean =
    (c >= 0x1 && c <= 0x8) || c == 0xb || (c >= 0xe && c <= 0x1f) || (c >= 0x7f && c <= 0x9f) ||
      (c >= 0xfdd0 && c <= 0xfdef) || (c & 0xfffe) == 0xfffe

  /** The names that may go without ';': the ISO 8859-1 ones, from U+00A0 on, and five capitals. */
  private val latin1 = Vector(
    "nbsp", "iexcl", "cent", "pound", "curren", "yen", "brvbar", "sect", "uml", "copy", "ordf",
    "laquo", "not", "shy", "reg", "macr", "deg", "plusmn", "sup2", "sup3", "acute", "micro", "para",
    "middot", "cedil", "sup1", "ordm", "raquo", "frac14", "frac12", "frac34", "iquest", "Agrave",
    "Aacute", "Acirc", "Atilde", "Auml", "Aring", "AElig", "Ccedil", "Egrave", "Eacute", "Ecirc",
    "Euml", "Igrave", "Iacute", "Icirc", "Iuml", "ETH", "Ntilde", "Ograve", "Oacute", "Ocirc",
    "Otilde", "Ouml", "times", "Oslash", "Ugrave", "Uacute", "Ucirc", "Uuml", "Yacute", "THORN",
    "szlig", "agrave", "aacute", "acirc", "atilde", "auml", "aring", "aelig", "ccedil", "egrave",
    "eacute", "ecirc", "euml", "igrave", "iacute", "icirc", "iuml", "eth", "ntilde", "ograve",
    "oacute", "ocirc", "otilde", "ouml", "divide", "oslash", "ugrave", "uacute", "ucirc", "uuml",
    "yacute", "thorn", "yuml",
  ).zipWithIndex.map((name, i) => name -> (0xa0 + i).toChar.toString).toMap ++ Map(
    "amp" -> "&", "lt" -> "<", "gt" -> ">", "quot" -> "\"",
    "AMP" -> "&", "LT" -> "<", "GT" -> ">", "QUOT" -> "\"", "COPY" -> "©", "REG" -> "®",
  )


  /** Names that need ';'. */
  private val others: Map[String, String] = Map(
    "apos" -> "'", "OElig" -> "Œ", "oelig" -> "œ", "Scaron" -> "Š", "scaron" -> "š",
    "Yuml" -> "Ÿ", "fnof" -> "ƒ", "circ" -> "ˆ", "tilde" -> "˜", "ensp" -> " ",
    "emsp" -> " ", "thinsp" -> " ", "zwnj" -> "‌", "zwj" -> "‍", "lrm" -> "‎",
    "rlm" -> "‏", "ndash" -> "–", "mdash" -> "—", "lsquo" -> "‘", "rsquo" -> "’",
    "sbquo" -> "‚", "ldquo" -> "“", "rdquo" -> "”", "bdquo" -> "„",
    "dagger" -> "†", "Dagger" -> "‡", "bull" -> "•", "hellip" -> "…",
    "permil" -> "‰", "prime" -> "′", "Prime" -> "″", "lsaquo" -> "‹",
    "rsaquo" -> "›", "oline" -> "‾", "frasl" -> "⁄", "euro" -> "€",
    "trade" -> "™", "larr" -> "←", "uarr" -> "↑", "rarr" -> "→", "darr" -> "↓",
    "harr" -> "↔", "minus" -> "−", "infin" -> "∞", "asymp" -> "≈", "ne" -> "≠",
    "le" -> "≤", "ge" -> "≥", "loz" -> "◊", "hearts" -> "♥", "check" -> "✓",
  )

  private val named: Map[String, String] = latin1 ++ others
