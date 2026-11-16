package piabrota.metrics

import scala.collection.immutable.VectorMap

/** JSON as jq 1.7 reads and writes it, for the export and the preview. Two things ujson does not
  * do: a number keeps the text it was read with, so a host file's numbers come out as they went in
  * (jq keeps number literals), and `Infinity`, `-Infinity` and `NaN` are read (the hostile fixture
  * has them) and written as jq writes them: the largest double, and null.
  */
enum Json:
  case Null
  case Bool(value: Boolean)
  case Num(text: String, value: Double)
  case Str(value: String)
  case Arr(items: Vector[Json])
  case Obj(fields: VectorMap[String, Json])

  /** `.[key]` of an object; null for anything else, as jq gives it. */
  def apply(key: String): Json = this match
    case Obj(f) => f.getOrElse(key, Null)
    case _      => Null

  /** jq's `tostring`: a string as it is, anything else as JSON. */
  def tostring: String = this match
    case Str(s) => s
    case other  => Json.write(other)

object Json:
  /** A number that was computed, not read. */
  def num(n: Long): Num = Num(n.toString, n.toDouble)

  def num(d: Double): Num =
    if d == math.rint(d) && math.abs(d) < 1e17 then Num(d.toLong.toString, d) else Num(d.toString, d)

  def finite(j: Json): Boolean = j match
    case Num(_, v) => v.isFinite
    case _         => false

  def parse(text: String): Option[Json] =
    try
      val p = Parser(text)
      val value = p.value()
      p.blanks()
      Option.when(p.atEnd)(value)
    catch case _: (Parser.Bad | NumberFormatException) => None

  /** Compact, as `jq -c` and `tojson` write it. */
  def write(j: Json): String =
    val b = new StringBuilder
    writeTo(b, j)
    b.toString

  private def writeTo(b: StringBuilder, j: Json): Unit = j match
    case Null                         => b ++= "null"
    case Bool(v)                      => b ++= v.toString
    case Num(_, v) if v.isNaN         => b ++= "null"
    case Num(_, v) if v.isInfinite    => b ++= (if v > 0 then "" else "-") ++= "1.7976931348623157e+308"
    case Num(t, _)                    => b ++= t
    case Str(s)                       => quote(b, s)
    case Arr(items) =>
      b += '['
      items.zipWithIndex.foreach { (v, i) => if i > 0 then b += ','; writeTo(b, v) }
      b += ']'
    case Obj(fields) =>
      b += '{'
      fields.zipWithIndex.foreach { case ((k, v), i) =>
        if i > 0 then b += ','
        quote(b, k)
        b += ':'
        writeTo(b, v)
      }
      b += '}'

  /** jq's escapes: the quote, the backslash, and the control characters and DEL. */
  private def quote(b: StringBuilder, s: String): Unit =
    b += '"'
    s.foreach {
      case '"'                    => b ++= "\\\""
      case '\\'                   => b ++= "\\\\"
      case '\n'                   => b ++= "\\n"
      case '\t'                   => b ++= "\\t"
      case '\r'                   => b ++= "\\r"
      case '\b'                   => b ++= "\\b"
      case '\f'                   => b ++= "\\f"
      case c if c < ' ' || c == 127 => b ++= f"\\u${c.toInt}%04x"
      case c                      => b += c
    }
    b += '"'

  /** A recursive descent over the text; `Bad` is any error, and `parse` turns it into None. */
  private final class Parser(s: String):
    private var i = 0

    def atEnd: Boolean = i == s.length

    def blanks(): Unit = while i < s.length && " \t\n\r".contains(s(i)) do i += 1

    def value(): Json =
      blanks()
      if atEnd then throw Parser.Bad()
      s(i) match
        case '{' => obj()
        case '[' => arr()
        case '"' => Str(string())
        case _ if word("true")      => Bool(true)
        case _ if word("false")     => Bool(false)
        case _ if word("null")      => Null
        case _ if word("NaN") || word("nan") => Num("NaN", Double.NaN)
        case _ if word("Infinity")  => Num("Infinity", Double.PositiveInfinity)
        case _ if word("-Infinity") => Num("-Infinity", Double.NegativeInfinity)
        case _                      => number()

    private def word(w: String): Boolean =
      val ok = s.startsWith(w, i)
      if ok then i += w.length
      ok

    private def expect(c: Char): Unit =
      blanks()
      if atEnd || s(i) != c then throw Parser.Bad()
      i += 1

    private def obj(): Json =
      expect('{')
      blanks()
      if !atEnd && s(i) == '}' then { i += 1; Obj(VectorMap.empty) }
      else
        val fields = VectorMap.newBuilder[String, Json]
        var more = true
        while more do
          blanks()
          if atEnd || s(i) != '"' then throw Parser.Bad()
          val key = string()
          expect(':')
          fields += key -> value()
          blanks()
          if !atEnd && s(i) == ',' then i += 1 else { expect('}'); more = false }
        Obj(fields.result())

    private def arr(): Json =
      expect('[')
      blanks()
      if !atEnd && s(i) == ']' then { i += 1; Arr(Vector.empty) }
      else
        val items = Vector.newBuilder[Json]
        var more = true
        while more do
          items += value()
          blanks()
          if !atEnd && s(i) == ',' then i += 1 else { expect(']'); more = false }
        Arr(items.result())

    private def string(): String =
      i += 1
      val b = new StringBuilder
      while !atEnd && s(i) != '"' do
        if s(i) == '\\' then
          if i + 1 >= s.length then throw Parser.Bad()
          s(i + 1) match
            case '"'  => b += '"'
            case '\\' => b += '\\'
            case '/'  => b += '/'
            case 'b'  => b += '\b'
            case 'f'  => b += '\f'
            case 'n'  => b += '\n'
            case 'r'  => b += '\r'
            case 't'  => b += '\t'
            case 'u' if i + 6 <= s.length =>
              b += Integer.parseInt(s.substring(i + 2, i + 6), 16).toChar
              i += 4
            case _ => throw Parser.Bad()
          i += 2
        else if s(i) < ' ' then throw Parser.Bad()
        else
          b += s(i)
          i += 1
      if atEnd then throw Parser.Bad()
      i += 1
      b.toString

    private def number(): Json =
      val start = i
      while !atEnd && "+-.eE0123456789".contains(s(i)) do i += 1
      val t = s.substring(start, i)
      if !Parser.Number.matches(t) then throw Parser.Bad()
      Num(canonical(t), t.toDouble)

  /** A number literal as jq 1.7 writes it back: decNumber's to-scientific-string of its digits and
    * exponent. A plain literal stays as it is ("0.10", "1.000", "-0"); 1e2 becomes 1E+2 and 1e-7 1E-7.
    */
  private def canonical(literal: String): String =
    val body = literal.stripPrefix("-")
    val e = body.indexWhere(c => c == 'e' || c == 'E')
    val (mantissa, power) = if e < 0 then (body, Some(0)) else (body.take(e), body.drop(e + 1).toIntOption)
    power.fold(literal) { power =>
      val point = mantissa.indexOf('.')
      val exponent = power - (if point < 0 then 0 else mantissa.length - point - 1)
      val digits = mantissa.filter(_ != '.').dropWhile(_ == '0') match
        case "" => "0"
        case d  => d
      val adjusted = exponent + digits.length - 1
      val text =
        if exponent == 0 then digits
        else if exponent < 0 && adjusted >= -6 then
          val padded = "0" * math.max(0, -exponent + 1 - digits.length) + digits
          padded.dropRight(-exponent) + "." + padded.takeRight(-exponent)
        else
          val fraction = if digits.length > 1 then "." + digits.tail else ""
          s"${digits.head}${fraction}E${if adjusted >= 0 then "+" else "-"}${math.abs(adjusted)}"
      (if literal.startsWith("-") then "-" else "") + text
    }

  private object Parser:
    final class Bad extends Exception(null, null, false, false)
    val Number = "-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?".r
