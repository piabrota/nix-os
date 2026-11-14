package piabrota.scripts

// The repositories, pull requests and GitHub Apps that commit-counts, pr-stack, the token units,
// the credential helpers and the wrappers work with.

/** commit-counts's settings: the owner of the repositories (COMMIT_COUNTS_OWNER) and the file that
  * names them.
  */
final case class CommitCountsConfig(owner: String, data: os.Path)

object CommitCountsConfig:
  val defaultOwner = "piabrota"

/** The human and agent commits of one repository. */
final case class CommitCount(human: Int, agent: Int):
  def render: String = s"commits = { human = $human; agent = $agent; };"

object CommitCount:
  /** An agent's GitHub login ends with [bot] or is exactly "claude" (Claude Code's commit author). */
  def isAgent(login: String): Boolean = login.endsWith("[bot]") || login == "claude"

  def of(logins: List[String]): CommitCount =
    val agent = logins.count(isAgent)
    CommitCount(logins.length - agent, agent)

/** A pull request of a stack, by its number; its head is fetched to `ref`. */
final case class StackPr(number: String):
  def ref: String = s"refs/pr-stack/$number"
  def refspec: String = s"pull/$number/head:$ref"

object StackPr:
  val remote = "origin"
  val main = "main"
  val originMain = s"$remote/$main"

/** A GitHub App's id and key, from the credential file systemd hands a token unit
  * (`LoadCredential=app:...`): `GH_APP_ID` and `GH_APP_PRIVATE_KEY_B64` (the .pem, base64 on one
  * line). A missing field is "".
  */
final case class AppCredential(id: String, keyB64: String):
  /** The .pem; empty when the key is missing or broken, and GitHub then refuses the JWT. */
  def pem: Array[Byte] =
    scala.util.Try(java.util.Base64.getDecoder.decode(keyB64.trim)).getOrElse(Array.emptyByteArray)

object AppCredential:
  /** The credential file of the App, in the unit's credentials directory. */
  val file = "app"

  def parse(text: String): AppCredential =
    val fields = Util.envFile(text)
    AppCredential(fields.getOrElse("GH_APP_ID", ""), fields.getOrElse("GH_APP_PRIVATE_KEY_B64", ""))

/** The JWT an App signs to ask for installation tokens: RS256, nine minutes, issued a minute ago. */
object Jwt:
  def b64url(bytes: Array[Byte]): String = java.util.Base64.getUrlEncoder.withoutPadding.encodeToString(bytes)

  private def utf8(s: String) = s.getBytes(java.nio.charset.StandardCharsets.UTF_8)

  /** `header.payload`, the part that is signed. */
  def unsigned(appId: String, now: Long): String =
    s"""${b64url(utf8("""{"alg":"RS256","typ":"JWT"}"""))}.${b64url(utf8(s"""{"iat":${now - 60},"exp":${now + 540},"iss":"$appId"}"""))}"""

  def signed(unsigned: String, signature: Array[Byte]): String = s"$unsigned.${b64url(signature)}"

/** GitHub's REST API, as the token units call it. */
object GithubApi:
  val base = "https://api.github.com"
  val accept = "Accept: application/vnd.github+json"
  val installations = s"$base/app/installations"
  val app = s"$base/app"
  def accessTokens(installation: String): String = s"$base/app/installations/$installation/access_tokens"
  def botUser(slug: String): String = s"$base/users/$slug%5Bbot%5D"
  def repoInstallation(repo: RepoSlug): String = s"$base/repos/${repo.render}/installation"

/** An installation of an App: its id and the account it is on, as `GET /app/installations` lists them. */
final case class Installation(id: Option[String], login: Option[String])

object Installation:
  def parseList(v: ujson.Value): List[Installation] =
    v.arrOpt.toList.flatten.map { i =>
      Installation(i.objOpt.flatMap(_.get("id")).map(Jq.raw),
        i.objOpt.flatMap(_.get("account")).flatMap(_.objOpt).flatMap(_.get("login")).flatMap(_.strOpt))
    }

  /** The id of the first installation on `owner`. */
  def on(list: List[Installation], owner: String): Option[String] = list.find(_.login.contains(owner)).flatMap(_.id)

/** What an installation token may do, in the order GitHub gets it: `scope -> read|write`. */
final case class Permissions(entries: List[(String, String)]):
  def json: ujson.Obj = ujson.Obj.from(entries.map((k, v) => k -> ujson.Str(v)))

object Permissions:
  val read = "read"
  val write = "write"
  val readOnly: Permissions = Permissions(List("contents" -> read))
  val operator: Permissions = Permissions(List("contents" -> write, "pull_requests" -> write, "issues" -> write))
  val pullRequests: Permissions = Permissions(List("pull_requests" -> write))

  /** A JSON object of strings, as hermes-github.nix writes it. */
  def parse(text: String): Either[String, Permissions] =
    Jq.parse(text).flatMap(_.objOpt).flatMap { obj =>
      val entries = obj.toList.map((k, v) => v.strOpt.map(k -> _))
      Option.when(entries.forall(_.isDefined))(Permissions(entries.flatten))
    }.toRight(s"not a JSON object of strings: $text")

/** The body of `POST /app/installations/<id>/access_tokens`. */
final case class TokenRequest(repositories: Option[List[String]], permissions: Permissions):
  def render: String =
    ujson.Obj.from(repositories.map(r => "repositories" -> ujson.Arr.from(r)).toList :+ ("permissions" -> permissions.json)).render()

object TokenRequest:
  /** A seat's token of one repository: clone and fetch only, as the seats run without approval prompts. */
  def readOnly(repo: String): TokenRequest = TokenRequest(Some(List(repo)), Permissions.readOnly)

/** The token files the units write and the helpers read. */
object TokenFiles:
  /** marola-pr-bot's operator token, beside Hermes's tokens by owner. */
  val marolaBot = "marola-pr-bot"
  val hermesDir = "/run/hermes-github"
  val seatDir = "/run/openrig-github"

/** An App's bot user, as GitHub shows it: who Hermes commits as. */
final case class BotIdentity(slug: String, id: String):
  def login: String = s"$slug[bot]"
  def hasUserId: Boolean = id.nonEmpty && id.forall(_.isDigit)

  def gitconfig: String =
    s"""[user]
       |  name = $login
       |  email = $id+$login@users.noreply.github.com
       |""".stripMargin

  /** gh's hosts.yml with `token`. */
  def ghHosts(token: String): String =
    s"""github.com:
       |  oauth_token: $token
       |  git_protocol: https
       |  user: $login
       |""".stripMargin

  /** Hermes's ~/.gitconfig: this identity, the credential helper, and `more` appended. */
  def hermesGitconfig(helper: String, more: String): String =
    gitconfig +
      s"""[credential "https://github.com"]
         |  helper = $helper
         |  useHttpPath = true
         |[push]
         |  default = current
         |""".stripMargin + more

/** The settings files of the token units, written by their Nix modules. */
object TokenConfig:
  def read(v: ujson.Value, key: String): Either[String, ujson.Value] = v.objOpt.flatMap(_.get(key)).toRight(s"no $key")
  def str(v: ujson.Value, key: String): Either[String, String] = read(v, key).flatMap(_.strOpt.toRight(s"$key is not a string"))
  def path(v: ujson.Value, key: String): Either[String, os.Path] = str(v, key).map(os.Path(_))
  def strs(v: ujson.Value, key: String): Either[String, List[String]] =
    read(v, key).flatMap(_.arrOpt.toRight(s"$key is not a list")).flatMap { a =>
      a.toList.map(_.strOpt).foldRight[Either[String, List[String]]](Right(Nil)) {
        case (Some(s), acc) => acc.map(s :: _)
        case (None, _)      => Left(s"$key holds a value that is not a string")
      }
    }

/** hermes-github-token's settings (hermes-github.nix). */
final case class HermesTokenConfig(owners: List[String], permissions: Permissions, tokens: os.Path,
    seatRepos: List[RepoSlug], seatTokens: os.Path, home: os.Path, helper: String, marolaGitconfig: String)

object HermesTokenConfig:
  import TokenConfig.*
  def parse(v: ujson.Value): Either[String, HermesTokenConfig] =
    for
      owners <- strs(v, "owners")
      permissions <- str(v, "permissions").flatMap(Permissions.parse)
      tokens <- path(v, "tokens")
      seatRepos <- strs(v, "seatRepos")
      seatTokens <- path(v, "seatTokens")
      home <- path(v, "home")
      helper <- str(v, "helper")
      marola <- str(v, "marolaGitconfig")
    yield HermesTokenConfig(owners, permissions, tokens, seatRepos.map(RepoSlug.parse), seatTokens, home, helper, marola)

/** marola-bot-token's settings (marola-bot.nix). */
final case class MarolaTokenConfig(owner: String, names: List[String], tokens: os.Path, seatTokens: os.Path, home: os.Path)

object MarolaTokenConfig:
  import TokenConfig.*
  def parse(v: ujson.Value): Either[String, MarolaTokenConfig] =
    for
      owner <- str(v, "owner")
      names <- strs(v, "names")
      tokens <- path(v, "tokens")
      seatTokens <- path(v, "seatTokens")
      home <- path(v, "home")
    yield MarolaTokenConfig(owner, names, tokens, seatTokens, home)

/** tyler-durden-token's settings (tyler-durden-bot.nix). */
final case class TylerTokenConfig(repository: RepoSlug, tokens: os.Path, home: os.Path, profile: String):
  def profileDir: os.Path = home / "profiles" / profile

object TylerTokenConfig:
  import TokenConfig.*
  def parse(v: ujson.Value): Either[String, TylerTokenConfig] =
    for
      repository <- str(v, "repository")
      tokens <- path(v, "tokens")
      home <- path(v, "home")
      profile <- str(v, "profile")
    yield TylerTokenConfig(RepoSlug.parse(repository), tokens, home, profile)

/** The request git writes on a credential helper's stdin; only its `path` matters here. */
object CredentialRequest:
  /** The last `path=` up to the first empty line, or "". */
  def path(lines: Iterator[String]): String =
    lines.takeWhile(_.nonEmpty).flatMap { line =>
      line.split("=", 2) match
        case Array("path", value) => Some(value)
        case Array("path")        => Some("")
        case _                    => None
    }.toList.lastOption.getOrElse("")

  /** A token file name that is one plain file name, never a path. */
  def plain(name: String): Boolean = name.nonEmpty && !name.contains('/') && name != "." && name != ".."

  def answer(token: String): String = s"username=x-access-token\npassword=$token\n"

/** hermes-git-credential's settings: the token directory (HERMES_GIT_TOKENS) and the repositories
  * that take marola-pr-bot's token (HERMES_GIT_MAROLA_REPOS), lowercase.
  */
final case class HermesCredentialConfig(tokens: os.Path, marolaRepos: Set[String]):
  /** The token file for a request path. GitHub matches owner and name in any case: so must this, or
    * marola-dev/Marola-Front would get the owner's token. A marola repository fails closed: its
    * bot's token or nothing, never the owner's.
    */
  def tokenName(path: String): String =
    if marolaRepos(path.toLowerCase.stripSuffix(".git")) then TokenFiles.marolaBot else RepoSlug.parse(path).owner

/** How a request path names a seat's token: `owner--name`; None for an empty path. */
object SeatCredential:
  def tokenName(path: String): Option[String] =
    Some(path.stripSuffix(".git")).filter(_.nonEmpty).map(p => RepoSlug.parse(p).seatTokenName)

/** How a pull request merges onto the stack below it. */
enum StackMerge:
  case Clean(pr: StackPr)
  case Conflict(pr: StackPr, files: List[String])

  def render: String = this match
    case Clean(pr)           => s"#${pr.number}  clean"
    case Conflict(pr, files) => (s"#${pr.number}  CONFLICT in:" :: files.map(f => s"      $f")).mkString("\n")
