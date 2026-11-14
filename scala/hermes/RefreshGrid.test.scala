package piabrota.hermes

import piabrota.lib.{Sh, TestKit}
import java.time.LocalDateTime

/** refresh-grid with a bare git repository as origin, a stub gh and a fake generator. No network,
  * no Nix, no real GitHub; it needs git (skipped without it).
  */
class RefreshGridTest extends munit.FunSuite:
  override def beforeEach(context: BeforeEach): Unit =
    assume(Sh.which("git").isDefined, "needs git")

  // The stub gh: STUB_DIR holds origin.git, prs.json (the open PRs), log, title, body.md and head.
  private val gh = """#!/bin/sh
case "$1 $2" in
  "repo clone")
    echo "repo clone" >>"$STUB_DIR/log"
    git clone -q "file://$STUB_DIR/origin.git" "$4"
    ;;
  "pr list")
    echo "pr list" >>"$STUB_DIR/log"
    cat "$STUB_DIR/prs.json"
    ;;
  "pr create")
    echo "pr create" >>"$STUB_DIR/log"
    shift 2
    while [ $# -gt 0 ]; do
      case $1 in
        --title) printf '%s' "$2" >"$STUB_DIR/title" ;;
        --body-file) cp "$2" "$STUB_DIR/body.md" ;;
        --head) printf '%s' "$2" >"$STUB_DIR/head" ;;
      esac
      shift
    done
    echo "https://github.com/piabrota/room/pull/99"
    ;;
  *)
    echo "unexpected gh call: $*" >>"$STUB_DIR/log"
    exit 1
    ;;
esac
"""

  // The fake generator: it copies the run.json of FAKE_MODE from STUB_DIR and writes the binaries.
  private val fakegen = """#!/bin/sh
set -eu
case "$FAKE_MODE" in
  nochange) exit 0 ;;
  fail) for i in 1 2 3 4 5 6 7; do echo "generator line $i"; done; exit 3 ;;
  outside) echo changed >README.md ;;
esac
mode=$FAKE_MODE
[ "$mode" = outside ] && mode=ok
cp "$STUB_DIR/run-$mode.json" public/grid/run.json
printf 'bbbbbbbbbbbb' >public/grid/frames.bin
if [ "$FAKE_MODE" = size ]; then printf 'bb' >public/grid/frames.bin; fi
printf 'cccc' >public/grid/sst.bin
"""

  private val bin = TestKit.fakes("gh" -> gh, "fakegen" -> fakegen)

  private def hours(day: Int, n: Int): ujson.Arr =
    ujson.Arr.from((0 until n).map(i => ujson.Str(LocalDateTime.of(2026, 11, day, 4, 0).plusHours(i).toString)))

  /** A fresh origin, clone directory and stub state. */
  private final class Case:
    val root = os.temp.dir(prefix = "refresh-grid")
    val home = root / "home"
    os.makeDir.all(home)
    os.makeDir.all(root / "tmp")
    private val gitEnv = Map("HOME" -> home.toString, "XDG_CONFIG_HOME" -> home.toString, "GIT_CONFIG_NOSYSTEM" -> "1")
    private def git(args: os.Shellable*)(cwd: os.Path = root) =
      os.proc("git", args).call(cwd = cwd, env = gitEnv, stderr = os.Pipe).out.text().trim

    git("init", "-q", "--bare", "-b", "main", root / "origin.git")()
    private val seed = root / "seed"
    os.write(seed / "public" / "grid" / "run.json", ujson.write(ujson.Obj(
      "nodes" -> 11905, "triangles" -> 22366, "hours" -> hours(6, 25),
      "fetched" -> "2026-11-06T04:34:56.487Z", "sst" -> ujson.Obj("date" -> "2026-11-04", "scale" -> 0.01))),
      createFolders = true)
    os.write(seed / "public" / "grid" / "frames.bin", "aaaaaaaaaaaa")
    os.write(seed / "public" / "grid" / "sst.bin", "dddd")
    os.write(seed / "public" / "grid" / "mesh.bin", "mesh")
    os.write(seed / "public" / "grid" / "land.json", "{}")
    os.write(seed / "scripts" / "check.mjs", "// the invariant check\n", createFolders = true)
    os.write(seed / "README.md", "# room\n")
    git("init", "-q", "-b", "main")(seed)
    git("add", "-A")(seed)
    git("-c", "user.name=seed", "-c", "user.email=seed@example.com", "commit", "-q", "-m", "seed")(seed)
    git("push", "-q", s"file://$root/origin.git", "main")(seed)

    for (mode, n, sst) <- List(("ok", 25, true), ("size", 25, true), ("nosst", 25, false), ("hours24", 24, true)) do
      val json = ujson.Obj("nodes" -> 11905, "triangles" -> 22366, "hours" -> hours(7, n),
        "fetched" -> "2026-11-07T04:30:00.000Z")
      if sst then json("sst") = ujson.Obj("date" -> "2026-11-05", "scale" -> 0.01)
      os.write(root / s"run-$mode.json", ujson.write(json))
    os.write(root / "prs.json", "[]")
    os.write(root / "log", "")
    os.write(root / "token", "")

    var env = gitEnv ++ Map(
      "TMPDIR" -> (root / "tmp").toString, "STUB_DIR" -> root.toString,
      "REPO_DIR" -> (root / "room-src").toString, "TOKEN_FILE" -> (root / "token").toString,
      "REPO" -> "piabrota/room", "GRID_CMD" -> (bin / "fakegen").toString,
      "CHECK_CMD" -> "test -f scripts/check.mjs", "FAKE_MODE" -> "ok")

    def run(): os.CommandResult = TestKit.piabrota(Seq("refresh-grid"), env = env, fakes = Some(bin))
    def calls(what: String): Int = os.read.lines(root / "log").count(_ == what)
    def remoteBranches: List[String] =
      git("for-each-ref", "--format=%(refname:short)", "refs/heads")(root / "origin.git")
        .linesIterator.filter(b => b.nonEmpty && b != "main").toList.sorted
    def originGit(args: String*): String = git(args.map(os.Shellable.StringShellable(_))*)(root / "origin.git")

  private def today = Sh.out("date", "+%Y%m%d")

  test("a: no token file: the waiting line"):
    val c = Case()
    os.remove(c.root / "token")
    val r = c.run()
    assertEquals((r.exitCode, r.out.text()),
      (0, "grid refresh waiting: the piabrota-hermes App has no installation on piabrota/room (no token file)\n"))

  test("b: new data and no open PR: a branch, one commit, one PR; the second run takes -2"):
    val c = Case()
    os.write.over(c.root / "prs.json", """[{"headRefName":"feature/other"}]""")
    val r = c.run()
    val branch = s"hermes/grid-refresh-$today"
    assertEquals((r.exitCode, r.out.text()),
      (0, "grid refresh: opened https://github.com/piabrota/room/pull/99 (wind from 2026-11-07, temperature of 2026-11-05)\n"),
      r.err.text())
    assertEquals(c.remoteBranches, List(branch))
    assertEquals(c.originGit("rev-list", "--count", s"main..$branch"), "1")
    assert(c.originGit("diff", "--name-only", s"main..$branch").linesIterator.forall(_.startsWith("public/grid/")))
    assertEquals(c.originGit("log", "-1", "--format=%s|%an|%ae", branch),
      "Refresh the data of the grid: wind of 2026-11-07, temperature of 2026-11-05|piabrota-hermes|piabrota-hermes@users.noreply.github.com")
    val message = c.originGit("log", "-1", "--format=%B", branch)
    assert(!message.toLowerCase.contains("co-authored") && !message.toLowerCase.contains("generated"), message)
    assert(message.contains("Files changed: frames.bin run.json sst.bin. Hours: 25. Nodes: 11905. Triangles: 22366."), message)
    assertEquals(c.calls("pr create"), 1)
    assertEquals(os.read(c.root / "title"), "Refresh the data of the grid: wind of 2026-11-07, temperature of 2026-11-05")
    assertEquals(os.read(c.root / "head"), branch)
    val body = os.read(c.root / "body.md")
    for text <- List("2026-11-07T04:00 to 2026-11-08T04:00 UTC", "2026-11-07T04:30:00.000Z", "OSTIA day 2026-11-05",
        "`frames.bin`: 12 bytes before, 12 bytes after.", "`sst.bin`: 4 bytes before, 4 bytes after.",
        "The numbers of `run.json` equal the committed ones: 11905 nodes, 22366 triangles, 25 hours.")
    do assert(body.contains(text), s"no '$text' in:\n$body")
    assert(!body.contains("Natural Earth source"))
    assert(c.run().out.text().nonEmpty)
    assertEquals(c.remoteBranches, List(branch, s"$branch-2"))
    assert(os.list(c.root / "tmp").isEmpty, "the body file is left")

  test("c: an open PR of the job: nothing happens"):
    val c = Case()
    os.write.over(c.root / "prs.json", """[{"headRefName":"feature/other"},{"headRefName":"hermes/grid-refresh-20261108"}]""")
    val r = c.run()
    assertEquals((r.exitCode, r.out.text()), (0, ""))
    assertEquals((c.remoteBranches, c.calls("pr create")), (Nil, 0))

  test("d: the generator changes nothing: no output"):
    val c = Case()
    c.env += "FAKE_MODE" -> "nochange"
    val r = c.run()
    assertEquals((r.exitCode, r.out.text(), c.calls("pr create")), (0, "", 0))

  test("e: the generator fails: one failed line, then its last 5 lines"):
    val c = Case()
    c.env += "FAKE_MODE" -> "fail"
    val r = c.run()
    assertEquals((r.exitCode, r.out.text()),
      (1, "grid refresh failed: run the generator\n" + (3 to 7).map(i => s"generator line $i\n").mkString))
    assertEquals(c.remoteBranches, Nil)

  test("f: the sea temperature is missing: not opened, nothing pushed"):
    val c = Case()
    c.env += "FAKE_MODE" -> "nosst"
    val r = c.run()
    assertEquals((r.exitCode, r.out.text()), (1, "grid refresh not opened: the sea temperature is missing (Copernicus Marine)\n"))
    assertEquals((c.remoteBranches, c.calls("pr create")), (Nil, 0))

  test("g: DRY_RUN=1: no push, no gh call, the dry line and the diff stat; OUT_PATCH gets the commit"):
    val c = Case()
    os.remove(c.root / "token")
    c.env ++= Map("DRY_RUN" -> "1", "OUT_PATCH" -> (c.root / "out.patch").toString)
    val r = c.run()
    val lines = r.out.text().linesIterator.toList
    assertEquals(r.exitCode, 0, r.err.text())
    assertEquals(lines.take(2), List(s"patch: ${c.root / "out.patch"}", "dry run: would push hermes/grid-refresh-dry"))
    assert(lines.exists(_.contains("public/grid/frames.bin")), r.out.text())
    assert(os.read(c.root / "out.patch").contains("Refresh the data of the grid"))
    assertEquals((c.remoteBranches, c.calls("pr create"), c.calls("pr list")), (Nil, 0, 0))

  test("h: a file outside public/grid changed"):
    val c = Case()
    c.env += "FAKE_MODE" -> "outside"
    val r = c.run()
    assertEquals((r.exitCode, r.out.text()), (1, "grid refresh failed: the generator changed files outside public/grid\n"))
    assertEquals(c.remoteBranches, Nil)

  test("i: 24 hours instead of 25"):
    val c = Case()
    c.env += "FAKE_MODE" -> "hours24"
    val r = c.run()
    assertEquals((r.exitCode, r.out.text()), (1, "grid refresh not opened: run.json has 24 hours, the committed one has 25\n"))

  test("i: frames.bin has a new size"):
    val c = Case()
    c.env += "FAKE_MODE" -> "size"
    val r = c.run()
    assertEquals((r.exitCode, r.out.text()), (1, "grid refresh not opened: frames.bin has 2 bytes, the committed one has 12\n"))

  test("i: the check of the room fails"):
    val c = Case()
    c.env += "CHECK_CMD" -> "echo broken; exit 2"
    val r = c.run()
    assertEquals((r.exitCode, r.out.text()), (1, "grid refresh not opened: scripts/check.mjs fails\nbroken\n"))
    assertEquals(c.remoteBranches, Nil)
