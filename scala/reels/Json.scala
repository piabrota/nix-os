package piabrota.reels

import scala.collection.immutable.VectorMap

/** A JSON value as jq 1.8 holds it. The rules of the toolkit were jq programs, and their output is
  * kept byte for byte, so the values here behave as jq's do: a number read from a file keeps its
  * text (`1.0` stays `1.0`, `1e2` prints as `1E+2`), and a number that is computed prints in its
  * shortest form (`0.30000000000000004`, `1e-05`). ujson keeps no number text, and it refuses what
  * jq reads (`01`, `.5`, `nan`, two values in one file), so the reader is here too.
  */
enum Jv:
  case Null
  case Bool(b: Boolean)
  /** `lit` is the canonical text of a number read from JSON; empty for a computed number. */
  case Num(d: Double, lit: String)
  case Str(s: String)
  case Arr(items: Vector[Jv])
  case Obj(fields: VectorMap[String, Jv])

object Jv:
  val True: Jv = Bool(true)
  val False: Jv = Bool(false)
  val EmptyArr: Jv = Arr(Vector.empty)
  val EmptyObj: Jv = Obj(VectorMap.empty)
  def num(d: Double): Jv = Num(d, "")
  def arr(items: Jv*): Jv = Arr(items.toVector)
  def obj(fields: (String, Jv)*): Jv = Obj(VectorMap.from(fields))

/** What a jq program raises: its message, as jq prints it after "jq: error (at ...): ". */
final case class JqError(msg: String) extends RuntimeException(msg)

/** One value of a JSON text, and the line that jq names in an error about it. */
final case class Doc(value: Jv, line: Int)

object Json:
  import Jv.{Null, Bool, Num, Str, Arr, Obj, True, False}

  // ---- reading ----------------------------------------------------------------------------------

  /** The values of a JSON text, in order, as `jq` reads a file: several values, each one complete.
    * None when jq would refuse the text (a parse error, bytes that are not UTF-8).
    */
  def parse(bytes: Array[Byte]): Option[Vector[Doc]] =
    val decoder = java.nio.charset.StandardCharsets.UTF_8.newDecoder()
      .onMalformedInput(java.nio.charset.CodingErrorAction.REPORT)
      .onUnmappableCharacter(java.nio.charset.CodingErrorAction.REPORT)
    val text =
      try Some(decoder.decode(java.nio.ByteBuffer.wrap(bytes)).toString)
      catch case _: java.nio.charset.CharacterCodingException => None
    text.flatMap(t => Parser(t, bytes).all())

  def parseText(text: String): Option[Vector[Doc]] = parse(text.getBytes("UTF-8"))

  /** The one value of a text; None when it holds none, several, or is not JSON. */
  def read(text: String): Option[Jv] = parseText(text).collect { case Vector(d) => d.value }

  def readDocs(file: os.Path): Option[Vector[Doc]] =
    try parse(os.read.bytes(file))
    catch case _: java.io.IOException => None

  def readFile(file: os.Path): Option[Jv] = readDocs(file).collect { case Vector(d) => d.value }

  /** `jq -e . file` succeeds: valid JSON, at least one value, and the last is not null or false. */
  def valid(file: os.Path): Boolean = readDocs(file).exists(ds => ds.nonEmpty && ds.last.value.truthy)

  /** The text of a number as jq writes a number it read: decNumber's canonical form. None when jq
    * refuses the token; the double for nan and infinity has no text.
    */
  def literal(token: String): Option[Num] =
    val sign = if token.startsWith("-") then "-" else ""
    val body = if token.startsWith("-") || token.startsWith("+") then token.drop(1) else token
    body.toLowerCase match
      case "nan"               => Some(Num(Double.NaN, ""))
      case "inf" | "infinity"  => Some(Num(if sign.isEmpty then Double.PositiveInfinity else Double.NegativeInfinity, ""))
      case _ =>
        NumberToken.findFirstMatchIn(body).filter(_.matched == body).map { m =>
          val (ip, fp) = (Option(m.group(1)).getOrElse(""), Option(m.group(2)).getOrElse(""))
          val (ip2, fp2) = if ip.isEmpty && fp.isEmpty then (Option(m.group(3)).getOrElse("").stripSuffix("."), "") else (ip, fp)
          val exp = Option(m.group(4)).map(e => BigInt(e.stripPrefix("+"))).getOrElse(BigInt(0))
          val digits = (ip2 + fp2).dropWhile(_ == '0') match
            case "" => "0"
            case d  => d
          Num((sign + body).toDouble, sign + canonical(digits, exp - fp2.length))
        }

  // [int].[frac] or int. or int, then an exponent: what decNumber reads after an optional sign.
  private val NumberToken = """^(?:(\d+)?\.(\d+)|(\d+\.?))(?:[eE]([+-]?\d+))?$""".r

  /** decNumber's to-scientific-string of a coefficient and an exponent. */
  private def canonical(coef: String, exp: BigInt): String =
    val adjusted = exp + coef.length - 1
    if exp <= 0 && adjusted >= -6 then
      val e = (-exp).toInt
      if e == 0 then coef
      else if coef.length > e then s"${coef.dropRight(e)}.${coef.takeRight(e)}"
      else s"0.${"0" * (e - coef.length)}$coef"
    else
      val mantissa = if coef.length > 1 then s"${coef.head}.${coef.tail}" else coef
      s"${mantissa}E${if adjusted >= 0 then "+" else "-"}${adjusted.abs}"

  /** A reader that follows jq's: a value is any JSON value, or a bare token that jq takes as a
    * number; the line of a value is the count of whole lines that jq had read when it was complete
    * (jq reads a file with fgets, 4095 bytes at most at a time).
    */
  private final class Parser(t: String, bytes: Array[Byte]):
    private var i = 0
    private final class Fail extends RuntimeException

    def all(): Option[Vector[Doc]] =
      try
        val out = Vector.newBuilder[Doc]
        skip()
        while i < t.length do
          val (v, end) = value()
          out += Doc(v, lineAt(end))
          skip()
        Some(out.result())
      catch case _: Fail => None

    private def fail(): Nothing = throw Fail()
    private def skip(): Unit = while i < t.length && " \t\n\r".contains(t(i)) do i += 1
    private def isDelim(c: Char) = " \t\n\r[{]},:\"".contains(c)

    /** The value at i, and the char index where jq knows that it is complete. */
    private def value(): (Jv, Int) =
      if i >= t.length then fail()
      t(i) match
        case '{' =>
          i += 1
          var fields = VectorMap.empty[String, Jv]
          skip()
          if i < t.length && t(i) == '}' then i += 1
          else
            var more = true
            while more do
              skip()
              if i >= t.length || t(i) != '"' then fail()
              val k = string()
              skip()
              if i >= t.length || t(i) != ':' then fail()
              i += 1
              skip()
              fields = fields.updated(k, value()._1)
              skip()
              if i < t.length && t(i) == ',' then i += 1
              else if i < t.length && t(i) == '}' then { i += 1; more = false }
              else fail()
          (Obj(fields), i - 1)
        case '[' =>
          i += 1
          val items = Vector.newBuilder[Jv]
          skip()
          if i < t.length && t(i) == ']' then i += 1
          else
            var more = true
            while more do
              skip()
              items += value()._1
              skip()
              if i < t.length && t(i) == ',' then i += 1
              else if i < t.length && t(i) == ']' then { i += 1; more = false }
              else fail()
          (Arr(items.result()), i - 1)
        case '"' =>
          val s = string()
          (Str(s), i - 1)
        case c if isDelim(c) => fail()
        case _ =>
          val start = i
          while i < t.length && !isDelim(t(i)) do i += 1
          val v = t.substring(start, i) match
            case "true"  => True
            case "false" => False
            case "null"  => Null
            case tok     => literal(tok).getOrElse(fail())
          (v, i)

    private def string(): String =
      i += 1
      val b = StringBuilder()
      var done = false
      while !done do
        if i >= t.length then fail()
        val c = t(i)
        i += 1
        if c == '"' then done = true
        else if c < ' ' then fail()
        else if c != '\\' then b += c
        else
          if i >= t.length then fail()
          val e = t(i)
          i += 1
          e match
            case '"' | '\\' | '/' => b += e
            case 'b' => b += '\b'
            case 'f' => b += '\f'
            case 'n' => b += '\n'
            case 'r' => b += '\r'
            case 't' => b += '\t'
            case 'u' =>
              val u = hex4()
              if u >= 0xd800 && u < 0xdc00 then
                if i + 1 < t.length && t(i) == '\\' && t(i + 1) == 'u' then
                  i += 2
                  val lo = hex4()
                  if lo < 0xdc00 || lo > 0xdfff then fail()
                  b ++= String(Character.toChars(0x10000 + ((u - 0xd800) << 10) + (lo - 0xdc00)))
                else fail()
              else if u >= 0xdc00 && u <= 0xdfff then b += '�'
              else b += u.toChar
            case _ => fail()
      b.result()

    private def hex4(): Int =
      if i + 4 > t.length then fail()
      val h = t.substring(i, i + 4)
      if !h.forall(c => Character.digit(c, 16) >= 0) then fail()
      i += 4
      Integer.parseInt(h, 16)

    /** jq's line for a value that it knows is complete at char `end`. */
    private def lineAt(end: Int): Int =
      val at = t.substring(0, math.min(end, t.length)).getBytes("UTF-8").length
      val lineStart = bytes.lastIndexOf('\n'.toByte, at - 1) + 1
      val before = bytes.take(lineStart).count(_ == '\n')
      val nl = bytes.indexOf('\n'.toByte, at)
      // fgets gives the line in pieces of 4095 bytes; the piece with the line break counts the line.
      if nl >= 0 && (nl - lineStart) / 4095 == (at - lineStart) / 4095 then before + 1 else before
  end Parser

  // ---- writing ----------------------------------------------------------------------------------

  /** A computed number as jq prints it: the shortest digits that read back as the same double, in
    * C's %.17g layout (an exponent below 1e-4 and from 1e17 on, or for a few digits from 1e16).
    */
  def jqDouble(d: Double): String =
    if d.isNaN then "null"
    else if d.isInfinite then (if d > 0 then "1.7976931348623157e+308" else "-1.7976931348623157e+308")
    else if d == 0 then "0"
    else
      // The fewest digits that read back as d; Double.toString is not always the shortest (4.9E-324).
      val exact = java.math.BigDecimal(math.abs(d))
      val bd = (1 to 17).iterator
        .map(p => exact.round(java.math.MathContext(p)))
        .find(_.doubleValue == math.abs(d))
        .getOrElse(exact)
        .stripTrailingZeros
      val digits = bd.unscaledValue.toString
      val decpt = digits.length - bd.scale
      val sign = if d < 0 then "-" else ""
      val body =
        if decpt <= -4 || decpt > digits.length + 15 then
          val e = decpt - 1
          val m = if digits.length > 1 then s"${digits.head}.${digits.tail}" else digits
          f"${m}e${if e < 0 then "-" else "+"}${math.abs(e)}%02d"
        else if decpt <= 0 then s"0.${"0" * -decpt}$digits"
        else if decpt >= digits.length then digits + "0" * (decpt - digits.length)
        else s"${digits.take(decpt)}.${digits.drop(decpt)}"
      sign + body

  /** A number as the toolkit writes it into ffmpeg arguments and render.json: a whole number with no
    * point, any other in plain decimals.
    */
  def num(d: Double): String =
    if d.isWhole && math.abs(d) < 1e17 then d.toLong.toString
    else java.math.BigDecimal(d.toString).stripTrailingZeros.toPlainString

  /** A number with `num`'s text, so that it prints as `num` writes it. */
  def plainNum(d: Double): Jv = Num(d, num(d))

  def numText(n: Num): String = if n.lit.nonEmpty then n.lit else jqDouble(n.d)

  /** What the toolkit's own code reads of a value: a string as it is, a number as `num` writes it,
    * anything else as compact JSON with such numbers.
    */
  def plain(v: Jv): String = v match
    case Str(s) => s
    case _      => compact(v, n => num(n.d))

  /** The value as `jq -c` writes it. */
  def compact(v: Jv, number: Num => String = numText): String =
    val b = StringBuilder()
    def go(v: Jv): Unit = v match
      case Null    => b ++= "null"
      case Bool(x) => b ++= x.toString
      case n: Num  => b ++= number(n)
      case Str(s)  => quote(s, b)
      case Arr(xs) =>
        b += '['
        xs.zipWithIndex.foreach { (x, k) => if k > 0 then b += ','; go(x) }
        b += ']'
      case Obj(fs) =>
        b += '{'
        fs.zipWithIndex.foreach { case ((k, x), j) => if j > 0 then b += ','; quote(k, b); b += ':'; go(x) }
        b += '}'
    go(v)
    b.result()

  /** The value as `jq` writes it by default: two spaces a level. */
  def pretty(v: Jv): String =
    val b = StringBuilder()
    def pad(n: Int) = b ++= "  " * n
    def go(v: Jv, level: Int): Unit = v match
      case Arr(xs) if xs.nonEmpty =>
        b ++= "[\n"
        xs.zipWithIndex.foreach { (x, k) =>
          if k > 0 then b ++= ",\n"
          pad(level + 1); go(x, level + 1)
        }
        b += '\n'; pad(level); b += ']'
      case Obj(fs) if fs.nonEmpty =>
        b ++= "{\n"
        fs.zipWithIndex.foreach { case ((k, x), j) =>
          if j > 0 then b ++= ",\n"
          pad(level + 1); quote(k, b); b ++= ": "; go(x, level + 1)
        }
        b += '\n'; pad(level); b += '}'
      case other => b ++= compact(other)
    go(v, 0)
    b.result()

  private def quote(s: String, b: StringBuilder): Unit =
    b += '"'
    s.foreach {
      case '"'  => b ++= "\\\""
      case '\\' => b ++= "\\\\"
      case '\n' => b ++= "\\n"
      case '\t' => b ++= "\\t"
      case '\r' => b ++= "\\r"
      case '\b' => b ++= "\\b"
      case '\f' => b ++= "\\f"
      case c if c < ' ' || c == '\u007f' => b ++= f"\\u${c.toInt}%04x"
      case c    => b += c
    }
    b += '"'

  /** A value in a jq error message: its JSON, cut to 25 bytes and "..." past 29 (`..."` for a string). */
  def brief(v: Jv): String =
    val full = compact(v)
    val bytes = full.getBytes("UTF-8")
    if bytes.length <= 29 then full
    else
      // Back to the start of a character, as jq does.
      var n = 25
      while n > 0 && (bytes(n) & 0xc0) == 0x80 do n -= 1
      // jq closes what it cut: "...\"", "...]" or "...}".
      val close = v match
        case _: Str => "\""
        case _: Jv.Arr => "]"
        case _: Jv.Obj => "}"
        case _ => ""
      new String(bytes.take(n), "UTF-8") + "..." + close

  // ---- jq's operations --------------------------------------------------------------------------

  /** `a // b`: b when a is null or false. An error of a is not caught: jq 1.8 lets it through. */
  def alt(a: Jv, b: => Jv): Jv = if a.truthy then a else b

  /** jq evaluates the right side of an operator first; these keep that order, which decides the
    * message when both sides fail.
    */
  def add(a: => Jv, b: => Jv): Jv = { val y = b; a + y }
  def sub(a: => Jv, b: => Jv): Jv = { val y = b; a - y }
  def mul(a: => Jv, b: => Jv): Jv = { val y = b; a * y }
  def div(a: => Jv, b: => Jv): Jv = { val y = b; a / y }

  /** jq's order of values: null, false, true, numbers, strings, arrays, objects. */
  def compare(a: Jv, b: Jv): Int = (a, b) match
    case (Num(x, _), Num(y, _)) =>
      if x.isNaN || y.isNaN then (if x.isNaN && y.isNaN then 0 else if x.isNaN then -1 else 1)
      else java.lang.Double.compare(x + 0.0, y + 0.0)
    case (Str(x), Str(y)) => compareCodepoints(x, y)
    case (Arr(xs), Arr(ys)) =>
      xs.lazyZip(ys).map(compare).find(_ != 0).getOrElse(xs.length.compare(ys.length))
    case (Obj(xs), Obj(ys)) =>
      val (kx, ky) = (xs.keys.toVector.sortWith(compareCodepoints(_, _) < 0), ys.keys.toVector.sortWith(compareCodepoints(_, _) < 0))
      val keys = compare(Arr(kx.map(Str(_))), Arr(ky.map(Str(_))))
      if keys != 0 then keys else kx.map(k => compare(xs(k), ys(k))).find(_ != 0).getOrElse(0)
    case (Bool(x), Bool(y)) => x.compare(y)
    case _ => rank(a).compare(rank(b))

  private def rank(v: Jv): Int = v match
    case Null           => 0
    case Bool(false)    => 1
    case Bool(true)     => 2
    case _: Num         => 3
    case _: Str         => 4
    case _: Arr         => 5
    case _: Obj         => 6

  private def compareCodepoints(x: String, y: String): Int =
    val (a, b) = (x.codePoints.toArray, y.codePoints.toArray)
    a.lazyZip(b).map(_.compare(_)).find(_ != 0).getOrElse(a.length.compare(b.length))

  /** jq's `min` (the first of the least) and `max` (the last of the greatest); null when empty. */
  def min(vs: Seq[Jv]): Jv = vs.reduceLeftOption((m, v) => if compare(v, m) < 0 then v else m).getOrElse(Null)
  def max(vs: Seq[Jv]): Jv = vs.reduceLeftOption((m, v) => if compare(v, m) >= 0 then v else m).getOrElse(Null)
  def sort(vs: Seq[Jv]): Vector[Jv] = vs.toVector.sortWith(compare(_, _) < 0)

  /** Unicode White_Space, what `\s` matches in jq's Oniguruma. */
  def isSpace(c: Int): Boolean =
    (c >= 0x09 && c <= 0x0d) || c == 0x20 || c == 0x85 || c == 0xa0 || c == 0x1680 ||
      (c >= 0x2000 && c <= 0x200a) || c == 0x2028 || c == 0x2029 || c == 0x202f || c == 0x205f || c == 0x3000

  /** jq's `split(sep)` of a string: every empty piece kept, but nothing for an empty string. */
  def split(s: String, sep: String): Vector[String] =
    if s.isEmpty then Vector.empty else s.split(java.util.regex.Pattern.quote(sep), -1).toVector

  def codepoints(s: String): Vector[Int] = s.codePoints.toArray.toVector
  def fromCodepoints(cs: Seq[Int]): String = String(cs.toArray, 0, cs.length)

  /** jq's `round` (C's): half away from zero. A double from 2^52 on is whole already. */
  def round(d: Double): Double =
    if d.isNaN || math.abs(d) >= 4.5e15 then d
    else if d < 0 then -math.round(-d).toDouble
    else math.round(d).toDouble

  extension (v: Jv)
    def truthy: Boolean = v != Null && v != False

    def typeName: String = v match
      case Null    => "null"
      case _: Bool => "boolean"
      case _: Num  => "number"
      case _: Str  => "string"
      case _: Arr  => "array"
      case _: Obj  => "object"

    /** `<type> (<value>)`, how a jq error names a value. */
    def named: String = s"$typeName (${brief(v)})"

    /** jq's `.key`. */
    def apply(key: String): Jv = v match
      case Obj(fs) => fs.getOrElse(key, Null)
      case Null    => Null
      case _       => throw JqError(s"Cannot index $typeName with string (${brief(Str(key))})")

    /** jq's `.[i]`: the floor of i, from the end when negative. */
    def apply(i: Double): Jv = v match
      case Arr(xs) =>
        val k = math.floor(i).toInt
        val j = if k < 0 then xs.length + k else k
        if j >= 0 && j < xs.length then xs(j) else Null
      case Null => Null
      case _    => throw JqError(s"Cannot index $typeName with number (${jqDouble(i)})")

    /** jq's `.[key]` for a key of any type. */
    def index(key: Jv): Jv = key match
      case Str(k)    => v(k)
      case Num(d, _) => v(d)
      case _ =>
        v match
          case Null => Null
          case _    => throw JqError(s"Cannot index $typeName with ${key.typeName}")

    /** A field, or null for anything that is not an object: for reading the toolkit's own files. */
    def at(key: String): Jv = v match
      case Obj(fs) => fs.getOrElse(key, Null)
      case _       => Null

    def at(i: Int): Jv = v match
      case Arr(xs) if i >= 0 && i < xs.length => xs(i)
      case _                                   => Null

    /** The value, or `default` for null and false. */
    def or(default: Jv): Jv = if v.truthy then v else default

    /** The elements of an array, nothing for anything else. */
    def items: Vector[Jv] = v match
      case Arr(xs) => xs
      case _       => Vector.empty

    /** jq's `.[]`. */
    def iter: Vector[Jv] = v match
      case Arr(xs) => xs
      case Obj(fs) => fs.values.toVector
      case _       => throw JqError(s"Cannot iterate over $named")

    /** jq's `.[]?`. */
    def iterOpt: Vector[Jv] = v match
      case Arr(xs) => xs
      case Obj(fs) => fs.values.toVector
      case _       => Vector.empty

    /** jq's `keys_unsorted`. */
    def keysUnsorted: Vector[Jv] = v match
      case Obj(fs) => fs.keys.toVector.map(Str(_))
      case Arr(xs) => xs.indices.toVector.map(k => Jv.num(k.toDouble))
      case _       => throw JqError(s"$named has no keys")

    /** jq's `to_entries`: (key, value) pairs. */
    def entries: Vector[(Jv, Jv)] = v match
      case Obj(fs) => fs.toVector.map((k, x) => (Str(k), x))
      case Arr(xs) => xs.zipWithIndex.map((x, k) => (Jv.num(k.toDouble), x))
      case _       => throw JqError(s"$named has no keys")

    /** jq's `has(key)` for a string key. */
    def has(key: String): Boolean = v match
      case Obj(fs) => fs.contains(key)
      case _       => throw JqError(s"Cannot check whether $typeName has a string key")

    def length: Jv = v match
      case Null      => Jv.num(0)
      case _: Bool   => throw JqError(s"$named has no length")
      case Num(d, _) => Jv.num(math.abs(d))
      case Str(s)    => Jv.num(s.codePointCount(0, s.length).toDouble)
      case Arr(xs)   => Jv.num(xs.length.toDouble)
      case Obj(fs)   => Jv.num(fs.size.toDouble)

    /** The length when it is a count, as an Int. */
    def size: Int = length.number.toInt

    /** The double of a number; jq's "number required" for anything else. */
    def number: Double = v match
      case Num(d, _) => d
      case _         => throw JqError(s"$named number required")

    def isNum: Boolean = v.isInstanceOf[Num]
    def isStr: Boolean = v.isInstanceOf[Str]

    /** The string, or jq's error for a regular expression on anything else. */
    def matchable: String = v match
      case Str(s) => s
      case _      => throw JqError(s"$named cannot be matched, as it is not a string")

    /** jq's `tostring`, and what `"\(.)"` and `jq -r` print. */
    def show: String = v match
      case Str(s) => s
      case _      => compact(v)

    def +(o: Jv): Jv = (v, o) match
      case (Null, _)                => o
      case (_, Null)                => v
      case (Num(x, _), Num(y, _))   => Jv.num(x + y)
      case (Str(x), Str(y))         => Str(x + y)
      case (Arr(xs), Arr(ys))       => Arr(xs ++ ys)
      case (Obj(xs), Obj(ys))       => Obj(ys.foldLeft(xs)((m, kv) => m.updated(kv._1, kv._2)))
      case _                        => throw JqError(s"${v.named} and ${o.named} cannot be added")

    def -(o: Jv): Jv = (v, o) match
      case (Num(x, _), Num(y, _)) => Jv.num(x - y)
      case (Arr(xs), Arr(ys))     => Arr(xs.filterNot(x => ys.exists(compare(x, _) == 0)))
      case _                      => throw JqError(s"${v.named} and ${o.named} cannot be subtracted")

    def *(o: Jv): Jv = (v, o) match
      case (Num(x, _), Num(y, _))         => Jv.num(x * y)
      case (Str(s), Num(n, _))            => repeat(s, n)
      case (Num(n, _), Str(s))            => repeat(s, n)
      case (Obj(_), Obj(_))               => deepMerge(v, o)
      case _                              => throw JqError(s"${v.named} and ${o.named} cannot be multiplied")

    def /(o: Jv): Jv = (v, o) match
      case (Num(_, _), Num(0, _))  => throw JqError(s"${v.named} and ${o.named} cannot be divided because the divisor is zero")
      case (Num(x, _), Num(y, _))  => Jv.num(x / y)
      case (Str(x), Str(y))        => Arr(split(x, y).map(Str(_)))
      case _                       => throw JqError(s"${v.named} and ${o.named} cannot be divided")

    def unary_- : Jv = v match
      case Num(d, lit) =>
        Num(-d, if lit.isEmpty then "" else if d == 0 then lit.stripPrefix("-") else if lit.startsWith("-") then lit.drop(1) else "-" + lit)
      case _ => throw JqError(s"$named cannot be negated")

    def ===(o: Jv): Boolean = compare(v, o) == 0
    def <(o: Jv): Boolean = compare(v, o) < 0
    def >(o: Jv): Boolean = compare(v, o) > 0
    def <=(o: Jv): Boolean = compare(v, o) <= 0
    def >=(o: Jv): Boolean = compare(v, o) >= 0

    /** jq's `index($x)` of an array: the first place of x, or of the run x when x is an array. */
    def indexOf(x: Jv): Jv = (v, x) match
      case (Arr(xs), Arr(ys)) =>
        if ys.isEmpty then Null
        else xs.indices.find(i => i + ys.length <= xs.length && ys.indices.forall(j => compare(xs(i + j), ys(j)) == 0))
          .fold(Null)(i => Jv.num(i.toDouble))
      case (Arr(xs), _) => xs.indexWhere(compare(_, x) == 0) match
          case -1 => Null
          case i  => Jv.num(i.toDouble)
      case _ => Null

    /** jq's `.[from:to]` of an array or a string: the floor of from, the ceiling of to. */
    def slice(from: Option[Double], to: Option[Double]): Jv =
      def bounds(n: Int): (Int, Int) =
        def clip(i: Double) = (if i < 0 then n + i else i).max(0).min(n)
        val a = clip(math.floor(from.getOrElse(0.0)))
        val b = clip(math.ceil(to.getOrElse(n.toDouble)))
        (a.toInt, b.toInt.max(a.toInt))
      v match
        case Arr(xs) =>
          val (a, b) = bounds(xs.length)
          Arr(xs.slice(a, b))
        case Str(s) =>
          val cs = codepoints(s)
          val (a, b) = bounds(cs.length)
          Str(fromCodepoints(cs.slice(a, b)))
        case Null => Null
        case _    => throw JqError(s"Cannot index $typeName with object")

  private def repeat(s: String, n: Double): Jv =
    if n < 0 || n.isNaN then Null else Str(s * n.toInt)

  private def deepMerge(a: Jv, b: Jv): Jv = (a, b) match
    case (Obj(xs), Obj(ys)) =>
      Obj(ys.foldLeft(xs) { case (m, (k, y)) =>
        m.updated(k, (m.get(k), y) match
          case (Some(x: Obj), y: Obj) => deepMerge(x, y)
          case _                      => y)
      })
    case _ => b

  /** jq's `tonumber`: a number as it is, a string read as a JSON number (keeping its text). */
  def tonumber(v: Jv): Jv = v match
    case n: Num => n
    case Str(s) => literal(s).getOrElse(throw JqError(s"${v.named} cannot be parsed as a number"))
    case _      => throw JqError(s"${v.named} cannot be parsed as a number")

  /** jq's `join(sep)`: null as nothing, numbers and booleans as JSON, strings as they are. */
  def join(vs: Seq[Jv], sep: String): String =
    vs.zipWithIndex.foldLeft(Null: Jv) { case (acc, (x, k)) =>
      val glue: Jv = if k == 0 then Str("") else acc + Str(sep)
      glue + (x match
        case Null              => Str("")
        case _: Num | _: Bool  => Str(compact(x))
        case _                 => x)
    } match
      case Null => ""
      case r    => r.show

  /** jq's `ascii_upcase`. */
  def upcase(v: Jv): String = v match
    case Str(s) => s.map(c => if c >= 'a' && c <= 'z' then (c - 32).toChar else c)
    case _      => throw JqError("explode input must be a string")

  /** jq's `@tsv` of one row. */
  def tsv(row: Seq[Jv]): String = row.map {
    case Str(s)  => s.flatMap {
        case '\\' => "\\\\"
        case '\t' => "\\t"
        case '\n' => "\\n"
        case '\r' => "\\r"
        case c    => c.toString
      }
    case Null => ""
    case x @ (_: Num | _: Bool) => compact(x)
    case x => throw JqError(s"${x.named} is not valid in a csv row")
  }.mkString("\t")
