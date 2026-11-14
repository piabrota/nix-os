package piabrota.reels

/** JSON values read the way jq reads them: `.key` of anything that is not an object is null, `//`
  * takes the right side for null and false, and `jq -r` prints a number in its shortest form.
  */
object Json:
  def read(text: String): Option[ujson.Value] =
    try Some(ujson.read(text))
    catch case _: Exception => None

  def readFile(file: os.Path): Option[ujson.Value] =
    try read(os.read(file))
    catch case _: java.io.IOException => None

  extension (v: ujson.Value)
    /** jq's `.key`. */
    def at(key: String): ujson.Value = v match
      case o: ujson.Obj => o.value.getOrElse(key, ujson.Null)
      case _            => ujson.Null

    /** jq's `.[i]`. */
    def at(i: Int): ujson.Value = v match
      case a: ujson.Arr if i >= 0 && i < a.value.length => a.value(i)
      case _                                             => ujson.Null

    /** jq's `a // b`. */
    def or(default: ujson.Value): ujson.Value = if truthy then v else default

    def truthy: Boolean = v != ujson.Null && v != ujson.False

    /** The elements of an array, nothing for anything else. */
    def items: Seq[ujson.Value] = v match
      case a: ujson.Arr => a.value.toSeq
      case _            => Nil

    /** What `jq -r` prints, and what `"\(.)"` puts in a string. */
    def text: String = v match
      case ujson.Str(s) => s
      case _            => compact(v)

  /** A number as jq prints it: a whole number without a point, any other in its shortest form. */
  def num(d: Double): String =
    if d.isWhole && math.abs(d) < 1e17 then d.toLong.toString
    else java.math.BigDecimal(d.toString).stripTrailingZeros.toPlainString

  /** The value as `jq -c` writes it. */
  def compact(v: ujson.Value): String = v match
    case ujson.Str(s)  => quote(s)
    case ujson.Num(d)  => num(d)
    case ujson.Bool(b) => b.toString
    case ujson.Null    => "null"
    case a: ujson.Arr  => a.value.iterator.map(compact).mkString("[", ",", "]")
    case o: ujson.Obj  => o.value.iterator.map((k, x) => s"${quote(k)}:${compact(x)}").mkString("{", ",", "}")

  private def quote(s: String): String =
    val b = StringBuilder("\"")
    s.foreach {
      case '"'              => b ++= "\\\""
      case '\\'             => b ++= "\\\\"
      case '\n'             => b ++= "\\n"
      case '\t'             => b ++= "\\t"
      case '\r'             => b ++= "\\r"
      case '\b'             => b ++= "\\b"
      case '\f'             => b ++= "\\f"
      case c if c < ' ' || c == '\u007f' => b ++= f"\\u${c.toInt}%04x"
      case c                => b += c
    }
    b += '"'
    b.result()
