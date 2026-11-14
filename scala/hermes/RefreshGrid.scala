package piabrota.hermes

import piabrota.lib.{Sh, env}

/** `refresh-grid`: refreshes the data of the ▲ grid of piabrota/room and opens a PR. The
  * grid-refresh cron job of Hermes runs it once a day (HERMES_HOME/scripts/refresh-grid.sh). It
  * prints nothing when there is nothing to do. A new run adds nothing while a PR with a branch
  * hermes/grid-refresh* is open: the owner merges or closes that PR first.
  *
  * Environment (all optional):
  *   REPO_DIR       a clone of piabrota/room for this job only   (/var/lib/hermes/workspace/room-src)
  *   TOKEN_FILE     the GitHub token file                       (/run/hermes-github/piabrota)
  *   REPO           the GitHub repository                       (piabrota/room)
  *   GRID_CMD       the generator, run in REPO_DIR with bash    (nix develop ... --command just grid)
  *   CHECK_CMD      the invariant check, run in REPO_DIR        (nix develop ... --command node scripts/check.mjs)
  *   GRID_TIMEOUT   seconds for GRID_CMD                        (2400)
  *   CHECK_TIMEOUT  seconds for CHECK_CMD                       (600)
  *   DRY_RUN        1 = no git push and no gh pr create; print what would happen
  *   OUT_PATCH      a file path: write the commit there as a patch
  */
object RefreshGrid:
  def run(args: List[String]): Int =
    val job = CronJob("grid refresh", Seq(Tool.Git, Tool.Gh, Tool.Timeout, Tool.Env, Tool.Bash, Tool.Date),
      CronEnv.read(sys.env.getOrElse("PATH", ""), env))
    val cfg = GridConfig.read(env)
    Grid(job, cfg, job.env(job.token(cfg.tokenFile, cfg.repo))).run()
    0

  private final class Grid(job: CronJob, cfg: GridConfig, runEnv: Map[String, String]):
    import job.{steps, tool}
    import cfg.{repoDir, repo}
    private given Sh.Opts = Sh.Opts(cwd = repoDir, env = runEnv)
    private def git = tool(Tool.Git)

    def run(): Unit =
      prepareRepo()
      if !job.isDry then checkOpenPr()
      generate()
      val (changes, meshChanged) = lookAtChanges()
      val (fresh, old) = verify(meshChanged)
      val lines = describe(changes)
      val branch = chooseBranch()
      commitAndPublish(branch, changes, lines, fresh, old)

    // ---------------------------------------------------------------- Step 2
    private def prepareRepo(): Unit =
      if !os.isDir(repoDir) then
        steps.step = s"clone $repo"
        steps.quiet(tool(Tool.Gh), "repo", "clone", repo, repoDir, "--", "--depth", "1", "--filter=blob:none")(
          using Sh.Opts(env = runEnv))
      steps.step = s"update the clone of $repo"
      steps.run(git, "fetch", "-q", "--depth", "1", "origin", "main")
      steps.run(git, "checkout", "-q", "-f", "--detach", "FETCH_HEAD")
      // No -x: node_modules/ is ignored by git. It is the cache, with node_modules/.grid/ in it,
      // where the generator keeps Natural Earth.
      steps.run(git, "clean", "-fdq")

    // ---------------------------------------------------------------- Step 3
    private def checkOpenPr(): Unit =
      steps.step = "look for an open PR"
      val prs = OpenPr.parseList(steps.out(tool(Tool.Gh), "pr", "list", "-R", repo, "--state", "open", "--limit",
        "200", "--json", "headRefName"))
      if GridFiles.branches.ownsAny(prs).isDefined then steps.quit(0)

    // ---------------------------------------------------------------- Step 4
    /** Runs a command string with bash in REPO_DIR with a time limit: its exit code and output.
      * The token stays out of its environment: npm packages run code.
      */
    private def runCmd(limit: String, cmd: String): (Int, String) =
      val r = os.proc(tool(Tool.Timeout), "-k", "30", limit, tool(Tool.Env), "-u", GitHub.TokenVar, "-u",
        "GITHUB_TOKEN", tool(Tool.Bash), "-c", cmd)
        .call(cwd = repoDir, env = runEnv, stdin = "", mergeErrIntoOut = true, check = false)
      (r.exitCode, r.out.text())

    private def generate(): Unit =
      steps.step = "run the generator"
      val (rc, out) = runCmd(cfg.gridTimeout, cfg.gridCmd)
      if rc == 124 then steps.fail(s"${steps.step} (it did not end in ${cfg.gridTimeout} seconds)")
      if rc != 0 then
        println(s"grid refresh failed: ${steps.step}")
        print(Util.lastLines(out, 5))
        steps.quit(1)

    // ---------------------------------------------------------------- Step 5
    /** The `git status --porcelain` lines of public/grid, and whether mesh.bin is among them. */
    private def lookAtChanges(): (List[String], Boolean) =
      steps.step = "look for changes"
      if steps.out(git, "status", "--porcelain", "--", ".", s":(exclude)${GridFiles.Dir}").nonEmpty then
        steps.fail("the generator changed files outside public/grid")
      val changes = Sh.outOpt(git, "status", "--porcelain", "--", GridFiles.Dir).getOrElse("")
        .linesIterator.filter(_.nonEmpty).toList
      if changes.isEmpty then steps.quit(0)
      (changes, steps.out(git, "status", "--porcelain", "--", s"${GridFiles.Dir}/${GridFiles.Mesh}").nonEmpty)

    // ---------------------------------------------------------------- Step 6
    /** The sizes of a file in the committed tree and in the new one. */
    private def sizes(file: String): Sizes =
      val p = repoDir / os.SubPath(GridFiles.Dir) / os.SubPath(file)
      Sizes(file,
        before = Sh.outOpt(git, "cat-file", "-s", s"HEAD:${GridFiles.Dir}/$file").flatMap(_.toLongOption),
        after = Option.when(os.isFile(p))(os.size(p)))

    private def notOpened(why: String): Nothing =
      println(s"grid refresh not opened: $why")
      steps.quit(1)

    /** Checks the new data against the committed data: the new and the old run.json. */
    private def verify(meshChanged: Boolean): (RunJson, RunJson) =
      steps.step = "check the new data"
      val runJson = repoDir / os.SubPath(GridFiles.Dir) / GridFiles.RunJson
      if !os.isFile(runJson) then notOpened("run.json is missing")
      val fresh = RunJson.parse(os.read(runJson)).getOrElse(notOpened("run.json is not valid JSON"))
      val old = RunJson.parse(steps.out(git, "show", s"HEAD:${GridFiles.Dir}/${GridFiles.RunJson}"))
        .getOrElse(steps.fail(steps.step))
      RunJson.refuse(fresh, old, meshChanged).foreach(notOpened)
      GridFiles.Sized.iterator.map(sizes).flatMap(_.refuse).nextOption().foreach(notOpened)

      // Invariant 9 of the room (the 25 MB budget of public/, the radio apart) is in scripts/check.mjs:
      // a plain du of public/ would count the 77 MB of the radio.
      steps.step = "run the check of the room"
      val (rc, out) = runCmd(cfg.checkTimeout, cfg.checkCmd)
      if rc != 0 then
        println("grid refresh not opened: scripts/check.mjs fails")
        print(Util.lastLines(out, 5))
        steps.quit(1)
      (fresh, old)

    // ---------------------------------------------------------------- Step 7
    /** One line for each changed file: its sizes before and after. */
    private def describe(changes: List[String]): String =
      steps.step = "describe the changes"
      changes.map(line => sizes(GridFiles.changed(line)).describe).mkString

    private def chooseBranch(): String =
      val branch =
        if job.isDry then GridFiles.branches.dry
        else
          steps.step = "choose a branch name"
          job.freeBranch(GridFiles.branches.dated(job.today()))
      // -B: a branch of an earlier run that did not push may still exist here.
      steps.run(git, "checkout", "-q", "-B", branch)
      branch

    // ---------------------------------------------------------------- Step 8
    private def commitAndPublish(branch: String, changes: List[String], lines: String, fresh: RunJson,
        old: RunJson): Unit =
      val windDay = fresh.first.takeWhile(_ != 'T')
      val title = s"Refresh the data of the grid: wind of $windDay, temperature of ${fresh.sstDate}"
      val names = changes.map(GridFiles.changed).mkString(" ")

      steps.step = "commit"
      steps.run(git, "add", "-A", "--", GridFiles.Dir)
      steps.run(git, job.identity(), "commit", "-q", "-m", title,
        "-m", s"Files changed: $names. Hours: ${fresh.hours}. Nodes: ${fresh.nodes}. Triangles: ${fresh.triangles}.")
      job.writePatch()
      job.endDryRun(branch)

      steps.step = "push the branch"
      steps.quiet(git, "push", "origin", branch)

      steps.step = "open the pull request"
      val url = job.withBody("grid-refresh", body(lines, fresh, old)) { file =>
        steps.out(tool(Tool.Gh), "pr", "create", "-R", repo, "--base", "main", "--head", branch, "--title", title,
          "--body-file", file)
      }
      println(s"grid refresh: opened $url (wind from $windDay, temperature of ${fresh.sstDate})")

  /** The body of the pull request. */
  def body(lines: String, fresh: RunJson, old: RunJson): String =
    val numbers =
      if fresh.sameMesh(old) then
        s"- The numbers of `run.json` equal the committed ones: ${fresh.nodes} nodes, ${fresh.triangles} triangles, ${fresh.hours} hours."
      else
        s"- `mesh.bin` changed on purpose: ${old.nodes} to ${fresh.nodes} nodes, ${old.triangles} to ${fresh.triangles} triangles."
    s"""## Summary
       |
       |This PR refreshes the data of the ▲ grid. The daily job of Hermes made it.
       |The wind runs from ${fresh.first} to ${fresh.last} UTC, in ${fresh.hours} hourly frames. Open-Meteo gave it on ${fresh.fetched}.
       |The sea temperature is the OSTIA day ${fresh.sstDate}.
       |
       |## What changed
       |
       |$lines
       |## Tested
       |
       |- `scripts/check.mjs` passes.
       |$numbers
       |- Nothing else ran.
       |
       |## Not tested
       |
       |- No screenshot and no clip: the code did not change.
       |- The job did not look at the map.
       |
       |## Notes
       |
       |- The sea is an estimate from the wind, not WAVEWATCH III.
       |- The wind data come from Open-Meteo (CC BY 4.0). The temperature data come from Copernicus Marine.
       |- The site of the room shows these data only after a PR in piabrota/nix-os moves its pin of the room.
       |- A new run of the job adds nothing while this PR is open.
       |""".stripMargin
