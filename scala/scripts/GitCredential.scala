package piabrota.scripts

import piabrota.lib.env

/** git credential helpers that hand over a token file by the repository's path, which git sends
  * with credential.useHttpPath. They answer `get` only; for anything else, or a repository with no
  * token, they print nothing and git goes on with no password.
  */
object GitCredential:
  /** The token file `name` in `dir`, when the name is one plain file name and the file is readable. */
  private def answer(dir: os.Path, name: String): Unit =
    Some(name).filter(CredentialRequest.plain).map(dir / _).filter(Util.readable).foreach { file =>
      print(CredentialRequest.answer(Util.readToken(file)))
    }

  private def requestedPath(): String = CredentialRequest.path(scala.io.Source.stdin.getLines())

  /** `piabrota hermes-git-credential get` (hermes-github.nix): Hermes's token of the repository's
    * owner from $HERMES_GIT_TOKENS. The repositories in $HERMES_GIT_MAROLA_REPOS (space-separated,
    * owner/name) take marola-pr-bot's token instead and fail closed: no such token, no password,
    * and never the owner's.
    */
  def hermes(args: List[String]): Int =
    if args.headOption.contains("get") then
      val config = HermesCredentialConfig(
        os.Path(env("HERMES_GIT_TOKENS").getOrElse(TokenFiles.hermesDir)),
        env("HERMES_GIT_MAROLA_REPOS").getOrElse("").split(' ').filter(_.nonEmpty).map(_.toLowerCase).toSet)
      answer(config.tokens, config.tokenName(requestedPath()))
    0

  /** `piabrota openrig-git-credential get` (openrig.nix): a seat's read-only token of the repository,
    * `$OPENRIG_SEAT_TOKENS/<owner>--<name>`, written by hermes-github.nix and marola-bot.nix.
    */
  def seat(args: List[String]): Int =
    if args.headOption.contains("get") then
      val tokens = os.Path(env("OPENRIG_SEAT_TOKENS").getOrElse(TokenFiles.seatDir))
      SeatCredential.tokenName(requestedPath()).foreach(answer(tokens, _))
    0
