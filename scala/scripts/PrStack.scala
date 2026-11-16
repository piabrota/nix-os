package piabrota.scripts

import piabrota.lib.die

/** `piabrota pr-stack`: plans and checks a PR stack (.agents/skills/pr-stack/SKILL.md), in the
  * checkout it runs in. Run by `just pr-stack-plan` and `just pr-stack-check`. It changes no branch
  * and pushes nothing; the PR heads are fetched to refs/pr-stack/<pr>.
  */
object PrStack:
  def run(args: List[String]): Int = args match
    case "plan" :: prs   => plan(prs.map(StackPr(_)))
    case "check" :: rest => check(rest)
    case _               => stop("usage: piabrota pr-stack plan <pr>... | check <branch> <pr>...")

  private def stop(message: String): Nothing = die(s"pr-stack: $message", 2)

  /** git with its stderr on ours, as the script's own lines are on stdout. */
  private def git(args: String*): os.CommandResult =
    os.proc("git", args).call(stdin = os.Inherit, stdout = os.Pipe, stderr = os.Inherit, check = false)

  private def gitOut(args: String*): String =
    val r = git(args*)
    if r.exitCode != 0 then die(s"git ${args.mkString(" ")}: exit ${r.exitCode}")
    r.out.text().strip()

  private def ok(args: String*): Boolean = git(args*).exitCode == 0

  private def fetch(prs: List[StackPr]): Unit =
    gitOut("fetch", "-q", StackPr.remote, StackPr.main)
    prs.foreach { pr =>
      if !ok("fetch", "-q", "-f", StackPr.remote, pr.refspec) then stop(s"no PR #${pr.number} on origin")
    }

  private def plan(prs: List[StackPr]): Int =
    if prs.isEmpty then stop("usage: piabrota pr-stack plan <pr>...")
    fetch(prs)
    val (_, bad) = prs.foldLeft((gitOut("rev-parse", StackPr.originMain), false)) { case ((tip, bad), pr) =>
      val head = gitOut("rev-parse", pr.ref)
      val merge = git("merge-tree", "--write-tree", "--name-only", "--no-messages", tip, head)
      val lines = merge.out.lines().toList
      if merge.exitCode == 0 then
        println(StackMerge.Clean(pr).render)
        (gitOut("commit-tree", lines.head, "-p", tip, "-p", head, "-m", s"plan #${pr.number}"), bad)
      else
        // Go on from the tip before this PR, so the next lines still say something.
        println(StackMerge.Conflict(pr, lines.drop(1)).render)
        (tip, true)
    }
    if !bad then println(s"plan: all ${prs.length} PRs stack cleanly on origin/main, in this order")
    if bad then 1 else 0

  private def check(args: List[String]): Int = args match
    case branch :: numbers if numbers.nonEmpty =>
      val prs = numbers.map(StackPr(_))
      fetch(prs)
      if !ok("fetch", "-q", StackPr.remote, branch) then stop(s"no branch $branch on origin")
      val tip = gitOut("rev-parse", "FETCH_HEAD")
      val mainOk = ok("merge-base", "--is-ancestor", StackPr.originMain, tip)
      if mainOk then println(s"ok    $branch contains origin/main")
      else println(s"FAIL  $branch is behind origin/main: git merge origin/main into it (never rebase)")
      val headsOk = prs.map { pr =>
        val short = gitOut("rev-parse", "--short", pr.ref)
        val in = ok("merge-base", "--is-ancestor", pr.ref, tip)
        if in then println(s"ok    #${pr.number} head $short is in the stack")
        else println(s"FAIL  #${pr.number} head $short is not in the stack: its branch moved, merge it again")
        in
      }
      val good = mainOk && headsOk.forall(identity)
      if good then println(s"check: merge $branch with a merge commit (not squash, not rebase)")
      if good then 0 else 1
    case _ => stop("usage: piabrota pr-stack check <branch> <pr>...")
