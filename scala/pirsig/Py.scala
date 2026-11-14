package piabrota.pirsig

/** What the Python plugins did with text that Java does differently: Unicode whitespace and word
  * characters, `str()`, `repr()`, `json.dumps` and NFD without `java.text.Normalizer` (Scala Native
  * has none). The results go to the model and into files of the brain, so they must not change.
  */
object Py:
  /** Python's `str.isspace`: Java's `isWhitespace` misses the no-break spaces. */
  def isSpace(c: Char): Boolean =
    Character.isWhitespace(c) || Character.isSpaceChar(c) || c == '\u0085'

  /** A character of Python's `\w`: a letter, a digit or another number, or `_`. */
  def isWord(c: Char): Boolean =
    Character.isLetterOrDigit(c) || c == '_' || isOtherNumber(c)

  /** A character that `[\W\d_]` keeps: a word character that is not a digit or `_`. */
  def isLetterLike(c: Char): Boolean = Character.isLetter(c) || isOtherNumber(c)

  private def isOtherNumber(c: Char): Boolean =
    val t = Character.getType(c)
    t == Character.LETTER_NUMBER || t == Character.OTHER_NUMBER

  def strip(s: String): String =
    s.dropWhile(isSpace).reverse.dropWhile(isSpace).reverse

  /** `str.split()`: the words between runs of whitespace. */
  def split(s: String): List[String] =
    val words = List.newBuilder[String]
    val word = StringBuilder()
    s.foreach: c =>
      if isSpace(c) then
        if word.nonEmpty then words += word.result(); word.clear()
      else word += c
    if word.nonEmpty then words += word.result()
    words.result()

  /** `str.splitlines()`. */
  def splitlines(s: String): List[String] =
    if s.isEmpty then Nil
    else s.split("\r\n|[\n\r\u000b\u000c\u001c\u001d\u001e\u0085  ]", -1).toList match
      case lines if s.endsWith("\n") || s.endsWith("\r") => lines.init
      case lines                                          => lines

  /** The character class of Python's `\s`, for a regex. */
  val spaceClass = "[\\s \u0085  -     　\u001c-\u001f]"

  /** Lower case letters with a mark and their base letter: Latin-1 and Latin Extended-A, what NFD
    * splits for the owner's languages. A letter outside it stays whole.
    */
  private val marked = "àáâãäåçèéêëìíîïñòóôõöùúûüýÿāăąćĉċčďēĕėęěĝğġģĥĩīĭįĵķĺļľńņňōŏőŕŗřśŝşšţťũūŭůűųŵŷźżž"
  private val bases = "aaaaaaceeeeiiiinooooouuuuyyaaaccccdeeeeegggghiiiijklllnnnooorrrssssttuuuuuuwyzzz"

  /** `unicodedata.normalize("NFD", s)` for those letters; a mark becomes U+0301. Only the slugs
    * read it, and they keep [a-z0-9] alone, so which mark it is does not matter.
    */
  def nfd(s: String): String = s.flatMap: c =>
    marked.indexOf(c.toInt) match
      case -1 => c.toString
      case i  => s"${bases(i)}́"

  def isMark(c: Char): Boolean = Character.getType(c) == Character.NON_SPACING_MARK

  /** `str(value)` of a JSON value, as the plugins wrote `str(args.get(...))`. */
  def str(v: ujson.Value): String = v match
    case ujson.Str(s)   => s
    case ujson.Null     => "None"
    case ujson.Bool(b)  => if b then "True" else "False"
    case ujson.Num(n)   => number(n)
    case other          => dumps(other)

  /** `repr()` of a string, as `{name!r}` printed it. */
  def repr(s: String): String =
    val quote = if s.contains('\'') && !s.contains('"') then '"' else '\''
    val body = s.flatMap:
      case '\\'                   => "\\\\"
      case '\n'                   => "\\n"
      case '\r'                   => "\\r"
      case '\t'                   => "\\t"
      case c if c == quote        => s"\\$c"
      case c if !printable(c)     => if c < 0x100 then f"\\x${c.toInt}%02x" else f"\\u${c.toInt}%04x"
      case c                      => c.toString
    s"$quote$body$quote"

  private def printable(c: Char): Boolean =
    import Character.*
    c == ' ' || !Set(CONTROL, FORMAT, PRIVATE_USE, UNASSIGNED, LINE_SEPARATOR, PARAGRAPH_SEPARATOR,
      SPACE_SEPARATOR).contains(getType(c).toByte) && !Character.isSurrogate(c)

  /** `repr()` of a JSON value: a string quoted, anything else as `str()`. */
  def repr(v: ujson.Value): String = v match
    case ujson.Str(s) => repr(s)
    case other        => str(other)

  private def number(n: Double): String =
    if n.isWhole && math.abs(n) < 1e15 then n.toLong.toString else n.toString

  /** `json.dumps(v, ensure_ascii=False)`: `", "` and `": "` between items. */
  def dumps(v: ujson.Value): String = v match
    case ujson.Obj(kv) => kv.toSeq.map((k, x) => s"${quoted(k)}: ${dumps(x)}").mkString("{", ", ", "}")
    case ujson.Arr(xs) => xs.map(dumps).mkString("[", ", ", "]")
    case other         => scalar(other)

  /** `json.dumps(v, ensure_ascii=False, indent=2)`. */
  def dumpsIndented(v: ujson.Value, depth: Int = 0): String =
    val pad = "  " * (depth + 1)
    val end = "  " * depth
    v match
      case ujson.Obj(kv) if kv.nonEmpty =>
        kv.toSeq.map((k, x) => s"$pad${quoted(k)}: ${dumpsIndented(x, depth + 1)}").mkString("{\n", ",\n", s"\n$end}")
      case ujson.Arr(xs) if xs.nonEmpty =>
        xs.map(x => pad + dumpsIndented(x, depth + 1)).mkString("[\n", ",\n", s"\n$end]")
      case other => dumps(other)

  private def scalar(v: ujson.Value): String = v match
    case ujson.Str(s)  => quoted(s)
    case ujson.Num(n)  => number(n)
    case ujson.Bool(b) => b.toString
    case _             => "null"

  private def quoted(s: String): String =
    s.flatMap:
      case '"'          => "\\\""
      case '\\'         => "\\\\"
      case '\n'         => "\\n"
      case '\r'         => "\\r"
      case '\t'         => "\\t"
      case '\b'         => "\\b"
      case '\f'         => "\\f"
      case c if c < ' ' => f"\\u${c.toInt}%04x"
      case c            => c.toString
    .prepended('"').appended('"')
