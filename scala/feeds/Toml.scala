package piabrota.feeds

import scala.collection.immutable.ListMap

/** A value of the TOML that feeds.toml uses. */
enum Toml:
  case Str(value: String)
  case Integer(value: Long)
  case Decimal(value: Double)
  case Bool(value: Boolean)
  case Arr(values: Vector[Toml])
  case Table(fields: ListMap[String, Toml])

/** Reads the part of TOML that feeds.toml uses, so the owner keeps editing a TOML file: comments,
  * `key = value` with a bare key, basic and literal strings, integers, decimals, booleans, arrays
  * (on one line or several), `[table]` and `[[array of tables]]` with a bare name. Anything else
  * (dotted or quoted keys, inline tables, multi-line strings, dates) is an error that names its
  * line, never a silent guess.
  */
object Toml:
  def parse(text: String, file: String): Either[String, Table] =
    try Right(assemble(Reader(text, file).sections(), file))
    catch case e: Problem => Left(e.getMessage)

  private final class Problem(message: String) extends Exception(message, null, false, false)

  private val Subset =
    "feed-build reads plain keys, strings, numbers, booleans, arrays, [table] and [[array of tables]]"

  /** One part of the file: the top (no header), a `[name]` or a `[[name]]`, with its keys. */
  private final case class Section(name: Option[String], many: Boolean, line: Int,
      fields: ListMap[String, Toml])

  private def assemble(sections: Vector[Section], file: String): Table =
    def fail(line: Int, message: String) = throw Problem(s"$file:$line: $message")
    val root = sections.foldLeft(ListMap.empty[String, Toml]) { (root, s) =>
      s.name match
        case None => root ++ s.fields
        case Some(name) if !s.many =>
          if root.contains(name) then fail(s.line, s"[$name] is defined twice")
          root.updated(name, Table(s.fields))
        case Some(name) =>
          root.get(name) match
            case None                                                 => root.updated(name, Arr(Vector(Table(s.fields))))
            case Some(Arr(tables)) if tables.forall(_.isInstanceOf[Table]) => root.updated(name, Arr(tables :+ Table(s.fields)))
            case Some(_)                                              => fail(s.line, s"[[$name]] is also a key or a [table]")
    }
    Table(root)

  /** A cursor over the text. It throws `Problem`, which `parse` turns into a `Left`. */
  private final class Reader(text: String, file: String):
    private var at = 0
    private var line = 1

    def sections(): Vector[Section] =
      val done = Vector.newBuilder[Section]
      var current = Section(None, many = false, line = 1, ListMap.empty)
      skipBlankLines()
      while !atEnd do
        if peek == '[' then
          done += current
          current = header()
        else
          val keyLine = line
          val (key, value) = keyValue()
          if current.fields.contains(key) then fail(s"key '$key' is set twice", keyLine)
          current = current.copy(fields = current.fields.updated(key, value))
        endOfLine()
        skipBlankLines()
      (done += current).result()

    private def header(): Section =
      val headerLine = line
      val many = text.startsWith("[[", at)
      at += (if many then 2 else 1)
      skipSpaces()
      val name = bareKey("table name")
      skipSpaces()
      val close = if many then "]]" else "]"
      if !text.startsWith(close, at) then fail(s"expected '$close' after the table name")
      at += close.length
      Section(Some(name), many, headerLine, ListMap.empty)

    private def keyValue(): (String, Toml) =
      val key = bareKey("key")
      skipSpaces()
      if peekOption.contains('.') then unsupported("a dotted key")
      expect('=')
      skipSpaces()
      key -> value()

    private def bareKey(what: String): String =
      val start = at
      while !atEnd && (peek.isLetterOrDigit && peek < 128 || peek == '_' || peek == '-') do at += 1
      if at == start then
        if peekOption.exists(c => c == '"' || c == '\'') then unsupported(s"a quoted $what")
        fail(s"expected a $what")
      text.substring(start, at)

    private def value(): Toml =
      peekOption match
        case None                                     => fail("expected a value")
        case Some('"') if text.startsWith("\"\"\"", at) => unsupported("a multi-line string")
        case Some('\'') if text.startsWith("'''", at)   => unsupported("a multi-line string")
        case Some('"')                                => Str(basicString())
        case Some('\'')                               => Str(literalString())
        case Some('[')                                => array()
        case Some('{')                                => unsupported("an inline table")
        case Some(_)                                  => scalar()

    private def array(): Arr =
      expect('[')
      val values = Vector.newBuilder[Toml]
      skipBlankLines()
      while peekOption.exists(_ != ']') do
        values += value()
        skipBlankLines()
        if peekOption.contains(',') then
          at += 1
          skipBlankLines()
        else if !peekOption.contains(']') then fail("expected ',' or ']' in an array")
      expect(']')
      Arr(values.result())

    private val IntegerText = "[+-]?(0|[1-9](_?[0-9])*)".r
    private val DecimalText = "[+-]?(0|[1-9](_?[0-9])*)(\\.[0-9](_?[0-9])*)?([eE][+-]?[0-9](_?[0-9])*)?".r

    private def scalar(): Toml =
      val start = at
      while !atEnd && !" \t\r\n,]#".contains(peek) do at += 1
      text.substring(start, at) match
        case "true"            => Bool(true)
        case "false"           => Bool(false)
        case t @ IntegerText(_, _) =>
          Integer(t.replace("_", "").toLongOption.getOrElse(fail(s"the integer $t is too large")))
        case t @ DecimalText(_*) => Decimal(t.replace("_", "").toDouble)
        case t =>
          at = start
          unsupported(s"the value '$t' (a date, a hex number, inf or nan, or a typo)")

    private def basicString(): String =
      expect('"')
      val out = StringBuilder()
      while peekOption.exists(_ != '"') do
        peek match
          case '\n' => fail("a string ends at the end of its line")
          case '\\' =>
            at += 1
            out ++= escape()
          case c =>
            out += c
            at += 1
      expect('"')
      out.result()

    private def escape(): String =
      val c = peekOption.getOrElse(fail("a string ends after '\\'"))
      at += 1
      c match
        case 'b'  => "\b"
        case 't'  => "\t"
        case 'n'  => "\n"
        case 'f'  => "\f"
        case 'r'  => "\r"
        case '"'  => "\""
        case '\\' => "\\"
        case 'u'  => codePoint(4)
        case 'U'  => codePoint(8)
        case _    => fail(s"unknown escape '\\$c' in a string")

    private def codePoint(digits: Int): String =
      val hex = text.slice(at, at + digits)
      if hex.length != digits || !hex.forall(c => Character.digit(c, 16) >= 0) then
        fail(s"expected $digits hex digits after the escape")
      at += digits
      new String(Character.toChars(java.lang.Integer.parseInt(hex, 16)))

    private def literalString(): String =
      expect('\'')
      val start = at
      while peekOption.exists(c => c != '\'' && c != '\n') do at += 1
      if !peekOption.contains('\'') then fail("a string ends at the end of its line")
      val value = text.substring(start, at)
      at += 1
      value

    /** After a value or a header: spaces, a comment, then the end of the line or of the file. */
    private def endOfLine(): Unit =
      skipSpaces()
      if peekOption.contains('#') then while !atEnd && peek != '\n' do at += 1
      if !atEnd then
        if peek == '\r' then at += 1
        if peekOption.contains('\n') then
          at += 1
          line += 1
        else fail(s"unexpected '$peek' after the value")

    /** Spaces, comments and newlines. */
    private def skipBlankLines(): Unit =
      var going = true
      while going && !atEnd do
        peek match
          case ' ' | '\t' | '\r' => at += 1
          case '\n' =>
            at += 1
            line += 1
          case '#' => while !atEnd && peek != '\n' do at += 1
          case _   => going = false

    private def skipSpaces(): Unit = while !atEnd && (peek == ' ' || peek == '\t') do at += 1

    private def expect(c: Char): Unit =
      if !peekOption.contains(c) then fail(s"expected '$c'")
      at += 1

    private def atEnd: Boolean = at >= text.length
    private def peek: Char = text.charAt(at)
    private def peekOption: Option[Char] = Option.when(!atEnd)(peek)

    private def fail(message: String, where: Int = line): Nothing = throw Problem(s"$file:$where: $message")
    private def unsupported(what: String): Nothing = fail(s"$what is not supported: $Subset")
