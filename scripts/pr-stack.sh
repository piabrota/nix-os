#!/bin/sh
# Plan and check a PR stack (.agents/skills/pr-stack/SKILL.md).
#   pr-stack.sh plan  <pr>...          merge the PR heads, in order, onto origin/main in git's object
#                                      store only (merge-tree), and name each PR that conflicts
#   pr-stack.sh check <branch> <pr>... the stack branch is ready for one merge commit: not behind
#                                      origin/main, and every PR head is in it, so GitHub marks each
#                                      PR merged by the stack's merge
# It changes no branch and pushes nothing. The PR heads are fetched to refs/pr-stack/<pr>.
set -eu

die() { echo "pr-stack: $*" >&2; exit 2; }

fetch() {
  git fetch -q origin main
  for pr in "$@"; do
    git fetch -q -f origin "pull/$pr/head:refs/pr-stack/$pr" || die "no PR #$pr on origin"
  done
}

plan() {
  [ $# -gt 0 ] || die "usage: pr-stack.sh plan <pr>..."
  fetch "$@"
  tip=$(git rev-parse origin/main)
  bad=0
  for pr in "$@"; do
    head=$(git rev-parse "refs/pr-stack/$pr")
    if out=$(git merge-tree --write-tree --name-only --no-messages "$tip" "$head"); then
      tip=$(git commit-tree "$out" -p "$tip" -p "$head" -m "plan #$pr")
      echo "#$pr  clean"
    else
      bad=1
      echo "#$pr  CONFLICT in:"
      echo "$out" | sed -n '2,$p' | sed 's/^/      /'
      # Go on from the tip before this PR, so the next lines still say something.
    fi
  done
  [ "$bad" -eq 0 ] && echo "plan: all $# PRs stack cleanly on origin/main, in this order"
  return "$bad"
}

check() {
  [ $# -gt 1 ] || die "usage: pr-stack.sh check <branch> <pr>..."
  branch=$1; shift
  fetch "$@"
  git fetch -q origin "$branch" || die "no branch $branch on origin"
  tip=$(git rev-parse FETCH_HEAD)
  bad=0
  if git merge-base --is-ancestor origin/main "$tip"; then
    echo "ok    $branch contains origin/main"
  else
    bad=1
    echo "FAIL  $branch is behind origin/main: git merge origin/main into it (never rebase)"
  fi
  for pr in "$@"; do
    if git merge-base --is-ancestor "refs/pr-stack/$pr" "$tip"; then
      echo "ok    #$pr head $(git rev-parse --short "refs/pr-stack/$pr") is in the stack"
    else
      bad=1
      echo "FAIL  #$pr head $(git rev-parse --short "refs/pr-stack/$pr") is not in the stack: its branch moved, merge it again"
    fi
  done
  [ "$bad" -eq 0 ] && echo "check: merge $branch with a merge commit (not squash, not rebase)"
  return "$bad"
}

cmd=${1:-}; [ $# -gt 0 ] && shift
case $cmd in
  plan) plan "$@" ;;
  check) check "$@" ;;
  *) die "usage: pr-stack.sh plan <pr>... | check <branch> <pr>..." ;;
esac
