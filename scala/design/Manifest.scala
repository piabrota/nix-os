package piabrota.design

import scala.util.matching.Regex
import piabrota.lib.die

/** `proof-manifest`, a build step of proof-site/common.nix: the list of pages of a built site, as
  * JSON, for `proof-index`. The build runs it on `dist` after the brand bar is in. For each .html
  * page it reads the <title>, the lang of the <html> tag and whether archify drew it.
  *
  *   proof-manifest <dist> <proof|pirsig> > manifest.json
  */
object ManifestScan:
  private val entities = Map("amp" -> "&", "lt" -> "<", "gt" -> ">", "quot" -> "\"", "apos" -> "'", "nbsp" -> " ")
  private val entity = "&(?:#([0-9]+)|#[xX]([0-9a-fA-F]+)|([a-zA-Z]+));".r
  private val spaces = s"${Js.space}+".r
  // These match on `Js.lowerAscii` of the page, as the old /i regexes did.
  private val titleTag = """<title[^>]*>([\s\S]*?)</title>""".r
  private val htmlLang = """<html\b[^>]*\blang=["']?([a-z-]+)""".r
  private val videoCount = "([0-9]+) vídeos? indexados?".r

  /** Text of an HTML title as plain text: entities decoded, white space folded. */
  def decode(text: String): String =
    val decoded = entity.replaceAllIn(text, m =>
      val char =
        if m.group(1) != null then codePoint(BigInt(m.group(1)))
        else if m.group(2) != null then codePoint(BigInt(m.group(2), 16))
        else entities.getOrElse(m.group(3).toLowerCase(java.util.Locale.ROOT), m.matched)
      Regex.quoteReplacement(char))
    Js.trim(spaces.replaceAllIn(decoded, " "))

  private def codePoint(n: BigInt): String =
    if n > 0x10FFFF then die(s"proof-manifest: $n is not a code point")
    String(Character.toChars(n.toInt))

  /** The <title> of a page, or "" when it has none. */
  def titleOf(html: String): String =
    titleTag.findFirstMatchIn(Js.lowerAscii(html)).map(m => decode(html.substring(m.start(1), m.end(1)))).getOrElse("")

  /** The lang of the <html> tag; `en` when it has none. */
  def langOf(html: String): String =
    htmlLang.findFirstMatchIn(Js.lowerAscii(html)).map(m => html.substring(m.start(1), m.end(1))).getOrElse(Lang.default)

  /** The group of a page: the first folder under proof/ (docs/<name> for a page of docs/), or the
    * first folder of a pirsig page. A page at the top of its tree has the group "".
    */
  def groupOf(site: SiteName, path: String): String =
    val folders = path.split("/", -1).toList.drop(if site == SiteName.Proof then 1 else 0).dropRight(1)
    if site == SiteName.Proof && folders.headOption.contains(Layout.docs) then folders.take(2).mkString("/")
    else folders.headOption.getOrElse("")

  /** The readable title of a group: the title of the folder's own index (before a colon), else its name. */
  def groupTitle(group: String, indexTitle: String): String =
    val own = indexTitle.stripSuffix(Layout.proofTitleSuffix).split(": ", -1)(0)
    if own.nonEmpty then own else capital(group.split("/", -1).last.replace('-', ' '))

  private def capital(s: String): String =
    if s.isEmpty then s else s.substring(0, 1).toUpperCase(java.util.Locale.ROOT) + s.substring(1)

  def scan(dist: os.Path, site: SiteName): Manifest =
    val files = os.walk(dist)
      .filter(p => p.last.endsWith(Layout.html) && os.isFile(p, followLinks = false))
      .map(_.relativeTo(dist).segments.mkString("/"))
      .filter(_ != Layout.index)
      .sorted
      .toList
    val pages = files.map { path =>
      val html = os.read(dist / os.RelPath(path))
      val diagram = Archify.drew(html)
      Page(path, if diagram then s"$path${Archify.dark}" else path, Some(titleOf(html)).filter(_.nonEmpty).getOrElse(path),
        groupOf(site, path), langOf(html), PageKind.of(diagram))
    }
    val groups = pages.filter(p => p.kind == PageKind.Plain && p.group.nonEmpty).map(_.group).distinct.map { g =>
      Group(g, groupTitle(g, pages.find(_.path == s"${site.prefix}$g/${Layout.index}").fold("")(_.title)))
    }
    // `N vídeo(s) indexado(s)`, said by the page of the video notes; none when it does not say.
    val videos = pages.find(_.path == Layout.videosIndex)
      .flatMap(p => videoCount.findFirstMatchIn(os.read(dist / os.RelPath(p.path))))
      .map(_.group(1).toLong)
    Manifest(site, pages, Manifest.jsKeyOrder(groups)(_.id), videos)

  def run(args: List[String]): Int = args match
    case List(dist, name) =>
      val site = SiteName.parse(name).getOrElse(die(usage, 2))
      println(ujson.write(scan(os.Path(dist, os.pwd), site).render, indent = 1))
      0
    case _ => die(usage, 2)

  private val usage = "usage: proof-manifest <dist> <proof|pirsig> > manifest.json"
