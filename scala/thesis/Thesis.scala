package piabrota.thesis

import piabrota.lib.{Exit, env}

/** `thesis <command> ...`: the toolkit of the wave-forecaster-thesis rig (docs/THESIS.md). A project
  * is a folder of JSON, markdown and BibTeX (projects/<slug>/); the sections are written one by one
  * by writer seats and checked by four gates; the PDF is built with pandoc and a pinned LaTeX
  * template. No network, no model.
  */
object Thesis:
  val Usage: String =
    """thesis: a final project for the Escola Politécnica of UFRJ, written in independent sections.
      |
      |Editor:
      |  thesis new <slug> [--template forecast-energy-demand]   a project folder and a thesis.json to fill
      |  thesis sections [<slug>]                                the sections and their status (no slug: the projects)
      |  thesis status <slug>                                    one screen: status, rounds, sources, what blocks assemble
      |
      |Writer (one section at a time):
      |  thesis fetch <slug> [<id>] [--as <seat>]                claim the next todo section, print the work order
      |  thesis release <slug> <id> [--as <seat>]                free a claim
      |  thesis build-section <slug> <id>                        the LaTeX fragment and a one-section preview PDF
      |  thesis submit <slug> <id> [--as <seat>]                 build, lint, cite-check, slop, readability; then drafted
      |
      |Reviewer (no model, no network):
      |  thesis lint <slug> <id>                                 the rules of the markdown, characters, labels, length
      |  thesis readability <slug> <id>                          gate 1: human readable pt-BR
      |  thesis slop <slug> <id>                                 gate 2: surface patterns of model-written text
      |  thesis ufrj-check <slug>                                gate 3: the UFRJ patterns, PASS, FAIL or CANNOT-CHECK
      |  thesis cite-check <slug> [<id>]                         gate 4: sources fetched, verified, recorded
      |  thesis cite-score <slug> <id>                           the share of sentences with a citation mark
      |  thesis review-report <slug> <id|final>                  every gate on one section, or on the whole work, to review/
      |  thesis verdict <slug> <id> accept|revise --by <seat> [--note <file>]
      |
      |Build and hand-over:
      |  thesis assemble <slug>                                  every section accepted, then the PDF and pdf-qa
      |  thesis pdf-qa <slug>                                    A4, fonts, ??, margins, titles in order: build/qa.json
      |  thesis publish <slug> [--replace]                       thesis.pdf, qa.json, REFERENCES.md, review/ to the outbox
      |
      |Folders: THESIS_HOME (projects/<slug>/, out/<slug>/), THESIS_OUTBOX. A seat name comes from --as, THESIS_SEAT,
      |or the member folder you stand in. See docs/THESIS.md.
      |""".stripMargin

  /** The programs the toolkit still calls by name, checked once at start. */
  private val Tools = List("pandoc", "pdflatex", "pdfinfo", "pdftotext", "pdffonts", "pdftohtml", "timeout", "nice",
    "sha256sum", "date")

  private def command(cmd: Cmd): (Kit, List[String]) => Int = cmd match
    case Cmd.New          => ProjectCommands.newProject
    case Cmd.Sections     => ProjectCommands.sections
    case Cmd.Status       => ProjectCommands.status
    case Cmd.Fetch        => ProjectCommands.fetch
    case Cmd.Release      => ProjectCommands.release
    case Cmd.BuildSection => BuildCommands.buildSection
    case Cmd.Submit       => ProjectCommands.submit
    case Cmd.Lint         => Lint.run
    case Cmd.Readability  => Readability.run
    case Cmd.Slop         => Slop.run
    case Cmd.UfrjCheck    => Ufrj.run
    case Cmd.CiteCheck    => CiteCheck.run
    case Cmd.CiteScore    => CiteScore.run
    case Cmd.ReviewReport => ProjectCommands.reviewReport
    case Cmd.Verdict      => ProjectCommands.verdict
    case Cmd.Assemble     => BuildCommands.assemble
    case Cmd.PdfQa        => BuildCommands.pdfQa
    case Cmd.Publish      => BuildCommands.publish

  def run(args: List[String]): Int =
    val config = Config.fromEnv(env, Kit.selfExe).fold(message => throw Exit(1, message), identity)
    BuildCommands.needTools(Tools*)
    val profile = Profile.from(ujson.read(os.read(config.share / Names.ProfileJson)))
    val tmp = Kit.tempDir(config.tmpRoot, "thesis.").getOrElse(fail("cannot make a temporary folder"))
    val k = Kit(config, profile, tmp)
    try
      args match
        case Nil =>
          print(Usage)
          2
        case ("help" | "-h" | "--help") :: _ =>
          print(Usage)
          0
        case name :: rest =>
          Cmd.parse(name) match
            case Some(c) => command(c)(k, rest)
            case None =>
              System.err.print(Usage)
              fail(s"unknown command: $name")
    finally
      System.out.flush()
      k.cleanup()
