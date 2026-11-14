package piabrota.feeds

import java.nio.charset.StandardCharsets.UTF_8
import java.time.{Duration, Instant, LocalDate, ZoneOffset}
import piabrota.lib.die

/** feed.atom, digest.md, sources.opml, health.json and state.json, byte for byte as the Python
  * script wrote them.
  */
object Outputs:
  val FeedId = "tag:piabrota.art,2026:feed:personal"
  val ItemIdPrefix = "tag:piabrota.art,2026:item:"
  val Atom = "http://www.w3.org/2005/Atom"
  /** Sao Paulo, which has had no summer time since 2019. */
  val SaoPaulo: ZoneOffset = ZoneOffset.ofHours(-3)

  /** An element as ElementTree writes it: no indentation, attributes in order, `<a />` when empty. */
  final case class Node(name: String, attrs: Seq[(String, String)] = Nil, text: String = "",
      children: Seq[Node] = Nil):
    def render(out: StringBuilder): Unit =
      out ++= "<" ++= name
      attrs.foreach((k, v) => out ++= " " ++= k ++= "=\"" ++= escapeAttr(v) ++= "\"")
      if text.isEmpty && children.isEmpty then out ++= " />"
      else
        out ++= ">" ++= escapeText(text)
        children.foreach(_.render(out))
        out ++= "</" ++= name ++= ">"

  def document(root: Node): Array[Byte] =
    val out = StringBuilder("<?xml version='1.0' encoding='utf-8'?>\n")
    root.render(out)
    out.result().getBytes(UTF_8)

  private def escapeText(s: String): String = s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")

  private def escapeAttr(s: String): String =
    escapeText(s).replace("\"", "&quot;").replace("\r", "&#13;").replace("\n", "&#10;").replace("\t", "&#09;")

  def format1(x: Double): String = String.format(java.util.Locale.ROOT, "%.1f", Double.box(x))

  /** score N.N - source id - matched names - N stars */
  def detailLine(item: Item): String =
    (List(s"score ${format1(item.score)}", item.source) ++
      Option.when(item.matched.nonEmpty)(item.matched.mkString(", ")) ++
      Option.when(item.stars != 0)(s"${item.stars} stars")).mkString(" - ")

  private def entry(item: Item): Node =
    Node("entry", children = List(
      Node("title", text = s"[${item.group}] ${item.title}"),
      Node("link", List("rel" -> "alternate", "href" -> item.link)),
      Node("id", text = ItemIdPrefix + Links.itemId(item.link)),
      Node("updated", text = Dates.isoZ(item.date)),
      Node("summary", List("type" -> "text"), text = s"${detailLine(item)}\n${item.summary}"),
    ) ++ (item.group :: item.matched).map(term => Node("category", List("term" -> term))))

  /** The Atom 1.0 feed. */
  def atom(report: Report): Array[Byte] =
    document(Node("feed", List("xmlns" -> Atom), children = List(
      Node("id", text = FeedId),
      Node("title", text = report.cfg.title),
      Node("updated", text = Dates.isoZ(report.now)),
      Node("author", children = List(Node("name", text = report.cfg.title))),
    ) ++ report.items.map(entry)))

  /** OPML 2.0 with one outline per group and one rss outline per feed source. */
  def opml(cfg: Config, sources: List[Source]): Array[Byte] =
    val groups = cfg.groups.flatMap { group =>
      val feeds = sources.filter(s => s.group == group.id && s.kind == SourceKind.Feed)
      Option.when(feeds.nonEmpty) {
        Node("outline", List("text" -> group.title, "title" -> group.title), children = feeds.map { src =>
          Node("outline", List("type" -> "rss", "text" -> src.id, "title" -> src.id, "xmlUrl" -> src.url))
        })
      }
    }
    document(Node("opml", List("version" -> "2.0"), children = List(
      Node("head", children = List(Node("title", text = cfg.title))),
      Node("body", children = groups),
    )))

  /** health.json: status, error, item count and newest item date of each source. */
  def health(report: Report): Array[Byte] =
    val sources = report.sources.zip(report.results).map { (src, result) =>
      val dated = result.items.filter(_.dated).map(_.date)
      src.id -> ujson.Obj(
        HealthJson.Status -> result.status.text,
        HealthJson.Error -> result.error.fold(ujson.Null)(ujson.Str(_)),
        HealthJson.Items -> result.items.length,
        HealthJson.Newest -> dated.maxOption.fold(ujson.Null)(d => ujson.Str(Dates.isoZ(d))),
      )
    }
    val doc = ujson.Obj(HealthJson.Generated -> Dates.isoZ(report.now), HealthJson.Sources -> ujson.Obj.from(sources))
    (ujson.write(doc, indent = 2) + "\n").getBytes(UTF_8)

  def localDate(now: Instant): LocalDate = now.atOffset(SaoPaulo).toLocalDate

  /** Age as 5h or 2d. */
  def ageLabel(item: Item, now: Instant): String =
    if !item.dated then "n/a"
    else
      val hours = math.max(0L, Math.floorDiv(Duration.between(item.date, now).getSeconds, 3600L))
      if hours < 24 then s"${hours}h" else s"${hours / 24}d"

  private val MarkdownSpecial = "\\`*_{}[]<>()#+!|~"

  /** The score line, and the link in angle brackets so Discord shows no preview. */
  def itemLines(item: Item, now: Instant): List[String] =
    val title = item.title.flatMap(c => if MarkdownSpecial.contains(c) then s"\\$c" else c.toString)
    val link = item.link.replace(">", "%3E").replace(" ", "%20")
    List(s"- **${format1(item.score)}** $title - ${item.source}, ${ageLabel(item, now)}", s"  <$link>")

  /** Markdown: a dated heading, one section per group in config order, an error line. */
  def renderDigest(items: List[Item], cfg: Config, now: Instant, errors: List[String]): String =
    val sections = cfg.groups.flatMap { group =>
      val rows = items.filter(_.group == group.id)
      if rows.isEmpty then Nil else "" :: s"## ${group.title}" :: rows.flatMap(itemLines(_, now))
    }
    val errorLine = if errors.isEmpty then Nil else List("", s"Sources with errors: ${errors.mkString(", ")}")
    (s"# Digest ${localDate(now)}" :: sections ++ errorLine).mkString("\n") + "\n"

  /** The best digest items: a share for each group, cut at digest_items. With maxChars, drop the
    * last until the text fits.
    */
  def pickDigest(items: List[Item], report: Report, maxChars: Int = 0): List[Item] =
    val chosen = Score.selectForDigest(items, report.cfg.output)
    if maxChars <= 0 then chosen
    else
      chosen.inits.find { kept =>
        kept.isEmpty || Text.length(renderDigest(kept, report.cfg, report.now, report.errors)) <= maxChars
      }.getOrElse(Nil)

  /** feed.atom, digest.md, sources.opml and health.json. */
  def writeAll(report: Report, out: os.Path): Unit =
    val digest = renderDigest(pickDigest(report.items, report), report.cfg, report.now, report.errors)
    writeAtomic(out / FeedFile.Atom.name, atom(report))
    writeAtomic(out / FeedFile.Digest.name, digest.getBytes(UTF_8))
    writeAtomic(out / FeedFile.Opml.name, opml(report.cfg, report.sources))
    writeAtomic(out / FeedFile.Health.name, health(report))

  /** A temporary file in the same folder, then a rename over the target. A failure ends the run. */
  def writeAtomic(path: os.Path, data: Array[Byte]): Unit =
    try
      os.makeDir.all(path / os.up)
      piabrota.lib.Files.replace(path, data)
    catch case e: java.io.IOException => die(s"error: cannot write $path: ${e.getMessage}")

  /** A missing or damaged file is an empty state. */
  def loadState(path: os.Path): State =
    scala.util.Try(os.read(path)).toOption.fold(State.empty)(State.parse)

  def saveState(path: os.Path, state: State): Unit = writeAtomic(path, state.render.getBytes(UTF_8))
