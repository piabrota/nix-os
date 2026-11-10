#!/bin/sh
# Tests of commit-counts.sh with a stub `gh`, offline:
#   sh scripts/commit-counts.test.sh      (or: just commit-counts-test)
# The stub answers like `gh api --paginate ... --jq '.[] | (.author.login // "-")'`: one login a
# line. It calls no network and reads no token.
set -u
here=$(cd "$(dirname "$0")" && pwd)
script=$here/commit-counts.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin"
LOG=$work/calls.log
export LOG

cat >"$work/bin/gh" <<'EOF'
#!/bin/sh
echo "gh $*" >>"$LOG"
case $3 in
  repos/piabrota/mixed/commits*)
    printf '%s\n' h0ffmann 'piabrota-hermes[bot]' claude 'dependabot[bot]' aracyla - claudette 'x[bot]y' ;;
  repos/piabrota/robots/commits*)
    printf '%s\n' 'piabrota-ops[bot]' 'ouroboric-pr-bot[bot]' claude ;;
  repos/piabrota/people/commits*)
    printf '%s\n' h0ffmann h0ffmann robkler ;;
  repos/piabrota/empty/commits*) ;;
  repos/other/mixed/commits*) printf '%s\n' h0ffmann ;;
  *) echo "gh: HTTP 404" >&2; exit 1 ;;
esac
EOF
chmod +x "$work/bin/gh"
PATH=$work/bin:$PATH
export PATH

fail=0
check() { # name, expected, actual
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1"; echo "  want: $2"; echo "  got:  $3"; fail=1; fi
}

# The rule: [bot] and exactly "claude" are agents; a person, a missing account, "claudette" and a
# login that only contains [bot] are human.
out=$(sh "$script" mixed)
check "the rule" 'mixed: commits = { human = 5; agent = 3; };' "$out"

out=$(sh "$script" robots)
check "only agents" 'robots: commits = { human = 0; agent = 3; };' "$out"

out=$(sh "$script" people)
check "only people" 'people: commits = { human = 3; agent = 0; };' "$out"

out=$(sh "$script" empty)
check "no commits" 'empty: commits = { human = 0; agent = 0; };' "$out"

# An error prints "no data", the run goes on, and the status is 1 at the end.
out=$(sh "$script" missing people)
status=$?
check "no data, then goes on" 'missing: no data
people: commits = { human = 3; agent = 0; };' "$out"
check "exit status 1 after an error" 1 "$status"

sh "$script" people >/dev/null
check "exit status 0 when all answer" 0 $?

out=$(COMMIT_COUNTS_OWNER=other sh "$script" mixed)
check "another owner" 'mixed: commits = { human = 1; agent = 0; };' "$out"

# The request asks for the default branch's commits, 100 a page, all pages.
: >"$LOG"
sh "$script" people >/dev/null
check "the request" 'gh api --paginate repos/piabrota/people/commits?per_page=100 --jq .[] | (.author.login // "-")' "$(cat "$LOG")"

# --help prints the comment and runs nothing.
: >"$LOG"
sh "$script" --help | grep -q 'agent when its GitHub author login ends with \[bot\]'
check "help text" 0 $?
check "help calls nothing" "" "$(cat "$LOG")"

# With no argument it reads the qualifying names of mockups/data.nix (needs nix-instantiate).
if command -v nix-instantiate >/dev/null 2>&1; then
  : >"$LOG"
  sh "$script" >/dev/null 2>&1
  asked=$(sed -e 's|^gh api --paginate repos/piabrota/||' -e 's|/commits.*||' "$LOG" | tr '\n' ' ')
  check "names from data.nix" 'mu dojo .github pirsig gramatico skills alerts rax agents nix-os ihero ' "$asked"
else
  echo "skip names from data.nix: nix-instantiate is not on PATH"
fi

exit "$fail"
