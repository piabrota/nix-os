package piabrota.pirsig

import java.nio.charset.StandardCharsets.UTF_8

/** The pirsig brain (piabrota/pirsig) as a shallow, sparse git checkout in a tool's data
  * directory, and pull requests to it.
  *
  * Git runs as the hermes user: hermes-github.nix gives git a credential helper and gh a token of
  * the piabrota-hermes App. The tools push only branches under `hermes/` and only open pull requests;
  * that rule is checked here, because the deny list of custom-dangerous-patterns sees the terminal
  * tool only, not the processes of an MCP server.
  */
final class Brain(root: os.Path, val repo: String, val base: String):
  if !Brain.RepoName.matches(repo) then throw BrainError(s"not a GitHub repository: $repo")

  val path: os.Path = root / repo.replace("/", "__")
  def url: String = s"https://github.com/$repo"

  def git(args: String*): String = Brain.run("git" +: args, cwd = Some(path))

  /** Checks out the tip of the base branch; skips the fetch if the last one is younger than
    * `maxAge` seconds (0: always fetch).
    */
  def sync(maxAge: Int = 0): os.Path =
    val stamp = path / ".git" / Brain.FetchStamp
    def recent = maxAge > 0 && os.exists(stamp) &&
      System.currentTimeMillis() - os.mtime(stamp) < maxAge * 1000L
    if !os.isDir(path / ".git") then
      os.makeDir.all(path / os.up)
      Brain.run(Seq("git", "clone", "--quiet", "--depth", "1", "--filter=blob:none", "--sparse",
        "--branch", base, url, path.toString))
      git("sparse-checkout" +: "set" +: BrainTree.Sparse*)
      os.write.over(stamp, "")
    else if !recent then
      git("fetch", "--quiet", "--depth", "1", "origin", base)
      git("checkout", "--quiet", "--force", "-B", base, "FETCH_HEAD")
      git("clean", "--quiet", "-fd")
      os.write.over(stamp, "")
    path

  /** `hermes/<slug>`, with `-2`, `-3`... when the branch is already on GitHub. */
  def branchName(slug: String): String =
    val heads = git("ls-remote", "--heads", "origin", s"${Brain.BranchPrefix}$slug*")
    Brain.freeBranch(slug, Brain.remoteBranches(heads))

  /** Commits `files` (in order) on a new branch under hermes/, pushes it and opens a pull request
    * against the base branch.
    */
  def openPr(files: Seq[NewFile], slug: String, title: String, body: String): PullRequest =
    if files.isEmpty then throw BrainError("nothing to submit")
    sync()
    val branch = branchName(slug)
    // The ruleset on GitHub also blocks other branches; this refuses before any git write.
    if !branch.startsWith(Brain.BranchPrefix) then
      throw BrainError(s"refused: $branch is not a ${Brain.BranchPrefix}* branch")
    val targets = checkedTargets(files)
    pushBranch(branch, targets, title, body)
    val url = createPr(branch, title, body)
    PullRequest(branch, Py.splitlines(url).lastOption.getOrElse(""))

  /** Resolves every path before any write, so one bad path leaves the checkout untouched. */
  private def checkedTargets(files: Seq[NewFile]): Seq[(NewFile, os.Path)] =
    val allowed = Brain.resolve(path / BrainTree.Root)
    files.map: file =>
      val target = Brain.resolve(os.Path(file.path, path))
      if !target.startsWith(allowed) || target == allowed then
        throw BrainError(s"refused: ${file.path} is outside ${BrainTree.Root}/")
      if os.exists(target) then
        throw BrainError(s"refused: ${file.path} is already in $repo; a note is never rewritten")
      file -> target

  private def pushBranch(branch: String, targets: Seq[(NewFile, os.Path)], title: String, body: String): Unit =
    git("checkout", "--quiet", "-B", branch)
    try
      targets.foreach((file, target) => os.write(target, file.content.getBytes(UTF_8), createFolders = true))
      git(Seq("add", "--sparse", "--") ++ targets.map(_._1.path)*)
      git("commit", "--quiet", "-m", title, "-m", Brain.commitBody(body))
      git("push", "--quiet", "origin", s"HEAD:refs/heads/$branch")
    finally
      // Back to the base even when git failed, so the next call starts from a clean tree.
      git("checkout", "--quiet", "--force", base)
      git("clean", "--quiet", "-fd")

  /** Opens the PR with `gh` and returns its URL. */
  private def createPr(branch: String, title: String, body: String): String =
    val bodyFile = os.temp(body, suffix = ".md", deleteOnExit = false)
    try Py.strip(Brain.run(Seq("gh", "pr", "create", "--repo", repo, "--base", base, "--head", branch,
      "--title", title, "--body-file", bodyFile.toString)))
    finally os.remove(bodyFile)

  /** Every Markdown note of the brain's slip-box and inbox. */
  def notes(): List[BrainNote] =
    for
      folder <- Folder.values.toList
      dir = path / BrainTree.Root / folder.dir
      file <- if os.isDir(dir) then os.list(dir).filter(f => f.last.endsWith(BrainNote.Extension) && os.isFile(f)).sortBy(_.last).toList else Nil
    yield BrainNote.parse(folder, file.last, new String(os.read.bytes(file), UTF_8))

object Brain:
  val BranchPrefix = "hermes/"
  /** A fresh clone is enough for a search for this long; a submission always fetches. */
  val RefreshSeconds = 600
  val GitTimeout = 180
  /** The file in `.git` whose mtime is the last fetch, the Python plugins' name. */
  val FetchStamp = "pirsig-plugin-fetched"
  private val RepoName = "[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+".r
  private val HeadsRef = "refs/heads/"
  private val PluginData = "plugin-data"

  /** The Brain of one tool family. */
  def open(config: Config, family: ToolFamily): Brain = Brain(dataDir(config.home, family), config.repo, config.base)

  /** `$HERMES_HOME/plugin-data/<family>`, where the Python plugins kept their checkout and work
    * folders.
    */
  def dataDir(home: os.Path, family: ToolFamily): os.Path =
    val dir = home / PluginData / family.dataDir
    os.makeDir.all(dir)
    dir

  /** The branch names of `git ls-remote --heads`. */
  def remoteBranches(heads: String): Set[String] =
    heads.linesIterator.collect:
      case line if line.contains(HeadsRef) => line.split(HeadsRef, 2)(1)
    .toSet

  /** The first of `hermes/<slug>`, `hermes/<slug>-2`, ... that is not taken. */
  def freeBranch(slug: String, taken: Set[String]): String =
    val names = Iterator(s"$BranchPrefix$slug") ++ Iterator.from(2).map(n => s"$BranchPrefix$slug-$n")
    names.find(!taken.contains(_)).get

  /** Runs a program and returns its stdout; a failure, a timeout or a missing program is a
    * BrainError with the last lines of its output.
    */
  def run(args: Seq[String], cwd: Option[os.Path] = None, timeout: Int = GitTimeout): String =
    val started = System.currentTimeMillis()
    val r =
      try os.proc(args).call(cwd = cwd.orNull, stdin = "", stdout = os.Pipe, stderr = os.Pipe,
        check = false, timeout = timeout * 1000L)
      catch case _: java.io.IOException => throw BrainError(s"${args.head} is not on PATH")
    // os-lib kills a program at the timeout and returns its exit code, without saying why.
    if r.exitCode != 0 && System.currentTimeMillis() - started >= timeout * 1000L then
      throw BrainError(s"${args.take(2).mkString(" ")} took more than $timeout s")
    if r.exitCode != 0 then
      val output = if r.err.text().nonEmpty then r.err.text() else r.out.text()
      val tail = Py.splitlines(Py.strip(output)).takeRight(3)
      throw BrainError(s"${args.take(3).mkString(" ")} failed: ${tail.mkString(" / ")}")
    r.out.text()

  /** The first paragraph of the PR body, the commit's reason. */
  def commitBody(prBody: String): String =
    prBody.split("\n\n", -1).map(Py.strip).find(t => t.nonEmpty && !t.startsWith("#"))
      .getOrElse(Py.strip(prBody))

  /** `pathlib.Path.resolve()`: the links of the part that exists, then the rest as it is. */
  def resolve(p: os.Path): os.Path =
    if os.exists(p, followLinks = false) then os.Path(p.toNIO.toRealPath())
    else if p == os.root then p
    else resolve(p / os.up) / p.last
