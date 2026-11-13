#!/usr/bin/env python3
"""Plan and check a PR stack (.agents/skills/pr-stack/SKILL.md).

  pr_stack.py plan  <pr>...           merge the PR heads, in order, onto origin/main in git's object
                                      store only (merge-tree), and name each PR that conflicts
  pr_stack.py check <branch> <pr>...  the stack branch is ready for one merge commit: not behind
                                      origin/main, and every PR head is in it, so GitHub marks each
                                      PR merged by the stack's merge

It changes no branch and pushes nothing. The PR heads are fetched to refs/pr-stack/<pr>.
"""

import subprocess
import sys

USAGE = "usage: pr_stack.py plan <pr>... | check <branch> <pr>..."


def git(*args, check=True):
    done = subprocess.run(["git", *args], text=True, stdout=subprocess.PIPE, check=False)
    if check and done.returncode != 0:
        raise subprocess.CalledProcessError(done.returncode, ["git", *args], done.stdout)
    return done


def die(msg):
    print(f"pr-stack: {msg}", file=sys.stderr)
    sys.exit(2)


def fetch(prs):
    git("fetch", "-q", "origin", "main")
    for pr in prs:
        if git("fetch", "-q", "-f", "origin", f"pull/{pr}/head:refs/pr-stack/{pr}", check=False).returncode:
            die(f"no PR #{pr} on origin")


def rev(ref, short=False):
    return git("rev-parse", *(["--short"] if short else []), ref).stdout.strip()


def plan(prs):
    if not prs:
        die("usage: pr_stack.py plan <pr>...")
    fetch(prs)
    tip, bad = rev("origin/main"), False
    for pr in prs:
        head = rev(f"refs/pr-stack/{pr}")
        out = git("merge-tree", "--write-tree", "--name-only", "--no-messages", tip, head, check=False)
        lines = out.stdout.splitlines()
        if out.returncode == 0:
            tip = git("commit-tree", lines[0], "-p", tip, "-p", head, "-m", f"plan #{pr}").stdout.strip()
            print(f"#{pr}  clean")
        else:
            # Go on from the tip before this PR, so the next lines still say something.
            bad = True
            print(f"#{pr}  CONFLICT in:")
            for name in lines[1:]:
                print(f"      {name}")
    if not bad:
        print(f"plan: all {len(prs)} PRs stack cleanly on origin/main, in this order")
    return int(bad)


def check(args):
    if len(args) < 2:
        die("usage: pr_stack.py check <branch> <pr>...")
    branch, prs = args[0], args[1:]
    fetch(prs)
    if git("fetch", "-q", "origin", branch, check=False).returncode:
        die(f"no branch {branch} on origin")
    tip, bad = rev("FETCH_HEAD"), False
    if git("merge-base", "--is-ancestor", "origin/main", tip, check=False).returncode == 0:
        print(f"ok    {branch} contains origin/main")
    else:
        bad = True
        print(f"FAIL  {branch} is behind origin/main: git merge origin/main into it (never rebase)")
    for pr in prs:
        short = rev(f"refs/pr-stack/{pr}", short=True)
        if git("merge-base", "--is-ancestor", f"refs/pr-stack/{pr}", tip, check=False).returncode == 0:
            print(f"ok    #{pr} head {short} is in the stack")
        else:
            bad = True
            print(f"FAIL  #{pr} head {short} is not in the stack: its branch moved, merge it again")
    if not bad:
        print(f"check: merge {branch} with a merge commit (not squash, not rebase)")
    return int(bad)


def main(argv):
    cmd, rest = (argv[0], argv[1:]) if argv else ("", [])
    if cmd == "plan":
        return plan(rest)
    if cmd == "check":
        return check(rest)
    die(USAGE)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
