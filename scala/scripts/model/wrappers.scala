package piabrota.scripts

import EnvNames.*

// The wrappers in front of gh, omp, claude and git for Hermes and the OpenRig seats: what they let
// through, and the program and environment they exec.

/** The gh commands marola-gh lets through: they propose and read only (humans merge and review). */
object MarolaGh:
  val allowed: Set[String] = Set("pr create", "pr view", "pr list", "pr diff", "pr checks", "pr status",
    "pr comment", "pr edit", "issue view", "issue list", "issue comment")

  /** The first two arguments decide, so a global flag before the subcommand is refused too. */
  def allows(args: List[String]): Boolean = allowed(s"${args.lift(0).getOrElse("")} ${args.lift(1).getOrElse("")}")

/** The Claude tokens of the caller's environment. */
final case class ClaudeTokens(anthropicOauth: Option[String], claudeOauth: Option[String], apiKey: Option[String]):
  /** An API key that is a subscription token, which must not be sent as an API key. */
  def subscriptionKey: Option[String] = apiKey.filter(isSubscription)

/** `choom -n 500 --`: the kernel's OOM killer picks the program before its caller. */
object Choom:
  def args(choom: String): List[String] = List(choom, "-n", "500", "--")

/** omp's wrapper settings (omp/wrapper.nix, makeWrapper `--set`). */
final case class OmpSettings(config: String, append: String, ceiling: String, bin: String, timeout: String, choom: String)

object OmpSettings:
  val names: List[String] = List("OMP_CONFIG", "OMP_APPEND", "OMP_CEILING", "OMP_BIN", "OMP_TIMEOUT", "OMP_CHOOM")
  /** OMP_CEILING for no time ceiling (a seat). */
  val noCeiling = "none"

  /** omp with its ceiling, choom, its config overlay and its token. omp reads ANTHROPIC_OAUTH_TOKEN;
    * Hermes's token is CLAUDE_CODE_OAUTH_TOKEN, the same subscription; a subscription token that
    * OpenRig's runner passes as ANTHROPIC_API_KEY moves to ANTHROPIC_OAUTH_TOKEN, so omp never
    * sends it as an API key. The wrapper's settings are unset again.
    */
  def exec(s: OmpSettings, tokens: ClaudeTokens, args: List[String]): Exec =
    val oauth = tokens.anthropicOauth.orElse(tokens.claudeOauth)
    val (token, unset) = (oauth, tokens.subscriptionKey) match
      case (None, Some(key)) => (key, List(anthropicApiKey))
      case _                 => (oauth.getOrElse(""), Nil)
    val limit =
      if s.ceiling == noCeiling then Nil
      else List(s.timeout, "--signal=TERM", "--kill-after=30s", s.ceiling)
    Exec(limit ++ Choom.args(s.choom) ++ List(s.bin, "--append-system-prompt", s.append) ++ args,
      set = Map("PI_CONFIG_FILES" -> s.config, anthropicOauth -> token, "OTEL_SDK_DISABLED" -> "true",
        "PI_NO_TITLE" -> "1", "PI_PY" -> "0", "PI_JS" -> "0"),
      unset = unset ++ names)

/** seat-claude's wrapper settings (openrig.nix). */
final case class SeatClaudeSettings(bin: String, choom: String)

object SeatClaudeSettings:
  val names: List[String] = List("SEAT_CLAUDE_BIN", "SEAT_CHOOM")

  /** What outranks CLAUDE_CODE_OAUTH_TOKEN for Claude Code, dropped for Claude's process only. */
  val dropped: List[String] = List(anthropicAuth, "CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX",
    "CLAUDE_CODE_USE_FOUNDRY", anthropicApiKey)

  /** A subscription token in ANTHROPIC_API_KEY moves to CLAUDE_CODE_OAUTH_TOKEN (unless that is set);
    * anything else there (an API key) is dropped, so Claude cannot bill an API key by accident.
    */
  def exec(s: SeatClaudeSettings, tokens: ClaudeTokens, args: List[String]): Exec =
    val moved = tokens.subscriptionKey.map(key => claudeOauth -> tokens.claudeOauth.getOrElse(key))
    Exec(Choom.args(s.choom) ++ (s.bin :: args), set = moved.toMap, unset = dropped ++ names)

/** The seats' clones: through the seat credential helper, set in the clone's own config. */
object SeatClone:
  val marolaOrg = "marola-dev"
  val chaceon: RepoSlug = RepoSlug("h0ffmann", "chaceon")
  val helper: List[String] = List("--config",
    "credential.helper=/etc/profiles/per-user/openrig/bin/openrig-git-credential",
    "--config", "credential.useHttpPath=true")

  def clone(repo: RepoSlug, dir: String): List[String] =
    List("git", "clone", "--filter=blob:none") ++ helper ++ List(repo.gitUrl, dir)

  /** A name or `marola-dev/name` without the org. */
  def marolaName(s: String): String = s.stripPrefix(s"$marolaOrg/")

/** openrig-claude-token's DEST: Hermes's Claude token as the seats' ANTHROPIC_API_KEY, or empty. */
object SeatClaudeToken:
  def render(source: Seq[String]): String =
    lastValue(source, claudeOauth).map(token => s"$anthropicApiKey=$token\n").getOrElse("")
