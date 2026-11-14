package piabrota.reels

import Json.*

/** The screenplay, its lint and the gate of every command that makes a picture, a sound or a file. */
object Gate:
  def checkSlug(slug: String): Unit =
    if !slug.matches("[a-z0-9-]+") || slug.startsWith("-") then
      fail(s"slug: lowercase letters, digits and - only, and no - first (got: $slug)")
    if slug.length > 41 then fail("slug: at most 41 characters")

  /** A path to a .json file names a screenplay file; anything else is a slug. */
  def isFileArg(arg: String): Boolean = arg.endsWith(".json")

  /** Where the screenplay is: a path to a .json file is used as it is (lint, view and timing work
    * on any file); a slug means the project folder.
    */
  def spPath(tk: Toolkit, arg: String): os.Path =
    if isFileArg(arg) then
      val p = os.Path(arg, os.pwd)
      if !os.isFile(p) then fail(s"no such file: $arg")
      p
    else
      checkSlug(arg)
      val p = tk.project(arg).screenplay
      if !os.isFile(p) then fail(s"no screenplay for $arg: $p (reel new $arg <15|30>)")
      p

  def validJson(file: os.Path, shown: String = ""): Unit =
    if !Json.valid(file) then fail(s"${if shown.isEmpty then file.toString else shown} is not valid JSON")

  /** The findings of the screenplay lint. It fails closed: a file that the rules cannot read is an
    * error, never a pass.
    */
  def lint(tk: Toolkit, sp: os.Path): Seq[Finding] =
    rules(sp, "lint", "the rules cannot read this file")(Lint.screenplay(_, tk.profile.json, tk.styles))

  /** The findings of the shotlist. The screenplay must be sound (its lint passes). */
  def shotlistLint(tk: Toolkit, sp: os.Path, shot: os.Path): Seq[Finding] =
    val spJson = Json.readFile(sp).getOrElse(fail(s"cannot read $sp"))
    val st = style(tk, sp)
    val hash = tk.sha(sp)
    rules(shot, "shotlist", "the rules cannot read the shotlist")(Lint.shotlist(_, spJson, st, tk.profile.json, hash))

  /** The rules on each value of the file. More than one value, or a value they cannot read, is the
    * one finding that the file is unreadable, with the error of each value they could not read.
    */
  private def rules(file: os.Path, rule: String, why: String)(check: Jv => Seq[Finding]): Seq[Finding] =
    val docs = Json.readDocs(file).getOrElse(Vector.empty)
    val results = docs.map(d => try Right(check(d.value)) catch case JqError(msg) => Left(s"jq: error (at $file:${d.line}): $msg"))
    val errors = results.collect { case Left(e) => e }
    results match
      case Vector(Right(fs)) => fs
      case _                 => Finding.unreadable(rule, s"$why: ${errors.mkString("\n")}")

  /** One line a finding, then the count; the second value is false when there is an error. */
  def findings(fs: Seq[Finding]): (String, Boolean) =
    val lines = fs.map { f =>
      val level = if f.level == Level.Error then "ERROR" else "warn "
      printable(s"$level  ${f.beat}  [${f.rule}]  ${f.msg}")
    }
    val errors = fs.count(_.level == Level.Error)
    val warnings = fs.count(_.level == Level.Warn)
    ((lines :+ s"lint: $errors error(s), $warnings warning(s)").mkString("\n"), errors == 0)

  /** The first line of an approval: the hash of the screenplay and its name, as sha256sum writes it. */
  def approvalLine(hash: String): String = s"$hash  ${Name.Screenplay}"

  /** The slug a screenplay file says it is for. */
  def slugIn(file: os.Path): Option[String] = Json.readFile(file).map(Screenplay.from(_).slug)

  /** The gate of every command that makes a picture, a sound or a file in out/. It reads the
    * screenplay and its approval now, at the time of use: nothing is cached from an earlier run.
    * It refuses when
    *   - screenplay.json or screenplay.approved is missing, or is a link;
    *   - the first line of the approval is not exactly "<sha256 of screenplay.json>  screenplay.json"
    *     (lower case; another case, a short hash or another name does not match);
    *   - the lint of the screenplay fails (a hand-written approval does not skip the rules);
    *   - the slug in the file is not the folder's.
    */
  def requireApproved(tk: Toolkit, slug: String): Approved =
    checkSlug(slug)
    val dir = tk.project(slug)
    val spf = dir.screenplay
    if !plainFile(spf) then fail(s"no screenplay for $slug (a missing file or a link): $spf")
    if !plainFile(dir.approval) then fail(s"the screenplay of $slug is not approved: run reel lint $slug, then reel approve $slug")
    val sp = tk.tmp / Name.Screenplay
    try os.copy.over(spf, sp)
    catch case _: java.io.IOException => fail(s"cannot read $spf")
    val hash = tk.sha(sp)
    if firstLine(dir.approval) != approvalLine(hash) then
      fail(s"screenplay.json of $slug changed after its approval, or the approval is not in the form of reel approve (now ${hash.take(8)}): the creative director fixes it, then lint and approve again")
    if !Json.valid(sp) then fail(s"screenplay.json of $slug is not valid JSON")
    val (out, ok) = findings(lint(tk, sp))
    if !ok then
      System.err.println(out)
      fail(s"the lint of $slug fails: the approval does not count")
    if slugIn(sp) != Some(slug) then fail(s"the slug in screenplay.json is not $slug")
    Approved(slug, dir, sp, hash)

  /** The first line of a file, without its line break (`head -n 1`). */
  private def firstLine(file: os.Path): String =
    new String(os.read.bytes(file).takeWhile(_ != '\n'), "UTF-8")

  /** The style of the screenplay, with its palette overrides (`look.palette`) merged into its colours. */
  def style(tk: Toolkit, sp: os.Path): Jv =
    val name = Json.readFile(sp).map(Screenplay.from(_).style).getOrElse("null")
    if name.isEmpty || name == "null" || !name.matches("[a-z0-9-]+") then fail(s"no style: $name")
    val file = tk.styleFile(name)
    if !os.isFile(file) then fail(s"no style $name")
    val first = Json.readDocs(sp).flatMap(_.headOption).fold(Jv.Null)(_.value)
    Json.readFile(file).flatMap { s =>
      try Some(s * Jv.obj("colors" -> alt(first("look")("palette"), Jv.EmptyObj)))
      catch case _: JqError => None
    }.getOrElse(fail(s"no style $name"))

  /** The gate, then the screenplay, its style, its frame plan and its shotlist. */
  def load(tk: Toolkit, slug: String): Project =
    val a = requireApproved(tk, slug)
    val spJson = Json.readFile(a.sp).getOrElse(fail(s"screenplay.json of $slug is not valid JSON"))
    val st = style(tk, a.sp)
    val plan =
      try Frames.timeline(spJson, tk.profile.json)
      catch
        case JqError(msg) =>
          System.err.println(s"jq: error (at ${a.sp}:1): $msg")
          fail(s"cannot plan the frames of $slug")
    val shots = tk.tmp / Name.Shotlist
    val sf = a.dir.shotlist
    val shotsSha =
      if present(sf) then
        if !plainFile(sf) then fail(s"the shotlist is a link or not a file: $sf")
        try os.copy.over(sf, shots)
        catch case _: java.io.IOException => fail(s"cannot read $sf")
        tk.sha(shots)
      else
        os.remove(shots)
        Project.NoShotlist
    a.dir.workDirs.foreach(os.makeDir.all(_))
    tk.setupFonts()
    val shotsJson = if os.isFile(shots) then Json.readFile(shots).getOrElse(Jv.Null) else Jv.Null
    Project(a, spJson, Screenplay.from(spJson), st, plan, shots, shotsJson, shotsSha)

  /** The creative director's shotlist must exist, be valid and be made for this screenplay. */
  def requireShotlist(tk: Toolkit, p: Project): Unit =
    if !p.hasShots then
      fail(s"no shotlist: the creative director runs reel shotlist ${p.slug}, then edits direction/shotlist.json")
    validJson(p.shots)
    val (out, ok) = findings(shotlistLint(tk, p.sp, p.shots))
    if !ok then
      System.err.println(out)
      fail(s"the shotlist fails its lint (reel lint ${p.slug})")

  /** The shot of a beat in the shotlist, or the empty one. */
  def shotOf(p: Project, id: String): Shot =
    if !p.hasShots then Shot.Empty
    else p.shotsJson.at("shots").iterOpt.find(_.at("beat") === Jv.Str(id)).fold(Shot.Empty)(Shot.from)
