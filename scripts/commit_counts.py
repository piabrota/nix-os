#!/usr/bin/env python3
"""Count the commits on the default branch of each repository that the org owns, split into human
and agent, and print one line for each, ready to paste into mockups/data.nix:

  nix-os: commits = { human = 104; agent = 63; };

A commit is agent when its GitHub author login ends with [bot] or is exactly "claude" (the
account that GitHub maps Claude Code's commit author to). Every other commit is human. A commit
that a person made with an agent's help under their own name counts as human, because the
repository's rule is "no agent trail in a commit", so the count is a floor for agent work.

Read-only: it only calls `gh api` (GET). It needs `gh`, logged in. It prints no token.
Without arguments it reads the names of the qualifying projects from mockups/data.nix with
nix-instantiate: the projects whose repository is the org's own and not a card for another
repository (origin "own", no `repository`). With arguments, it counts those repositories.
A repository that answers with an error prints "<name>: no data" and the exit status is 1.

  python3 scripts/commit_counts.py              (or: just commit-counts)
  python3 scripts/commit_counts.py nix-os mu

COMMIT_COUNTS_OWNER names another owner (default: piabrota).
"""

import os
import subprocess
import sys
from pathlib import Path

DATA = Path(__file__).resolve().parent.parent / "mockups/data.nix"


def is_agent(login):
    return login.endswith("[bot]") or login == "claude"


def count(logins):
    agent = sum(1 for x in logins if is_agent(x))
    return len(logins) - agent, agent


def project_names():
    expr = f"""
      let d = import {DATA};
      in builtins.concatStringsSep "\\n"
        (map (p: p.name) (builtins.filter (p: d.origin p == "own" && !(p ? repository)) d.projects))"""
    try:
        out = subprocess.run(
            ["nix-instantiate", "--eval", "--raw", "--expr", expr], check=True, text=True, stdout=subprocess.PIPE
        )
    except (OSError, subprocess.CalledProcessError):
        print("commit-counts: cannot read the project names from mockups/data.nix", file=sys.stderr)
        sys.exit(2)
    return out.stdout.split()


def logins_of(owner, name):
    # --jq prints one author login for each commit; "-" stands for a commit with no GitHub account.
    done = subprocess.run(
        [
            "gh",
            "api",
            "--paginate",
            f"repos/{owner}/{name}/commits?per_page=100",
            "--jq",
            '.[] | (.author.login // "-")',
        ],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return done.stdout.split() if done.returncode == 0 else None


def main(argv):
    if argv[:1] in (["-h"], ["--help"]):
        print(__doc__.strip())
        return 0
    owner = os.environ.get("COMMIT_COUNTS_OWNER", "piabrota")
    failed = 0
    for name in argv or project_names():
        logins = logins_of(owner, name)
        if logins is None:
            print(f"{name}: no data")
            failed = 1
            continue
        human, agent = count(logins)
        print(f"{name}: commits = {{ human = {human}; agent = {agent}; }};")
    return failed


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
