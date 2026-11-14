package piabrota.thesis

import scala.collection.mutable.ArrayBuffer

/** One field of a BibTeX or BibLaTeX entry. The row with the field "@entry" carries the entry's
  * line in `value`. Braces and quotes around a value are gone, white space is one space, and the
  * field name and the entry type are lower case.
  */
final case class BibRow(key: String, kind: String, field: String, value: String):
  def isEntry: Boolean = field == Bib.EntryField

object Bib:
  /** The field of the row that stands for the entry itself. */
  val EntryField = "@entry"

  /** The entries of refs.bib, one field a row; @comment, @string and @preamble are skipped. */
  def rows(text: String): Vector[BibRow] =
    val out = ArrayBuffer[BibRow]()
    val s = text
    val len = s.length
    var pos = 0
    def at(i: Int): Char = if i < len then s.charAt(i) else '\u0000'
    def isWs(c: Char) = c == ' ' || c == '\t' || c == '\r' || c == '\n'
    def skipWs(): Unit = while pos < len && isWs(s.charAt(pos)) do pos += 1
    // A balanced {...} or (...) at pos; returns the inside and leaves pos after the close.
    def balanced(): String =
      val op = s.charAt(pos)
      val cl = if op == '{' then '}' else ')'
      var depth = 0
      val start = pos + 1
      var result: Option[String] = None
      while result.isEmpty && pos < len do
        val c = s.charAt(pos)
        if c == '\\' then pos += 2
        else
          if c == op then depth += 1
          else if c == cl then
            depth -= 1
            if depth == 0 then { pos += 1; result = Some(s.substring(start, pos - 1)) }
          if result.isEmpty then pos += 1
      result.getOrElse(if start <= len then s.substring(start) else "")
    def value(): String =
      skipWs()
      at(pos) match
        case '{' => balanced()
        case '"' =>
          pos += 1
          val start = pos
          while pos < len && s.charAt(pos) != '"' do
            if s.charAt(pos) == '\\' then pos += 1
            pos += 1
          val v = s.substring(start, pos.min(len))
          pos += 1
          v
        case _ =>
          val start = pos
          while pos < len && !",} \t\r\n".contains(s.charAt(pos)) do pos += 1
          s.substring(start, pos)
    def lineOf(p: Int): Int = s.substring(0, (p + 1).min(len)).count(_ == '\n') + 1

    var done = false
    while !done && pos < len do
      val atSign = s.indexOf('@', pos)
      if atSign < 0 then done = true
      else
        pos = atSign + 1
        val after = pos
        while pos < len && s.charAt(pos).isLetter && s.charAt(pos) < 128 do pos += 1
        val kind = s.substring(after, pos).toLowerCase
        skipWs()
        if kind == "comment" || kind == "string" || kind == "preamble" then
          if at(pos) == '{' || at(pos) == '(' then balanced(): Unit
        else if at(pos) == '{' || at(pos) == '(' then
          pos += 1
          skipWs()
          val start = pos
          while pos < len && !",}) \t\r\n".contains(s.charAt(pos)) do pos += 1
          val key = s.substring(start, pos)
          out += BibRow(key, kind, EntryField, lineOf(after).toString)
          var fields = true
          while fields && pos < len do
            skipWs()
            at(pos) match
              case ',' => pos += 1
              case '}' | ')' => pos += 1; fields = false
              case _ =>
                val nameStart = pos
                while pos < len && !"= \t\r\n,}".contains(s.charAt(pos)) do pos += 1
                val name = s.substring(nameStart, pos).toLowerCase
                skipWs()
                if at(pos) != '=' then pos += 1
                else
                  pos += 1
                  val v = value().replaceAll("[ \t\r\n]+", " ").replaceAll("^ | $", "")
                  out += BibRow(key, kind, name, v)
    out.toVector

/** One row of the REFERENCES.md table: key, status (lower case), what it was checked against, note. */
final case class RefRow(key: String, status: String, checked: String, note: String):
  /** The row as the shell version's `IFS=tab read` split its TSV line again: an empty cell is
    * lost and the cells after it move left. The whole-work checks of cite-check read it so.
    */
  def asShellRead: RefRow =
    val Vector(k, s, c, n) = Text.ifsRead(s"$key\t$status\t$checked\t$note", 4): @unchecked
    RefRow(k, s, c, n)

object RefRow:
  def rows(text: String): Vector[RefRow] =
    Prose.lines(text).filter(_.matches("^ *\\|.*")).flatMap { line =>
      val f = line.split("\\|", -1).toVector.padTo(6, "")
      val k = f(1).replaceAll("^[ \t`]+|[ \t`]+$", "")
      val s = f(2).replaceAll("^[ \t*`]+|[ \t*`]+$", "")
      val c = f(3).replaceAll("^[ \t]+|[ \t]+$", "")
      val n = f(4).replaceAll("^[ \t]+|[ \t]+$", "")
      Option.when(k.nonEmpty && k.toLowerCase != "key" && !k.matches("^[-: ]+$"))(RefRow(k, s.toLowerCase, c, n))
    }

  /** The status of the first row of a key, "" when it has none. */
  def status(rows: Seq[RefRow], key: String): String = rows.find(_.key == key).map(_.status).getOrElse("")

/** A citation mark of a section and the line it is on. */
final case class Mark(line: Int, text: String)

/** An inline quotation and its length in words. */
final case class InlineQuote(line: Int, words: Int)

/** The citation facts of one section's raw markdown: the keys cited, the long inline quotations,
  * the marks typed by hand and the numbered citations. Code fences, code spans and math are skipped.
  */
final case class Cites(keys: Vector[Mark], quotes: Vector[InlineQuote], hand: Vector[Mark], numbered: Vector[Mark])

object Cites:
  private val Key = """(^|[^\p{L}\p{N}_@/.])@[A-Za-z0-9_][A-Za-z0-9_:.-]*[A-Za-z0-9_]""".r
  val Hand = """\([A-ZÀ-Ú][A-Za-zÀ-ú' -]+( et al\.)?,[ ]?[0-9]{4}[a-z]?\)""".r
  private val Num = """\[[0-9]+([,–-][ ]?[0-9]+)*\]""".r

  /** Keys (@key, [@key]; not @fig:x), inline quotations longer than maxQuote words, hand-typed
    * (Author, 2016) marks and numbered citations [3].
    */
  def apply(text: String, maxQuote: Int): Cites =
    val keys = ArrayBuffer[Mark]()
    val quotes = ArrayBuffer[InlineQuote]()
    val hand = ArrayBuffer[Mark]()
    val numbered = ArrayBuffer[Mark]()
    var fence = false
    var mathBlock = false
    var para = ""
    var paraLine = 0
    def flush(): Unit =
      if para.nonEmpty then
        var rest = para
        var more = true
        while more do
          """“[^”]+”""".r.findFirstMatchIn(rest).orElse(""""[^"]+"""".r.findFirstMatchIn(rest)) match
            case Some(m) =>
              val w = m.matched.split("[ \t]+").length
              if w > maxQuote then quotes += InlineQuote(paraLine, w)
              rest = rest.substring(m.end)
            case None => more = false
        para = ""

    Prose.lines(text).zipWithIndex.foreach { (raw, i) =>
      val ln = i + 1
      val line0 = raw.stripSuffix("\r")
      if line0.matches("^ {0,3}(```|~~~).*") then { flush(); fence = !fence }
      else if fence then ()
      else if line0.matches("""^ *\$\$ *""") then { flush(); mathBlock = !mathBlock }
      else if mathBlock then ()
      else if line0.matches("""^ *\$\$.*\$\$.*""") then ()
      else if line0.matches("^ *") then flush()
      else
        val line = line0.replaceAll("`[^`]*`", "").replaceAll("""\$[^$]*\$""", "")
        eachMatch(Key, line) { m =>
          val k = m.replaceFirst("^[^@]*@", "")
          if !k.matches("^(fig|tbl|eq|sec|cap):.*") then keys += Mark(ln, k)
        }
        eachMatch(Hand, line)(m => hand += Mark(ln, m))
        var rest = line
        var more = true
        while more do
          Num.findFirstMatchIn(rest) match
            case Some(m) =>
              val after = if m.end < rest.length then rest.charAt(m.end) else ' '
              if after != '(' && after != ':' then numbered += Mark(ln, m.matched)
              rest = rest.substring(m.end)
            case None => more = false
        if para.isEmpty then paraLine = ln
        para = if para.isEmpty then line else s"$para $line"
    }
    flush()
    Cites(keys.toVector, quotes.toVector, hand.toVector, numbered.toVector)

  /** awk's `while (match(rest, re)) { ...; rest = substr(rest, RSTART + RLENGTH) }`: a ^ in the
    * pattern matches again at the start of each rest.
    */
  private def eachMatch(re: scala.util.matching.Regex, line: String)(f: String => Unit): Unit =
    var rest = line
    var more = true
    while more do
      re.findFirstMatchIn(rest) match
        case Some(m) if m.end > 0 => f(m.matched); rest = rest.substring(m.end)
        case _                    => more = false
