#!/bin/sh
# Counts the commits on the default branch of each repository that the org owns, split into human
# and agent, and prints one line for each, ready to paste into mockups/data.nix:
#
#   nix-os: commits = { human = 104; agent = 63; };
#
# A commit is agent when its GitHub author login ends with [bot] or is exactly "claude" (the
# account that GitHub maps Claude Code's commit author to). Every other commit is human. A commit
# that a person made with an agent's help under their own name counts as human, because the
# repository's rule is "no agent trail in a commit", so the count is a floor for agent work.
#
# Read-only: it only calls `gh api` (GET). It needs `gh`, logged in. It prints no token.
# Without arguments it reads the names of the qualifying projects from mockups/data.nix with
# nix-instantiate: the projects whose repository is the org's own and not a card for another
# repository (origin "own", no `repository`). With arguments, it counts those repositories.
# A repository that answers with an error prints "<name>: no data" and the exit status is 1.
#
#   sh scripts/commit-counts.sh                (or: just commit-counts)
#   sh scripts/commit-counts.sh nix-os mu
# COMMIT_COUNTS_OWNER names another owner (default: piabrota).
set -u

case ${1:-} in
  -h | --help)
    sed -n '2,/^set -u/p' "$0" | sed -e '/^set -u/d' -e 's/^# \{0,1\}//'
    exit 0
    ;;
esac

here=$(cd "$(dirname "$0")" && pwd)
owner=${COMMIT_COUNTS_OWNER:-piabrota}

if [ $# -gt 0 ]; then
  names=$(printf '%s\n' "$@")
else
  names=$(nix-instantiate --eval --raw --expr "
    let d = import $here/../mockups/data.nix;
    in builtins.concatStringsSep \"\\n\"
      (map (p: p.name) (builtins.filter (p: d.origin p == \"own\" && !(p ? repository)) d.projects))") || {
    echo "commit-counts: cannot read the project names from mockups/data.nix" >&2
    exit 2
  }
fi

failed=0
for name in $names; do
  # --jq prints one author login for each commit; "-" stands for a commit with no GitHub account.
  if logins=$(gh api --paginate "repos/$owner/$name/commits?per_page=100" --jq '.[] | (.author.login // "-")' 2>/dev/null); then
    counts=$(printf '%s\n' "$logins" | awk '
      NF == 0 { next }
      /\[bot\]$/ || $0 == "claude" { agent++; next }
      { human++ }
      END { printf "%d %d\n", human, agent }')
    printf '%s: commits = { human = %s; agent = %s; };\n' "$name" "${counts% *}" "${counts#* }"
  else
    printf '%s: no data\n' "$name"
    failed=1
  fi
done
exit "$failed"
