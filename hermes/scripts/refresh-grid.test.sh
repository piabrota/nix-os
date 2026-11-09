#!/usr/bin/env bash
# Tests of refresh-grid.sh with a bare git repository as origin and a stub gh. They need git, jq
# and GNU date, and no network, no Nix, no real GitHub: `bash hermes/scripts/refresh-grid.test.sh`.
# The script runs for real. Its GRID_CMD and CHECK_CMD are small shell commands.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
script=${REFRESH_GRID_UNDER_TEST:-$here/refresh-grid.sh}
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# No identity of the real user: the script must set its own.
export HOME="$T/home"
export GIT_CONFIG_NOSYSTEM=1
export TMPDIR="$T/tmp"
mkdir -p "$HOME" "$TMPDIR" "$T/bin"

# ---- The stub gh. It answers three calls and records the rest.
cat >"$T/bin/gh" <<'EOF'
#!/usr/bin/env bash
# STUB_DIR: origin.git, prs.json (the open PRs), log, title, body.md
case "$1 $2" in
  "repo clone")
    echo "repo clone" >>"$STUB_DIR/log"
    git clone -q "file://$STUB_DIR/origin.git" "$4"
    ;;
  "pr list")
    echo "pr list" >>"$STUB_DIR/log"
    expr=""
    while [ $# -gt 0 ]; do
      [ "$1" != --jq ] || expr=$2
      shift
    done
    jq -r "$expr" "$STUB_DIR/prs.json"
    ;;
  "pr create")
    echo "pr create" >>"$STUB_DIR/log"
    shift 2
    while [ $# -gt 0 ]; do
      case $1 in
        --title) printf '%s' "$2" >"$STUB_DIR/title" ;;
        --body-file) cp "$2" "$STUB_DIR/body.md" ;;
        --head) printf '%s' "$2" >"$STUB_DIR/head" ;;
      esac
      shift
    done
    echo "https://github.com/piabrota/room/pull/99"
    ;;
  *)
    echo "unexpected gh call: $*" >>"$STUB_DIR/log"
    exit 1
    ;;
esac
EOF
chmod +x "$T/bin/gh"
export PATH="$T/bin:$PATH"

# ---- The fake generator. FAKE_MODE says what it does.
cat >"$T/bin/fakegen" <<'EOF'
#!/usr/bin/env bash
set -eu
hours=25
sst=true
case "$FAKE_MODE" in
  nochange) exit 0 ;;
  fail)
    for i in 1 2 3 4 5 6 7; do echo "generator line $i"; done
    exit 3
    ;;
  nosst) sst=false ;;
  hours24) hours=24 ;;
  outside) echo changed >README.md ;;
esac
start=$(date -u -d 2026-11-07T04:00:00Z +%s)
jq --argjson start "$start" --argjson n "$hours" --argjson sst "$sst" '
  .hours = [range(0; $n) | ($start + . * 3600) | strftime("%Y-%m-%dT%H:%M")]
  | .fetched = "2026-11-07T04:30:00.000Z"
  | if $sst then .sst.date = "2026-11-05" else del(.sst) end' public/grid/run.json >run.json.new
mv run.json.new public/grid/run.json
printf 'bbbbbbbbbbbb' >public/grid/frames.bin
if [ "$FAKE_MODE" = size ]; then printf 'bb' >public/grid/frames.bin; fi
printf 'cccc' >public/grid/sst.bin
EOF
chmod +x "$T/bin/fakegen"

# ---- A fresh origin and a fresh state for each case.
CASE=0
case_dir() {
  CASE=$((CASE + 1))
  C="$T/case$CASE"
  rm -rf "$C"
  mkdir -p "$C/seed"
  export STUB_DIR="$C"
  git init -q --bare -b main "$C/origin.git"
  (
    cd "$C/seed"
    git init -q -b main
    mkdir -p public/grid scripts
    local_start=$(date -u -d 2026-11-06T04:00:00Z +%s)
    jq -n --argjson start "$local_start" '{
      nodes: 11905, triangles: 22366,
      hours: [range(0; 25) | ($start + . * 3600) | strftime("%Y-%m-%dT%H:%M")],
      fetched: "2026-11-06T04:34:56.487Z",
      sst: {date: "2026-11-04", scale: 0.01}
    }' >public/grid/run.json
    printf 'aaaaaaaaaaaa' >public/grid/frames.bin
    printf 'dddd' >public/grid/sst.bin
    printf 'mesh' >public/grid/mesh.bin
    printf '{}' >public/grid/land.json
    echo "// the invariant check" >scripts/check.mjs
    echo "# room" >README.md
    git add -A
    git -c user.name=seed -c user.email=seed@example.com commit -q -m seed
    git push -q "file://$C/origin.git" main
  )
  echo '[]' >"$C/prs.json"
  : >"$C/log"
  : >"$C/token"
  export REPO_DIR="$C/room-src" TOKEN_FILE="$C/token" REPO=piabrota/room
  export GRID_CMD="$T/bin/fakegen" CHECK_CMD="test -f scripts/check.mjs"
  export FAKE_MODE=ok
  unset DRY_RUN OUT_PATCH
}

STDOUT=""
RC=0
run() {
  RC=0
  STDOUT=$(bash "$script" 2>"$C/stderr") || RC=$?
}

FAILED=0
ok() { echo "ok  $1"; }
bad() {
  echo "FAIL  $1"
  echo "  rc=$RC stdout=[$STDOUT]"
  sed 's/^/  stderr: /' "$C/stderr" 2>/dev/null || true
  FAILED=1
}
# check NAME CONDITION...: the condition is a command.
check() {
  local name=$1
  shift
  if "$@"; then ok "$name"; else bad "$name"; fi
}

calls() { grep -c "^$1\$" "$C/log" || true; }
# has_all FILE TEXT...: the file holds every TEXT.
has_all() {
  local f=$1 p
  shift
  for p in "$@"; do grep -qF -- "$p" "$f" || return 1; done
}
remote_branches() { git -C "$C/origin.git" for-each-ref --format='%(refname:short)' refs/heads | grep -v '^main$' || true; }
today=$(date +%Y%m%d)

# ---- (a) No token file: the waiting line.
case_dir
rm -f "$TOKEN_FILE"
run
check "a: no token, the waiting line" \
  test "$RC" = 0 -a "$STDOUT" = "grid refresh waiting: the piabrota-hermes App has no installation on piabrota/room (no token file)"

# ---- (b) New data and no open PR: a branch, one commit, one PR. The second run takes -2.
case_dir
echo '[{"headRefName":"feature/other"}]' >"$C/prs.json"
run
branch="hermes/grid-refresh-$today"
check "b: one line, opened" \
  test "$RC" = 0 -a "$STDOUT" = "grid refresh: opened https://github.com/piabrota/room/pull/99 (wind from 2026-11-07, temperature of 2026-11-05)"
check "b: the branch is in the remote" test "$(remote_branches)" = "$branch"
check "b: one commit on top of main" test "$(git -C "$C/origin.git" rev-list --count "main..$branch")" = 1
check "b: the commit changes only public/grid" \
  test "$(git -C "$C/origin.git" diff --name-only "main..$branch" | grep -vc '^public/grid/' || true)" = 0
check "b: the commit has the title, the identity and no trailer" \
  test "$(git -C "$C/origin.git" log -1 --format='%s|%an|%ae' "$branch")" = \
  "Refresh the data of the grid: wind of 2026-11-07, temperature of 2026-11-05|piabrota-hermes|piabrota-hermes@users.noreply.github.com" \
  -a "$(git -C "$C/origin.git" log -1 --format=%B "$branch" | grep -ci 'co-authored\|generated')" = 0
check "b: gh pr create ran once" test "$(calls 'pr create')" = 1
check "b: the PR title and head" \
  test "$(cat "$C/title")" = "Refresh the data of the grid: wind of 2026-11-07, temperature of 2026-11-05" -a "$(cat "$C/head")" = "$branch"
check "b: the body has the dates and the sizes" \
  has_all "$C/body.md" '2026-11-07T04:00 to 2026-11-08T04:00 UTC' '2026-11-07T04:30:00.000Z' 'OSTIA day 2026-11-05' \
  "\`frames.bin\`: 12 bytes before, 12 bytes after." "\`sst.bin\`: 4 bytes before, 4 bytes after."
check "b: the body has no changed-mesh note" test "$(grep -c 'Natural Earth source' "$C/body.md" || true)" = 0
run
check "b: the second run takes the branch -2" test "$STDOUT" != "" -a "$(remote_branches | sort | tr '\n' ' ')" = "$branch $branch-2 "

# ---- (c) An open PR of the job: nothing happens.
case_dir
echo '[{"headRefName":"feature/other"},{"headRefName":"hermes/grid-refresh-20261108"}]' >"$C/prs.json"
run
check "c: an open PR: no output" test "$RC" = 0 -a -z "$STDOUT"
check "c: no push, no pr create" test -z "$(remote_branches)" -a "$(calls 'pr create')" = 0

# ---- (d) The generator changes nothing: no output.
case_dir
FAKE_MODE=nochange
run
check "d: no change: no output" test "$RC" = 0 -a -z "$STDOUT" -a "$(calls 'pr create')" = 0

# ---- (e) The generator fails: one failed line, then its last 5 lines.
case_dir
FAKE_MODE=fail
run
check "e: the generator fails" \
  test "$RC" = 1 -a "$(grep -c '^grid refresh failed' <<<"$STDOUT")" = 1 -a "$(wc -l <<<"$STDOUT")" = 6 \
  -a -z "$(remote_branches)"

# ---- (f) The sea temperature is missing: not opened, nothing pushed.
case_dir
FAKE_MODE=nosst
run
check "f: no sst: not opened" \
  test "$RC" = 1 -a "$STDOUT" = "grid refresh not opened: the sea temperature is missing (Copernicus Marine)" \
  -a -z "$(remote_branches)" -a "$(calls 'pr create')" = 0

# ---- (g) DRY_RUN=1: no push, no pr create, the dry line.
case_dir
rm -f "$TOKEN_FILE"
export DRY_RUN=1
run
check "g: dry run" \
  test "$RC" = 0 -a "$(head -n 1 <<<"$STDOUT")" = "dry run: would push hermes/grid-refresh-dry" \
  -a -z "$(remote_branches)" -a "$(calls 'pr create')" = 0 -a "$(calls 'pr list')" = 0
check "g: the diff stat names the files" grep -q 'public/grid/frames.bin' <<<"$STDOUT"
unset DRY_RUN

# ---- (h) A file outside public/grid changed.
case_dir
FAKE_MODE=outside
run
check "h: a change outside public/grid" \
  test "$RC" = 1 -a "$STDOUT" = "grid refresh failed: the generator changed files outside public/grid" -a -z "$(remote_branches)"

# ---- (i) Other safety checks: hours, sizes, the check of the room.
case_dir
FAKE_MODE=hours24
run
check "i: 24 hours instead of 25" \
  test "$RC" = 1 -a "$STDOUT" = "grid refresh not opened: run.json has 24 hours, the committed one has 25" -a -z "$(remote_branches)"
case_dir
FAKE_MODE=size
run
check "i: frames.bin has a new size" \
  test "$RC" = 1 -a "$STDOUT" = "grid refresh not opened: frames.bin has 2 bytes, the committed one has 12" -a -z "$(remote_branches)"
case_dir
CHECK_CMD="echo broken; exit 2"
run
check "i: the check of the room fails" \
  test "$RC" = 1 -a "$(head -n 1 <<<"$STDOUT")" = "grid refresh not opened: scripts/check.mjs fails" -a -z "$(remote_branches)"

if [ "$FAILED" -ne 0 ]; then
  echo "failed"
  exit 1
fi
echo "all passed"
