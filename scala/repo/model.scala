package piabrota.repo

/** DeepWiki's plan of this repository's wiki (.devin/wiki.json), as far as its rules read it. */
final case class WikiPlan(repoNotes: Option[List[Note]], pages: Option[List[Page]]):
  def notes: List[Note] = repoNotes.getOrElse(Nil) ++ pages.getOrElse(Nil).flatMap(_.pageNotes)

final case class Page(title: String, purpose: String, parent: Option[String], pageNotes: List[Note], raw: ujson.Value)
final case class Note(content: String)

/** DeepWiki's limits (docs.devin.ai, "DeepWiki"). */
object WikiLimits:
  val maxPages = 30
  val maxNotes = 100
  val maxNoteLength = 10000

/** One figure: its source under docs/archify/ (`pt/` for a pt-BR mirror) and what it draws. */
final case class Figure(slug: String):
  def isMirror: Boolean = slug.startsWith(FigurePaths.mirrorDir + "/")
  def source: os.SubPath = FigurePaths.sources / os.SubPath(s"$slug.json")
  def png: os.SubPath = FigurePaths.docsImg / os.SubPath(s"$slug.png")
  def wikiPng: os.SubPath = FigurePaths.wikiImg / os.SubPath(s"$slug.png")
  /** How a page links the PNG, in docs/FIGURES.md or a wiki page. */
  def link: String = s"](img/$slug.png)"

/** The files of the figures, relative to the repository root. */
object FigurePaths:
  val sources: os.SubPath = os.sub / "docs" / "archify"
  val mirrorDir = "pt"
  val look: os.SubPath = sources / "piabrota.css"
  val crop: os.SubPath = sources / "crop.tsv"
  val lock: os.SubPath = sources / "figures.lock"
  val docsImg: os.SubPath = os.sub / "docs" / "img"
  val wikiImg: os.SubPath = os.sub / "wiki" / "img"
  val wiki: os.SubPath = os.sub / "wiki"
  val index: os.SubPath = os.sub / "docs" / "FIGURES.md"
  val archify: os.SubPath = os.sub / "vendor" / "archify"

/** One line of figures.lock: the slug and the hash of its inputs with the Archify pin. */
final case class LockLine(slug: String, inputs: String):
  def render: String = s"$slug\t$inputs"
