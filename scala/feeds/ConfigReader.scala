package piabrota.feeds

import scala.collection.immutable.ListMap
import ConfigKey as K

/** The TOML tables of feeds.toml as a Config. As in the Python script, an unknown key of [output]
  * or of a [[source]] is an error, and an unknown key elsewhere is ignored.
  */
object ConfigReader:
  def fromToml(raw: Toml.Table, file: String): Either[String, Config] =
    try
      val top = Fields("the file", raw.fields)
      val output = readOutput(top.table(K.Output))
      val rows = top.tables(K.Source).map(readSource(_, output))
      val groups = top.tables(K.Group).map(g => Group(g.str(K.Id), g.str(K.Title)))
      val interests = top.tables(K.Interest).map(i => Interest(i.str(K.Name), i.int(K.Weight), Terms(i.strs(K.Terms))))
      val negative = Terms(top.table(K.Negative).strsOr(K.Terms, Nil))
      checkSources(rows, groups).map(Config(top.str(K.Title), output, negative, groups, interests, _))
    catch case Bad(message) => Left(s"$file: bad configuration: $message")

  /** A [[source]] as read; `source` is None when its kind is unknown. */
  final case class SourceRow(id: String, group: String, source: Option[Source])

  /** A duplicate id, an unknown group or an unknown kind is the Left. */
  def checkSources(rows: List[SourceRow], groups: List[Group]): Either[String, List[Source]] =
    val known = groups.map(_.id).toSet
    rows.zipWithIndex.collectFirst {
      case (r, i) if rows.take(i).exists(_.id == r.id)      => s"duplicate source id: ${r.id}"
      case (r, _) if !known(r.group) || r.source.isEmpty => s"source ${r.id}: unknown group or kind"
    }.toLeft(rows.flatMap(_.source))

  private def readOutput(f: Fields): Output =
    val d = Output()
    f.only(K.output)
    Output(
      maxItems = f.intOr(K.MaxItems, d.maxItems),
      maxPerGroup = f.intOr(K.MaxPerGroup, d.maxPerGroup),
      maxAgeDays = f.intOr(K.MaxAgeDays, d.maxAgeDays),
      minScore = f.decOr(K.MinScore, d.minScore),
      digestItems = f.intOr(K.DigestItems, d.digestItems),
      digestPerGroup = f.intOr(K.DigestPerGroup, d.digestPerGroup),
      digestMinScore = f.decOr(K.DigestMinScore, d.digestMinScore),
      digestMaxChars = f.intOr(K.DigestMaxChars, d.digestMaxChars),
      pinnedKeep = f.intOr(K.PinnedKeep, d.pinnedKeep),
    )

  /** A missing age limit or pin count comes from [output]. Every key is read, in this order, before
    * the kind is looked at, so the first error is the one the Python script gave.
    */
  private def readSource(f: Fields, output: Output): SourceRow =
    f.only(K.source)
    val id = f.str(K.Id)
    val group = f.str(K.Group)
    val kind = f.str(K.Kind)
    val weight = f.int(K.Weight)
    val maxAgeDays = f.intOr(K.MaxAgeDays, output.maxAgeDays)
    val pinnedKeep = f.intOr(K.PinnedKeep, output.pinnedKeep)
    val url = f.strOr(K.Url, "")
    val query = f.strOr(K.Query, "")
    val limit = f.intOr(K.Limit, Source.DefaultLimit)
    val pinned = f.boolOr(K.Pinned, false)
    val requiresMatch = f.boolOr(K.RequiresMatch, false)
    val genres = f.strsOr(K.Genres, Nil)
    val excludeTerms = f.strsOr(K.ExcludeTerms, Nil)
    SourceRow(id, group, SourceKind.parse(kind).map { k =>
      Source(id, group, k, weight, maxAgeDays, pinnedKeep, url, query, limit, pinned, requiresMatch, genres, excludeTerms)
    })

  private final case class Bad(message: String) extends Exception(message, null, false, false)

  /** The keys of one table, read by type. A missing key or a wrong type throws `Bad`. */
  private final case class Fields(where: String, fields: ListMap[String, Toml]):
    def only(allowed: Set[ConfigKey]): Unit =
      val names = allowed.map(_.name)
      fields.keys.find(k => !names(k)).foreach(k => throw Bad(s"$where has an unknown key '$k'"))

    def str(key: ConfigKey): String = strOr(key, missing(key))
    def strOr(key: ConfigKey, default: => String): String = get(key, default) { case Toml.Str(s) => s }
    def int(key: ConfigKey): Int = intOr(key, missing(key))
    def intOr(key: ConfigKey, default: => Int): Int = get(key, default) {
      case Toml.Integer(n) if n.isValidInt => n.toInt
    }
    def decOr(key: ConfigKey, default: => Double): Double = get(key, default) {
      case Toml.Decimal(d) => d
      case Toml.Integer(n) => n.toDouble
    }
    def boolOr(key: ConfigKey, default: => Boolean): Boolean = get(key, default) { case Toml.Bool(b) => b }
    def strs(key: ConfigKey): List[String] = strsOr(key, missing(key))
    def strsOr(key: ConfigKey, default: => List[String]): List[String] = get(key, default) {
      case Toml.Arr(values) if values.forall(_.isInstanceOf[Toml.Str]) => values.toList.collect { case Toml.Str(s) => s }
    }

    /** [name], or an empty table when it is not there. */
    def table(key: ConfigKey): Fields = get(key, Fields(s"[${key.name}]", ListMap.empty)) {
      case Toml.Table(t) => Fields(s"[${key.name}]", t)
    }

    /** Every [[name]]. */
    def tables(key: ConfigKey): List[Fields] = get(key, List.empty[Fields]) {
      case Toml.Arr(values) if values.forall(_.isInstanceOf[Toml.Table]) =>
        values.toList.zipWithIndex.collect { case (Toml.Table(t), i) => Fields(s"[[${key.name}]] number ${i + 1}", t) }
    }

    private def get[A](key: ConfigKey, default: => A)(read: PartialFunction[Toml, A]): A =
      fields.get(key.name) match
        case None                                   => default
        case Some(value) if read.isDefinedAt(value) => read(value)
        case Some(_)                                => throw Bad(s"$where: '${key.name}' has the wrong type")

    private def missing(key: ConfigKey): Nothing = throw Bad(s"$where has no '${key.name}'")
