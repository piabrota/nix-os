package piabrota.scripts

import piabrota.lib.TestKit

/** commit-counts against a stand-in `gh` that logs each call and answers per repository. */
class CommitCountsTest extends munit.FunSuite:
  val gh = """#!/bin/sh
             |echo "gh $*" >> "$LOG"
             |case "$3" in
             |  repos/piabrota/mixed/*) printf '%s\n' h0ffmann 'piabrota-hermes[bot]' claude 'dependabot[bot]' aracyla - claudette 'x[bot]y' ;;
             |  repos/piabrota/robots/*) printf '%s\n' 'piabrota-ops[bot]' 'ouroboric-pr-bot[bot]' claude ;;
             |  repos/piabrota/people/*) printf '%s\n' h0ffmann h0ffmann robkler ;;
             |  repos/piabrota/empty/*) ;;
             |  repos/other/mixed/*) echo h0ffmann ;;
             |  *) echo "gh: HTTP 404" >&2; exit 1 ;;
             |esac
             |""".stripMargin

  final case class Run(code: Int, out: String, log: String)

  def counts(args: Seq[String], env: Map[String, String] = Map.empty, more: Seq[(String, String)] = Nil): Run =
    val fakes = TestKit.fakes((("gh" -> gh) +: more)*)
    val log = fakes / "calls.log"
    val r = TestKit.piabrota("commit-counts" +: args, env = env + ("LOG" -> log.toString),
      cwd = os.temp.dir(prefix = "counts"), fakes = Some(fakes))
    Run(r.exitCode, r.out.text(), if os.exists(log) then os.read(log) else "")

  test("the rule"):
    // [bot] and exactly "claude" are agents; a person, a missing account, "claudette" and a login
    // that only contains [bot] are human.
    assertEquals(counts(Seq("mixed")).out, "mixed: commits = { human = 5; agent = 3; };\n")
    assertEquals(counts(Seq("robots")).out, "robots: commits = { human = 0; agent = 3; };\n")
    assertEquals(counts(Seq("people")).out, "people: commits = { human = 3; agent = 0; };\n")
    assertEquals(counts(Seq("empty")).out, "empty: commits = { human = 0; agent = 0; };\n")

  test("no data, then goes on"):
    val r = counts(Seq("missing", "people"))
    assertEquals(r.out, "missing: no data\npeople: commits = { human = 3; agent = 0; };\n")
    assertEquals(r.code, 1)
    assertEquals(counts(Seq("people")).code, 0)

  test("another owner"):
    assertEquals(counts(Seq("mixed"), Map("COMMIT_COUNTS_OWNER" -> "other")).out,
      "mixed: commits = { human = 1; agent = 0; };\n")

  test("the request"):
    assertEquals(counts(Seq("people")).log,
      "gh api --paginate repos/piabrota/people/commits?per_page=100 --jq .[] | (.author.login // \"-\")\n")

  test("help calls nothing"):
    val r = counts(Seq("--help"))
    assert(r.out.contains("agent when its GitHub author login ends with [bot]"), r.out)
    assertEquals(r.log, "")

  test("the names come from mockups/data.nix through nix-instantiate"):
    val nix = "#!/bin/sh\ncase \"$*\" in *mockups/data.nix*) printf 'people\\nrobots\\n' ;; *) exit 1 ;; esac\n"
    val r = counts(Nil, more = Seq("nix-instantiate" -> nix))
    assertEquals(r.out, "people: commits = { human = 3; agent = 0; };\nrobots: commits = { human = 0; agent = 3; };\n")

  test("no names from mockups/data.nix exits 2"):
    val r = TestKit.piabrota(Seq("commit-counts"), cwd = os.temp.dir(),
      fakes = Some(TestKit.fakes("nix-instantiate" -> "#!/bin/sh\nexit 1\n")))
    assertEquals(r.exitCode, 2)
    assert(r.err.text().contains("cannot read the project names from mockups/data.nix"), r.err.text())
