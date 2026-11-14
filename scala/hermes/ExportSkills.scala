package piabrota.hermes

import piabrota.lib.{Sh, env}
import SkillsRepo.{SkillFile, Tag}

/** `export-skills`: exports the skills that Hermes loads to piabrota/skills and opens or updates a
  * PR. The skills-export cron job of Hermes runs it once a day (HERMES_HOME/scripts/export-skills.sh).
  * It prints nothing when there is nothing to do.
  *
  * Environment (all optional):
  *   SKILLS_DIR   the skills of Hermes          ($HOME/.hermes/skills)
  *   HERMES_HOME  the home of Hermes            ($HOME/.hermes)
  *   REPO_DIR     a clone of piabrota/skills    (/var/lib/hermes/workspace/skills-src)
  *   TOKEN_FILE   the GitHub token file         (/run/hermes-github/piabrota)
  *   REPO         the GitHub repository         (piabrota/skills)
  *   DRY_RUN      1 = no git push and no gh call; print what would happen
  *   OUT_PATCH    a file path: write the commit there as a patch
  */
object ExportSkills:
  def run(args: List[String]): Int =
    val job = CronJob("skills export", Seq(Tool.Git, Tool.Gh, Tool.Date),
      CronEnv.read(sys.env.getOrElse("PATH", ""), env))
    val cfg = SkillsConfig.read(env)
    val runEnv = job.env(job.token(cfg.tokenFile, cfg.repo))
    val found = findSkills(job.steps, cfg.skillsDir, cfg.hermesHome)
    if found.skills.isEmpty then job.steps.quit(0)
    Export(job, cfg, runEnv, found).run()
    0

  // ---------------------------------------------------------------- Step 2
  private val nameRe = "[A-Za-z0-9][A-Za-z0-9._-]*".r

  /** Every skill that Hermes loads and that the owner wrote or changed for it: source A (the skills
    * directory), B (the skills of plugins) and C (the external directories of nix-os). A second
    * skill with a name that is taken already is a duplicate.
    */
  def findSkills(steps: Steps, skillsDir: os.Path, hermesHome: os.Path): Found =
    steps.step = "find the skills of Hermes"
    if !os.isDir(skillsDir) then steps.fail("no skills directory")
    val found = sourceA(skillsDir) ++ sourceB(hermesHome / "plugins") ++ sourceC(hermesHome / "config.yaml")
    val own = found.filter(_.origin.isOwn)
    // The name builds a path that is removed later: keep it plain.
    own.find(s => !nameRe.matches(s.name)).foreach(s => steps.fail(s"bad skill name: ${s.name}"))
    Found.of(own)

  /** The SKILL.md files under a directory, sorted by path as `sort -z` in the C locale sorts them. */
  private def sorted(paths: Iterable[os.Path]): List[os.Path] = paths.toList.sortBy(_.toString)

  private def sourceA(skillsDir: os.Path): List[Skill] =
    val manifest = skillsDir / ".bundled_manifest"
    // Bundled skills: lines "name:hash".
    val bundled =
      if os.isFile(manifest) then os.read.lines(manifest).map(_.takeWhile(_ != ':')).toSet else Set.empty[String]
    val hub = hubSkills(skillsDir / ".hub" / "lock.json")
    val files = os.walk(skillsDir, followLinks = false)
      .filter(p => p.last == SkillFile && os.isFile(p, followLinks = false))
      // Leave out a path with a component that starts with a dot.
      .filter(p => !p.relativeTo(skillsDir).segments.exists(_.startsWith(".")))
    sorted(files).map(_ / os.up).filter(_ != skillsDir).map { dir =>
      val origin =
        if bundled(dir.last) then Origin.Bundled
        else if hub(dir.last) then Origin.Hub
        else Origin.MadeHere
      Skill(dir.last, dir, origin)
    }

  /** Hub skills: the keys of `.installed`, or the top-level keys. An odd shape gives none. */
  private def hubSkills(lock: os.Path): Set[String] =
    if !os.isFile(lock) then Set.empty
    else
      scala.util.Try(ujson.read(os.read(lock))).toOption.flatMap(_.objOpt).map { top =>
        top.get("installed").flatMap(_.objOpt).getOrElse(top).keySet.toSet
      }.getOrElse(Set.empty)

  /** Source B: <plugins>/<plugin>/skills/<name>/SKILL.md. The plugins are symlinks. */
  private def sourceB(plugins: os.Path): List[Skill] =
    val files = for
      plugin <- if os.isDir(plugins) then os.list(plugins) else Nil
      skills = plugin / "skills" if os.isDir(skills)
      dir <- os.list(skills) if os.isFile(dir / SkillFile)
    yield dir / SkillFile
    sorted(files).map { f =>
      val dir = f / os.up
      val plugin = (dir / os.up / os.up).last.stripPrefix("nix-managed-")
      Skill(dir.last, dir, Origin.Plugin(plugin))
    }

  private val storeHash = "[a-z0-9]{32}-(.+)".r

  /** Source C: <external dir>/<name>/SKILL.md (or one level deeper), for each store path in the
    * external_dirs block of config.yaml, as a list or an inline [a, b].
    */
  private def sourceC(config: os.Path): List[Skill] =
    val dirs = if os.isFile(config) then externalDirs(os.read.lines(config)) else Nil
    dirs.map(_.stripSuffix("]").stripSuffix("/")).map(os.Path(_)).filter(os.isDir(_)).flatMap { d =>
      val base = d.last match
        case storeHash(name) => name
        case other           => other
      val files = for
        a <- os.list(d) if os.isDir(a)
        f <- (a / SkillFile) :: os.list(a).filter(os.isDir(_)).map(_ / SkillFile).toList if os.isFile(f)
      yield f
      sorted(files).map(f => Skill((f / os.up).last, f / os.up, Origin.NixOs(base)))
    }

  /** The store paths in the lines of the external_dirs block, without a repeat. */
  def externalDirs(lines: Seq[String]): List[String] =
    var inBlock = false
    val block = lines.filter { line =>
      if line.contains("external_dirs:") then inBlock = true
      if inBlock && line.nonEmpty && line(0) != ' ' && line(0) != '-' then inBlock = false
      inBlock
    }
    block.flatMap("""/nix/store/[^ ,"]*""".r.findAllIn(_)).distinct.toList

  // ---------------------------------------------------------------- Front matter
  private val keyLine = "(?s)([A-Za-z][A-Za-z0-9_-]*):.*".r

  /** The front matter of a file and what follows it: the lines between a first line "---" and the
    * next line that is "---", the closing line, and the rest. None when there is no front matter.
    */
  def frontMatter(text: String): Option[FrontMatter] =
    if !text.startsWith("---\n") then None
    else
      val body = text.drop(4)
      // The closing line starts the body or follows a newline, and ends with a newline or the text.
      val starts = Iterator.single(0) ++ body.indices.iterator.filter(body(_) == '\n').map(_ + 1)
      starts.find(i => body.startsWith("---", i) && (i + 3 == body.length || body(i + 3) == '\n')).map { i =>
        val close = if i + 3 == body.length then "---" else "---\n"
        FrontMatter(body.take(i), close, body.drop(i + close.length))
      }

  /** Keeps only the keys of the Agent Skills format in the front matter, sets name to the name of
    * the directory and adds disable-model-invocation. The body stays byte for byte. Left: why not.
    */
  def normalize(text: String, name: String): Either[String, String] =
    frontMatter(text) match
      case None => Left(s"$name has no front matter")
      case Some(FrontMatter(fm, close, rest)) =>
        // A key line starts a block; its continuation lines follow it.
        val blocks = Util.linesKeep(fm).foldLeft(Vector.empty[(String, String)]) { (acc, line) =>
          line match
            case keyLine(key) => acc :+ (key -> line)
            case _ if acc.nonEmpty => acc.init :+ (acc.last._1 -> (acc.last._2 + line))
            case _ => acc
        }
        var hasName = false
        var hasDescription = false
        val kept = blocks.flatMap { (key, text) =>
          if !SkillsRepo.AgentSkillsKeys(key) then None
          else if key == "name" then
            if hasName then None else { hasName = true; Some(s"name: $name\n") }
          else if key == "description" then
            if hasDescription then None else { hasDescription = true; Some(text + "disable-model-invocation: true\n") }
          else Some(text)
        }
        if !hasDescription then Left(s"$name has no description")
        else Right("---\n" + (if hasName then "" else s"name: $name\n") + kept.mkString + close + rest)

  /** The value of a key in the front matter, or "not stated". */
  def field(text: String, key: String): String =
    val value = frontMatter(text).fold("") { fm =>
      val lines = fm.head.split("\n").toList
      val start = lines.indexWhere(l => keyLine.matches(l) && l.takeWhile(_ != ':') == key)
      if start < 0 then ""
      else
        val first = lines(start).dropWhile(_ != ':').drop(1).dropWhile(c => c == ' ' || c == '\t').strip
        val more = lines.drop(start + 1).takeWhile(l => !keyLine.matches(l))
          .filter(l => (l.startsWith(" ") || l.startsWith("\t")) && l.strip.nonEmpty).map(_.strip)
        (first :: more).mkString(" ")
    }
    val unfolded = value.replaceFirst("^[>|][+-]?\\s*", "")
    val unquoted =
      if unfolded.length >= 2 && (unfolded.head == '"' || unfolded.head == '\'') && unfolded.last == unfolded.head
      then unfolded.drop(1).dropRight(1)
      else unfolded
    val clean = unquoted.replaceAll("[|\r\n]", "").strip
    if clean.isEmpty then "not stated" else clean

  // ---------------------------------------------------------------- www/tags.txt
  private val onlyTag = s"\\S+: $Tag\\s*".r
  private val tagWord = s" $Tag"

  /** tags.txt without the tag hermes-skill: a line with only that tag goes, and the tag leaves the
    * other lines.
    */
  def untag(text: String): String =
    Util.linesKeep(text).filterNot(l => onlyTag.matches(l.stripSuffix("\n"))).map { l =>
      val out = StringBuilder()
      var i = 0
      while i < l.length do
        if l.startsWith(tagWord, i) && i + tagWord.length < l.length && l(i + tagWord.length).isWhitespace then
          i += tagWord.length
        else { out += l(i); i += 1 }
      out.toString
    }.mkString

  /** tags.txt with the tag hermes-skill on the line of each name, and a new line for a name that
    * has none.
    */
  def tag(text: String, names: Seq[String]): String =
    val lines = Util.linesKeep(text).toVector
    val tagged = names.foldLeft(lines) { (lines, name) =>
      if !lines.exists(_.startsWith(s"$name:")) then
        val ended = if lines.nonEmpty && !lines.last.endsWith("\n") then lines.init :+ (lines.last + "\n") else lines
        ended :+ s"$name: $Tag\n"
      else
        lines.map { l =>
          if !l.startsWith(s"$name:") then l
          else
            val tags = l.stripSuffix("\n").dropWhile(_ != ':').drop(1).trim.split("\\s+")
            if tags.contains(Tag) then l else l.replaceAll("\\s+$", "") + s"$tagWord\n"
        }
    }
    tagged.mkString

  // ---------------------------------------------------------------- Secrets
  private val secretPatterns = List(
    "gh[pousr]_([A-Za-z0-9]{20,})",
    "github_pat_[A-Za-z0-9_]{20,}",
    "sk-ant-[A-Za-z0-9_-]{10,}",
    "sk-[A-Za-z0-9]{32,}",
    "-----BEGIN [A-Z ]*PRIVATE KEY-----",
    "AKIA[0-9A-Z]{16}",
    "xox[abprs]-[A-Za-z0-9-]{10,}",
    "(TOKEN|SECRET|PASSWORD|API_KEY|PRIVATE_KEY)[A-Z_]*[=:] *[\"']?[A-Za-z0-9_+/=-]{20,}",
    "eyJ[A-Za-z0-9_-]{20,}\\.[A-Za-z0-9_-]{20,}\\.[A-Za-z0-9_-]{10,}",
  ).map(_.r)
  // A match that is plainly a placeholder (xxxx, ..., your-..., example) is not a secret.
  private val placeholder = "(?i):[^:]*(x{4,}|\\.\\.\\.|your-|example|changeme|placeholder|<)".r

  /** The first finding, as `<file>:<line> (<pattern number>)`, never the text. */
  def scanSecrets(root: os.Path, base: os.Path): Option[String] =
    val files = if os.isDir(root) then os.walk(root, followLinks = false).filter(os.isFile(_, followLinks = false)).sortBy(_.toString) else Nil
    // Text files only, as grep -I reads them.
    val texts = files.map(f => f -> os.read.bytes(f)).filterNot(_._2.contains(0.toByte))
      .map((f, b) => f -> String(b, java.nio.charset.StandardCharsets.UTF_8))
    secretPatterns.zipWithIndex.iterator.flatMap { (re, i) =>
      texts.iterator.flatMap { (f, text) =>
        val rel = f.relativeTo(base).toString
        text.split("\n", -1).iterator.zipWithIndex.flatMap { (line, n) =>
          re.findAllMatchIn(line)
            // `gh?_` followed only by x's is a placeholder (the old (?!...) of grep -P).
            .filterNot(m => m.groupCount > 0 && i == 0 && m.group(1).forall(c => c == 'x' || c == 'X'))
            .map(m => s"$rel:${n + 1}:${m.matched}")
            .filterNot(placeholder.findFirstIn(_).isDefined)
            .map(_ => s"$rel:${n + 1} (${i + 1})")
        }
      }.take(1)
    }.nextOption()

  // ---------------------------------------------------------------- Step 10
  /** The body of the pull request. `checkEdited`: this run exempted skills/hermes/ in check.py. */
  def body(list: String, owned: List[String], dups: List[String], checkEdited: Boolean): String =
    val sb = StringBuilder()
    sb ++= """## Summary
             |
             |Hermes exports the skills that the owner wrote or changed for it. Skills that other authors wrote stay out.
             |This PR adds or updates them under `skills/hermes/`.
             |Each skill has the tag `hermes-skill` in `www/tags.txt`.
             |
             |## Tested
             |
             |- `scripts/check.py` passes.
             |- `agentskills_check.py skills` passes.
             |- A scan found no secret in the exported files.
             |
             |## What changed
             |
             |""".stripMargin
    sb ++= s"- Skills: $list.\n"
    if checkEdited then
      sb ++= "- `scripts/check.py`: a skill under `skills/hermes/` counts as copied as is. It gets warnings, not failures. These skills are not written in ASD-STE100 and they have links. Decide if you accept this.\n"
    sb ++= """
             |## Notes
             |
             |- The skills are public in this repository. Read them before you merge.
             |- The front matter keeps only the keys of the Agent Skills format. The export adds `disable-model-invocation: true`.
             |""".stripMargin
    if owned.nonEmpty then sb ++= s"- Skipped, because the repository already has them: ${joinNames(owned)}.\n"
    if dups.nonEmpty then sb ++= s"- Skipped, same name as another Hermes skill: ${joinNames(dups)}.\n"
    sb.toString

  /** The names, sorted and without a repeat, in one line. */
  private def joinNames(names: List[String]): String = names.distinct.sorted.mkString(", ")

  /** The first 20 names, then "and <K> more". */
  def namesList(skills: List[Skill]): String =
    val names = skills.map(_.name)
    names.take(20).mkString(", ") + (if names.length > 20 then s" and ${names.length - 20} more" else "")

  // ---------------------------------------------------------------- The export
  private final class Export(job: CronJob, cfg: SkillsConfig, runEnv: Map[String, String], found: Found):
    import job.{steps, tool}
    import cfg.{repoDir, repo}
    private given Sh.Opts = Sh.Opts(cwd = repoDir, env = runEnv)
    private def git = tool(Tool.Git)
    private val target = repoDir / SkillsRepo.Target
    private val tags = repoDir / SkillsRepo.Tags

    def run(): Unit =
      val (branch, prUrl) = prepareRepo()
      val (skills, owned) = skipOwned()
      if skills.isEmpty then steps.quit(0)
      copySkills(skills)
      tagSkills(skills)
      val checkEdited = exemptCheck()
      steps.step = "scan for secrets"
      scanSecrets(target, repoDir).foreach(hit => steps.fail(s"possible secret in $hit"))
      steps.step = "look for changes"
      if steps.out(git, "status", "--porcelain").isEmpty then steps.quit(0)
      runChecks()
      commitAndPublish(branch, prUrl, skills, owned, checkEdited)

    // ---------------------------------------------------------------- Step 3
    /** The branch to work on, and the URL of the open PR that has it, if one does. */
    private def prepareRepo(): (String, Option[String]) =
      steps.step = s"update the clone of $repo"
      if !os.isDir(repoDir) then steps.fail(steps.step)
      steps.run(git, "fetch", "-q", "--depth", "1", "origin", "main")
      steps.run(git, "checkout", "-q", "-f", "--detach", "FETCH_HEAD")
      steps.run(git, "clean", "-fdq")
      if job.isDry then
        val branch = SkillsRepo.branches.dry
        steps.run(git, "checkout", "-q", "-B", branch, "FETCH_HEAD")
        return (branch, None)

      steps.step = "look for an open PR"
      val prs = OpenPr.parseList(steps.out(tool(Tool.Gh), "pr", "list", "-R", repo, "--state", "open", "--json",
        "number,headRefName,url"))
      SkillsRepo.branches.ownsAny(prs) match
        case Some(pr) =>
          // Reuse the open PR: work on its branch.
          steps.step = "check out the branch of the open PR"
          steps.run(git, "fetch", "-q", "--depth", "1", "origin", pr.branch)
          steps.run(git, "checkout", "-q", "-B", pr.branch, "FETCH_HEAD")
          (pr.branch, Some(pr.url))
        case None =>
          steps.step = "choose a branch name"
          val branch = job.freeBranch(SkillsRepo.branches.dated(job.today()))
          steps.run(git, "checkout", "-q", "-B", branch, "FETCH_HEAD")
          (branch, None)

    /** Leaves out each skill that has the name of a skill in another category of the repository. */
    private def skipOwned(): (List[Skill], List[String]) =
      steps.step = "skip the skills that the repository has"
      val categories = if os.isDir(repoDir / "skills") then os.list(repoDir / "skills").filter(os.isDir(_))
        .filter(c => !c.last.startsWith(".") && c.last != SkillsRepo.Category) else Nil
      val (owned, skills) = found.skills.partition(s => categories.exists(c => os.isDir(c / s.name)))
      (skills, owned.map(_.name))

    // ---------------------------------------------------------------- Step 4
    private def copySkills(skills: List[Skill]): Unit =
      steps.step = "copy the skills"
      // The directory is generated: start empty, so a skill that left the list leaves the repository.
      os.remove.all(target)
      if os.isFile(tags) then os.write.over(tags, untag(os.read(tags)))
      os.makeDir.all(target)
      val rows = skills.map { s =>
        val source = os.read(s.dir / SkillFile)
        // The whole directory: these skills are the owner's and small, and their references matter.
        copyTree(s.dir, target / s.name)
        steps.step = s"normalize the front matter of ${s.name}"
        val file = target / s.name / SkillFile
        normalize(os.read(file), s.name) match
          case Right(text) => os.write.over(file, text)
          case Left(why)   => steps.fail(why)
        steps.step = "copy the skills"
        s.name -> s"| `${s.name}` | ${cell(s.origin.render)} | ${cell(field(source, "license"))} | ${cell(field(source, "author"))} |"
      }
      steps.step = "write skills/hermes/README.md"
      os.write.over(target / "README.md", readme + rows.sortBy(_._1).map(_._2 + "\n").mkString)

    /** `cp -rL`, then `chmod -R u+w`: a copy from the Nix store is read only. */
    private def copyTree(from: os.Path, to: os.Path): Unit =
      if os.isDir(from) then
        os.makeDir.all(to)
        os.list(from).foreach(p => copyTree(p, to / p.last))
      else if os.isFile(from) then
        os.write.over(to, os.read.bytes(from))
        os.perms.set(to, os.perms(from) + java.nio.file.attribute.PosixFilePermission.OWNER_WRITE)
      else steps.fail(steps.step)

    /** A table cell has no "|" and no newline. */
    private def cell(v: String): String = v.replace("|", "").replace("\n", " ").replace("\r", "")

    private val readme =
      """# hermes
        |
        |The skills that the owner wrote or changed for Hermes. Hermes copies them here once a day. Do not edit them by hand.
        |Each skill has the tag `hermes-skill` in `www/tags.txt`.
        |These skills are copied as is, with the files next to each `SKILL.md`.
        |The `license` column is the value in the front matter of the skill. `not stated` means that the skill has no value.
        |Check the licence of the source before you reuse a skill.
        |
        || Skill | Origin | Licence | Author |
        ||---|---|---|---|
        |""".stripMargin

    // ---------------------------------------------------------------- Step 5
    /** Each exported skill has the tag hermes-skill in www/tags.txt. */
    private def tagSkills(skills: List[Skill]): Unit =
      steps.step = "tag the skills in www/tags.txt"
      if !os.isFile(tags) then steps.fail(steps.step)
      os.write.over(tags, tag(os.read(tags), skills.map(_.name)))

    // ---------------------------------------------------------------- Step 6
    /** Skills of Hermes are copied as is: exempt them in scripts/check.py. True if it was edited. */
    private def exemptCheck(): Boolean =
      steps.step = "edit scripts/check.py"
      val check = repoDir / SkillsRepo.Check
      val comment = "        # skills/hermes/ holds the skills of Hermes, copied as is on the owner's word."
      val line = """        as_is = rel in AS_IS or rel.startswith("skills/hermes/")"""
      val text = if os.isFile(check) then os.read(check) else ""
      if text.contains("skills/hermes/") then false
      else
        val edited = Util.linesKeep(text).map { l =>
          if "        as_is = rel in AS_IS\\s*".r.matches(l.stripSuffix("\n")) then s"$comment\n$line\n" else l
        }.mkString
        if !edited.split("\n").contains(line) then steps.fail("scripts/check.py has no as_is line to edit")
        os.write.over(check, edited)
        true

    // ---------------------------------------------------------------- Step 9
    private def runChecks(): Unit =
      steps.step = "find a Python for the checks"
      val python = job.which("hermes").flatMap { hermes =>
        "/nix/store/[a-z0-9]*-hermes-agent-env/bin/python3[.0-9]*".r
          .findFirstIn(String(os.read.bytes(hermes), java.nio.charset.StandardCharsets.ISO_8859_1))
      }
      val py = python.getOrElse {
        println("skills export: no python for the checks")
        steps.quit(1)
      }
      steps.step = "run the checks"
      // The checks must not leave bytecode in the tree that is committed.
      runCheck("scripts/check.py", py, SkillsRepo.Check.toString)
      runCheck("agentskills_check.py", py, "skills/dev-flow/agentskills-checker/scripts/agentskills_check.py", "skills")

    private def runCheck(label: String, cmd: String*): Unit =
      val r = os.proc(cmd).call(cwd = repoDir, env = runEnv + ("PYTHONDONTWRITEBYTECODE" -> "1"),
        mergeErrIntoOut = true, check = false)
      if r.exitCode != 0 then
        println(s"skills export failed: the checks of the repository fail ($label)")
        print(Util.lastLines(r.out.text(), 5))
        steps.quit(1)

    // ---------------------------------------------------------------- Step 10
    private def commitAndPublish(branch: String, prUrl: Option[String], skills: List[Skill],
        owned: List[String], checkEdited: Boolean): Unit =
      val list = namesList(skills)
      val counts = s"${skills.length} skills, ${owned.length + found.dups.length} skipped"
      val text = body(list, owned, found.dups, checkEdited)

      steps.step = "commit"
      steps.run(git, "add", "-A", "skills", "www", "scripts")
      steps.run(git, job.identity(), "commit", "-q", "-m", SkillsRepo.Title,
        "-m", s"Skills: $list.", "-m", "Tested: scripts/check.py and agentskills_check.py pass")
      job.writePatch()
      job.endDryRun(branch)

      steps.step = "push the branch"
      steps.quiet(git, "push", "origin", branch)

      prUrl match
        case Some(url) =>
          // Keep the description true: the list of skills changes between runs.
          job.withBody("skills-export", text) { file =>
            if os.proc(tool(Tool.Gh), "pr", "edit", url, "--body-file", file)
              .call(env = runEnv, stdout = os.Pipe, check = false).exitCode != 0
            then steps.fail(steps.step)
          }
          println(s"skills export: updated $url ($counts)")
        case None =>
          steps.step = "open the pull request"
          val url = job.withBody("skills-export", text) { file =>
            steps.out(tool(Tool.Gh), "pr", "create", "-R", repo, "--base", "main", "--head", branch,
              "--title", SkillsRepo.Title, "--body-file", file)
          }
          println(s"skills export: opened $url ($counts)")
