package piabrota.scripts

import java.time.{Instant, ZoneOffset}
import java.util.regex.Pattern
import piabrota.lib.die

/** `piabrota pins`: moves the website pins to the head of their source's main. Run by
  * `just site-pins`, `just <site>-pin` and the `*-pin` workflows, on a workstation or a runner.
  */
object Pins:
  val usage: String =
    """Move the website pins to the head of their source's main.
      |
      |For each site: rev, the source hash and the numbers the site reads from its commit (commits, the
      |README's history, npmDepsHash and version), then a build with this flake's nixpkgs, so a pin that
      |does not build never reaches a pull request.
      |
      |  piabrota pins all                 every site               (just site-pins)
      |  piabrota pins all closed proof    those sites only
      |  piabrota pins all --list          each pin and the head of its main; writes nothing
      |  piabrota pins one ww3 [sha]       one site, to the head of main or to <sha>
      |                                    (just ww3-pin, just room-pin, the *-pin workflows)
      |  PIN_BUILD=0 ...                   move the pins and build nothing
      |
      |`all` prints one line per site: `<site> same <sha>`, `<site> moved <old> <new>` or
      |`<site> FAILED <step>`; a site that fails is put back as it was, the others go on, and the exit
      |status is 1 if one failed. `one` prints `old=<sha>` and `new=<sha>` on its last two lines, or
      |`same=true` when the pin is already there. It needs `nix` with flakes and `git`; it reads the
      |sources anonymously, so it needs no token. It writes only the pinned files and `result-<site>`
      |links, in the top of the git checkout it runs in. The site-pins skill (hermes/skills/site-pins)
      |says how to open the pull request.""".stripMargin

  private val nix = List("nix", "--extra-experimental-features", "nix-command", "--extra-experimental-features", "flakes")

  def run(args: List[String]): Int =
    val config = PinsConfig(piabrota.lib.Repo.root(), build = sys.env.getOrElse("PIN_BUILD", "1") == "1")
    args match
      case ("-h" | "--help") :: _ => println(usage); 0
      case "one" :: rest          => one(config, rest)
      case "all" :: rest          => all(config, rest)
      case _                      => println(usage); 2

  def revOf(text: String, revname: String): Option[String] =
    s"""(?m)^ *$revname = "([0-9a-f]{40})";""".r.findFirstMatchIn(text).map(_.group(1))

  /** The pinned file with rev, the hash after `repo = "<name>";` and the extra values moved. */
  def rewrite(text: String, site: PinSite, old: String, sha: String, values: PinValues): PinStep[String] =
    for
      t <- replace(text, s"""(?m)^ *${site.revname} = "($old)";""", sha, site.revname)
      t <- replace(t, s"""${Pattern.quote(s"repo = \"${site.repo.name}\";")}(?:.*\\n)*? *hash = "(sha256-[^"]*)";""",
        values.hash, "hash")
      t <- values.commits.fold(Right(t))(n => replace(t, """(?m)^ *commits = (\d+);""", n.toString, "commits"))
      t <- values.npm.fold(Right(t)) { npm =>
        replace(t, """(?m)^ *npmDepsHash = "([^"]*)";""", npm.depsHash, "npmDepsHash")
          .flatMap(replace(_, """(?m)^ *version = "([^"]*)";""", npm.version, "version"))
      }
    yield t

  /** `text` with the first group of the first match of `regex` replaced by `value`. */
  private def replace(text: String, regex: String, value: String, what: String): PinStep[String] =
    regex.r.findFirstMatchIn(text).toRight(s"the rewrite of $what")
      .map(m => text.substring(0, m.start(1)) + value + text.substring(m.end(1)))

  /** nixpkgs' version of an unreleased package: `0-unstable-<day of the commit, UTC>`. */
  def unstableVersion(epochSecond: Long): String =
    s"0-unstable-${Instant.ofEpochSecond(epochSecond).atOffset(ZoneOffset.UTC).toLocalDate}"

  /** What `all` does with a site whose pin is `old` and whose main is at `head`: the line to print,
    * or `Right(old)` to move it.
    */
  def next(site: PinSite, old: Option[String], head: String, listing: Boolean): Either[PinLine, String] =
    old match
      case None                        => Left(PinLine.Failed(site.name, s"no ${site.revname} in ${site.file}"))
      case Some(_) if !Sha.isSha(head) => Left(PinLine.Failed(site.name, s"the head of ${site.repo.render}'s main"))
      case Some(o) if head == o        => Left(PinLine.Same(site.name, o))
      case Some(o) if listing          => Left(PinLine.Behind(site.name, o, head))
      case Some(o)                     => Right(o)

  /** The program's stdout; its stderr goes to ours. */
  private def out(root: os.Path, cmd: String*): PinStep[String] =
    val r = os.proc(cmd).call(cwd = root, stdin = os.Inherit, stdout = os.Pipe, stderr = os.Inherit, check = false)
    if r.exitCode == 0 then Right(r.out.text())
    else Left(s"CalledProcessError ${cmd.mkString(" ")}: exit ${r.exitCode}")

  private def headOf(root: os.Path, repo: RepoSlug): PinStep[String] =
    out(root, "git", "ls-remote", repo.gitUrl, "refs/heads/main").map(_.split("\t", 2)(0).strip())

  /** fetchFromGitHub's hash is the NAR hash of the unpacked tarball, as `flake prefetch` gives it.
    * Where the tarball cannot be had, the same tree over git gives the same hash (a source with
    * export-ignore in .gitattributes would differ; the build then fails on the hash).
    */
  private def prefetch(root: os.Path, repo: RepoSlug, rev: String): PinStep[Prefetched] =
    List(s"github:${repo.render}/$rev", s"git+https://github.com/${repo.render}?rev=$rev&shallow=1").iterator
      .flatMap(ref => out(root, (nix ++ List("flake", "prefetch", "--json", ref))*).toOption)
      .flatMap(Prefetched.parse)
      .nextOption()
      .toRight("prefetch")

  private def valuesFor(root: os.Path, site: PinSite, sha: String, work: os.Path): PinStep[PinValues] =
    prefetch(root, site.repo, sha).flatMap { src =>
      val values = PinValues(src.hash)
      site.extra match
        case PinExtra.Nothing => Right(values)
        case PinExtra.Commits =>
          // A clone with no blobs is enough for a count, and stays small.
          val gitDir = work / s"${site.name}.git"
          for
            _ <- out(root, "git", "clone", "--quiet", "--bare", "--filter=blob:none", site.repo.gitUrl,
              gitDir.toString).left.map(_ => "clone")
            count <- out(root, "git", "-C", gitDir.toString, "rev-list", "--count", sha)
          yield values.copy(commits = Some(count.strip().toLong))
        case PinExtra.Npm =>
          for
            store <- src.storePath.toRight("KeyError storePath")
            lock = os.Path(store) / "package-lock.json"
            npm <- out(root, (nix ++ List("run", "nixpkgs#prefetch-npm-deps", "--", lock.toString))*)
            hash <- npm.strip().linesIterator.toList.lastOption.filter(_.startsWith(Prefetched.hashPrefix))
              .toRight("prefetch-npm-deps")
            modified <- src.lastModified.toRight("KeyError lastModified")
          yield values.copy(npm = Some(NpmPin(hash, unstableVersion(modified))))
    }

  private def build(config: PinsConfig, site: PinSite): PinStep[Unit] =
    if !config.build then Right(())
    else
      val expr = "let f = builtins.getFlake (toString ./.); " +
        "pkgs = import f.inputs.nixpkgs { system = builtins.currentSystem; }; " +
        s"in pkgs.callPackage ./${site.file} { }"
      // The build log goes to stderr, so that stdout keeps only this command's lines.
      val r = os.proc(nix, "build", "--impure", "-o", site.link, "--print-build-logs", "--expr", expr)
        .call(cwd = config.root, stdin = os.Inherit, stdout = os.ProcessOutput.Readlines(System.err.println),
          stderr = os.Inherit, check = false)
      if r.exitCode == 0 && os.exists(config.root / site.link / os.RelPath(site.must)) then Right(()) else Left("build")

  /** Moves one pin to `sha` with `values`, then `build`s it; on a failure, puts the file back. */
  def move(path: os.Path, site: PinSite, sha: String, values: => PinStep[PinValues], build: => PinStep[Unit]): PinStep[Unit] =
    val orig = os.read(path)
    val old = revOf(orig, site.revname).getOrElse("")
    val done = for
      v <- values
      text <- rewrite(orig, site, old, sha, v)
      _ = os.write.over(path, text)
      _ <- build
    yield ()
    if done.isLeft then os.write.over(path, orig)
    done

  private def move(config: PinsConfig, site: PinSite, sha: String, work: os.Path): PinStep[Unit] =
    move(config.root / os.RelPath(site.file), site, sha, valuesFor(config.root, site, sha, work), build(config, site))

  private def one(config: PinsConfig, args: List[String]): Int =
    val site = args.headOption.flatMap(PinSite.byName.get)
      .getOrElse(die(s"usage: piabrota pins one <${PinSite.all.map(_.name).mkString("|")}> [sha]"))
    val old = revOf(os.read(config.root / os.RelPath(site.file)), site.revname)
      .getOrElse(die(s"no ${site.revname} in ${site.file}"))
    val sha = args.lift(1).getOrElse(headOf(config.root, site.repo).fold(die(_), identity))
    if !Sha.isSha(sha) then die(s"not a whole commit (40 hex characters): $sha")
    if sha == old then
      println(s"${site.name} is pinned at $old already.")
      println("same=true")
      0
    else
      val work = os.temp.dir(prefix = "pins")
      try move(config, site, sha, work).left.foreach(step => die(s"${site.name}: $step failed; ${site.file} is as it was"))
      finally os.remove.all(work)
      println(s"old=$old")
      println(s"new=$sha")
      0

  private def all(config: PinsConfig, args: List[String]): Int =
    val listing = args.headOption.contains("--list")
    val wanted = if listing then args.tail else args
    val unknown = wanted.filterNot(PinSite.byName.contains)
    if unknown.nonEmpty then
      die(s"no such site: ${unknown.mkString(" ")} (the sites: ${PinSite.all.map(_.name).mkString(" ")})")
    def say(line: PinLine): PinLine = { println(line.render); System.out.flush(); line }
    val work = os.temp.dir(prefix = "pins")
    try
      val lines = PinSite.all.filter(s => wanted.isEmpty || wanted.contains(s.name)).map { site =>
        val old = revOf(os.read(config.root / os.RelPath(site.file)), site.revname)
        // The head is asked for only when there is a pin to compare it with.
        val head = old.fold("")(_ => headOf(config.root, site.repo).getOrElse(""))
        say(next(site, old, head, listing).fold(identity, o =>
          move(config, site, head, work).fold(PinLine.Failed(site.name, _), _ => PinLine.Moved(site.name, o, head))))
      }
      if lines.exists(_.failed) then 1 else 0
    finally os.remove.all(work)
