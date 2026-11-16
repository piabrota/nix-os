package piabrota.feeds

import java.nio.charset.{Charset, StandardCharsets}
import java.time.Instant
import scala.util.control.ControlThrowable
import scala.xml.{Comment, Elem, MetaData, NamespaceBinding, NodeSeq, ProcInstr}
import scala.xml.parsing.ConstructingParser

/** A document that is not well-formed XML and gave no item. */
final class ParseError(message: String) extends Exception(message)

/** The items of one answer: an RSS or Atom document, a GitHub repository search, an Apple chart. */
object Parse:
  private val EntryTags = Set("item", "entry")
  private val DateTags = List("pubDate", "updated", "published", "date")
  private val SummaryTags = List("description", "summary", "encoded", "content")

  /** The first `src.limit` items of an RSS or Atom document. A podcast feed is cut at 1.5 MB, so a
    * document that breaks off keeps the items it completed; one that breaks before any item is a
    * ParseError.
    */
  def feed(data: Array[Byte], src: Source, now: Instant): List[Item] =
    val items = List.newBuilder[Item]
    var count = 0
    val parser = EntryParser(decode(data), elem =>
      entry(elem, src, now).foreach { item =>
        items += item
        count += 1
      }
      count >= src.limit
    )
    try parser.run()
    catch
      case Enough                        => None
      case _: ParseError if count > 0 => None
    items.result()

  /** One RSS item or Atom entry; None when it has no link. */
  def entry(elem: Elem, src: Source, now: Instant): Option[Item] =
    val link = entryLink(elem)
    Option.when(link.nonEmpty) {
      val moment = Dates.parse(childText(elem, DateTags))
      Item(
        title = Some(Text.clean(childText(elem, List("title")))).filter(_.nonEmpty).getOrElse(link),
        link = link,
        summary = Text.summarize(childText(elem, SummaryTags)),
        date = moment.getOrElse(now),
        dated = moment.isDefined,
        source = src.id,
        group = src.group,
      )
    }

  private def children(elem: Elem): Seq[Elem] = elem.child.collect { case e: Elem => e }

  /** The text of the first child with one of the names; earlier names win. */
  private def childText(elem: Elem, names: List[String]): String =
    names.iterator
      .flatMap(name => children(elem).iterator.filter(_.label == name).map(c => Text.strip(c.text)))
      .find(_.nonEmpty)
      .getOrElse("")

  /** The alternate link of an Atom entry, or the text of an RSS link. */
  private def entryLink(elem: Elem): String =
    val links = children(elem).filter(_.label == "link").map { link =>
      val href = link.attribute("href").map(_.text).getOrElse("")
      val target = if href.nonEmpty then href else Text.strip(ownText(link))
      val rel = link.attribute("rel").map(_.text)
      (target, rel.forall(_ == "alternate"))
    }
    links.collectFirst { case (target, true) if target.nonEmpty => target }
      .orElse(links.collectFirst { case (target, _) if target.nonEmpty => target })
      .getOrElse("")

  /** The text before the first child element (ElementTree's `elem.text`). */
  private def ownText(elem: Elem): String =
    elem.child.takeWhile(!_.isInstanceOf[Elem]).filter {
      case _: Comment | _: ProcInstr => false
      case _                         => true
    }.map(_.text).mkString

  /** The bytes in the encoding the XML declaration names, UTF-8 when it names none. */
  private def decode(data: Array[Byte]): String =
    val head = new String(data.take(200), StandardCharsets.ISO_8859_1)
    val charset = """^\s*<\?xml[^>]*encoding=["']([A-Za-z0-9._-]+)["']""".r.findFirstMatchIn(head)
      .flatMap(m => scala.util.Try(Charset.forName(m.group(1))).toOption)
      .getOrElse(StandardCharsets.UTF_8)
    new String(data, charset).stripPrefix("﻿")

  private object Enough extends ControlThrowable

  /** scala-xml's own parser (no javax.xml on Scala Native), which hands each element over as it
    * closes, the way ElementTree's iterparse does. `onEntry` says when there are enough items.
    */
  private final class EntryParser(text: String, onEntry: Elem => Boolean)
      extends ConstructingParser(scala.io.Source.fromString(text), true):
    override def reportSyntaxError(pos: Int, msg: String): Unit =
      throw ParseError(s"not well-formed XML: $msg")

    // Never fetch an external DTD; the default needs java.net.URL, which Scala Native has not.
    override def externalSource(systemId: String): scala.io.Source = scala.io.Source.fromString("")

    override def elem(pos: Int, pre: String, label: String, attrs: MetaData, scope: NamespaceBinding,
        empty: Boolean, nodes: NodeSeq): NodeSeq =
      val built = super.elem(pos, pre, label, attrs, scope, empty, nodes)
      built match
        case e: Elem if EntryTags(e.label) && onEntry(e) => throw Enough
        case _                                          => built

    /** The root element, when the document reaches its end. */
    def run(): Option[Elem] =
      Option(initialize.document()).map(_.docElem).collect { case e: Elem => e }

  /** A whole XML document; a test reads the files feed-build writes with it. */
  def xml(text: String): Elem =
    EntryParser(text, _ => false).run().getOrElse(throw ParseError("no root element"))

  /** Items of a GitHub repository search. */
  def github(data: Array[Byte], src: Source, now: Instant): List[Item] =
    import GithubApi as G
    ujson.read(data).obj.get(G.Items).map(_.arr.toList).getOrElse(Nil).take(src.limit).map { repo =>
      // Its date is the last push, else the creation.
      val moment = Dates.parse(optStr(repo, G.PushedAt)).orElse(Dates.parse(optStr(repo, G.CreatedAt)))
      Item(
        title = repo(G.FullName).str,
        link = repo(G.HtmlUrl).str,
        summary = Text.summarize(optStr(repo, G.Description)),
        date = moment.getOrElse(now),
        dated = moment.isDefined,
        source = src.id,
        group = src.group,
        stars = repo.obj.get(G.Stars).flatMap(_.numOpt).fold(0)(_.toInt),
      )
    }

  /** Items of an Apple podcast chart. A podcast has no date; one of an unwanted genre is left out. */
  def apple(data: Array[Byte], src: Source, now: Instant): List[Item] =
    import AppleChart as A
    ujson.read(data)(A.Feed)(A.Results).arr.toList.take(src.limit).flatMap { entry =>
      val genres = entry.obj.get(A.Genres).map(_.arr.toList).getOrElse(Nil).map(g => optStr(g, A.Name))
      Option.when(src.genres.isEmpty || genres.exists(src.genres.contains)) {
        Item(
          title = Text.clean(entry(A.Name).str),
          link = entry(A.Url).str,
          summary = Text.summarize(s"${optStr(entry, A.Artist)}. ${genres.mkString(", ")}"),
          date = now,
          dated = false,
          source = src.id,
          group = src.group,
        )
      }
    }

  /** A string field, "" when it is missing or null. */
  private def optStr(value: ujson.Value, key: String): String =
    value.obj.get(key).flatMap(_.strOpt).getOrElse("")
