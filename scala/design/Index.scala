package piabrota.design

import java.util.Locale
import piabrota.lib.{die, env}

/** `proof-index`, a build step of proof-site/common.nix: the index of proof.piabrota.art or of
  * pirsig.piabrota.art, made with the design kit from the manifest of `proof-manifest`
  * (docs/DESIGN-KIT.md). The page loads no script.
  *
  *   proof-index <proof|pirsig> <manifest.json> --rev <commit> --sites <sites.json> --icons <html> [--loc <loc.json>] > index.html
  */
object Index:
  /** What a page of an index needs besides its manifest. `loc` is what `proof-loc` counted. */
  final case class Context(css: Css, rev: String, sites: List[Site], icons: String, loc: List[LocCount] = Nil)

  private val modules = List(Module.Chrome, Module.Hero, Module.Section, Module.Cards, Module.Pills, Module.Footer)

  private val proofRepo = "h0ffmann/proof"
  private val pirsigRepo = "piabrota/pirsig"
  private def github(repo: String) = s"https://github.com/$repo"

  private def langPill(lang: String) = Pill(Lang.base(lang).toUpperCase(Locale.ROOT))

  // The drawings beside the heroes, in the red of --accent-text: proof's ∀, and pirsig's net of notes.
  private val forAll = """<svg viewBox="0 0 100 100"><g fill="none" stroke="var(--accent-text)" stroke-linecap="round" stroke-linejoin="round" stroke-width="7"><path d="M18 18 L50 86 L82 18"></path><path d="M32 52 H68"></path></g></svg>"""
  private val noteNet = """<svg viewBox="0 0 100 100"><g fill="none" stroke="var(--accent-text)" stroke-linecap="round" stroke-linejoin="round" stroke-width="4"><path d="M24 30 L52 20 L78 40 L64 76 L30 70 Z M52 20 L64 76 M24 30 L64 76 M30 70 L78 40"></path></g><g fill="var(--accent-text)"><circle cx="24" cy="30" r="7"></circle><circle cx="52" cy="20" r="7"></circle><circle cx="78" cy="40" r="7"></circle><circle cx="64" cy="76" r="7"></circle><circle cx="30" cy="70" r="7"></circle></g></svg>"""

  /** A page's title as a card shows it: without the site's suffix, and without archify's "Diagram" word. */
  def cleanTitle(p: Page): String =
    val t = p.title.stripSuffix(Layout.proofTitleSuffix)
    if p.kind == PageKind.Diagram then t.stripSuffix(" Diagram").stripPrefix("Diagrama ") else t

  // An archify title reads "Name: what it says" (figures-site does the same): the card shows the two parts.
  private def pageCard(p: Page, pills: Seq[Pill], line: String = ""): String =
    val title = cleanTitle(p)
    val at = if p.kind == PageKind.Diagram then title.indexOf(": ") else -1
    if at < 0 then Kit.card(title, line, s"/${p.path}", p.href, pills)
    else Kit.card(title.substring(0, at), title.substring(at + 2), s"/${p.path}", p.href, pills)

  private def diagramGrids(diagrams: List[Page]): String =
    val langs = diagrams.map(p => Lang.base(p.lang)).distinct.sortBy(l => (l != Lang.default, l))
    langs.map { l =>
      Kit.sub(Lang.name(l)) +
        Kit.cardGrid(diagrams.filter(p => Lang.base(p.lang) == l).map(p => pageCard(p, List(langPill(p.lang)))))
    }.mkString

  /** Lines of code as the hero shows them: 2,475. */
  def thousands(n: Long): String =
    val digits = n.abs.toString
    val grouped = digits.reverse.grouped(3).mkString(",").reverse
    if n < 0 then s"-$grouped" else grouped

  /** The hero's numbers of lines of code, from what `proof-loc` counted. */
  def locStats(loc: List[LocCount]): List[Stat] =
    loc.map(c => Stat(thousands(c.lines.toLong), s"lines of ${c.language.label}"))

  def proofIndex(m: Manifest, ctx: Context): String =
    val short = ctx.rev.take(7)
    val pages = m.pages
    val own = pages.find(_.path == Layout.proofIndex)
    val diagramIndex = pages.find(p => p.kind == PageKind.Plain && p.group == Layout.diagrams)
    val diagrams = pages.filter(_.kind == PageKind.Diagram)
    val plain = pages.filter(p => p.kind == PageKind.Plain && p.group.nonEmpty && p.group != Layout.diagrams)
    val languages = pages.map(p => Lang.base(p.lang)).distinct

    val sections = m.groups.filter(_.id != Layout.diagrams).sortBy(_.id).map { case Group(g, title) =>
      val inGroup = plain.filter(_.group == g)
      val mixed = inGroup.map(p => Lang.base(p.lang)).distinct.size > 1
      Kit.section(
        id = g.replace('/', '-'),
        title = title,
        count = Some(inGroup.size),
        note = s"${SiteName.Proof.prefix}$g/",
        body = Kit.cardGrid(inGroup.map(p => pageCard(p, if mixed then List(langPill(p.lang)) else Nil))),
      )
    }
    val lead = diagramIndex.fold("")(d =>
      s"""<p>The diagrams are drawn by <a href="https://github.com/tt-a1i/archify" rel="noopener">archify</a> and open dark. <a href="${Kit.url(d.href)}">One index</a> lists them in the repository's own words.</p>""")
    val diagramSection = Kit.section(id = "diagrams", title = "Diagrams", count = Some(diagrams.size),
      note = s"${SiteName.Proof.prefix}${Layout.diagrams}/", body = lead + diagramGrids(diagrams))

    val actions = List(Action(s"$proofRepo ↗", github(proofRepo), Variant.Primary)) ++
      own.map(o => Action("Its own index", o.href)) :+
      Action(short, s"${github(proofRepo)}/tree/${ctx.rev}", Variant.Mono)

    Kit.page(
      ctx.css,
      title = "proof · piabrota",
      description = s"Every HTML page of $proofRepo: specifications checked by a prover, Z3 reports and diagrams.",
      modules = modules,
      icons = ctx.icons,
      body = Kit.top(
        Kit.chrome(SiteName.Proof.id, ctx.sites),
        Kit.hero(
          eyebrow = "piabrota.art · proof",
          title = "proof",
          tail = "· checked by a prover",
          lede = s"Specifications checked by a prover, implementations that follow them name for name, and data experiments with papers. Every HTML page of $proofRepo, built from a pinned commit.",
          stats = List(
            Stat(plain.size.toString, "pages"),
            Stat(diagrams.size.toString, "diagrams"),
            Stat(languages.size.toString, "languages"),
          ) ++ locStats(ctx.loc),
          actions = actions,
          mark = forAll,
        ),
      ) +
        Kit.main((sections :+ diagramSection)*) +
        Kit.footer(ctx.sites, s"Pages of $proofRepo at $short. Served by nix-os from /nix/store, on piabrota2.", SiteName.Proof.id),
    )

  def pirsigIndex(m: Manifest, ctx: Context): String =
    val short = ctx.rev.take(7)
    val notes = m.pages.filter(_.group == Layout.videos)
    val figures = m.pages.filter(_.group == Layout.figures)
    // The page says how many videos it indexes; the card repeats it only when the page said it.
    val noteCards = notes.map { p =>
      val line = m.videos.filter(_ => p.path == Layout.videosIndex)
        .fold("")(n => s"$n ${if n == 1 then "vídeo indexado" else "vídeos indexados"}")
      pageCard(p, List(langPill(p.lang)), line)
    }
    val stats = m.videos.map(n => Stat(n.toString, if n == 1 then "video note" else "video notes")).toList :+
      Stat(figures.size.toString, "figures")

    Kit.page(
      ctx.css,
      title = "pirsig · piabrota",
      description = s"The video notes and the archify figures of $pirsigRepo, the second brain.",
      modules = modules,
      icons = ctx.icons,
      body = Kit.top(
        Kit.chrome(SiteName.Pirsig.id, ctx.sites),
        Kit.hero(
          eyebrow = "piabrota.art · pirsig",
          title = "pirsig",
          tail = "· a second brain",
          lede = s"The brain: smart notes, PARA and the track record of decisions. The video notes and the figures of $pirsigRepo, built from a pinned commit. The figures open dark.",
          stats = stats,
          mark = noteNet,
          actions = List(
            Action(s"$pirsigRepo ↗", github(pirsigRepo), Variant.Primary),
            Action(short, s"${github(pirsigRepo)}/tree/${ctx.rev}", Variant.Mono),
          ),
        ),
      ) +
        Kit.main(
          Kit.section(id = "videos", title = "Video notes", count = Some(notes.size), note = "brain/Videos/", body = Kit.cardGrid(noteCards)),
          Kit.section(id = "figures", title = "Figures", count = Some(figures.size), note = "docs/archify/",
            body = Kit.cardGrid(figures.map(p => pageCard(p, List(langPill(p.lang)))))),
        ) +
        Kit.footer(ctx.sites, s"Pages of $pirsigRepo at $short. Served by nix-os from /nix/store, on piabrota2. archify draws the figures.", SiteName.Pirsig.id),
    )

  private val usage = "usage: proof-index <proof|pirsig> <manifest.json> --rev <commit> --sites <sites.json> --icons <html> [--loc <loc.json>]"

  def run(args: List[String]): Int = args match
    case site :: manifest :: rest =>
      // `--name value` pairs; the last of a name wins.
      val f = Flags.parse(rest)
      val (rev, sites) = (f.last("rev"), f.last("sites")) match
        case (Some(r), Some(s)) => (r, Site.parseAll(readJson(s)).fold(e => die(s"$s: $e"), identity))
        case _ => die(usage)
      val css = Css.locate(env(Css.envVar), os.pwd).fold(die(_), identity)
      val loc = f.last("loc").map(l => LocCount.parse(readJson(l)).fold(e => die(s"$l: $e"), identity)).getOrElse(Nil)
      val ctx = Context(css, rev, sites, f.last("icons").getOrElse(""), loc)
      val m = Manifest.parse(readJson(manifest)).fold(e => die(s"$manifest: $e"), identity)
      SiteName.parse(site) match
        case Some(SiteName.Proof)  => print(proofIndex(m, ctx))
        case Some(SiteName.Pirsig) => print(pirsigIndex(m, ctx))
        case None                  => die(usage)
      0
    case _ => die(usage)

  private def readJson(file: String): ujson.Value = ujson.read(os.read(os.Path(file, os.pwd)))
