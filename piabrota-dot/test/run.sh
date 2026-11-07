#!/bin/sh
# Offline tests of piabrota-dot/run.sh, git-credential.sh, mint-token.sh and
# hermes/scripts/piabrota-dot-report.sh. Needs sh, git, jq, awk, flock; openssl for the mint test
# (skipped without it). Shims for gh, nix and git sit first on the PATH, record their calls and
# return fixtures. The "remote" is a bare git repository in a temp folder, so the pushes are real.
# Prints "N checks, M failed" and exits 1 on a failure.
#   RUN=/path/run.sh sh piabrota-dot/test/run.sh    test another copy of run.sh (a naive gate)
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
DOT=$(dirname "$HERE")
ROOT=$(dirname "$DOT")
RUN=${RUN:-$DOT/run.sh}
REPORT=$ROOT/hermes/scripts/piabrota-dot-report.sh
REAL_GIT=$(command -v git)
FAKE=ghs_FAKETOKEN_0a1b2c3d4e5f
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
N=0
F=0

t() { # description, then a command
  desc=$1
  shift
  N=$((N + 1))
  if "$@"; then :; else F=$((F + 1)); echo "FAIL: $desc"; fi
}
has() { grep -q -- "$1" "$2"; }
hasnt() { ! grep -q -- "$1" "$2"; }
count_is() { [ "$(grep -c -- "$1" "$2" 2>/dev/null || true)" = "$3" ]; }

# ---------------------------------------------------------------- shims

mkdir -p "$T/shim"
cat >"$T/shim/gh" <<'EOF'
#!/bin/sh
# gh shim: fixtures in $FX/gh/<METHOD_endpoint>, calls in $CALLS.
echo "gh $*" >>"$CALLS/all"
[ -n "${GH_TOKEN:-}" ] && echo "GH_TOKEN set" >>"$CALLS/all"
method=GET
ep=
shift
while [ $# -gt 0 ]; do
  case $1 in
    -X) method=$2; shift ;;
    -f | -F) case $2 in body=@*) cp "${2#body=@}" "$CALLS/body.$(wc -l <"$CALLS/all")" ;; esac; shift ;;
    --paginate) ;;
    *) ep=$1 ;;
  esac
  shift
done
[ "$method" = GET ] || echo "$method $ep" >>"$CALLS/writes"
key=$(printf '%s %s' "$method" "$ep" | tr -c 'A-Za-z0-9\n' _)
if [ -e "$FX/gh/$key.rc" ]; then
  [ -e "$FX/gh/$key.err" ] && cat "$FX/gh/$key.err" >&2
  exit "$(cat "$FX/gh/$key.rc")"
fi
if [ -e "$FX/gh/$key" ]; then cat "$FX/gh/$key"; exit 0; fi
case "$method $ep" in
  "POST repos/piabrota/nix-os/pulls") echo '{"number":7,"html_url":"https://github.com/piabrota/nix-os/pull/7"}' ;;
  "POST repos/piabrota/nix-os/issues") echo '{"number":8,"html_url":"https://github.com/piabrota/nix-os/issues/8"}' ;;
  "GET users/piabrota-dot%5Bbot%5D") echo '{"id":123}' ;;
  GET*pulls\?state=open*) echo '[]' ;;
  GET*issues\?state=all*) echo '[]' ;;
  *) echo '{}' ;;
esac
EOF
cat >"$T/shim/nix" <<'EOF'
#!/bin/sh
# nix shim: only `nix eval ...#nixosConfigurations.<host>...`; a failing host has $FX/eval-<host>.fail.
echo "nix $*" >>"$CALLS/nix"
case $* in *nixosConfigurations.piabrota2.*) host=piabrota2 ;; *) host=piabrota ;; esac
if [ -e "$FX/eval-$host.fail" ]; then
  i=1
  while [ $i -le 60 ]; do echo "error: line $i of the evaluation error (env: $GH_TOKEN)" >&2; i=$((i + 1)); done
  exit 1
fi
echo "/nix/store/00000000000000000000000000000000-nixos-system-$host.drv"
EOF
cat >"$T/shim/git" <<EOF
#!/bin/sh
echo "git \$*" >>"\$CALLS/git"
exec $REAL_GIT "\$@"
EOF
cat >"$T/shim/bump" <<'EOF'
#!/bin/sh
# Fake bump script. The component is its name; $FX/<component>.mode: current | newer | fail | outside.
comp=$(basename "$0" | sed 's/-bump.sh//')
mode=$(cat "$FX/$comp.mode")
case " $* " in
  *" --check "*)
    case $mode in
      current) printf 'pin: v1\nlatest: v1\nstate: current\n'; exit 0 ;;
      fail) echo "boom"; exit 1 ;;
      *) printf 'pin: v1\nlatest: v2\nstate: behind\n'; exit 10 ;;
    esac ;;
esac
out=
while [ $# -gt 0 ]; do [ "$1" = --output ] && out=$2; shift; done
[ -n "$out" ] || exit 1
case $comp in hermes) echo "# bumped" >>hermes.nix ;; openrig) echo "# bumped" >>openrig/package.nix ;; esac
[ "$mode" = outside ] && echo "x" >README.md
printf 'old=v1\nnew=v2\ncompare_url=https://github.com/x/y/compare/v1...v2\ncommit=abc\nchanged=true\n' >"$out"
printf 'Fixture upgrade notes.\n' >"$out.notes.md"
EOF
chmod +x "$T/shim/gh" "$T/shim/nix" "$T/shim/git" "$T/shim/bump"

# The remote: a bare repository with the pin files and the two fake bump scripts.
seed() {
  mkdir -p "$T/seed/scripts" "$T/seed/openrig"
  (
    cd "$T/seed" || exit 1
    echo 'hermes' >hermes.nix; echo f >flake.nix; echo l >flake.lock; echo o >openrig/package.nix
    echo readme >README.md
    cp "$T/shim/bump" scripts/hermes-bump.sh
    cp "$T/shim/bump" scripts/openrig-bump.sh
    "$REAL_GIT" init -q -b main .
    "$REAL_GIT" add -A
    "$REAL_GIT" -c user.name=t -c user.email=t@t commit -q -m seed
    "$REAL_GIT" clone -q --bare . "$T/origin-template.git"
  )
}
seed

# ---------------------------------------------------------------- one case

# new_case NAME: a fresh state, a fresh remote, both components current, a token.
new_case() {
  C=$T/$1
  mkdir -p "$C/fx/gh" "$C/calls" "$C/home"
  cp -r "$T/origin-template.git" "$C/origin.git"
  : >"$C/calls/all"
  echo current >"$C/fx/hermes.mode"
  echo current >"$C/fx/openrig.mode"
  printf '%s' "$FAKE" >"$C/token"
  OUT=$C/out
}
fx() { printf '%s\n' "$3" >"$C/fx/gh/$(printf '%s %s' "$1" "$2" | tr -c 'A-Za-z0-9\n' _)"; }
fxrc() { printf '%s\n' "$3" >"$C/fx/gh/$(printf '%s %s' "$1" "$2" | tr -c 'A-Za-z0-9\n' _).rc"; printf '%s\n' "$4" >"$C/fx/gh/$(printf '%s %s' "$1" "$2" | tr -c 'A-Za-z0-9\n' _).err"; }
dot() { # run.sh arguments; sets RC
  env PATH="$T/shim:$PATH" FX="$C/fx" CALLS="$C/calls" HOME="$C/home" \
    DOT_STATE="$C/state" DOT_TOKEN_FILE="$C/token" DOT_CLONE_URL="file://$C/origin.git" \
    DOT_CREDENTIAL_HELPER="$DOT/git-credential.sh" "$@" >"$OUT" 2>&1
  RC=$?
}
runit() { dot sh "$RUN" "$@"; }
writes() { cat "$C/calls/writes" 2>/dev/null || true; }
branch_sha() { "$REAL_GIT" --git-dir "$C/origin.git" rev-parse --verify -q "refs/heads/$1"; }
branch_files() { "$REAL_GIT" --git-dir "$C/origin.git" diff --name-only main "refs/heads/$1"; }

REPO_API=repos/piabrota/nix-os
PRLIST="$REPO_API/pulls?state=open&head=piabrota:piabrota-dot/hermes&per_page=10"
ISSUELIST="$REPO_API/issues?state=all&creator=piabrota-dot%5Bbot%5D&per_page=100"
GREEN='{"total_count":1,"check_runs":[{"status":"completed","conclusion":"success"}]}'

# A newer Hermes with an open pull request of the bot, a stamp that matches its head, and a gate that
# is open (green checks, the bot as author, the pin file only). Change one fixture, then run.
mergeable() {
  new_case "$1"
  echo newer >"$C/fx/hermes.mode"
  mkdir -p "$C/state"
  S=0123456789abcdef0123456789abcdef01234567
  echo "v2 $S" >"$C/state/pushed-hermes"
  fx GET "$PRLIST" "[{\"number\":7,\"html_url\":\"https://github.com/piabrota/nix-os/pull/7\",\"user\":{\"login\":\"piabrota-dot[bot]\"},\"head\":{\"sha\":\"$S\"}}]"
  fx GET "$REPO_API/pulls/7" "{\"user\":{\"login\":\"piabrota-dot[bot]\"},\"draft\":false,\"head\":{\"sha\":\"$S\"}}"
  fx GET "$REPO_API/pulls/7/files?per_page=100" '[{"filename":"hermes.nix"},{"filename":"flake.lock"}]'
  fx GET "$REPO_API/commits/$S/check-runs?per_page=100" "$GREEN"
  fx GET "$REPO_API/commits/$S/status" '{"state":"pending","total_count":0}'
}
no_merge() { [ "$(writes | grep -c 'PUT')" = 0 ]; }

# ---------------------------------------------------------------- run.sh

# 1. No token: quiet, no call.
new_case no-token; rm "$C/token"
runit
t "no token: exit 0" [ "$RC" = 0 ]
t "no token: no tool called" [ ! -s "$C/calls/all" ]
t "no token: no result file" [ ! -e "$C/state/last-run.txt" ]
t "no token: no output" [ ! -s "$OUT" ]

# 2. Both current.
new_case current
runit
t "current: exit 0" [ "$RC" = 0 ]
t "current: first line" [ "$(head -n 1 "$C/state/last-run.txt")" = "piabrota-dot: nothing new" ]
t "current: hermes line" has 'hermes: current at v1' "$C/state/last-run.txt"
t "current: openrig line" has 'openrig: current at v1' "$C/state/last-run.txt"
t "current: no write call" [ -z "$(writes)" ]
t "current: world-readable result" [ "$(stat -c %a "$C/state/last-run.txt")" = 644 ]
t "current: the clone is private" [ "$(stat -c %a "$C/state/nix-os" | sed "s/^2//")" = 700 ]

# 3. A newer Hermes: a branch and a pull request.
new_case newer
echo newer >"$C/fx/hermes.mode"
runit
t "newer: exit 0" [ "$RC" = 0 ]
t "newer: one pull request" count_is 'POST repos/piabrota/nix-os/pulls$' "$C/calls/writes" 1
t "newer: title" has 'title=chore(hermes): bump Hermes Agent to v2' "$C/calls/all"
t "newer: base main" has 'base=main' "$C/calls/all"
t "newer: head branch" has 'head=piabrota-dot/hermes' "$C/calls/all"
t "newer: label" has 'POST repos/piabrota/nix-os/issues/7/labels' "$C/calls/writes"
t "newer: branch pushed" [ -n "$(branch_sha piabrota-dot/hermes)" ]
t "newer: allow list respected" [ "$(branch_files piabrota-dot/hermes)" = hermes.nix ]
BODY=$(find "$C/calls" -name "body.*" | head -n 1)
t "newer: body Summary" has '^## Summary' "$BODY"
t "newer: body compare link" has 'compare/v1...v2' "$BODY"
t "newer: body notes" has 'Fixture upgrade notes' "$BODY"
# shellcheck disable=SC2016
t "newer: body Risk" has 'restarts the units `hermes-agent` and `hermes-backend`' "$BODY"
t "newer: body Tested" has '^## Tested' "$BODY"
t "newer: body Not tested" has '^## Not tested' "$BODY"
t "newer: both hosts evaluated" [ "$(wc -l <"$C/calls/nix")" = 2 ]
t "newer: result line" has 'hermes: opened https://github.com/piabrota/nix-os/pull/7 for v1 to v2' "$C/state/last-run.txt"
t "newer: openrig untouched" has 'openrig: current at v1' "$C/state/last-run.txt"
msg=$("$REAL_GIT" --git-dir "$C/origin.git" log -1 --format='%an|%B' piabrota-dot/hermes)
t "newer: committed as the bot" [ "${msg%%|*}" = 'piabrota-dot[bot]' ]
t "newer: no agent mark" sh -c "! printf '%s' \"\$1\" | grep -qiE 'co-authored|generated|claude'" _ "$msg"
t "newer: no agent mark in the body" sh -c "! grep -qiE 'generated|claude|co-authored' '$BODY'"
t "newer: merge not touched" no_merge
FIRST_SHA=$(branch_sha piabrota-dot/hermes)

# 3b. The second run on the same day: nothing changes.
fx GET "$PRLIST" "[{\"number\":7,\"html_url\":\"https://github.com/piabrota/nix-os/pull/7\",\"user\":{\"login\":\"piabrota-dot[bot]\"},\"head\":{\"sha\":\"$FIRST_SHA\"}}]"
: >"$C/calls/writes"
runit
t "again: exit 0" [ "$RC" = 0 ]
t "again: no write" [ -z "$(writes)" ]
t "again: branch unchanged" [ "$(branch_sha piabrota-dot/hermes)" = "$FIRST_SHA" ]
t "again: no new evaluation" [ "$(wc -l <"$C/calls/nix")" = 2 ]
t "again: still open" has 'hermes: open https://github.com/piabrota/nix-os/pull/7 for v1 to v2' "$C/state/last-run.txt"

# 4. An open pull request on an old head: refreshed, not duplicated.
new_case refresh
echo newer >"$C/fx/hermes.mode"
fx GET "$PRLIST" '[{"number":7,"html_url":"https://github.com/piabrota/nix-os/pull/7","user":{"login":"piabrota-dot[bot]"},"head":{"sha":"old"}}]'
runit
t "refresh: PATCH of the open pull request" has 'PATCH repos/piabrota/nix-os/pulls/7' "$C/calls/writes"
t "refresh: no second pull request" count_is 'POST repos/piabrota/nix-os/pulls$' "$C/calls/writes" 0
t "refresh: branch pushed" [ -n "$(branch_sha piabrota-dot/hermes)" ]
t "refresh: result line" has 'hermes: refreshed https://github.com/piabrota/nix-os/pull/7' "$C/state/last-run.txt"

# 4b. A pull request on the bot's branch by someone else: the bot leaves it alone.
new_case foreign-branch
echo newer >"$C/fx/hermes.mode"
fx GET "$PRLIST" '[{"number":7,"html_url":"u","user":{"login":"someone"},"head":{"sha":"old"}}]'
runit
t "foreign branch pr: nothing pushed" [ -z "$(branch_sha piabrota-dot/hermes)" ]
t "foreign branch pr: failure recorded" has 'hermes: failed:' "$C/state/last-run.txt"
t "foreign branch pr: first line says failed" has '^piabrota-dot failed:' "$C/state/last-run.txt"

# 5. An evaluation that fails: an issue, no pull request, no second issue.
new_case evalfail
echo newer >"$C/fx/hermes.mode"
touch "$C/fx/eval-piabrota2.fail"
runit
t "evalfail: one issue" count_is 'POST repos/piabrota/nix-os/issues$' "$C/calls/writes" 1
t "evalfail: issue title" has 'title=piabrota-dot: hermes v2 does not evaluate' "$C/calls/all"
t "evalfail: no pull request" count_is 'POST repos/piabrota/nix-os/pulls$' "$C/calls/writes" 0
t "evalfail: nothing pushed" [ -z "$(branch_sha piabrota-dot/hermes)" ]
IBODY=$(find "$C/calls" -name "body.*" | head -n 1)
t "evalfail: body has the end of the error" has 'line 60 of the evaluation error' "$IBODY"
t "evalfail: body is cut at 40 lines" hasnt 'line 20 of the evaluation error' "$IBODY"
t "evalfail: result line" has 'hermes: issue https://github.com/piabrota/nix-os/issues/8' "$C/state/last-run.txt"
fx GET "$ISSUELIST" '[{"title":"piabrota-dot: hermes v2 does not evaluate","html_url":"https://github.com/piabrota/nix-os/issues/8"}]'
: >"$C/calls/writes"; : >"$C/calls/nix"
runit
t "evalfail again: no second issue" [ -z "$(writes)" ]
t "evalfail again: no evaluation" [ ! -s "$C/calls/nix" ]
t "evalfail again: the issue is recorded" has 'hermes: issue https://github.com/piabrota/nix-os/issues/8' "$C/state/last-run.txt"
# A closed issue counts too: the list has state=all.

# 6. A diff outside the allow list: an issue, no push.
new_case outside
echo outside >"$C/fx/hermes.mode"
runit
t "outside: issue" has 'title=piabrota-dot: hermes v2 changes files outside its pin files' "$C/calls/all"
t "outside: no pull request" count_is 'POST repos/piabrota/nix-os/pulls$' "$C/calls/writes" 0
t "outside: nothing pushed" [ -z "$(branch_sha piabrota-dot/hermes)" ]
t "outside: no evaluation" [ ! -s "$C/calls/nix" ]
t "outside: the issue names the file" has 'README.md' "$(find "$C/calls" -name "body.*" | head -n 1)"

# 7. Merge off (the default): green and still no merge.
mergeable merge-off
runit
t "merge off: no PUT" no_merge
t "merge off: still open" has 'hermes: open ' "$C/state/last-run.txt"

# 8. Merge on, everything green: one merge, of that pull request, squashed.
mergeable merge-on
dot env DOT_MERGE_HERMES=true sh "$RUN"
t "merge on: exactly one PUT" [ "$(writes | grep -c 'PUT')" = 1 ]
t "merge on: that pull request" has 'PUT repos/piabrota/nix-os/pulls/7/merge' "$C/calls/writes"
t "merge on: squash" has 'merge_method=squash' "$C/calls/all"
t "merge on: pinned to the head" has "sha=$S" "$C/calls/all"
t "merge on: recorded" has 'hermes: merged https://github.com/piabrota/nix-os/pull/7' "$C/state/last-run.txt"
t "merge on: openrig has no merge" hasnt 'openrig/' "$C/calls/writes"

# 9. Merge on, one condition not met each time: no merge.
mergeable gate-pending
fx GET "$REPO_API/commits/$S/check-runs?per_page=100" '{"total_count":2,"check_runs":[{"status":"completed","conclusion":"success"},{"status":"in_progress","conclusion":null}]}'
dot env DOT_MERGE_HERMES=true sh "$RUN"
t "gate pending: no merge" no_merge
t "gate pending: reason recorded" has 'merge waits: a check is not finished' "$C/state/last-run.txt"

mergeable gate-red
fx GET "$REPO_API/commits/$S/check-runs?per_page=100" '{"total_count":2,"check_runs":[{"status":"completed","conclusion":"success"},{"status":"completed","conclusion":"failure"}]}'
dot env DOT_MERGE_HERMES=true sh "$RUN"
t "gate red: no merge" no_merge
t "gate red: reason recorded" has 'merge waits: a check is not green' "$C/state/last-run.txt"

mergeable gate-empty
fx GET "$REPO_API/commits/$S/check-runs?per_page=100" '{"total_count":0,"check_runs":[]}'
dot env DOT_MERGE_HERMES=true sh "$RUN"
t "gate empty list: no merge" no_merge
t "gate empty list: reason recorded" has 'merge waits: the head has no check run' "$C/state/last-run.txt"

mergeable gate-status
fx GET "$REPO_API/commits/$S/status" '{"state":"failure","total_count":1}'
dot env DOT_MERGE_HERMES=true sh "$RUN"
t "gate red status: no merge" no_merge

mergeable gate-sha
fx GET "$REPO_API/pulls/7" '{"user":{"login":"piabrota-dot[bot]"},"draft":false,"head":{"sha":"ffffffffffffffffffffffffffffffffffffffff"}}'
dot env DOT_MERGE_HERMES=true sh "$RUN"
t "gate other head: no merge" no_merge

mergeable gate-author
fx GET "$REPO_API/pulls/7" "{\"user\":{\"login\":\"someone-else\"},\"draft\":false,\"head\":{\"sha\":\"$S\"}}"
dot env DOT_MERGE_HERMES=true sh "$RUN"
t "gate foreign author: no merge" no_merge
t "gate foreign author: reason recorded" has 'merge waits: the author is not' "$C/state/last-run.txt"

mergeable gate-draft
fx GET "$REPO_API/pulls/7" "{\"user\":{\"login\":\"piabrota-dot[bot]\"},\"draft\":true,\"head\":{\"sha\":\"$S\"}}"
dot env DOT_MERGE_HERMES=true sh "$RUN"
t "gate draft: no merge" no_merge

mergeable gate-files
fx GET "$REPO_API/pulls/7/files?per_page=100" '[{"filename":"hermes.nix"},{"filename":".github/workflows/deploy.yml"}]'
dot env DOT_MERGE_HERMES=true sh "$RUN"
t "gate file outside the list: no merge" no_merge

# 10. The ruleset refuses: one try, recorded, no way round.
mergeable refused
fxrc PUT "$REPO_API/pulls/7/merge" 1 'gh: Repository rule violations found (HTTP 405)'
dot env DOT_MERGE_HERMES=true sh "$RUN"
t "refused: one try only" [ "$(writes | grep -c 'PUT')" = 1 ]
t "refused: recorded" has 'hermes: merge refused by the ruleset' "$C/state/last-run.txt"
t "refused: nothing else written" [ "$(writes | grep -vc 'PUT')" = 0 ]

# 11. Dry run: every step runs, no write.
new_case dry
echo newer >"$C/fx/hermes.mode"
runit --dry-run
t "dry run: exit 0" [ "$RC" = 0 ]
t "dry run: no GitHub write" [ -z "$(writes)" ]
t "dry run: nothing pushed" [ -z "$(branch_sha piabrota-dot/hermes)" ]
t "dry run: both hosts evaluated" [ "$(wc -l <"$C/calls/nix")" = 2 ]
t "dry run: no result file" [ ! -e "$C/state/last-run.txt" ]
t "dry run: says what it would do" has 'dry-run: would push' "$OUT"

# 12. The token never reaches a log, a call, a result or a file.
t "token: gh saw it in its environment" has 'GH_TOKEN set' "$T/evalfail/calls/all"
t "token: in no file or log" sh -c "! grep -rl '$FAKE' '$T' --exclude=token --exclude=gh --exclude=nix 2>/dev/null | grep -q ."
t "token: the nix shim echoed it, and the issue body has it scrubbed" has '\*\*\*' "$IBODY"

# ---------------------------------------------------------------- git-credential.sh

new_case cred
t "credential: get answers" sh -c "[ \"\$(DOT_TOKEN_FILE='$C/token' sh '$DOT/git-credential.sh' get)\" = \"username=x-access-token
password=$FAKE\" ]"
t "credential: store is silent" sh -c "[ -z \"\$(DOT_TOKEN_FILE='$C/token' sh '$DOT/git-credential.sh' store </dev/null)\" ]"
t "credential: no file is silent" sh -c "[ -z \"\$(DOT_TOKEN_FILE='$C/none' sh '$DOT/git-credential.sh' get)\" ]"

# ---------------------------------------------------------------- mint-token.sh

if command -v openssl >/dev/null 2>&1; then
  M=$T/mint
  mkdir -p "$M/cred" "$M/shim"
  openssl genrsa -out "$M/key.pem" 2048 2>/dev/null
  printf 'GH_APP_ID=4242\nGH_APP_PRIVATE_KEY_B64=%s\n' "$(base64 <"$M/key.pem" | tr -d '\n')" >"$M/cred/app"
  cat >"$M/shim/curl" <<'EOF'
#!/bin/sh
echo "curl $*" >>"$M/calls"
case $* in
  *"/repos/piabrota/nix-os/installation"*) echo '{"id":42}' ;;
  *"/app/installations/42/access_tokens"*) echo '{"token":"ghs_MINTED"}' ;;
  *) exit 22 ;;
esac
EOF
  chmod +x "$M/shim/curl"
  env M="$M" PATH="$M/shim:$PATH" CREDENTIALS_DIRECTORY="$M/cred" DOT_REPO=piabrota/nix-os \
    DOT_TOKEN_FILE="$M/token" DOT_TOKEN_USER="$(id -un)" sh "$DOT/mint-token.sh" >"$M/out" 2>&1
  t "mint: exit 0" [ "$?" = 0 ]
  t "mint: token written" [ "$(cat "$M/token")" = ghs_MINTED ]
  t "mint: token mode 0400" [ "$(stat -c %a "$M/token")" = 400 ]
  body=$(sed -n 's/.* -d \({.*}\) .*/\1/p' "$M/calls")
  t "mint: one repository" [ "$(printf '%s' "$body" | jq -c .repositories)" = '["nix-os"]' ]
  t "mint: the four permissions and no more" [ "$(printf '%s' "$body" | jq -cS .permissions)" = '{"contents":"write","issues":"write","metadata":"read","pull_requests":"write"}' ]
  jwt=$(sed -n 's/.*Authorization: Bearer \([^ ]*\).*/\1/p' "$M/calls" | head -n 1)
  t "mint: a JWT of three parts" [ "$(printf '%s' "$jwt" | tr -cd . | wc -c)" = 2 ]
  t "mint: RS256" sh -c "printf '%s' '${jwt%%.*}' | tr '_-' '/+' | base64 -d 2>/dev/null | grep -q RS256"
  t "mint: the token is not in the output" hasnt ghs_MINTED "$M/out"
else
  echo "skip: openssl is not on the PATH, no mint test"
fi

# ---------------------------------------------------------------- piabrota-dot-report.sh

R=$T/report
mkdir -p "$R/home"
rep() { env HERMES_HOME="$R/home" LAST_RUN="$R/last-run.txt" PATH="$PATH" sh "$REPORT"; }
t "report: no file prints nothing" [ -z "$(rep)" ]
printf 'piabrota-dot: nothing new\ntime: 2026-11-07 14:00 -03\nhermes: current at v1\n' >"$R/last-run.txt"
t "report: nothing new prints nothing" [ -z "$(rep)" ]
printf 'piabrota-dot: news\ntime: 2026-11-08 14:00 -03\nhermes: opened https://x/pull/7 for v1 to v2\n' >"$R/last-run.txt"
t "report: a new result is printed" [ "$(rep | grep -c 'hermes: opened')" = 1 ]
t "report: the same result is not printed again" [ -z "$(rep)" ]
printf 'piabrota-dot: news\ntime: 2026-11-09 14:00 -03\nhermes: opened https://x/pull/7 for v1 to v2\n' >"$R/last-run.txt"
t "report: only the time changed: nothing" [ -z "$(rep)" ]
printf 'piabrota-dot failed: hermes: the check of hermes exited with 1\ntime: 2026-11-10 14:00 -03\nhermes: failed: the check of hermes exited with 1\n' >"$R/last-run.txt"
t "report: a failure is printed" [ "$(rep | head -n 1)" = 'piabrota-dot failed: hermes: the check of hermes exited with 1' ]
t "report: the same failure once only" [ -z "$(rep)" ]

echo "$N checks, $F failed"
[ "$F" = 0 ]
