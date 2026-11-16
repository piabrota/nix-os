package piabrota.scripts

import piabrota.lib.TestKit

/** The token units against a stub curl (GitHub's API), openssl, chown and install. */
class GithubTokensTest extends munit.FunSuite:
  private val curl = """#!/bin/sh
echo "$*" >> "$LOG"
for a; do url=$a; done
case "$url" in
  */app/installations) echo '[{"id":1,"account":{"login":"piabrota"}},{"id":3,"account":{"login":"h0ffmann"}},{"id":7,"account":{"login":"marola-dev"}}]' ;;
  */installations/1/access_tokens) case "$*" in *'"contents":"read"'*) echo '{"token":"t-seat"}' ;; *) echo '{"token":"t1"}' ;; esac ;;
  */installations/7/access_tokens) case "$*" in *'"contents":"read"'*) echo '{"token":"t-ro"}' ;; *) echo '{"token":"t-op"}' ;; esac ;;
  */repos/piabrota/room/installation) echo '{"id":9}' ;;
  */installations/9/access_tokens) echo '{"token":"t-td"}' ;;
  */app) echo '{"slug":"piabrota-hermes"}' ;;
  */users/piabrota-hermes%5Bbot%5D) echo '{"id":42}' ;;
  *) echo "curl: (22) 404" >&2; exit 22 ;;
esac
"""
  private val fakes = TestKit.fakes("curl" -> curl,
    "openssl" -> "#!/bin/sh\ncat >/dev/null\nprintf sig\n",
    "chown" -> "#!/bin/sh\necho \"chown $*\" >> \"$LOG\"\n",
    "install" -> "#!/bin/sh\nfor a; do case $a in /*) mkdir -p \"$a\" ;; esac; done\n")

  private val work = os.temp.dir(prefix = "gh")
  private val creds = work / "creds"
  os.write(creds / "app", "GH_APP_ID=123\nGH_APP_PRIVATE_KEY_B64=a2V5\n", createFolders = true)
  os.write(creds / "hermes", "X=1\nCLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat-c\n")
  private val tokens = work / "tokens"
  private val seats = work / "seats"
  private val home = work / "home"
  private val log = work / "log"
  for d <- List(tokens, seats, home) do os.makeDir.all(d)

  private def run(command: String, config: ujson.Value) =
    os.write.over(log, "")
    val file = work / s"$command.json"
    os.write.over(file, config.render())
    val r = TestKit.piabrota(Seq(command, file.toString),
      env = Map("CREDENTIALS_DIRECTORY" -> creds.toString, "LOG" -> log.toString), fakes = Some(fakes))
    assertEquals(r.exitCode, 0, r.out.text() + r.err.text())
    r.out.text()

  test("hermes-github-token: a token per installed owner, the seats' tokens, the identity"):
    os.write.over(tokens / "h0ffmann", "stale")
    val out = run("hermes-github-token", ujson.Obj(
      "owners" -> ujson.Arr("piabrota", "nobody", "h0ffmann"),
      "permissions" -> """{"contents":"write","pull_requests":"write","issues":"write"}""",
      "tokens" -> tokens.toString, "seatRepos" -> ujson.Arr("piabrota/chaceon", "nobody/x"),
      "seatTokens" -> seats.toString, "home" -> home.toString, "helper" -> "/nix/store/x-helper",
      "marolaGitconfig" -> "[includeIf \"x\"]\n  path = y\n"))
    assertEquals(out.linesIterator.toList, List(
      "piabrota: token for one hour",
      "nobody: the App is not installed there",
      "h0ffmann: GitHub refused a token",
      "piabrota/chaceon: read-only token for the seats, for one hour",
      "nobody/x: no read-only token for the seats (is the App installed on it?)"))
    assertEquals(os.read(tokens / "piabrota"), "t1")
    assertEquals(os.perms(tokens / "piabrota").toString, "rw-r-----")
    assert(os.exists(tokens / "h0ffmann"), "a refused token leaves the old file, as before")
    assertEquals(os.read(seats / "piabrota--chaceon"), "t-seat")
    val calls = os.read(log)
    assert(calls.contains("Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9."), calls)
    assert(calls.contains("""-d {"permissions":{"contents":"write","pull_requests":"write","issues":"write"}}"""), calls)
    assert(calls.contains("chown root:hermes") && calls.contains("chown root:openrig"), calls)
    assertEquals(os.read(home / ".gitconfig"),
      """[user]
        |  name = piabrota-hermes[bot]
        |  email = 42+piabrota-hermes[bot]@users.noreply.github.com
        |[credential "https://github.com"]
        |  helper = /nix/store/x-helper
        |  useHttpPath = true
        |[push]
        |  default = current
        |[includeIf "x"]
        |  path = y
        |""".stripMargin)
    assertEquals(os.read(home / ".config" / "gh" / "hosts.yml"),
      "github.com:\n  oauth_token: t1\n  git_protocol: https\n  user: piabrota-hermes[bot]\n")
    assertEquals(os.perms(home / ".gitconfig").toString, "rw-------")

  test("marola-bot-token: the operator token, the seats' tokens, the bot's identity"):
    val out = run("marola-bot-token", ujson.Obj("owner" -> "marola-dev", "names" -> ujson.Arr("marola-front", "marola-back"),
      "tokens" -> tokens.toString, "seatTokens" -> seats.toString, "home" -> home.toString))
    assertEquals(out.linesIterator.toList, List(
      "marola-dev: operator token for one hour",
      "marola-dev/marola-front: read-only token for the seats, for one hour",
      "marola-dev/marola-back: read-only token for the seats, for one hour"))
    assertEquals(os.read(tokens / "marola-pr-bot"), "t-op")
    assertEquals(os.read(seats / "marola-dev--marola-back"), "t-ro")
    assert(os.read(log).contains("""{"repositories":["marola-front","marola-back"],"permissions":{"contents":"write","pull_requests":"write","issues":"write"}}"""))
    assertEquals(os.read(home / ".gitconfig-marola-bot"),
      "[user]\n  name = piabrota-hermes[bot]\n  email = 42+piabrota-hermes[bot]@users.noreply.github.com\n")

  test("marola-bot-token: not installed drops every token"):
    os.write.over(tokens / "marola-pr-bot", "old")
    val out = run("marola-bot-token", ujson.Obj("owner" -> "elsewhere", "names" -> ujson.Arr("a"),
      "tokens" -> tokens.toString, "seatTokens" -> seats.toString, "home" -> home.toString))
    assertEquals(out, "elsewhere: marola-pr-bot is not installed there\n")
    assert(!os.exists(tokens / "marola-pr-bot"))

  test("tyler-durden-token: the token and the profile's .env"):
    val td = work / "td"
    os.makeDir.all(td)
    val out = run("tyler-durden-token", ujson.Obj("repository" -> "piabrota/room", "tokens" -> td.toString,
      "home" -> home.toString, "profile" -> "tyler-durden"))
    assertEquals(out, "piabrota/room: token for one hour\n")
    assertEquals(os.read(td / "token"), "t-td")
    assertEquals(os.read(home / "profiles" / "tyler-durden" / ".env"), "GH_TOKEN=t-td\nCLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat-c\n")
    assert(os.read(log).contains("""{"repositories":["room"],"permissions":{"pull_requests":"write"}}"""))

  test("tyler-durden-token: not installed is a line and exit 0"):
    val out = run("tyler-durden-token", ujson.Obj("repository" -> "piabrota/other", "tokens" -> work.toString,
      "home" -> home.toString, "profile" -> "p"))
    assertEquals(out, "tyler-durden-bot is not installed on piabrota/other, or GitHub refused the App's JWT\n")
