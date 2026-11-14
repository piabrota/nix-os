package piabrota.reels

import piabrota.lib.Exit

/** The commands that read the screenplay and open the gate. */
object Screenplays:
  def create(tk: Toolkit, args: List[String]): Int =
    if args.length < 2 || args.length > 3 then fail("usage: reel new <slug> <15|30> [--example]")
    val example = args.length == 3
    if example && args(2) != "--example" then fail(s"unknown option: ${args(2)}")
    val List(slug, fmt) = args.take(2): @unchecked
    Gate.checkSlug(slug)
    if !Format.Seconds.contains(fmt) then fail("format: 15 or 30 seconds")
    val proj = tk.project(slug).root
    if present(proj) then fail(s"the project exists: $proj")
    // Built in a staging folder and moved into place with one rename: a failure leaves no half
    // project that "the project exists" would then refuse to replace. A slug never starts with a dot.
    val stage = ProjectDir(tk.cfg.projects / s".new-$slug")
    os.remove.all(stage.root)
    try
      stage.newDirs.foreach(os.makeDir.all(_))
      os.makeDir.all(tk.out(slug).root)
    catch case _: java.io.IOException => fail(s"cannot make $proj")
    if example then
      val dir = ProjectDir(tk.cfg.example(fmt))
      val text = Json.readDocs(dir.screenplay).flatMap { docs =>
        try Some(docs.map(d => Json.pretty(Drafts.example(d.value, slug)) + "\n").mkString)
        catch case _: JqError => None
      }.getOrElse(fail("cannot copy the example"))
      os.write(stage.screenplay, text)
      glob(dir.root / "svg", "", ".svg").foreach(f => os.copy(f, stage.svg / f.last))
      os.write(stage.brief,
        s"""# Brief: $slug
           |
           |This project starts from the example screenplay of the toolkit (`reel new $slug $fmt --example`).
           |It is a sample, not a client brief.
           |""".stripMargin)
    else
      val format = Json.literal(fmt).getOrElse(fail("cannot write the skeleton"))
      os.write(stage.screenplay, Json.pretty(Drafts.skeleton(slug, format)) + "\n")
      os.write(stage.brief, brief)
    try os.move(stage.root, proj)
    catch case _: java.io.IOException => fail(s"cannot move the project into place: $proj")
    say(s"new project: $proj")
    say(s"next: the creative director fills screenplay.json, then: reel lint $slug")
    0

  private val brief =
    """# Brief
      |
      |## Audience
      |Who watches, and where (in the feed, with the sound off, on a phone).
      |
      |## Promise
      |What the viewer has after 15 or 30 seconds, in one sentence.
      |
      |## Constraint
      |What the reel must not say or show. The format, the language, the look.
      |
      |## Sources
      |Every fact the reel states, with its source. Write `own` for what is the author's own claim.
      |""".stripMargin

  def lint(tk: Toolkit, args: List[String]): Int =
    if args.length != 1 then fail("usage: reel lint <slug|file.json>")
    val arg = args.head
    val sp = Gate.spPath(tk, arg)
    Gate.validJson(sp, arg)
    val (out, ok) = Gate.findings(Gate.lint(tk, sp))
    say(out)
    // A project with a shotlist: its lint too, when the screenplay itself is sound.
    val shot = Option.when(!Gate.isFileArg(arg))(tk.project(arg).shotlist).filter(os.isFile(_))
    val pass = shot.fold(ok) { shot =>
      Gate.validJson(shot)
      if ok then
        val (sout, sok) = Gate.findings(Gate.shotlistLint(tk, sp, shot))
        say("shotlist:")
        say(sout)
        sok
      else
        say("shotlist: not checked (the screenplay fails)")
        ok
    }
    say(if pass then "lint: PASS" else "lint: FAIL")
    if pass then 0 else 1

  /** A view of each value of the file, without control characters. A value that the view cannot
    * read gets its error line and what was written before it; the command does not fail for it.
    */
  private def view(sp: os.Path)(program: (Jv, String => Unit) => Unit): String =
    val printed = Views.each(Json.readDocs(sp).getOrElse(Vector.empty), sp.toString)(program)
    printed.err.foreach(System.err.println)
    printable(printed.out)

  def screenplayView(tk: Toolkit, args: List[String]): Int =
    if args.length != 1 then fail("usage: reel screenplay-view <slug|file.json>")
    val sp = Gate.spPath(tk, args.head)
    Gate.validJson(sp, args.head)
    print(view(sp)(Views.screenplay))
    0

  def timingReport(tk: Toolkit, args: List[String]): Int =
    if args.length != 1 then fail("usage: reel timing-report <slug|file.json>")
    val sp = Gate.spPath(tk, args.head)
    Gate.validJson(sp, args.head)
    val out = view(sp)(Views.timing(_, tk.profile.json, _)).stripSuffix("\n")
    say(out)
    if out.contains("result: FAIL") then 1 else 0

  def approve(tk: Toolkit, args: List[String]): Int =
    if !(args.length == 1 || (args.length == 3 && args(1) == "--by")) then
      fail("usage: reel approve <slug> [--by <name>]")
    val slug = args.head
    val by = args.lift(2).filter(_.nonEmpty).getOrElse("unnamed")
    if !by.matches("[A-Za-z0-9._@ -]+") then fail("--by: letters, digits, space and . _ @ - only")
    if by.length > 60 then fail("--by: at most 60 characters")
    Gate.checkSlug(slug)
    val proj = tk.project(slug)
    if !plainFile(proj.screenplay) then fail(s"no screenplay for $slug (a missing file or a link)")
    // One copy is linted and hashed, so the hash is the one of the text that passed.
    val copy = tk.tmp / "approve.json"
    try os.copy.over(proj.screenplay, copy)
    catch case _: java.io.IOException => fail("cannot read the screenplay")
    Gate.validJson(copy)
    val (out, ok) = Gate.findings(Gate.lint(tk, copy))
    say(out)
    if !ok then fail("the lint fails: the screenplay is not approved")
    if Gate.slugIn(copy) != Some(slug) then fail(s"the slug in screenplay.json is not $slug")
    val h = tk.sha(copy)
    val now = java.time.format.DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss'Z'")
      .withZone(java.time.ZoneOffset.UTC).format(java.time.Instant.now())
    os.write.over(Name.part(proj.approval), s"${Gate.approvalLine(h)}\napproved $now by $by\n")
    os.move(Name.part(proj.approval), proj.approval, replaceExisting = true)
    say(s"approved: $slug (sha256 $h)")
    0

  /** The default shotlist, for the creative director to refine. */
  def shotlist(tk: Toolkit, args: List[String]): Int =
    if args.isEmpty || args.length > 2 then fail("usage: reel shotlist <slug> [--force]")
    val force = args.length == 2
    if force && args(1) != "--force" then fail(s"unknown option: ${args(1)}")
    val a = Gate.requireApproved(tk, args.head)
    val dest = a.dir.shotlist
    if os.exists(dest) && !force then fail(s"$dest exists: edit it, or use --force to start again")
    os.makeDir.all(a.dir.direction)
    val style = Gate.style(tk, a.sp)
    val docs = Json.readDocs(a.sp).getOrElse(Vector.empty)
    val text = docs.map { d =>
      try Json.pretty(Drafts.shotlist(d.value, style, a.hash)) + "\n"
      catch
        case JqError(msg) =>
          System.err.println(s"jq: error (at ${a.sp}:${d.line}): $msg")
          throw Exit(5)
    }.mkString
    val part = Name.part(dest)
    os.write.over(part, text)
    os.move(part, dest, replaceExisting = true)
    say(s"wrote $dest")
    0
