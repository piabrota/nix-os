#!/usr/bin/env bash
# Refresh the data of the ▲ grid of piabrota/room and open a PR.
# Cron runs it once a day. It prints nothing when there is nothing to do.
# A new run adds nothing while a PR with a branch hermes/grid-refresh* is open: the owner merges
# or closes that PR first.
#
# Environment (all optional):
#   REPO_DIR       a clone of piabrota/room for this job only   (/var/lib/hermes/workspace/room-src)
#   TOKEN_FILE     the GitHub token file                       (/run/hermes-github/piabrota)
#   REPO           the GitHub repository                       (piabrota/room)
#   GRID_CMD       the generator, run in REPO_DIR              (nix develop ... --command just grid)
#   CHECK_CMD      the invariant check, run in REPO_DIR        (nix develop ... --command node scripts/check.mjs)
#   GRID_TIMEOUT   seconds for GRID_CMD                        (2400)
#   CHECK_TIMEOUT  seconds for CHECK_CMD                       (600)
#   DRY_RUN        1 = no git push and no gh pr create; print what would happen
#   OUT_PATCH      a file path: write the commit there as a patch

# -E: the ERR trap also fires inside functions.
set -eEuo pipefail

# Cron runs this script with the PATH of the hermes-agent unit. The system profile has nix, so
# add it at the end: the unit's own tools keep their order.
export PATH="$PATH:/run/current-system/sw/bin"

# A missing tool must stop the run now, not half way through the generator.
for tool in git gh jq timeout wc date cat tail mktemp rm env; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "grid refresh failed: $tool is not on the PATH"
    exit 1
  fi
done

STEP="start"
BODY=""
BRANCH=""
PR_URL=""
OUT=""
RC=0
CHANGES=()
CHANGE_LINES=""
MESH_CHANGED=0
OLD_JSON=""
NEW_JSON=""
HOURS=""
FIRST=""
LAST=""
FETCHED=""
SST_DATE=""
NODES=""
TRIANGLES=""
OLD_NODES=""
OLD_TRIANGLES=""

# Any failed command ends here with one line on stdout.
trap 'echo "grid refresh failed: $STEP"; exit 1' ERR
trap '[ -z "$BODY" ] || rm -f "$BODY"' EXIT

REPO_DIR=${REPO_DIR:-/var/lib/hermes/workspace/room-src}
TOKEN_FILE=${TOKEN_FILE:-/run/hermes-github/piabrota}
REPO=${REPO:-piabrota/room}
NIX_DEVELOP="nix develop --extra-experimental-features 'nix-command flakes' \"path:$REPO_DIR\" --command"
GRID_CMD=${GRID_CMD:-"$NIX_DEVELOP just grid"}
CHECK_CMD=${CHECK_CMD:-"$NIX_DEVELOP node scripts/check.mjs"}
GRID_TIMEOUT=${GRID_TIMEOUT:-2400}
CHECK_TIMEOUT=${CHECK_TIMEOUT:-600}
DRY_RUN=${DRY_RUN:-}
OUT_PATCH=${OUT_PATCH:-}

fail() {
  echo "grid refresh failed: $1"
  exit 1
}

not_opened() {
  echo "grid refresh not opened: $1"
  exit 1
}

is_dry() {
  [ "$DRY_RUN" = 1 ]
}

# ---------------------------------------------------------------- Step 1
read_token() {
  STEP="read the token"
  if [ ! -r "$TOKEN_FILE" ]; then
    echo "grid refresh waiting: the piabrota-hermes App has no installation on piabrota/room (no token file)"
    exit 0
  fi
  GH_TOKEN=$(cat "$TOKEN_FILE")
  export GH_TOKEN
}

# ---------------------------------------------------------------- Step 2
prepare_repo() {
  if [ ! -d "$REPO_DIR" ]; then
    STEP="clone $REPO"
    gh repo clone "$REPO" "$REPO_DIR" -- --depth 1 --filter=blob:none >/dev/null 2>&1
  fi
  STEP="update the clone of $REPO"
  cd "$REPO_DIR"
  git fetch -q --depth 1 origin main
  git checkout -q -f --detach FETCH_HEAD
  # No -x: node_modules/ is ignored by git. It is the cache, with node_modules/.grid/ in it,
  # where the generator keeps Natural Earth.
  git clean -fdq
}

# ---------------------------------------------------------------- Step 3
check_open_pr() {
  STEP="look for an open PR"
  local n
  n=$(gh pr list -R "$REPO" --state open --limit 200 --json headRefName \
    --jq '[.[]|select(.headRefName|startswith("hermes/grid-refresh"))]|length')
  if [ "$n" != 0 ]; then
    exit 0
  fi
}

# ---------------------------------------------------------------- Step 4
# Run a command string in REPO_DIR with a time limit. The output goes to OUT and the status to RC.
# The token stays out of the environment of the command: npm packages run code.
run_cmd() {
  local limit=$1 cmd=$2
  RC=0
  OUT=$(cd "$REPO_DIR" && trap - ERR && timeout -k 30 "$limit" env -u GH_TOKEN -u GITHUB_TOKEN bash -c "$cmd" 2>&1) || RC=$?
}

generate() {
  STEP="run the generator"
  run_cmd "$GRID_TIMEOUT" "$GRID_CMD"
  if [ "$RC" -ne 0 ]; then
    if [ "$RC" -eq 124 ]; then
      fail "$STEP (it did not end in $GRID_TIMEOUT seconds)"
    fi
    echo "grid refresh failed: $STEP"
    printf '%s\n' "$OUT" | tail -n 5
    exit 1
  fi
}

# ---------------------------------------------------------------- Step 5
look_at_changes() {
  STEP="look for changes"
  if [ -n "$(git status --porcelain -- . ':(exclude)public/grid')" ]; then
    fail "the generator changed files outside public/grid"
  fi
  mapfile -t CHANGES < <(git status --porcelain -- public/grid)
  if [ "${#CHANGES[@]}" -eq 0 ]; then
    exit 0
  fi
  if [ -n "$(git status --porcelain -- public/grid/mesh.bin)" ]; then
    MESH_CHANGED=1
  fi
}

# ---------------------------------------------------------------- Step 6
# The size of a file in the committed tree. It fails when the tree has no such file.
old_size() {
  git cat-file -s "HEAD:public/grid/$1" 2>/dev/null
}

new_size() {
  local n
  n=$(wc -c <"public/grid/$1")
  printf '%s' "${n// /}"
}

verify() {
  STEP="check the new data"
  local f old new

  [ -f public/grid/run.json ] || not_opened "run.json is missing"
  NEW_JSON=$(cat public/grid/run.json)
  jq -e 'type == "object"' <<<"$NEW_JSON" >/dev/null 2>&1 || not_opened "run.json is not valid JSON"
  OLD_JSON=$(git show HEAD:public/grid/run.json)

  # The sea temperature: a missing OSTIA day must not replace a good one.
  if jq -e '.sst != null' <<<"$OLD_JSON" >/dev/null && ! jq -e '.sst != null' <<<"$NEW_JSON" >/dev/null; then
    not_opened "the sea temperature is missing (Copernicus Marine)"
  fi

  old=$(jq -r '.hours | length' <<<"$OLD_JSON")
  HOURS=$(jq -r '.hours | length' <<<"$NEW_JSON")
  [ "$HOURS" = "$old" ] || not_opened "run.json has $HOURS hours, the committed one has $old"

  NODES=$(jq -r '.nodes' <<<"$NEW_JSON")
  TRIANGLES=$(jq -r '.triangles' <<<"$NEW_JSON")
  OLD_NODES=$(jq -r '.nodes' <<<"$OLD_JSON")
  OLD_TRIANGLES=$(jq -r '.triangles' <<<"$OLD_JSON")
  if [ "$MESH_CHANGED" = 0 ] && { [ "$NODES" != "$OLD_NODES" ] || [ "$TRIANGLES" != "$OLD_TRIANGLES" ]; }; then
    not_opened "run.json has other nodes or triangles, but mesh.bin did not change"
  fi

  # Same nodes and same hours: the binary files keep their sizes.
  for f in frames.bin sst.bin; do
    if old=$(old_size "$f"); then
      [ -f "public/grid/$f" ] || not_opened "$f is missing"
      new=$(new_size "$f")
      [ "$new" = "$old" ] || not_opened "$f has $new bytes, the committed one has $old"
    fi
  done

  # Invariant 9 of the room (the 25 MB budget of public/, the radio apart) is in scripts/check.mjs:
  # a plain du of public/ would count the 77 MB of the radio.
  STEP="run the check of the room"
  run_cmd "$CHECK_TIMEOUT" "$CHECK_CMD"
  if [ "$RC" -ne 0 ]; then
    echo "grid refresh not opened: scripts/check.mjs fails"
    printf '%s\n' "$OUT" | tail -n 5
    exit 1
  fi

  FIRST=$(jq -r '.hours[0]' <<<"$NEW_JSON")
  LAST=$(jq -r '.hours[-1]' <<<"$NEW_JSON")
  FETCHED=$(jq -r '.fetched // "not stated"' <<<"$NEW_JSON")
  SST_DATE=$(jq -r '.sst.date // "none"' <<<"$NEW_JSON")
}

# ---------------------------------------------------------------- Step 7
# One line for each changed file: its sizes before and after.
describe_changes() {
  STEP="describe the changes"
  local line file before after note
  CHANGE_LINES=""
  for line in "${CHANGES[@]}"; do
    file=${line:3}
    file=${file#public/grid/}
    if before=$(old_size "$file"); then
      before="$before bytes"
    else
      before="no file"
    fi
    if [ -f "public/grid/$file" ]; then
      after="$(new_size "$file") bytes"
    else
      after="no file"
    fi
    note=""
    case $file in
      mesh.bin | land.json) note=" **changed: check the Natural Earth source**" ;;
    esac
    CHANGE_LINES+="- \`$file\`: $before before, $after after.$note"$'\n'
  done
}

remote_branch_exists() {
  local rc=0
  git ls-remote --exit-code --heads origin "$1" >/dev/null || rc=$?
  case $rc in
    0) return 0 ;;
    2) return 1 ;;
    *) fail "$STEP" ;;
  esac
}

choose_branch() {
  if is_dry; then
    BRANCH="hermes/grid-refresh-dry"
  else
    STEP="choose a branch name"
    local base n=2
    base="hermes/grid-refresh-$(date +%Y%m%d)"
    BRANCH=$base
    while remote_branch_exists "$BRANCH"; do
      BRANCH="$base-$n"
      n=$((n + 1))
    done
  fi
  # -B: a branch of an earlier run that did not push may still exist here.
  git checkout -q -B "$BRANCH"
}

# ---------------------------------------------------------------- Step 8
write_body() {
  cat <<EOF
## Summary

This PR refreshes the data of the ▲ grid. The daily job of Hermes made it.
The wind runs from $FIRST to $LAST UTC, in $HOURS hourly frames. Open-Meteo gave it on $FETCHED.
The sea temperature is the OSTIA day $SST_DATE.

## What changed

$CHANGE_LINES
## Tested

- \`scripts/check.mjs\` passes.
EOF
  if [ "$NODES" = "$OLD_NODES" ] && [ "$TRIANGLES" = "$OLD_TRIANGLES" ]; then
    echo "- The numbers of \`run.json\` equal the committed ones: $NODES nodes, $TRIANGLES triangles, $HOURS hours."
  else
    echo "- \`mesh.bin\` changed on purpose: $OLD_NODES to $NODES nodes, $OLD_TRIANGLES to $TRIANGLES triangles."
  fi
  cat <<'EOF'
- Nothing else ran.

## Not tested

- No screenshot and no clip: the code did not change.
- The job did not look at the map.

## Notes

- The sea is an estimate from the wind, not WAVEWATCH III.
- The wind data come from Open-Meteo (CC BY 4.0). The temperature data come from Copernicus Marine.
- The site of the room shows these data only after a PR in piabrota/nix-os moves its pin of the room.
- A new run of the job adds nothing while this PR is open.
EOF
}

commit_and_publish() {
  local title ident=() names=() line

  title="Refresh the data of the grid: wind of ${FIRST%%T*}, temperature of $SST_DATE"
  for line in "${CHANGES[@]}"; do
    names+=("${line:3}")
  done

  STEP="commit"
  git add -A -- public/grid
  if [ -z "$(git config user.name || true)" ]; then
    ident=(-c user.name=piabrota-hermes -c user.email=piabrota-hermes@users.noreply.github.com)
  fi
  git ${ident[@]+"${ident[@]}"} commit -q \
    -m "$title" \
    -m "Files changed: ${names[*]#public/grid/}. Hours: $HOURS. Nodes: $NODES. Triangles: $TRIANGLES."

  if [ -n "$OUT_PATCH" ]; then
    STEP="write the patch"
    git format-patch -1 --stdout >"$OUT_PATCH"
    echo "patch: $OUT_PATCH"
  fi

  if is_dry; then
    echo "dry run: would push $BRANCH"
    git --no-pager diff --stat HEAD~1
    exit 0
  fi

  STEP="push the branch"
  git push origin "$BRANCH" >/dev/null 2>&1

  STEP="open the pull request"
  BODY=$(mktemp "${TMPDIR:-/tmp}/grid-refresh-XXXXXX.md")
  write_body >"$BODY"
  PR_URL=$(gh pr create -R "$REPO" --base main --head "$BRANCH" --title "$title" --body-file "$BODY")
  echo "grid refresh: opened $PR_URL (wind from ${FIRST%%T*}, temperature of $SST_DATE)"
}

# ---------------------------------------------------------------- Main
if ! is_dry; then
  read_token
fi
prepare_repo
if ! is_dry; then
  check_open_pr
fi
generate
look_at_changes
verify
describe_changes
choose_branch
commit_and_publish
