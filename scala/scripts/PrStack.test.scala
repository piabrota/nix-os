package piabrota.scripts

import piabrota.lib.TestKit

/** An origin with main and three PR heads: 1 and 2 touch other files, 3 conflicts with 1. */
class PrStackTest extends munit.FunSuite:
  val env = Map("GIT_AUTHOR_NAME" -> "t", "GIT_AUTHOR_EMAIL" -> "t@t", "GIT_COMMITTER_NAME" -> "t",
    "GIT_COMMITTER_EMAIL" -> "t@t", "GIT_CONFIG_GLOBAL" -> "/dev/null", "GIT_CONFIG_NOSYSTEM" -> "1")

  lazy val checkout: os.Path =
    val work = os.temp.dir(prefix = "pr-stack")
    val (origin, seed) = (work / "origin.git", work / "seed")
    def git(cwd: os.Path, args: String*): Unit =
      val r = os.proc("git", args).call(cwd = cwd, env = env, stderr = os.Pipe, check = false)
      assertEquals(r.exitCode, 0, r.err.text())
    git(work, "init", "-q", "--bare", "-b", "main", origin.toString)
    git(work, "init", "-q", "-b", "main", seed.toString)
    os.write(seed / "a", "a\n")
    git(seed, "add", "a")
    git(seed, "commit", "-qm", "base")
    git(seed, "remote", "add", "origin", origin.toString)
    git(seed, "push", "-q", "origin", "main")
    for (pr, name, text) <- List((1, "x", "one\n"), (2, "y", "two\n"), (3, "x", "three\n")) do
      git(seed, "switch", "-qc", s"pr$pr", "main")
      os.write.over(seed / name, text)
      git(seed, "add", name)
      git(seed, "commit", "-qm", s"pr $pr")
      git(seed, "push", "-q", "origin", s"pr$pr:refs/pull/$pr/head")
    git(seed, "switch", "-qc", "stack", "main")
    git(seed, "merge", "-q", "--no-ff", "pr1", "-m", "m1")
    git(seed, "merge", "-q", "--no-ff", "pr2", "-m", "m2")
    git(seed, "push", "-q", "origin", "stack")
    git(work, "clone", "-q", origin.toString, (work / "clone").toString)
    work / "clone"

  def stack(args: String*) = TestKit.piabrota("pr-stack" +: args, env = env, cwd = checkout)

  test("plan"):
    val good = stack("plan", "1", "2")
    assertEquals(good.out.text(), "#1  clean\n#2  clean\nplan: all 2 PRs stack cleanly on origin/main, in this order\n")
    val bad = stack("plan", "1", "3", "2")
    assertEquals(bad.exitCode, 1)
    assertEquals(bad.out.text(), "#1  clean\n#3  CONFLICT in:\n      x\n#2  clean\n")

  test("check"):
    val good = stack("check", "stack", "1", "2")
    assertEquals(good.exitCode, 0, good.out.text())
    assert(good.out.text().contains("check: merge stack with a merge commit"), good.out.text())
    val bad = stack("check", "stack", "1", "3")
    assertEquals(bad.exitCode, 1)
    assert(bad.out.text().contains("FAIL  #3 head"), bad.out.text())

  test("no such PR"):
    val r = stack("plan", "9")
    assertEquals(r.exitCode, 2)
    assert(r.err.text().contains("no PR #9 on origin"), r.err.text())

  test("usage"):
    val r = stack()
    assertEquals(r.exitCode, 2)
    assert(r.err.text().contains("pr-stack: usage: piabrota pr-stack plan <pr>..."), r.err.text())
