package piabrota.scripts

import piabrota.lib.TestKit

/** The wrappers exec a stand-in that prints its arguments and the variables that matter. */
class WrappersTest extends munit.FunSuite:
  private val show = """#!/bin/sh
echo "args: $*"
for v in GH_TOKEN PI_CONFIG_FILES ANTHROPIC_OAUTH_TOKEN ANTHROPIC_API_KEY CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_AUTH_TOKEN OMP_BIN SEAT_CHOOM; do
  eval "[ -n \"\${$v+x}\" ] && echo \"$v=\$$v\""
done
exit 0
"""
  // choom -n 500 -- prog args, and timeout ... prog args: both run what follows.
  private val fakes = TestKit.fakes("gh" -> show, "show" -> show,
    "choom" -> "#!/bin/sh\necho \"choom $1 $2\"\nshift 3\nexec \"$@\"\n",
    "timeout" -> "#!/bin/sh\necho \"timeout $1 $2 $3\"\nshift 3\nexec \"$@\"\n")
  private val bin = fakes.toString

  // The variables of the test's own environment that the wrappers read: unset (os-lib's null).
  private val clean: Map[String, String] = List("GH_TOKEN", "ANTHROPIC_OAUTH_TOKEN", "ANTHROPIC_API_KEY",
    "CLAUDE_CODE_OAUTH_TOKEN", "ANTHROPIC_AUTH_TOKEN").map(_ -> (null: String)).toMap

  private def run(args: Seq[String], env: Map[String, String] = Map.empty) =
    val r = TestKit.piabrota(args, env = clean ++ env, fakes = Some(fakes))
    (r.exitCode, r.out.text(), r.err.text())

  test("marola-gh lets through what proposes, with the bot's token"):
    val tokens = os.temp.dir()
    os.write(tokens / "marola-pr-bot", "tok\n")
    val env = Map("MAROLA_GH_TOKENS" -> tokens.toString)
    val (code, out, _) = run(Seq("marola-gh", "pr", "create", "--fill"), env)
    assertEquals(code, 0)
    assert(out.contains("args: pr create --fill") && out.contains("GH_TOKEN=tok\n"), out)
    val (refused, _, err) = run(Seq("marola-gh", "pr", "merge", "1"), env)
    assertEquals(refused, 2)
    assert(err.contains("marola-gh: pr merge 1 is not allowed (humans merge and review)"), err)
    assertEquals(run(Seq("marola-gh", "--repo", "x", "pr", "create"), env)._1, 2)
    assertEquals(run(Seq("marola-gh", "pr", "view"), Map("MAROLA_GH_TOKENS" -> (tokens / "none").toString))._1, 1)

  private val omp = Map("OMP_CONFIG" -> "/omp.yml", "OMP_APPEND" -> "/append.md", "OMP_CEILING" -> "35m",
    "OMP_BIN" -> s"$bin/show", "OMP_TIMEOUT" -> s"$bin/timeout", "OMP_CHOOM" -> s"$bin/choom")

  test("omp: the ceiling, choom, the config and Hermes's token as omp's"):
    val (code, out, err) = run(Seq("omp", "-p", "hi"), omp + ("CLAUDE_CODE_OAUTH_TOKEN" -> "sk-ant-oat-h"))
    assertEquals(code, 0, err)
    assert(out.startsWith("timeout --signal=TERM --kill-after=30s 35m\nchoom -n 500\n"), out)
    assert(out.contains("args: --append-system-prompt /append.md -p hi\n"), out)
    assert(out.contains("PI_CONFIG_FILES=/omp.yml\n") && out.contains("ANTHROPIC_OAUTH_TOKEN=sk-ant-oat-h\n"), out)
    assert(!out.contains("OMP_BIN="), out)

  test("omp: a subscription token in ANTHROPIC_API_KEY moves; no ceiling for a seat"):
    val (_, out, _) = run(Seq("omp"), omp ++ Map("OMP_CEILING" -> "none", "ANTHROPIC_API_KEY" -> "sk-ant-oat-s"))
    assert(out.startsWith("choom -n 500\n"), out)
    assert(out.contains("ANTHROPIC_OAUTH_TOKEN=sk-ant-oat-s\n") && !out.contains("ANTHROPIC_API_KEY="), out)
    val (_, kept, _) = run(Seq("omp"), omp + ("ANTHROPIC_API_KEY" -> "sk-ant-api-x"))
    assert(kept.contains("ANTHROPIC_API_KEY=sk-ant-api-x\n") && kept.contains("ANTHROPIC_OAUTH_TOKEN=\n"), kept)

  test("seat-claude: the subscription token moves, an API key is dropped"):
    val seat = Map("SEAT_CLAUDE_BIN" -> s"$bin/show", "SEAT_CHOOM" -> s"$bin/choom", "ANTHROPIC_AUTH_TOKEN" -> "x")
    val (code, out, err) = run(Seq("seat-claude", "--help"), seat + ("ANTHROPIC_API_KEY" -> "sk-ant-oat-s"))
    assertEquals(code, 0, err)
    assert(out.contains("args: --help\n") && out.contains("CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat-s\n"), out)
    assert(!out.contains("ANTHROPIC_API_KEY=") && !out.contains("ANTHROPIC_AUTH_TOKEN=") && !out.contains("SEAT_CHOOM="), out)
    val (_, api, _) = run(Seq("seat-claude"), seat + ("ANTHROPIC_API_KEY" -> "sk-ant-api-x"))
    assert(!api.contains("ANTHROPIC_API_KEY=") && !api.contains("CLAUDE_CODE_OAUTH_TOKEN="), api)

  test("openrig-claude-token copies the last token line only, as ANTHROPIC_API_KEY, mode 0600"):
    val dir = os.temp.dir()
    os.write(dir / "hermes.env", "A=1\nCLAUDE_CODE_OAUTH_TOKEN=old\nCLAUDE_CODE_OAUTH_TOKEN=new\nB=2\n")
    val (code, out, _) = run(Seq("openrig-claude-token", (dir / "hermes.env").toString, (dir / ".env").toString))
    assertEquals(code, 0)
    assertEquals(out, "")
    assertEquals(os.read(dir / ".env"), "ANTHROPIC_API_KEY=new\n")
    assertEquals(os.perms(dir / ".env").toString, "rw-------")
    run(Seq("openrig-claude-token", (dir / "missing").toString, (dir / ".env").toString))
    assertEquals(os.read(dir / ".env"), "")

  test("marola-clone refuses a repository it does not know"):
    val (code, _, err) = run(Seq("marola-clone", "marola-dev/other"), Map("MAROLA_REPOS" -> "marola-dev/marola-front"))
    assertEquals(code, 2)
    assert(err.contains("marola-clone: marola-dev/other is not one of: marola-dev/marola-front"), err)
