package piabrota.repo

/** `piabrota deepwiki-check [file]`: .devin/wiki.json against DeepWiki's rules. Prints what is
  * wrong and exits 1, or prints nothing. CI runs it; it replaced scripts/deepwiki-check.jq.
  */
object DeepWikiCheck:
  val defaultFile = ".devin/wiki.json"

  def run(args: List[String]): Int =
    val file = args match
      case Nil         => defaultFile
      case List(path)  => path
      case _           => piabrota.lib.die("usage: piabrota deepwiki-check [wiki.json]", 2)
    problems(parse(ujson.read(os.read(os.Path(file, os.pwd))))) match
      case Nil => 0
      case found => System.err.println(found.mkString("\n")); 1

  def parse(json: ujson.Value): WikiPlan =
    val obj = json.obj
    def notes(v: Option[ujson.Value]) =
      v.flatMap(_.arrOpt).toList.flatten.map(n => Note(n.obj.get("content").flatMap(_.strOpt).getOrElse("")))
    WikiPlan(
      repoNotes = obj.get("repo_notes").map(v => notes(Some(v))),
      pages = obj.get("pages").map(_.arr.toList.map { p =>
        val o = p.obj
        def text(key: String) = o.get(key).flatMap(_.strOpt).getOrElse("")
        Page(text("title"), text("purpose"), o.get("parent").flatMap(_.strOpt),
          notes(o.get("page_notes")), p)
      }),
    )

  /** Every rule that the plan breaks, in the order of the old jq program. */
  def problems(plan: WikiPlan): List[String] =
    val pages = plan.pages.getOrElse(Nil)
    val titles = pages.map(_.title)
    val notes = plan.notes
    List(
      Option.when(plan.repoNotes.isEmpty)("repo_notes is missing (use [] for none)"),
      Option.when(pages.isEmpty)("pages must list at least one page"),
      Option.when(pages.size > WikiLimits.maxPages)(s"${pages.size} pages: at most ${WikiLimits.maxPages}"),
    ).flatten ++
      pages.filter(p => p.title.isEmpty || p.purpose.isEmpty).map(p => s"a page needs a title and a purpose: ${ujson.write(p.raw)}") ++
      titles.groupBy(identity).toList.sortBy(_._1).collect { case (t, ts) if ts.size > 1 => s"duplicate page title: $t" } ++
      pages.flatMap(p => p.parent.filterNot(titles.contains).map(parent => s"page ${p.title}: parent $parent is not a page")) ++
      Option.when(notes.size > WikiLimits.maxNotes)(s"${notes.size} notes: at most ${WikiLimits.maxNotes}").toList ++
      notes.map(n => n.content.codePointCount(0, n.content.length)).filter(_ > WikiLimits.maxNoteLength)
        .map(n => s"a note has $n characters: at most ${WikiLimits.maxNoteLength}")
