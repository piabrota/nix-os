package piabrota.scripts

/** The user and group a written file gets (`chown user:group`). */
final case class Owner(user: String, group: String):
  def render: String = s"$user:$group"

object Owner:
  val hermes: Owner = Owner("hermes", "hermes")
  val openrig: Owner = Owner("openrig", "openrig")
  val marola: Owner = Owner("marola", "marola")
  val rootHermes: Owner = Owner("root", "hermes")
  val rootOpenrig: Owner = Owner("root", "openrig")

/** The mode of a written file. */
enum Mode(val perms: String):
  case OwnerOnly extends Mode("rw-------")
  case GroupRead extends Mode("rw-r-----")

/** A program to `exec`, with the environment it gets: `set` added, `unset` removed. */
final case class Exec(cmd: List[String], set: Map[String, String] = Map.empty, unset: List[String] = Nil)

/** A GitHub repository, `owner/name`. */
final case class RepoSlug(owner: String, name: String):
  def render: String = s"$owner/$name"
  def gitUrl: String = s"https://github.com/$render.git"

  /** The file of a seat's read-only token of this repository (hermes-github.nix, marola-bot.nix). */
  def seatTokenName: String = s"$owner--$name"

object RepoSlug:
  /** sh's `${s%%/*}` and `${s#*/}`: before and after the first slash (all of `s` after, if none). */
  def parse(s: String): RepoSlug =
    RepoSlug(s.takeWhile(_ != '/'), if s.contains('/') then s.substring(s.indexOf('/') + 1) else s)

/** The systemd units that several commands name. */
object Units:
  val hermesAgent = "hermes-agent.service"
  val hermesBackend = "hermes-backend.service"
  val openrig = "openrig.service"

/** Paths of a NixOS box. */
object BoxPaths:
  val currentSystem = "/run/current-system"
  val bootedSystem = "/run/booted-system"
  val systemProfile = "/nix/var/nix/profiles/system"

/** The environment variables the token units and the wrappers read, write or drop. */
object EnvNames:
  val claudeOauth = "CLAUDE_CODE_OAUTH_TOKEN"
  val anthropicOauth = "ANTHROPIC_OAUTH_TOKEN"
  val anthropicApiKey = "ANTHROPIC_API_KEY"
  val anthropicAuth = "ANTHROPIC_AUTH_TOKEN"
  val ghToken = "GH_TOKEN"
  val credentialsDirectory = "CREDENTIALS_DIRECTORY"

  /** A Claude subscription token, as opposed to an API key. */
  val subscriptionPrefix = "sk-ant-oat"
  def isSubscription(token: String): Boolean = token.startsWith(subscriptionPrefix)

  /** The value of the last `NAME=` line of an env file's lines. */
  def lastValue(lines: Seq[String], name: String): Option[String] =
    lines.filter(_.startsWith(s"$name=")).lastOption.map(_.stripPrefix(s"$name="))

/** A line's priority for journald: `<3>` is logged as an error, `<4>` as a warning. */
enum Priority(val prefix: String):
  case Error extends Priority("<3>")
  case Warning extends Priority("<4>")
  case Info extends Priority("")

  def apply(line: String): String = prefix + line
