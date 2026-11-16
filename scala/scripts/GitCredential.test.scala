package piabrota.scripts

import piabrota.lib.TestKit

class GitCredentialTest extends munit.FunSuite:
  private val tokens = os.temp.dir(prefix = "tokens")
  os.write(tokens / "piabrota", "tok-piabrota\n")
  os.write(tokens / "marola-pr-bot", "tok-bot")
  os.write(tokens / "marola-dev--marola-front", "tok-seat")

  private def ask(command: String, path: String, env: Map[String, String], op: String = "get"): String =
    TestKit.piabrota(Seq(command, op), env = env,
      stdin = s"protocol=https\nhost=github.com\npath=$path\n\n").out.text()

  private val hermes = Map("HERMES_GIT_TOKENS" -> tokens.toString,
    "HERMES_GIT_MAROLA_REPOS" -> "marola-dev/marola-front marola-dev/marola-back")
  private def answer(token: String) = s"username=x-access-token\npassword=$token\n"

  test("hermes: the token of the repository's owner"):
    assertEquals(ask("hermes-git-credential", "piabrota/nix-os.git", hermes), answer("tok-piabrota"))

  test("hermes: a marola repository, in any case, takes the bot's token"):
    assertEquals(ask("hermes-git-credential", "marola-dev/Marola-Front.git", hermes), answer("tok-bot"))

  test("hermes: a marola repository with no bot token gets nothing, never the owner's"):
    val ownerOnly = os.temp.dir(prefix = "tokens")
    os.write(ownerOnly / "marola-dev", "tok-owner")
    assertEquals(ask("hermes-git-credential", "marola-dev/marola-back", hermes + ("HERMES_GIT_TOKENS" -> ownerOnly.toString)), "")
    assertEquals(ask("hermes-git-credential", "marola-dev/marola-site", hermes + ("HERMES_GIT_TOKENS" -> ownerOnly.toString)),
      answer("tok-owner"))

  test("hermes: no token, a strange path or another operation: nothing"):
    assertEquals(ask("hermes-git-credential", "h0ffmann/x", hermes), "")
    assertEquals(ask("hermes-git-credential", "../etc/passwd", hermes), "")
    assertEquals(ask("hermes-git-credential", "piabrota/nix-os", hermes, op = "store"), "")

  test("seat: the read-only token of the repository"):
    val seat = Map("OPENRIG_SEAT_TOKENS" -> tokens.toString)
    assertEquals(ask("openrig-git-credential", "marola-dev/marola-front.git", seat), answer("tok-seat"))
    assertEquals(ask("openrig-git-credential", "marola-dev/marola-back", seat), "")
    assertEquals(ask("openrig-git-credential", "", seat), "")
