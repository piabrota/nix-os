package piabrota.metrics

import java.io.{FileInputStream, IOException}
import java.nio.charset.StandardCharsets.ISO_8859_1

/** What the collector and the probe used to do in awk, done the same way, so that their files stay
  * byte for byte what metrics/index.html reads: a file as text, fields split on blanks, a string
  * read as a number, printf's numbers and the escaper of the JSON strings. Text is one char a byte
  * (ISO-8859-1), as awk sees it under LC_ALL=C.
  */
private[metrics] object Awk:
  /** The file without its last newline, or None when it is gone, unreadable or empty (awk's
    * getline loop: a process can end between the listing and the read). /proc reports a size of 0,
    * so the file is read to its end.
    */
  def read(path: String): Option[String] =
    try
      val in = FileInputStream(path)
      try
        val text = String(in.readAllBytes(), ISO_8859_1)
        Option.when(text.nonEmpty)(text.stripSuffix("\n"))
      finally in.close()
    catch case _: IOException => None

  /** A string from the environment as awk gets it: one char for each byte of its UTF-8. */
  def bytewise(s: String): String = String(s.getBytes(java.nio.charset.StandardCharsets.UTF_8), ISO_8859_1)

  def lines(text: Option[String]): Array[String] = text.fold(Array.empty[String])(_.split("\n", -1))

  /** `split(s, f, " ")`: the fields between runs of blanks. */
  def fields(s: String): Array[String] =
    val out = Array.newBuilder[String]
    var i = 0
    while i < s.length do
      while i < s.length && isBlank(s(i)) do i += 1
      val start = i
      while i < s.length && !isBlank(s(i)) do i += 1
      if i > start then out += s.substring(start, i)
    out.result()

  /** Field `n` of `f`, counted from 1 as awk does (`$n`, the kernel's docs); "" past the end. */
  def nth(f: Array[String], n: Int): String = if n >= 1 && n <= f.length then f(n - 1) else ""

  private def isBlank(c: Char): Boolean = c == ' ' || c == '\t' || c == '\n'

  private val Leading = """(?s)[ \t\n]*([+-]?(?:[0-9]+\.?[0-9]*|\.[0-9]+)(?:[eE][+-]?[0-9]+)?).*""".r

  /** `s + 0`: the number at the start of `s`, or 0. */
  def num(s: String): Double = s match
    case Leading(n) => n.toDouble
    case _          => 0

  def isDigits(s: String): Boolean = s.nonEmpty && s.forall(c => c >= '0' && c <= '9')

  /** printf's `%.<n>f`. C rounds the exact binary value half to even; Java's `%f` rounds half up. */
  def fixed(x: Double, decimals: Int): String =
    if !x.isFinite then "0"
    else
      val s = java.math.BigDecimal(math.abs(x)).setScale(decimals, java.math.RoundingMode.HALF_EVEN)
        .toPlainString
      if math.copySign(1.0, x) < 0 then "-" + s else s

  /** printf's `%d`: the value cut to a whole number. */
  def int(x: Double): String = x.toLong.toString

  /** awk's `print` of a number that is whole, and the exact value of one that is not. */
  def plain(x: Double): String =
    if x == math.rint(x) && math.abs(x) < 1e18 then x.toLong.toString
    else java.math.BigDecimal.valueOf(x).toPlainString

  /** Printable ASCII only (anything else becomes ?), then a backslash or a quote gets a backslash. */
  def esc(s: String): String =
    val out = StringBuilder(s.length)
    s.foreach { c =>
      if c < ' ' || c > '~' then out += '?'
      else
        if c == '\\' || c == '"' then out += '\\'
        out += c
    }
    out.toString
