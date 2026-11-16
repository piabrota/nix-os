package piabrota.thesis

import Text.jqNum

/** The environment of a `thesis` run, read once by Thesis.run. */
final case class Config(share: os.Path, home: os.Path, outbox: os.Path, tmpRoot: os.Path,
    pandocTimeout: Option[String], texTimeout: Option[String], seat: Option[String], logSeat: Option[String],
    user: Option[String])

object Config:
  object Env:
    val Share = "THESIS_SHARE"
    val Home = "THESIS_HOME"
    val Outbox = "THESIS_OUTBOX"
    val Tmp = "TMPDIR"
    val PandocTimeout = "THESIS_PANDOC_TIMEOUT"
    val TexTimeout = "THESIS_TEX_TIMEOUT"
    val Seat = "THESIS_SEAT"
    /** The seat that the rig's member shell sets; only the log reads it. */
    val LogSeat = "SEAT"
    val User = "USER"

  val DefaultHome = "/var/lib/openrig/work/wave-forecaster-thesis"
  val DefaultOutbox = "/var/lib/rig-outbox/wave-forecaster-thesis"
  val DefaultTmp = "/tmp"

  /** The share folder is THESIS_SHARE, or share/thesis beside this binary; it must hold profile.json. */
  def fromEnv(env: String => Option[String], selfExe: => os.Path): Either[String, Config] =
    val share = env(Env.Share).getOrElse((selfExe / os.up / os.up / "share" / "thesis").toString)
    scala.util.Try(os.Path(share, os.pwd)).toOption.filter(d => os.isFile(d / Names.ProfileJson)) match
      case None => Left(s"thesis: cannot find the toolkit data (${Env.Share}=${env(Env.Share).getOrElse("")})")
      case Some(dir) =>
        def path(name: String, default: String) = os.Path(env(name).getOrElse(default), os.pwd)
        Right(Config(dir, path(Env.Home, DefaultHome), path(Env.Outbox, DefaultOutbox), path(Env.Tmp, DefaultTmp),
          env(Env.PandocTimeout), env(Env.TexTimeout), env(Env.Seat), env(Env.LogSeat), env(Env.User)))

/** The file and folder names of the toolkit's data and of a project. */
object Names:
  val ProfileJson = "profile.json"
  val TemplateJson = "template.json"
  val Projects = "projects"
  val Out = "out"
  val ThesisJson = "thesis.json"
  val RefsBib = "refs.bib"
  val ReferencesMd = "REFERENCES.md"
  val Sections = "sections"
  val Sources = "sources"
  val Claims = "claims"
  val Review = "review"
  val Build = "build"
  val Notes = "notes"
  val State = "state"
  val Figures = "figures"
  val Assets = "assets"
  /** The folders of a new project, in the order `thesis new` makes them. */
  val ProjectDirs = List(Sections, Sources, Claims, Review, Build, Notes, State, Figures, Assets)
  val FactsMd = "facts.md"
  val GlossaryMd = "glossary.md"
  val ThesisLog = "thesis.log"
  val ThesisPdf = "thesis.pdf"
  val QaJson = "qa.json"
  val AssembledJson = "assembled.json"
  val MainLog = "main.log"
  val Tex = "tex"
  /** The rules of a work order, by section role (share/thesis/lib). */
  val WorkOrderTxt = "workorder.txt"
  val MainLatex = "main.latex"
  val PreviewLatex = "preview.latex"
  val Final = "final"

/** The subcommands of `thesis`. The gates call each other through these, in their own process. */
enum Cmd(val name: String):
  case New extends Cmd("new")
  case Sections extends Cmd("sections")
  case Status extends Cmd("status")
  case Fetch extends Cmd("fetch")
  case Release extends Cmd("release")
  case BuildSection extends Cmd("build-section")
  case Submit extends Cmd("submit")
  case Lint extends Cmd("lint")
  case Readability extends Cmd("readability")
  case Slop extends Cmd("slop")
  case UfrjCheck extends Cmd("ufrj-check")
  case CiteCheck extends Cmd("cite-check")
  case CiteScore extends Cmd("cite-score")
  case ReviewReport extends Cmd("review-report")
  case Verdict extends Cmd("verdict")
  case Assemble extends Cmd("assemble")
  case PdfQa extends Cmd("pdf-qa")
  case Publish extends Cmd("publish")

object Cmd:
  def parse(name: String): Option[Cmd] = values.find(_.name == name)

/** Where a section stands: omit, claimed, drafted, linted, revise, accepted, changed (accepted, then
  * edited) or todo. A state file edited by hand may hold any other word, shown as it is.
  */
enum SectionState:
  case Todo, Omit, Claimed, Drafted, Linted, Revise, Accepted, Changed
  case Other(raw: String)

  def render: String = this match
    case Other(raw) => raw
    case named      => named.toString.toLowerCase

object SectionState:
  private val named = List(Todo, Omit, Claimed, Drafted, Linted, Revise, Accepted, Changed)
  def parse(s: String): SectionState = named.find(_.render == s).getOrElse(Other(s))

/** The kind of a sheet in thesis.json. */
enum Kind:
  case Pretextual, Textual, Postextual
  def render: String = toString.toLowerCase

object Kind:
  def parse(s: String): Option[Kind] = values.find(_.render == s)

/** The role of a section in thesis.json. */
enum Role:
  case Resumo, Abstract, Agradecimentos, Dedicatoria, Chapter, Appendix
  def render: String = toString.toLowerCase
  /** A sheet before the text: no headings, no lists. */
  def pretext: Boolean = this match
    case Resumo | Abstract | Agradecimentos | Dedicatoria => true
    case Chapter | Appendix                               => false

object Role:
  def parse(s: String): Option[Role] = values.find(_.render == s)

/** The reviewer's decision on a drafted section. */
enum Decision:
  case Accept, Revise
  def render: String = toString.toLowerCase

object Decision:
  def parse(s: String): Either[String, Decision] =
    values.find(_.render == s).toRight("verdict: say accept or revise")

/** The status of a row of REFERENCES.md. */
enum SourceStatus:
  case Verified, Partial, Unverified
  def render: String = toString.toLowerCase

object SourceStatus:
  def parse(s: String): Option[SourceStatus] = values.find(_.render == s)

/** FAIL or WARN: the level of a lint or cite-check finding. */
enum Level:
  case Fail, Warn
  def render: String = toString.toUpperCase

/** The keys of thesis.json. */
object ThesisKey:
  val Version = "version"
  val Template = "template"
  val Title = "title"
  val TitleEn = "title_en"
  val Author = "author"
  val AuthorRef = "author_ref"
  val Advisor = "advisor"
  val Examiners = "examiners"
  val Course = "course"
  val Month = "month"
  val Year = "year"
  val Language = "language"
  val CitationStyle = "citation_style"
  val Lists = "lists"
  val Assets = "assets"
  val Sections = "sections"
  val Figures = "figures"
  val Tables = "tables"
  val ListFigures = s"$Lists.$Figures"
  val ListTables = s"$Lists.$Tables"
  val UfrjLogo = "ufrj_logo"
  val AssetsUfrjLogo = s"$Assets.$UfrjLogo"

/** The values that thesis.json must hold, and the mark of a field still to fill. */
object ThesisValue:
  val ToFill = "A PREENCHER"
  val Language = "pt-BR"
  val CitationStyle = "author-date"
  val DefaultCourse = "Engenharia Eletrônica e de Computação"

/** The keys of one section of thesis.json. */
object SectionKey:
  val Id = "id"
  val Order = "order"
  val Kind = "kind"
  val Role = "role"
  val Title = "title"
  val Brief = "brief"
  val TargetWords = "target_words"
  val Status = "status"
  val CiteClass = "cite_class"
  val Sources = "sources"
  val Keywords = "keywords"
  val Part = "part"
  val DefaultCiteClass = "medium"

/** The parts that the Resolução wants in the text, by the field part of a section. */
val RequiredParts: List[String] = List("introducao", "revisao", "metodologia", "resultados", "conclusoes")

/** The keys of state/<id>.json, the progress of a section. */
enum StateKey(val key: String):
  case Status extends StateKey("status")
  case By extends StateKey("by")
  case Sha extends StateKey("sha")
  case Drafted extends StateKey("drafted")
  case Round extends StateKey("round")
  case ReviewedSha extends StateKey("reviewed_sha")
  case ReportOk extends StateKey("report_ok")
  case AcceptedSha extends StateKey("accepted_sha")
  case VerdictBy extends StateKey("verdict_by")
  case VerdictAt extends StateKey("verdict_at")

/** The keys of build/qa.json, written by pdf-qa and read by ufrj-check, status and publish. */
object QaKey:
  val Pass = "pass"
  val Pages = "pages"
  val PageSizeOk = "page_size_ok"
  val PagesNotA4 = "pages_not_a4"
  val MinMargins = "min_margins_mm"
  val MarginsOk = "margins_ok"
  val LinePitch = "line_pitch_pt"
  val LineSpacing = "line_spacing"
  val BodyFamily = "body_font.family"
  val BodySize = "body_font.size_pt"
  val MaxFontSize = "max_font_size_pt"
  val NonBlackFonts = "non_black_fonts"

/** A claim file, claims/<id>.claim: who writes the section and since when (`claim_info`). */
final case class Claim(seat: String, epoch: Long):
  def render(id: String, iso: String): String = s"seat=$seat\nepoch=$epoch\niso=$iso\nsection=$id\n"

object Claim:
  /** The seat and the epoch, if both are there. */
  def parse(text: String): Option[Claim] =
    val lines = Prose.lines(text)
    def value(key: String) =
      lines.collectFirst { case l if l.startsWith(s"$key=") => l.drop(key.length + 1) }.filter(_.nonEmpty)
    for seat <- value("seat"); epoch <- value("epoch") yield Claim(seat, epoch.toLongOption.getOrElse(0L))

/** Four values, one a side of the page. */
final case class Sides[A](top: A, bottom: A, left: A, right: A):
  def toList: List[A] = List(top, bottom, left, right)
  def map[B](f: A => B): Sides[B] = Sides(f(top), f(bottom), f(left), f(right))
  def zip[B](o: Sides[B]): Sides[(A, B)] = Sides((top, o.top), (bottom, o.bottom), (left, o.left), (right, o.right))

object Sides:
  val Names: Sides[String] = Sides("top", "bottom", "left", "right")

/** A course of the Escola Politécnica and the title it confers. */
final case class Course(name: String, title: Option[String])

final case class Limits(pandocTimeoutS: Double, texTimeoutS: Double, texPassesMax: Int, popplerTimeoutS: Double,
    claimStaleS: Double, maxReviewRounds: Double, slugMax: Int, idMax: Int, sectionMaxBytes: Double)

final case class PageRules(paperMm: (Double, Double), paperToleranceMm: Double, marginMinMm: Sides[Double],
    marginToleranceMm: Double, bodyFontPt: Double, titleFontMaxPt: Double, singleBaselineskipPt: Double,
    lineSpacingTolerance: Double, fontFamiliesOk: List[String], bboxFooterZonePt: Double, overfullMaxPt: Double)

final case class WordRules(resumoMax: Int, keywordsMin: Int, keywordsMax: Int, inlineQuoteMaxWords: Int,
    targetToleranceLow: Double, targetToleranceHigh: Double)

final case class ReadabilityLimits(sentenceMeanMax: Double, sentenceLongWords: Double, sentenceLongShareMax: Double,
    paragraphWordsMax: Double, oneSentenceParagraphShareMax: Double, passiveShareMax: Double, fleschPtMin: Double,
    worstSentences: Int, minSentences: Double, anglicismFailDistinct: Double)

/** The signals of the slop score; the name is the key in profile.json and the row of the report. */
enum Signal(val name: String):
  case Phrases extends Signal("phrases")
  case Dashes extends Signal("dashes")
  case Tricolon extends Signal("tricolon")
  case SameOpening extends Signal("same_opening")
  case LowVariation extends Signal("low_variation")
  case SummaryEndings extends Signal("summary_endings")
  case RepeatedNgrams extends Signal("repeated_ngrams")
  case Hedging extends Signal("hedging")
  case BoldLeadins extends Signal("bold_leadins")
  case RestatedHeading extends Signal("restated_heading")
  case Transitions extends Signal("transitions")

/** A signal scores weight * clamp((value - warn) / (max - warn), 0, 1). */
final case class Band(weight: Double, warn: Double, max: Double)

final case class SlopParams(threshold: Double, minWords: Double, minSentencesForCv: Double, ngramSize: Int,
    ngramMinRepeats: Double, sameOpeningRun: Double, tricolonItemMaxWords: Int, bands: Map[Signal, Band])

final case class CiteRules(doiRegex: String, scoreTargets: Map[String, Double], scoreMinWords: Double,
    bibRequired: Map[String, List[String]])

final case class WordLists(anglicisms: List[String], slopPhrases: List[String], transitions: List[String],
    summaryOpeners: List[String], hedges: List[String], serForms: List[String], irregularParticiples: List[String],
    adjectiveLikeParticiples: List[String], abbreviations: Set[String], allowedChars: Set[Int],
    placeholderMarkers: List[String])

/** Every number and list of the toolkit: share/thesis/profile.json. */
final case class Profile(limits: Limits, defaultTemplate: String, courses: List[Course], page: PageRules,
    words: WordRules, readability: ReadabilityLimits, slop: SlopParams, cite: CiteRules, lists: WordLists,
    mixedTerms: List[List[String]])

object Profile:
  /** A missing number is 0 and a missing list is empty, as the shell version's jq read them. */
  def from(json: ujson.Value): Profile =
    def at(path: String) = J.path(json, path)
    def num(path: String): Double = at(path).flatMap(_.numOpt).getOrElse(0.0)
    def int(path: String): Int = num(path).toInt
    def list(path: String): List[String] = at(path).flatMap(_.arrOpt).map(_.toList.map(J.rawValue)).getOrElse(Nil)
    def words(v: ujson.Value): List[String] =
      v.arrOpt.toList.flatten.map(J.rawValue).flatMap(_.split("\\s+").filter(_.nonEmpty))
    def obj(path: String) = at(path).flatMap(_.objOpt).toList.flatMap(_.toList)
    Profile(
      limits = Limits(num("limits.pandoc_timeout_s"), num("limits.tex_timeout_s"), int("limits.tex_passes_max"),
        num("limits.poppler_timeout_s"), num("limits.claim_stale_s"), num("limits.max_review_rounds"),
        int("limits.slug_max"), int("limits.id_max"), num("limits.section_max_bytes")),
      defaultTemplate = J.raw(at("template.default")),
      courses = at("courses").flatMap(_.arrOpt).toList.flatten.map(c => Course(J.raw(J.get(c, "name")), J.str(c, "title"))),
      page = PageRules((num("layout.paper_mm.0"), num("layout.paper_mm.1")), num("layout.paper_tolerance_mm"),
        Sides.Names.map(side => num(s"layout.margin_min_mm.$side")), num("layout.margin_tolerance_mm"),
        num("layout.body_font_pt"), num("layout.title_font_max_pt"), num("layout.single_baselineskip_pt"),
        num("layout.line_spacing_tolerance"), list("layout.font_families_ok"), num("layout.bbox_footer_zone_pt"),
        num("layout.overfull_max_pt")),
      words = WordRules(int("words.resumo_max"), int("words.keywords_min"), int("words.keywords_max"),
        int("words.inline_quote_max_words"), num("words.target_tolerance_low"), num("words.target_tolerance_high")),
      readability = ReadabilityLimits(num("readability.sentence_mean_max"), num("readability.sentence_long_words"),
        num("readability.sentence_long_share_max"), num("readability.paragraph_words_max"),
        num("readability.one_sentence_paragraph_share_max"), num("readability.passive_share_max"),
        num("readability.flesch_pt_min"), int("readability.worst_sentences"), num("readability.min_sentences"),
        num("readability.anglicism_fail_distinct")),
      slop = SlopParams(num("slop.threshold"), num("slop.min_words"), num("slop.min_sentences_for_cv"),
        int("slop.ngram_size"), num("slop.ngram_min_repeats"), num("slop.same_opening_run"),
        int("slop.tricolon_item_max_words"),
        Signal.values.map(s => s -> Band(num(s"slop.weights.${s.name}"), num(s"slop.warn.${s.name}"), num(s"slop.max.${s.name}"))).toMap),
      cite = CiteRules(J.raw(at("cite.doi_regex")),
        obj("cite.score_targets").flatMap((cls, v) => v.numOpt.map(cls -> _)).toMap, num("cite.score_min_words"),
        obj("cite.bib_required").map((kind, v) => kind -> words(v)).toMap),
      lists = WordLists(list("lists.anglicisms"), list("lists.slop_phrases"), list("lists.transitions"),
        list("lists.summary_openers"), list("lists.hedges"), list("lists.ser_forms"), list("lists.irregular_participles"),
        list("lists.adjective_like_participles"), list("lists.abbreviations").mkString(" ").split(' ').filter(_.nonEmpty).toSet,
        at("lists.allowed_chars").flatMap(_.arrOpt).toList.flatten.flatMap(r => r.arr(0).num.toInt to r.arr(1).num.toInt).toSet,
        list("lists.placeholder_markers")),
      mixedTerms = at("terms.mixed").flatMap(_.arrOpt).toList.flatten.map(_.arr.toList.map(J.rawValue)),
    )

  /** A number of the profile as `jq -r` printed it in a message. */
  def show(d: Double): String = jqNum(d)
