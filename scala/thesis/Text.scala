package piabrota.thesis

import java.math.{BigDecimal, MathContext, RoundingMode}
import java.nio.charset.StandardCharsets.UTF_8

/** The number and text formats that the shell version got from awk, printf, fold, read and jq, so
  * that every message keeps its exact form.
  */
object Text:
  /** printf "%.<n>f": C rounds the exact binary value half to even; Java's format rounds half up. */
  def fixed(d: Double, n: Int): String =
    if d.isNaN || d.isInfinite then d.toString
    else new BigDecimal(d).setScale(n, RoundingMode.HALF_EVEN).toPlainString

  /** awk's print of a number (CONVFMT "%.6g"): 1.0 is "1", 0.06 is "0.06". */
  def g6(d: Double): String =
    if d.isWhole && math.abs(d) < 1e16 then d.toLong.toString
    else if d.isNaN || d.isInfinite then d.toString
    else new BigDecimal(d).round(new MathContext(6, RoundingMode.HALF_EVEN)).stripTrailingZeros.toPlainString

  /** jq's print of a number: integers without a fraction. */
  def jqNum(d: Double): String =
    if d.isWhole && math.abs(d) < 1e17 then d.toLong.toString else d.toString

  /** awk's string to number: the longest numeric prefix, else 0. */
  def awkNum(s: String): Double =
    val m = """^[ \t\n]*([+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?)""".r.findFirstMatchIn(s)
    m.flatMap(x => x.group(1).toDoubleOption).getOrElse(0.0)

  /** awk's `a > b` on two -v values: numbers if both look like numbers, else strings. */
  def awkGt(a: String, b: String): Boolean =
    (a.trim.toDoubleOption, b.trim.toDoubleOption) match
      case (Some(x), Some(y)) => x > y
      case _                  => a > b

  /** printf "%-<n>s" of bash: the width counts bytes, as bash and dash do. */
  def padBytes(s: String, n: Int): String =
    s + " " * (n - s.getBytes(UTF_8).length).max(0)

  /** awk's substr(s, 1, n): the first n characters (code points). */
  def take(s: String, n: Int): String =
    if s.codePointCount(0, s.length) <= n then s else s.substring(0, s.offsetByCodePoints(0, n))

  /** The upper case of jq's JQ_UPCASE in the shell version: a-z and the Latin-1 letters only. */
  def upcase(s: String): String =
    s.codePoints.toArray.map { c =>
      if (c >= 97 && c <= 122) || (c >= 224 && c <= 254 && c != 247) then c - 32 else c
    }.map(c => new String(Character.toChars(c))).mkString

  /** `read -r a b c` with IFS set to a tab: runs of tabs are one separator, leading and trailing
    * tabs go, and the last name gets the rest of the line.
    */
  def ifsRead(line: String, names: Int): Vector[String] =
    val trimmed = line.dropWhile(_ == '\t').reverse.dropWhile(_ == '\t').reverse
    val fields = Vector.newBuilder[String]
    var rest = trimmed
    var i = 1
    while i < names do
      val cut = rest.indexOf('\t')
      if cut < 0 then { fields += rest; rest = "" }
      else { fields += rest.substring(0, cut); rest = rest.substring(cut).dropWhile(_ == '\t') }
      i += 1
    fields += rest
    fields.result()

  /** `fold -s -w <width>` of GNU coreutils 9.11 in a UTF-8 locale: it counts characters and
    * breaks after the last blank.
    */
  def foldSpaces(text: String, width: Int): String =
    def adjust(col: Int, c: Int): Int = c match
      case 8  => (col - 1).max(0)
      case 13 => 0
      case 9  => col + 8 - col % 8
      case _  => col + 1
    val out = new java.lang.StringBuilder
    val line = scala.collection.mutable.ArrayBuffer[Int]()
    def emit(cs: Iterable[Int]): Unit = cs.foreach(out.appendCodePoint)
    var col = 0
    text.codePoints.toArray.foreach { c =>
      if c == '\n' then
        line += c; emit(line); line.clear(); col = 0
      else
        var placed = false
        while !placed do
          col = adjust(col, c)
          if col <= width then { line += c; placed = true }
          else
            val blank = line.lastIndexWhere(b => b == ' ' || b == '\t')
            if blank >= 0 then
              emit(line.take(blank + 1)); out.append('\n')
              line.remove(0, blank + 1)
              col = line.foldLeft(0)(adjust)
            else if line.isEmpty then { line += c; placed = true }
            else
              line += '\n'; emit(line); line.clear(); col = 0
    }
    emit(line)
    out.toString

  /** Lines of `grep -m <max> -A <after> <regex>`: the first matches with their trailing context,
    * "--" between groups that do not touch.
    */
  def grepContext(lines: IndexedSeq[String], re: scala.util.matching.Regex, max: Int, after: Int): List[String] =
    val hits = lines.indices.filter(i => re.findFirstIn(lines(i)).isDefined).take(max)
    val shown = hits.flatMap(i => i to (i + after).min(lines.length - 1)).distinct.sorted
    shown.zipWithIndex.flatMap { (i, k) =>
      if k > 0 && shown(k - 1) != i - 1 then List("--", lines(i)) else List(lines(i))
    }.toList

  /** Lines sorted as `sort` does in the C.UTF-8 locale: by code point. */
  def sortC(lines: scala.collection.Seq[String]): List[String] = lines.toList.sorted
