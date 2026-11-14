package piabrota.hermes

import piabrota.lib.Sh

/** What the two pull-request cron jobs (refresh-grid, export-skills) share: the PATH they run
  * with, their programs, the token and the git steps.
  */
final class CronJob(prefix: String, tools: Seq[Tool], val cfg: CronEnv):
  val steps = Steps(prefix)

  /** Where a program is on the job's PATH. */
  def which(name: String): Option[os.Path] =
    cfg.path.split(':').iterator.filter(_.nonEmpty).map(dir => os.Path(dir, os.pwd) / name)
      .find(p => os.isFile(p) && p.toIO.canExecute)

  // A missing tool must stop the run now, not half way through.
  private val found: Map[Tool, os.Path] = tools.map { t =>
    t -> which(t.cmd).getOrElse {
      println(s"$prefix failed: ${t.cmd} is not on the PATH")
      throw piabrota.lib.Exit(1)
    }
  }.toMap

  /** A tool of the list, by its path. */
  def tool(t: Tool): os.Path = found(t)

  def isDry: Boolean = cfg.dryRun

  /** The environment of every program the job runs: the PATH, and the token once it is read. */
  def env(token: Option[String]): Map[String, String] =
    Map("PATH" -> cfg.path) ++ token.map(GitHub.TokenVar -> _)

  /** The GitHub token, or the end of the job with the waiting line when there is none. */
  def readToken(tokenFile: os.Path, repo: String): String =
    steps.step = "read the token"
    if !(os.isFile(tokenFile) && tokenFile.toIO.canRead) then
      println(s"$prefix waiting: the piabrota-hermes App has no installation on $repo (no token file)")
      steps.quit(0)
    os.read(tokenFile).replaceAll("\n+$", "")

  /** The token, read unless this is a dry run. */
  def token(tokenFile: os.Path, repo: String): Option[String] =
    Option.unless(isDry)(readToken(tokenFile, repo))

  /** True if the branch is on origin; fails the step when git cannot tell. */
  def remoteBranchExists(branch: String)(using Sh.Opts): Boolean =
    steps.code(tool(Tool.Git), "ls-remote", "--exit-code", "--heads", "origin", branch) match
      case 0 => true
      case 2 => false
      case _ => steps.fail(steps.step)

  /** `<base>`, or `<base>-2`, `<base>-3`, ... : the first name that origin does not have. */
  def freeBranch(base: String)(using Sh.Opts): String =
    Iterator.single(base).concat(Iterator.from(2).map(n => s"$base-$n")).find(!remoteBranchExists(_)).get

  /** The `-c` options of a commit, when the clone has no identity of its own. */
  def identity()(using Sh.Opts): Seq[String] =
    if Sh.outOpt(tool(Tool.Git), "config", "user.name").exists(_.nonEmpty) then Nil else GitHub.Identity

  /** Writes the commit as a patch to OUT_PATCH, when it is set. */
  def writePatch()(using Sh.Opts): Unit =
    cfg.outPatch.foreach { out =>
      steps.step = "write the patch"
      val opts = summon[Sh.Opts]
      val r = os.proc(tool(Tool.Git), "format-patch", "-1", "--stdout")
        .call(cwd = opts.cwd, env = opts.env, stdout = os.Path(out, opts.cwd), check = false)
      if r.exitCode != 0 then steps.fail(steps.step)
      println(s"patch: $out")
    }

  /** A dry run ends here: what would be pushed, and the diff stat of the commit. */
  def endDryRun(branch: String)(using Sh.Opts): Unit =
    if isDry then
      println(s"dry run: would push $branch")
      System.out.flush()
      steps.run(tool(Tool.Git), "--no-pager", "diff", "--stat", "HEAD~1")
      steps.quit(0)

  /** A temporary file with the text of a pull request body, removed when `use` returns. */
  def withBody[A](name: String, text: String)(use: os.Path => A): A =
    val body = os.temp(text, dir = os.Path(cfg.tmpDir, os.pwd), prefix = s"$name-", suffix = ".md",
      deleteOnExit = false)
    try use(body)
    finally os.remove(body)

  /** The date of today, for a branch name (`date +%Y%m%d`, in the box's time zone). */
  def today(): String = Sh.out(tool(Tool.Date), "+%Y%m%d")
