package piabrota.scripts

import piabrota.lib.{Sh, die, env}

/** The root units that turn a GitHub App's key into installation tokens of one hour, every 45
  * minutes. Each takes a JSON file of its settings, written by its Nix module, and never fails its
  * unit: a refusal by GitHub prints a line and exits 0.
  */
object GithubTokens:
  private val refusedJwt = "GitHub refused the App's JWT: check GH_APP_ID and the key"

  /** The command's settings file, parsed, or the command stops. */
  private def config[A](args: List[String], command: String)(parse: ujson.Value => Either[String, A]): A = args match
    case List(file) => parse(ujson.read(os.read(os.Path(file, os.pwd)))).fold(e => die(s"$command: $e", 2), identity)
    case _          => die(s"usage: piabrota $command CONFIG.json", 2)

  /** The unit's credentials directory, or the command stops. */
  private def credentials(): os.Path =
    os.Path(env(EnvNames.credentialsDirectory).getOrElse(die(s"${EnvNames.credentialsDirectory} is not set", 1)))

  /** `piabrota hermes-github-token CONFIG.json` (hermes-github.nix): a token per account in
    * `owners` the App is installed on, for git (through `helper`, by the repository's owner) and gh
    * (the first token); read-only tokens for the OpenRig seats (`seatRepos`); the bot's git identity
    * and gh's hosts.yml in Hermes's home, with `marolaGitconfig` appended to the git config.
    */
  def hermes(args: List[String]): Int =
    val c = config(args, "hermes-github-token")(HermesTokenConfig.parse)
    val app = GithubApp.load(credentials() / AppCredential.file)
    app.installations() match
      case None =>
        println(refusedJwt)
        0
      case Some(installations) =>
        val request = TokenRequest(None, c.permissions)
        val minted = c.owners.flatMap { owner =>
          Installation.on(installations, owner) match
            case None =>
              os.remove(c.tokens / owner)
              println(s"$owner: the App is not installed there")
              None
            case Some(id) =>
              app.mint(id, request) match
                case Some(token) =>
                  Util.put(c.tokens / owner, token, Owner.rootHermes, Mode.GroupRead, tmpName = s".$owner")
                  println(s"$owner: token for one hour")
                  Some(token)
                case None =>
                  println(s"$owner: GitHub refused a token")
                  None
        }
        for repo <- c.seatRepos do
          val file = c.seatTokens / repo.seatTokenName
          Installation.on(installations, repo.owner).flatMap(app.mint(_, TokenRequest.readOnly(repo.name))) match
            case Some(token) =>
              Util.put(file, token, Owner.rootOpenrig, Mode.GroupRead)
              println(s"${repo.render}: read-only token for the seats, for one hour")
            case None =>
              os.remove(file)
              println(s"${repo.render}: no read-only token for the seats (is the App installed on it?)")
        minted.headOption.foreach { first =>
          val bot = app.identity(first)
          Sh.run("install", "-d", "-o", Owner.hermes.user, "-g", Owner.hermes.group, "-m", "0750", c.home / ".config",
            c.home / ".config" / "gh")
          Util.put(c.home / ".gitconfig", bot.hermesGitconfig(c.helper, c.marolaGitconfig), Owner.hermes, Mode.OwnerOnly)
          Util.put(c.home / ".config" / "gh" / "hosts.yml", bot.ghHosts(first), Owner.hermes, Mode.OwnerOnly)
        }
        0

  /** `piabrota marola-bot-token CONFIG.json` (marola-bot.nix): marola-pr-bot's operator token for
    * Hermes on the repositories `names` of `owner`, a read-only token per repository for the seats,
    * and the bot's git identity for hermes-github.nix's includeIf blocks.
    */
  def marola(args: List[String]): Int =
    val c = config(args, "marola-bot-token")(MarolaTokenConfig.parse)
    val repos = c.names.map(RepoSlug(c.owner, _))
    val operatorFile = c.tokens / TokenFiles.marolaBot
    val app = GithubApp.load(credentials() / AppCredential.file)
    app.installations().map(Installation.on(_, c.owner)) match
      case None =>
        println(refusedJwt)
      case Some(None) =>
        os.remove(operatorFile)
        repos.foreach(r => os.remove(c.seatTokens / r.seatTokenName))
        println(s"${c.owner}: marola-pr-bot is not installed there")
      case Some(Some(id)) =>
        // The operator token, for Hermes: one request for all the repos.
        val operator = app.mint(id, TokenRequest(Some(c.names), Permissions.operator))
        operator match
          case Some(token) =>
            Util.put(operatorFile, token, Owner.rootHermes, Mode.GroupRead)
            println(s"${c.owner}: operator token for one hour")
          case None =>
            os.remove(operatorFile)
            println(s"${c.owner}: GitHub refused the operator token")
        for repo <- repos do
          app.mint(id, TokenRequest.readOnly(repo.name)) match
            case Some(token) =>
              Util.put(c.seatTokens / repo.seatTokenName, token, Owner.rootOpenrig, Mode.GroupRead)
              println(s"${repo.render}: read-only token for the seats, for one hour")
            case None =>
              os.remove(c.seatTokens / repo.seatTokenName)
              println(s"${repo.render}: no read-only token for the seats")
        operator.foreach { token =>
          // Who Hermes commits as on these repos.
          val bot = app.identity(token)
          if !bot.hasUserId then println(s"${c.owner}: no bot user id, the identity file stays as it is")
          else Util.put(c.home / ".gitconfig-marola-bot", bot.gitconfig, Owner.hermes, Mode.OwnerOnly)
        }
    0

  /** `piabrota tyler-durden-token CONFIG.json` (tyler-durden-bot.nix): a token of tyler-durden-bot
    * for `repository`, pull requests write only, for its Hermes profile, whose .env also gets the
    * Claude token of Hermes's own env file (credential `hermes`), since a profile reads only its own.
    */
  def tylerDurden(args: List[String]): Int =
    val c = config(args, "tyler-durden-token")(TylerTokenConfig.parse)
    val repo = c.repository
    val creds = credentials()
    val app = GithubApp.load(creds / AppCredential.file)
    app.api(GithubApi.repoInstallation(repo)).flatMap(Jq.field(_, "id")) match
      case None =>
        println(s"tyler-durden-bot is not installed on ${repo.render}, or GitHub refused the App's JWT")
      case Some(id) =>
        app.mint(id, TokenRequest(Some(List(repo.name)), Permissions.pullRequests)) match
          case None => println(s"${repo.render}: GitHub refused a token")
          case Some(token) =>
            Util.put(c.tokens / "token", token, Owner.rootHermes, Mode.GroupRead, tmpName = ".token")
            Sh.run("install", "-d", "-o", Owner.hermes.user, "-g", Owner.hermes.group, "-m", "0750", c.profileDir)
            val hermesEnv = creds / "hermes"
            val claude = if os.isFile(hermesEnv) then
              os.read.lines(hermesEnv).filter(_.startsWith(s"${EnvNames.claudeOauth}=")).map(_ + "\n").mkString
            else ""
            Util.put(c.profileDir / ".env", s"${EnvNames.ghToken}=$token\n$claude", Owner.hermes, Mode.OwnerOnly)
            println(s"${repo.render}: token for one hour")
    0
