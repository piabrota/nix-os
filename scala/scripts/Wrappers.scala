package piabrota.scripts

import piabrota.lib.{Sh, die, env}

/** The small programs that stand in front of another one for Hermes and the OpenRig seats:
  * they check or move a credential, then `exec` the real program, so its pid, signals and cgroup
  * stay the caller's.
  */
object Wrappers:
  /** `piabrota marola-gh <gh args>` (marola-bot.nix): gh as marola-pr-bot, for the commands that
    * propose and read only. The token is $MAROLA_GH_TOKENS/marola-pr-bot.
    */
  def marolaGh(args: List[String]): Int =
    if !MarolaGh.allows(args) then die(s"marola-gh: ${args.mkString(" ")} is not allowed (humans merge and review)", 2)
    val token = os.Path(env("MAROLA_GH_TOKENS").getOrElse(TokenFiles.hermesDir)) / TokenFiles.marolaBot
    if !Util.readable(token) then die("marola-gh: no marola-pr-bot token (is marola-bot-token running?)", 1)
    Util.exec(Exec("gh" :: args, set = Map(EnvNames.ghToken -> Util.readToken(token))))

  /** A setting a wrapper gets from its Nix module (makeWrapper `--set`); the wrapper unsets it again
    * before the exec, so that the program and its children never see it.
    */
  private def setting(name: String): String = env(name).getOrElse(die(s"$name is not set (the Nix wrapper sets it)", 2))

  private def claudeTokens(): ClaudeTokens =
    ClaudeTokens(env(EnvNames.anthropicOauth), env(EnvNames.claudeOauth), env(EnvNames.anthropicApiKey))

  /** `piabrota omp [args...]` (omp/wrapper.nix): oh-my-pi with its own read-only config overlay
    * (OMP_CONFIG, as PI_CONFIG_FILES) and the rules OMP_APPEND appended to its system prompt.
    * OMP_CEILING is a `timeout` duration for the whole run (SIGTERM, SIGKILL 30 s later), or `none`.
    * OMP_BIN, OMP_TIMEOUT and OMP_CHOOM are the programs. `OmpSettings.exec` says what moves.
    */
  def omp(args: List[String]): Int =
    val List(config, append, ceiling, bin, timeout, choom) = OmpSettings.names.map(setting): @unchecked
    Util.exec(OmpSettings.exec(OmpSettings(config, append, ceiling, bin, timeout, choom), claudeTokens(), args))

  /** `piabrota seat-claude [args...]` (openrig.nix): the `claude` of a Claude seat (SEAT_CLAUDE_BIN,
    * under SEAT_CHOOM as omp's). The unit gives every seat ANTHROPIC_API_KEY for the omp seats, which
    * Claude Code ranks above CLAUDE_CODE_OAUTH_TOKEN; `SeatClaudeSettings.exec` says what moves.
    */
  def seatClaude(args: List[String]): Int =
    val List(bin, choom) = SeatClaudeSettings.names.map(setting): @unchecked
    Util.exec(SeatClaudeSettings.exec(SeatClaudeSettings(bin, choom), claudeTokens(), args))

  /** `piabrota openrig-claude-token SOURCE DEST` (openrig.nix, ExecStartPre as root): the last line
    * CLAUDE_CODE_OAUTH_TOKEN= of SOURCE (Hermes's secrets), and nothing else, as ANTHROPIC_API_KEY=
    * in DEST, which only the openrig user reads; DEST is empty when the line or the source is
    * missing. It prints nothing.
    */
  def openrigClaudeToken(args: List[String]): Int = args match
    case List(source, dest) =>
      val lines = scala.util.Try(os.read.lines(os.Path(source, os.pwd))).toOption.toList.flatten
      Util.put(os.Path(dest, os.pwd), SeatClaudeToken.render(lines), Owner.openrig, Mode.OwnerOnly)
      0
    case _ => die("usage: piabrota openrig-claude-token SOURCE DEST", 2)

  /** `piabrota chaceon-clone [dir]` (openrig.nix): a seat's clone of h0ffmann/chaceon, with the
    * credential helper in the clone's own config, so a later fetch works after a deploy too. WW3/ is
    * public (metocean/WW3) and pinned by the superproject.
    */
  def chaceonClone(args: List[String]): Int =
    val dir = args.headOption.getOrElse(SeatClone.chaceon.name)
    val cloned = Util.run(SeatClone.clone(SeatClone.chaceon, dir))
    if cloned != 0 then cloned
    else if Sh.run("git", "-C", dir, "submodule", "update", "--init", "--depth", "1", "WW3") == 0 then 0
    else Sh.run("git", "-C", dir, "submodule", "update", "--init", "WW3")

  /** `piabrota marola-clone <name|marola-dev/name> [dir]` (openrig.nix): a seat's clone of one of
    * the repositories in $MAROLA_REPOS (space-separated, marola-dev/name), the way of chaceon-clone.
    * Any other name is refused.
    */
  def marolaClone(args: List[String]): Int =
    val repos = env("MAROLA_REPOS").getOrElse("").split(' ').filter(_.nonEmpty).toList
    args match
      case Nil => die("usage: marola-clone <marola-front|marola-back|owner/name> [dir]", 2)
      case first :: rest =>
        val name = SeatClone.marolaName(first)
        if !repos.map(SeatClone.marolaName).contains(name) then
          die(s"marola-clone: $first is not one of: ${repos.mkString(" ")}", 2)
        Util.run(SeatClone.clone(RepoSlug(SeatClone.marolaOrg, name), rest.headOption.getOrElse(name)))
