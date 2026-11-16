package piabrota.scripts

import piabrota.lib.{Sh, die}

/** `piabrota commit-counts`: the human and agent commits of each own repository, for
  * mockups/data.nix. Run by `just commit-counts` on a workstation.
  */
object CommitCounts:
  val usage: String =
    """Count the commits on the default branch of each repository that the org owns, split into human
      |and agent, and print one line for each, ready to paste into mockups/data.nix:
      |
      |  nix-os: commits = { human = 104; agent = 63; };
      |
      |A commit is agent when its GitHub author login ends with [bot] or is exactly "claude" (the
      |account that GitHub maps Claude Code's commit author to). Every other commit is human. A commit
      |that a person made with an agent's help under their own name counts as human, because the
      |repository's rule is "no agent trail in a commit", so the count is a floor for agent work.
      |
      |Read-only: it only calls `gh api` (GET). It needs `gh`, logged in. It prints no token.
      |Without arguments it reads the names of the qualifying projects from mockups/data.nix with
      |nix-instantiate: the projects whose repository is the org's own and not a card for another
      |repository (origin "own", no `repository`). With arguments, it counts those repositories.
      |A repository that answers with an error prints "<name>: no data" and the exit status is 1.
      |
      |  piabrota commit-counts              (or: just commit-counts)
      |  piabrota commit-counts nix-os mu
      |
      |COMMIT_COUNTS_OWNER names another owner (default: piabrota).""".stripMargin

  def run(args: List[String]): Int = args match
    case ("-h" | "--help") :: _ => println(usage); 0
    case _ =>
      val config = CommitCountsConfig(sys.env.getOrElse("COMMIT_COUNTS_OWNER", CommitCountsConfig.defaultOwner),
        piabrota.lib.Repo.root() / "mockups" / "data.nix")
      val names = if args.nonEmpty then args else projectNames(config.data)
      val failed = names.map { name =>
        loginsOf(config.owner, name) match
          case None =>
            println(s"$name: no data"); true
          case Some(logins) =>
            println(s"$name: ${CommitCount.of(logins).render}"); false
      }
      if failed.contains(true) then 1 else 0

  private def projectNames(data: os.Path): List[String] =
    val expr = s"""
      let d = import $data;
      in builtins.concatStringsSep "\\n"
        (map (p: p.name) (builtins.filter (p: d.origin p == "own" && !(p ? repository)) d.projects))"""
    Sh.outOpt("nix-instantiate", "--eval", "--raw", "--expr", expr)
      .getOrElse(die("commit-counts: cannot read the project names from mockups/data.nix", 2))
      .split("\\s+").filter(_.nonEmpty).toList

  private def loginsOf(owner: String, name: String): Option[List[String]] =
    // --jq prints one author login for each commit; "-" stands for a commit with no GitHub account.
    val r = Sh.call("gh", "api", "--paginate", s"repos/$owner/$name/commits?per_page=100", "--jq",
      """.[] | (.author.login // "-")""")
    Option.when(r.exitCode == 0)(r.out.text().split("\\s+").filter(_.nonEmpty).toList)
