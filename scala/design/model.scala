package piabrota.design

/** The domain of the design kit and of the proof and pirsig sites: what their commands read
  * (sites.json, manifest.json, loc.json, design/css), decide and write.
  */

/** Who may open a site of design/sites.nix. */
enum Access(val id: String):
  case Public extends Access("public")
  case Login  extends Access("login")

object Access:
  def parse(s: String): Either[String, Access] =
    values.find(_.id == s).toRight(s"""design kit: access "$s" is neither public nor login""")

/** A site of design/sites.nix, as the nav lists it. */
final case class Site(id: String, label: String, url: String, access: Access)

object Site:
  /** The list that proof-site/common.nix writes from design/sites.nix. */
  def parseAll(v: ujson.Value): Either[String, List[Site]] =
    Json.list(v).flatMap(Json.traverse(_)(s =>
      for
        id     <- Json.str(s, "id")
        label  <- Json.str(s, "label")
        url    <- Json.str(s, "url")
        access <- Json.str(s, "access").flatMap(Access.parse)
      yield Site(id, label, url, access)))

/** The two sites that `proof-manifest` and `proof-index` build. `prefix` is the folder of the
  * pages under the site's root.
  */
enum SiteName(val id: String, val prefix: String):
  case Proof  extends SiteName("proof", "proof/")
  case Pirsig extends SiteName("pirsig", "")

object SiteName:
  def parse(s: String): Option[SiteName] = values.find(_.id == s)

/** The file names and folders of a built site that the commands look for. */
object Layout:
  val index = "index.html"
  val html = ".html"
  val docs = "docs"
  val diagrams = "docs/diagrams"
  val videos = "videos"
  val figures = "figures"
  val videosIndex = s"$videos/$index"
  val proofIndex = s"${SiteName.Proof.prefix}$index"
  /** What every page title of h0ffmann/proof ends with. */
  val proofTitleSuffix = " · proof"

/** What archify leaves in the pages it draws. */
object Archify:
  /** The class of a page that archify drew. */
  val themeClass = "archify-theme"
  /** The code with which an archify page reads `?theme=` from its address. */
  val readsTheme = "URLSearchParams(window.location.search).get('theme')"
  /** The query that opens an archify page dark. */
  val dark = "?theme=dark"

  def drew(html: String): Boolean = html.contains(themeClass)

/** The languages of the pages. */
object Lang:
  val default = "en"
  private val names = Map(default -> "English", "pt" -> "Português (BR)")

  /** `pt-BR` -> `pt`. */
  def base(lang: String): String = lang.takeWhile(_ != '-').toLowerCase(java.util.Locale.ROOT)
  def name(base: String): String = names.getOrElse(base, base)

/** `diagram` (archify drew it) or `page`. */
enum PageKind(val id: String):
  case Diagram extends PageKind("diagram")
  case Plain   extends PageKind("page")

object PageKind:
  def of(diagram: Boolean): PageKind = if diagram then Diagram else Plain
  def parse(s: String): Either[String, PageKind] = values.find(_.id == s).toRight(s"no page kind $s")

/** One page of a built site, as the index draws it. */
final case class Page(path: String, href: String, title: String, group: String, lang: String, kind: PageKind)

/** A folder of pages and its readable title. */
final case class Group(id: String, title: String)

/** The pages of a site, their groups, and how many videos pirsig's page of video notes says it
  * indexes.
  */
final case class Manifest(site: SiteName, pages: List[Page], groups: List[Group], videos: Option[Long]):
  import Manifest.Key
  def render: ujson.Obj = ujson.Obj(
    Key.site -> site.id,
    Key.pages -> pages.map(p => ujson.Obj(Key.path -> p.path, Key.href -> p.href, Key.title -> p.title,
      Key.group -> p.group, Key.lang -> p.lang, Key.kind -> p.kind.id)),
    Key.groups -> ujson.Obj.from(groups.map(g => g.id -> ujson.Str(g.title))),
    Key.videos -> videos.fold(ujson.Null)(n => ujson.Num(n.toDouble)),
  )

object Manifest:
  object Key:
    val site = "site"
    val pages = "pages"
    val groups = "groups"
    val videos = "videos"
    val path = "path"
    val href = "href"
    val title = "title"
    val group = "group"
    val lang = "lang"
    val kind = "kind"

  def parse(v: ujson.Value): Either[String, Manifest] =
    def page(p: ujson.Value) =
      for
        path  <- Json.str(p, Key.path)
        href  <- Json.str(p, Key.href)
        title <- Json.str(p, Key.title)
        group <- Json.str(p, Key.group)
        lang  <- Json.str(p, Key.lang)
        kind  <- Json.str(p, Key.kind).flatMap(PageKind.parse)
      yield Page(path, href, title, group, lang, kind)
    for
      site   <- Json.str(v, Key.site).flatMap(s => SiteName.parse(s).toRight(s"no site $s"))
      pages  <- Json.field(v, Key.pages).flatMap(Json.list).flatMap(Json.traverse(_)(page))
      groups <- Json.field(v, Key.groups).flatMap(g => g.objOpt.toRight(s"${Key.groups} is not an object"))
        .flatMap(o => Json.traverse(o.toList)((k, t) => t.strOpt.map(Group(k, _)).toRight(s"group $k is not a text")))
    yield Manifest(site, pages, groups, v.obj.get(Key.videos).flatMap(_.numOpt).map(_.toLong))

  // JavaScript writes an object's keys that read as array indexes first, by number; the manifest
  // keeps that order so that its JSON stays the one manifest.mjs wrote.
  def jsKeyOrder[A](items: List[A])(key: A => String): List[A] =
    def index(k: String) = Option.when(k.matches("0|[1-9][0-9]{0,9}"))(k.toLong).filter(_ < 4294967295L)
    val (numbers, names) = items.partition(a => index(key(a)).isDefined)
    numbers.sortBy(a => index(key(a))) ++ names

/** A language of the proofs of h0ffmann/proof: what a file must be, its line comment and its block
  * comment. "Z3" is the Scala of z3-scala/, where every Z3 check of the repository is written.
  */
enum Language(val id: String, val label: String, val line: String, val open: String, val close: String):
  case Lean extends Language("lean", "Lean 4", "--", "/-", "-/")
  case Agda extends Language("agda", "Agda", "--", "{-", "-}")
  case Z3   extends Language("z3", "Z3", "//", "/*", "*/")

  def matches(path: String): Boolean = this match
    case Lean => path.endsWith(".lean")
    case Agda => path.endsWith(".agda")
    case Z3   => path.startsWith("z3-scala/") && path.endsWith(".scala")

/** The files and the lines of code of one language. */
final case class LocCount(language: Language, files: Int, lines: Int)

/** The JSON of `proof-loc`: `{"lean":{"label":"Lean 4","files":18,"lines":1264},...}`. */
object LocCount:
  private val label = "label"
  private val files = "files"
  private val lines = "lines"

  def render(counts: List[LocCount]): ujson.Obj =
    ujson.Obj.from(counts.map(c => c.language.id -> ujson.Obj(label -> c.language.label, files -> c.files, lines -> c.lines)))

  /** The counts in the order of `Language`; a key that names no language is left out. */
  def parse(v: ujson.Value): Either[String, List[LocCount]] =
    v.objOpt.toRight("loc: not an object").flatMap(o =>
      Json.traverse(Language.values.toList.flatMap(l => o.get(l.id).map(l -> _)))((l, c) =>
        for
          f <- Json.num(c, files)
          n <- Json.num(c, lines)
        yield LocCount(l, f.toInt, n.toInt)))

/** A CSS file of design/css/. `page` inlines tokens and base, then the optional modules it is
  * asked for, in the order of `Module.optional`.
  */
enum Module(val name: String):
  case Tokens  extends Module("tokens")
  case Base    extends Module("base")
  case Chrome  extends Module("chrome")
  case Hero    extends Module("hero")
  case Section extends Module("section")
  case Cards   extends Module("cards")
  case Pills   extends Module("pills")
  case Footer  extends Module("footer")
  case Prose   extends Module("prose")

  def file: String = s"$name.css"

object Module:
  val always: List[Module] = List(Tokens, Base)
  val optional: List[Module] = values.toList.filterNot(always.contains)

/** The CSS files of design/css/, read once each. */
final class Css(dir: os.Path):
  private val cache = scala.collection.mutable.Map.empty[Module, String]

  def apply(m: Module): String = cache.getOrElseUpdate(m, os.read(dir / m.file))

object Css:
  /** The environment variable in which the Nix build gives the folder of design/css. */
  val envVar = "DESIGN_CSS"

  /** `DESIGN_CSS`, else `design/css` under `cwd` (the root of the repository). */
  def locate(designCss: Option[String], cwd: os.Path): Either[String, Css] =
    designCss.map(os.Path(_, cwd)).orElse(Some(cwd / "design" / "css").filter(os.isDir(_)))
      .map(Css(_))
      .toRight(s"$envVar is not set: it names the folder of design/css")

/** A number of the hero: `<dt>label</dt><dd>value</dd>`. */
final case class Stat(value: String, label: String)

/** How a button of the hero looks: `Primary` is the one filled button of a page. */
enum Variant(val css: Option[String]):
  case Plain   extends Variant(None)
  case Primary extends Variant(Some("primary"))
  case Mono    extends Variant(Some("mono"))

/** A button of the hero. */
final case class Action(label: String, href: String, variant: Variant = Variant.Plain)

/** The colour of a pill. `Off` is the dashed pill of a state that is not there. */
enum Tone(val css: Option[String]):
  case Plain  extends Tone(None)
  case Ok     extends Tone(Some("ok"))
  case Warn   extends Tone(Some("warn"))
  case Off    extends Tone(Some("none"))
  case Accent extends Tone(Some("accent"))
  case Mono   extends Tone(Some("mono"))

/** A state or a tag. */
final case class Pill(text: String, tone: Tone = Tone.Plain)

/** The two forms of the chrome: the header of a kit page, or the 44 px bar that design-inject puts
  * into a foreign page, with a link back to the site's index when there is one.
  */
enum Chrome:
  case Header
  case Bar(index: Option[String])

/** What breaks the rule of `proof-dark-gate`. */
enum DarkBreach:
  case Outside(page: String)
  case Blind(page: String)

  def render: String = this match
    case Outside(page) => s"$page: an archify page outside proof.nix's dark location"
    case Blind(page)   => s"$page: archify no longer reads ?theme= from the address"

/** `--name value` pairs of a command line, in order. */
final case class Flags(pairs: List[(String, String)]):
  def all(name: String): List[String] = pairs.collect { case (`name`, value) => value }
  def first(name: String): Option[String] = all(name).headOption
  def last(name: String): Option[String] = all(name).lastOption

object Flags:
  def parse(args: List[String]): Flags =
    Flags(args.grouped(2).toList.collect { case name :: value :: Nil => name.stripPrefix("--") -> value })

/** Reading JSON at the edge, with the missing key as the message. */
object Json:
  def field(v: ujson.Value, key: String): Either[String, ujson.Value] =
    v.objOpt.flatMap(_.get(key)).toRight(s"no $key")

  def str(v: ujson.Value, key: String): Either[String, String] =
    field(v, key).flatMap(_.strOpt.toRight(s"$key is not a text"))

  def num(v: ujson.Value, key: String): Either[String, Double] =
    field(v, key).flatMap(_.numOpt.toRight(s"$key is not a number"))

  def list(v: ujson.Value): Either[String, List[ujson.Value]] =
    v.arrOpt.map(_.toList).toRight("not a list")

  def traverse[A, B](as: List[A])(f: A => Either[String, B]): Either[String, List[B]] =
    as.foldRight(Right(Nil): Either[String, List[B]])((a, acc) => for b <- f(a); bs <- acc yield b :: bs)
