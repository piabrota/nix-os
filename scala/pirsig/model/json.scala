package piabrota.pirsig

/** JSON from the model, yt-dlp and the work folders, read as the Python plugins read it. A value
  * that is no object has no keys.
  */
object Json:
  def read(text: String): Either[String, ujson.Value] =
    try Right(ujson.read(text, trace = false))
    catch case e: (ujson.ParseException | ujson.IncompleteParseException) => Left(e.getMessage)

  /** `d.get(key)`, null when it is missing. */
  def get(v: ujson.Value, key: String): ujson.Value = v.objOpt.flatMap(_.get(key)).getOrElse(ujson.Null)

  /** `d[key]`: a missing key is Python's KeyError. */
  def field(v: ujson.Value, key: String): ujson.Value =
    v.objOpt.flatMap(_.get(key)).getOrElse(throw BadData(Py.repr(key)))

  /** `str(d.get(key, ""))`, as the plugins read an argument. */
  def text(v: ujson.Value, key: String): String = Py.str(v.objOpt.flatMap(_.get(key)).getOrElse(ujson.Str("")))

  /** The value of `key` if it is a string. */
  def string(v: ujson.Value, key: String): Option[String] = v.objOpt.flatMap(_.get(key)).flatMap(_.strOpt)

  /** The items of `key` if it is a list. */
  def list(v: ujson.Value, key: String): List[ujson.Value] = get(v, key).arrOpt.map(_.toList).getOrElse(Nil)

  /** The keys of `key` if it is an object. */
  def keys(v: ujson.Value, key: String): List[String] = get(v, key).objOpt.map(_.keys.toList).getOrElse(Nil)

  def obj(v: ujson.Value): ujson.Obj = v.objOpt.map(ujson.Obj(_)).getOrElse(ujson.Obj())

  def number(v: ujson.Value): Double = v.numOpt.getOrElse(throw BadData(s"not a number: ${Py.str(v)}"))

  /** Python's `bool()` of a value. */
  def truthy(v: ujson.Value): Boolean = v match
    case ujson.Null    => false
    case ujson.Bool(b) => b
    case ujson.Num(n)  => n != 0
    case ujson.Str(s)  => s.nonEmpty
    case ujson.Arr(xs) => xs.nonEmpty
    case ujson.Obj(kv) => kv.nonEmpty

  def strings(xs: Seq[String]): ujson.Arr = ujson.Arr.from(xs.map(ujson.Str(_)))
