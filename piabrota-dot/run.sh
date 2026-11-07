#!/bin/sh
# piabrota-dot: once a day, look for a new release of Hermes Agent and of OpenRig, and open (or
# refresh) one pull request on piabrota/nix-os for each, as the GitHub App piabrota-dot[bot]. No
# model: only git, gh, jq and nix. Run by the unit piabrota-dot (piabrota-dot.nix, docs/PIABROTA-DOT.md).
#
#   run.sh [--dry-run]    every step runs; every GitHub write and every push is printed and skipped
#
# Environment (the unit sets them; the defaults are the box's):
#   DOT_STATE             state folder                      /var/lib/piabrota-dot
#   DOT_TOKEN_FILE        one-hour token (piabrota-dot-token) /run/piabrota-dot/token
#   DOT_REPO              owner/name                        piabrota/nix-os
#   DOT_CLONE_URL         where to clone from               https://github.com/$DOT_REPO.git
#   DOT_CREDENTIAL_HELPER git credential helper             git-credential.sh next to this file
#   DOT_MERGE_HERMES, DOT_MERGE_OPENRIG   "true" lets the bot merge ITS OWN pull request (off)
#
# The bump scripts of the clone (scripts/hermes-bump.sh, scripts/openrig-bump.sh) are the contract:
#   --check             prints "pin:", "latest:" and "state:" lines; exit 0 current, 10 newer, else failure
#   --output FILE       writes key=value lines (old, new, compare_url, commit, changed) and the
#                       Markdown notes to FILE.notes.md; rewrites the pin files only, never commits
# The result of a run is $DOT_STATE/last-run.txt (no secret in it: Hermes reads it).
set -eu
umask 077

DRY=0
for arg in "$@"; do
  case $arg in
    --dry-run) DRY=1 ;;
    *) echo "usage: run.sh [--dry-run]" >&2; exit 2 ;;
  esac
done
if [ "${DOT_DRY_RUN:-}" = 1 ]; then DRY=1; fi

STATE=${DOT_STATE:-/var/lib/piabrota-dot}
TOKEN_FILE=${DOT_TOKEN_FILE:-/run/piabrota-dot/token}
REPO=${DOT_REPO:-piabrota/nix-os}
OWNER=${REPO%%/*}
CLONE_URL=${DOT_CLONE_URL:-https://github.com/$REPO.git}
HERE=$(cd "$(dirname "$0")" && pwd)
HELPER=${DOT_CREDENTIAL_HELPER:-$HERE/git-credential.sh}
BOT='piabrota-dot[bot]'
CLONE=$STATE/nix-os
W=$STATE/work
LAST_RUN=$STATE/last-run.txt

# No token, no work: the key file is not on the box, or the token unit has not run yet.
[ -r "$TOKEN_FILE" ] || exit 0
TOKEN=$(cat "$TOKEN_FILE")
[ -n "$TOKEN" ] || exit 0
export GH_TOKEN="$TOKEN" GH_PROMPT_DISABLED=1 GH_NO_UPDATE_NOTIFIER=1 GIT_TERMINAL_PROMPT=0
export DOT_TOKEN_FILE="$TOKEN_FILE"

mkdir -p "$STATE"
# One run at a time. A second one, started while the first runs, leaves quietly.
exec 9>"$STATE/lock"
flock -n 9 || exit 0

rm -rf "$W"
mkdir -p "$W"
: >"$W/result"

# git reads the token through the helper, so it is never in a URL or a command line.
export GIT_CONFIG_COUNT=2
export GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0=
export GIT_CONFIG_KEY_1=credential.helper GIT_CONFIG_VALUE_1="$HELPER"

# ------------------------------------------------------------------ helpers

# Every line that leaves this script goes through scrub: the token is replaced, in case a tool echoes it.
scrub() {
  DOT_SCRUB=$TOKEN awk 'BEGIN { t = ENVIRON["DOT_SCRUB"] }
    { if (t != "") while ((i = index($0, t)) > 0) $0 = substr($0, 1, i - 1) "***" substr($0, i + length(t)); print }'
}
log() { printf '%s\n' "$*" | scrub >&2; }

# One line of the result, for the component C.
note() { printf '%s\n' "$*" >>"$W/result"; }
news() { : >"$W/news"; }

die() {
  note "$C: failed: $*"
  [ -s "$W/failed" ] || printf '%s: %s\n' "$C" "$*" >"$W/failed"
  log "$C: failed: $*"
  exit 1
}

# Reads from GitHub. A failure leaves gh's message in $W/gh.err.
ghr() { gh api "$@" 2>"$W/gh.err"; }
die_gh() { die "$1 ($(head -n 1 "$W/gh.err" | scrub))"; }

# Writes to GitHub: printed and skipped in a dry run. Prints the JSON answer.
ghw() {
  if [ "$DRY" = 1 ]; then
    log "dry-run: gh api $*"
    return 0
  fi
  gh api "$@" 2>"$W/gh.err"
}

# ------------------------------------------------------------------ the component table

# What each component moves, the pin files it may change, and its fixed Risk text.
component_name() {
  case $1 in
    hermes) echo "Hermes Agent" ;;
    openrig) echo "OpenRig" ;;
  esac
}
component_script() {
  case $1 in
    hermes) echo "scripts/hermes-bump.sh" ;;
    openrig) echo "scripts/openrig-bump.sh --channel release" ;;
  esac
}
component_allow() {
  case $1 in
    hermes) printf '%s\n' flake.nix flake.lock hermes.nix ;;
    openrig) printf '%s\n' openrig/package.nix ;;
  esac
}
component_merge() {
  case $1 in
    hermes) [ "${DOT_MERGE_HERMES:-false}" = true ] ;;
    openrig) [ "${DOT_MERGE_OPENRIG:-false}" = true ] ;;
  esac
}
component_risk() {
  case $1 in
    hermes)
      echo "- A merge deploys. The deploy restarts the units \`hermes-agent\` and \`hermes-backend\`."
      echo "- The restart ends every live agent run."
      ;;
    openrig)
      echo "- The daemon runs new database migrations at its first start. They only go forward."
      echo "- Before you merge, take \`rig snapshot\` and make a copy of the daemon database."
      echo "- A merge restarts the \`openrig\` unit. The restart ends every live seat."
      ;;
  esac
}
component_units() {
  case $1 in
    hermes) echo "\`hermes-agent\` and \`hermes-backend\`" ;;
    openrig) echo "\`openrig\`" ;;
  esac
}

# ------------------------------------------------------------------ the clone

sync_clone() {
  if [ -d "$CLONE/.git" ]; then
    git -C "$CLONE" remote set-url origin "$CLONE_URL"
    git -C "$CLONE" fetch -q --depth 1 origin main
  else
    rm -rf "$CLONE"
    git clone -q --depth 1 --filter=blob:none --branch main "$CLONE_URL" "$CLONE"
  fi
  # This clone is the bot's own: nothing in it is worth keeping.
  git -C "$CLONE" checkout -q -f --detach origin/main
  git -C "$CLONE" reset -q --hard origin/main
  git -C "$CLONE" clean -fdxq
}

set_identity() {
  id=$(ghr "users/piabrota-dot%5Bbot%5D" | jq -r '.id // empty' || true)
  if [ -n "$id" ]; then email="$id+$BOT@users.noreply.github.com"; else email="$BOT@users.noreply.github.com"; fi
  export GIT_AUTHOR_NAME="$BOT" GIT_AUTHOR_EMAIL="$email" GIT_COMMITTER_NAME="$BOT" GIT_COMMITTER_EMAIL="$email"
}

# ------------------------------------------------------------------ GitHub lookups

# The JSON of the open pull request on the bot's branch of component $1, or nothing.
open_pr() {
  out=$(ghr "repos/$REPO/pulls?state=open&head=$OWNER:piabrota-dot/$1&per_page=10") || die_gh "cannot list pull requests"
  printf '%s' "$out" | jq -c '.[0] // empty'
}

# The URL of an issue with exactly this title, open or closed, made by the bot; or nothing.
find_issue() {
  out=$(ghr --paginate "repos/$REPO/issues?state=all&creator=piabrota-dot%5Bbot%5D&per_page=100") || die_gh "cannot list issues"
  printf '%s' "$out" | jq -r --arg t "$1" '[.[] | select(.pull_request == null and .title == $t)][0].html_url // empty'
}

ensure_label() {
  if ghr "repos/$REPO/labels/piabrota-dot" >/dev/null 2>&1; then return 0; fi
  ghw -X POST "repos/$REPO/labels" -f name=piabrota-dot -f color=0e8a16 \
    -f description="Opened by the piabrota-dot script" >/dev/null || log "the label piabrota-dot is missing and was not created: no label"
}
add_label() {
  ghw -X POST "repos/$REPO/issues/$1/labels" -f 'labels[]=piabrota-dot' >/dev/null || log "label not added"
}

# An issue for a release that cannot be used. $1 title, $2 file with the body. Sets ISSUE_URL.
open_issue() {
  out=$(ghw -X POST "repos/$REPO/issues" -f title="$1" -F body=@"$2") || die_gh "cannot open the issue"
  ISSUE_URL=$(printf '%s' "$out" | jq -r '.html_url // empty')
  : "${ISSUE_URL:=(dry run)}"
  if [ "$DRY" != 1 ]; then add_label "$(printf '%s' "$ISSUE_URL" | sed 's|.*/||')"; fi
}

# ------------------------------------------------------------------ the pull request body

write_body() { # $1 component, $2 old, $3 new, $4 compare url, $5 notes file, $6 body file, $7 changed files
  name=$(component_name "$1")
  {
    echo "## Summary"
    echo
    echo "This pull request moves $name from \`$2\` to \`$3\`."
    [ -z "$4" ] || echo "Compare the two releases: $4"
    echo "The script \`$(component_script "$1" | sed 's/ .*//')\` made the change. It edits only the pin files."
    echo
    echo "## Upgrade notes"
    echo
    if [ -s "$5" ]; then head -c 20000 "$5"; echo; else echo "The release has no upgrade notes."; fi
    echo
    echo "## Risk"
    echo
    component_risk "$1"
    echo
    echo "## Tested"
    echo
    echo "- \`nix eval\` of the \`piabrota\` system derivation: it evaluates."
    echo "- \`nix eval\` of the \`piabrota2\` system derivation: it evaluates."
    echo "- The bump script ran without error. It changed only these files: $7."
    echo
    echo "## Not tested"
    echo
    echo "- The build. \`deploy.yml\` builds the system at the merge."
    echo "- A live start of $(component_units "$1")."
  } >"$6"
}

# ------------------------------------------------------------------ evaluation and allow list

# Evaluation only, no build. A failure leaves its log in $W/eval-<host>.log.
eval_host() {
  nix eval --raw --no-update-lock-file \
    "path:$CLONE#nixosConfigurations.$1.config.system.build.toplevel.drvPath" >"$W/eval-$1.log" 2>&1
}

changed_files() { git -C "$CLONE" status --porcelain | cut -c4- ; }

outside_allow_list() { # $1 component: prints each changed file that is not allowed
  allow=$(component_allow "$1")
  changed_files | while IFS= read -r f; do
    printf '%s\n' "$allow" | grep -qxF -- "$f" || printf '%s\n' "$f"
  done
}

# An issue and a record, then stop this component. $1 title, $2 reason, $3 body text file.
issue_and_stop() {
  url=$(find_issue "$1")
  if [ -z "$url" ]; then
    open_issue "$1" "$3"
    url=$ISSUE_URL
  fi
  note "$C: issue $url"
  news
  log "$C: $2: issue $url"
  exit 0
}

# ------------------------------------------------------------------ the merge gate

# Prints why the pull request $1 (number) may not be merged, or nothing when every condition holds.
# $2 is the component, $3 the head sha that the bot pushed. Each check has a "gate:" tag.
gate_reason() {
  json=$(ghr "repos/$REPO/pulls/$1") || die_gh "cannot read the pull request"
  [ "$(printf '%s' "$json" | jq -r '.user.login')" = "$BOT" ] || { echo "the author is not $BOT"; return 0; } # gate:author
  [ "$(printf '%s' "$json" | jq -r '.draft')" = false ] || { echo "it is a draft"; return 0; } # gate:draft
  head=$(printf '%s' "$json" | jq -r '.head.sha')
  [ "$head" = "$3" ] || { echo "the head is not the commit that the bot pushed"; return 0; } # gate:sha

  files=$(ghr --paginate "repos/$REPO/pulls/$1/files?per_page=100") || die_gh "cannot read the files"
  allow=$(component_allow "$2")
  for f in $(printf '%s' "$files" | jq -r '.[].filename'); do
    printf '%s\n' "$allow" | grep -qxF -- "$f" || { echo "the diff touches $f"; return 0; } # gate:files
  done

  runs=$(ghr "repos/$REPO/commits/$head/check-runs?per_page=100") || die_gh "cannot read the check runs"
  [ "$(printf '%s' "$runs" | jq -r '.check_runs | length')" -gt 0 ] || { echo "the head has no check run"; return 0; } # gate:empty
  [ "$(printf '%s' "$runs" | jq -r '.total_count == (.check_runs | length)')" = true ] || { echo "too many check runs to read"; return 0; } # gate:empty
  [ "$(printf '%s' "$runs" | jq -r '[.check_runs[] | select(.status != "completed")] | length')" = 0 ] || { echo "a check is not finished"; return 0; } # gate:pending
  [ "$(printf '%s' "$runs" | jq -r '[.check_runs[] | select(.conclusion != "success" and .conclusion != "neutral" and .conclusion != "skipped")] | length')" = 0 ] || { echo "a check is not green"; return 0; } # gate:red

  stat=$(ghr "repos/$REPO/commits/$head/status") || die_gh "cannot read the statuses"
  if [ "$(printf '%s' "$stat" | jq -r '.total_count')" -gt 0 ]; then
    case $(printf '%s' "$stat" | jq -r '.state') in
      success) ;;
      pending) echo "a status is not finished"; return 0 ;; # gate:pending
      *) echo "a status is not green"; return 0 ;; # gate:red
    esac
  fi
}

# Merges the bot's own pull request $1 when the option of component $2 is on and the gate is open.
# $3 is the head sha that the bot pushed, $4 the URL. Prints nothing; notes the outcome.
try_merge() {
  component_merge "$2" || return 0
  why=$(gate_reason "$1" "$2" "$3")
  if [ -n "$why" ]; then
    note "$C: merge waits: $why"
    return 0
  fi
  if [ "$DRY" = 1 ]; then
    log "dry-run: would merge $4 with the squash method"
    return 0
  fi
  # One try. If the ruleset refuses, the bot stops: it does not retry and does not look for a way round.
  if ghw -X PUT "repos/$REPO/pulls/$1/merge" -f merge_method=squash -f sha="$3" >"$W/merge.out"; then
    note "$C: merged $4"
    return 0
  fi
  err=$(head -n 1 "$W/gh.err" | scrub)
  case $err in
    *"HTTP 405"* | *"HTTP 403"*) note "$C: merge refused by the ruleset" ;;
    *) note "$C: merge not done: $err" ;;
  esac
}

# ------------------------------------------------------------------ one component

process() {
  c=$1
  script=$(component_script "$c")
  # The script is a file of the clone, and runs from its root. $script may carry a flag.
  # shellcheck disable=SC2086
  (cd "$CLONE" && ./$script --check) >"$W/$c.check" 2>&1 && rc=0 || rc=$?
  pin=$(sed -n 's/^pin: *//p' "$W/$c.check" | head -n 1)
  case $rc in
    0)
      note "$C: current at ${pin:-the pinned release}"
      return 0
      ;;
    10) ;;
    *) die "the check of $c exited with $rc" ;;
  esac

  latest=$(sed -n 's/^latest: *//p' "$W/$c.check" | head -n 1)
  [ -n "$latest" ] || die "the check of $c gave no latest release"
  name=$(component_name "$c")
  branch=piabrota-dot/$c
  stamp=$STATE/pushed-$c

  # A release that did not evaluate has an issue already: do not work on it again.
  bad_title="piabrota-dot: $c $latest does not evaluate"
  url=$(find_issue "$bad_title")
  if [ -n "$url" ]; then
    note "$C: issue $url"
    news
    return 0
  fi

  pr=$(open_pr "$c")
  if [ -n "$pr" ]; then
    [ "$(printf '%s' "$pr" | jq -r '.user.login')" = "$BOT" ] || die "the open pull request on $branch is not the bot's"
    num=$(printf '%s' "$pr" | jq -r '.number')
    pr_url=$(printf '%s' "$pr" | jq -r '.html_url')
    head_sha=$(printf '%s' "$pr" | jq -r '.head.sha')
    s_latest=; s_sha=
    if [ -r "$stamp" ]; then read -r s_latest s_sha <"$stamp" || true; fi
    if [ "$s_latest" = "$latest" ] && [ "$s_sha" = "$head_sha" ]; then
      # Up to date: nothing to push. Only the merge may still happen.
      note "$C: open $pr_url for $pin to $latest"
      news
      try_merge "$num" "$c" "$head_sha" "$pr_url"
      return 0
    fi
  else
    num=
  fi

  # Build the change on a fresh branch from origin/main.
  git -C "$CLONE" checkout -q -f -B "$branch" origin/main
  git -C "$CLONE" clean -fdxq
  # shellcheck disable=SC2086
  (cd "$CLONE" && ./$script --output "$W/$c.out") >"$W/$c.bump" 2>&1 || die "the bump script of $c failed"
  old=$(sed -n 's/^old=//p' "$W/$c.out"); new=$(sed -n 's/^new=//p' "$W/$c.out")
  compare=$(sed -n 's/^compare_url=//p' "$W/$c.out")
  [ -n "$new" ] || die "the bump script of $c wrote no new version"
  : "${old:=$pin}"

  # The pin files only.
  files=$(changed_files | tr '\n' ' ' | sed 's/ $//')
  [ -n "$files" ] || die "the bump script of $c changed no file"
  extra=$(outside_allow_list "$c")
  if [ -n "$extra" ]; then
    {
      echo "The bump script for $name $new changed files outside its pin files. The bot opened no pull request."
      echo
      echo "Files outside the allow list:"
      echo
      # shellcheck disable=SC2016
      printf '%s\n' "$extra" | sed 's/^/- `/; s/$/`/'
    } >"$W/issue.md"
    issue_and_stop "piabrota-dot: $c $latest changes files outside its pin files" "files outside the allow list" "$W/issue.md"
  fi

  # Prove that both hosts still evaluate. A build is the deploy workflow's job, at the merge.
  for host in piabrota piabrota2; do
    if ! eval_host "$host"; then
      {
        echo "The bot did not open a pull request for $name $new. The system derivation of \`$host\` does not evaluate."
        echo
        echo "The last 40 lines of the error:"
        echo
        echo '```'
        tail -n 40 "$W/eval-$host.log" | scrub
        echo '```'
      } >"$W/issue.md"
      issue_and_stop "piabrota-dot: $c $latest does not evaluate" "$host does not evaluate" "$W/issue.md"
    fi
  done

  # shellcheck disable=SC2086,SC2016
  listed=$(printf '%s\n' $files | sed 's/.*/`&`/' | paste -sd, - | sed 's/,/, /g')
  write_body "$c" "$old" "$new" "$compare" "$W/$c.out.notes.md" "$W/$c.body.md" "$listed"
  title="chore($c): bump $name to $new"
  set_identity
  git -C "$CLONE" add -A
  git -C "$CLONE" commit -q -m "$title" -m "Old: $old. New: $new.${compare:+ Compare: $compare}"
  sha=$(git -C "$CLONE" rev-parse HEAD)

  if [ "$DRY" = 1 ]; then
    log "dry-run: would push $branch ($sha) and ${num:+update pull request $num}${num:-open a pull request}"
    log "dry-run: title: $title"
    sed 's/^/dry-run: | /' "$W/$c.body.md"
    note "$C: would open or refresh a pull request for $old to $new (dry run)"
    return 0
  fi

  git -C "$CLONE" push -q --force origin "$branch:refs/heads/$branch" 2>"$W/git.err" || die "the push of $branch failed ($(head -n 1 "$W/git.err" | scrub))"

  if [ -n "$num" ]; then
    ghw -X PATCH "repos/$REPO/pulls/$num" -f title="$title" -F body=@"$W/$c.body.md" >/dev/null || die_gh "cannot update the pull request"
    verb=refreshed
  else
    ensure_label
    out=$(ghw -X POST "repos/$REPO/pulls" -f title="$title" -f head="$branch" -f base=main -F body=@"$W/$c.body.md") || die_gh "cannot open the pull request"
    num=$(printf '%s' "$out" | jq -r '.number')
    pr_url=$(printf '%s' "$out" | jq -r '.html_url')
    add_label "$num"
    verb=opened
  fi
  printf '%s %s\n' "$latest" "$sha" >"$stamp"
  if [ "$verb" = opened ]; then
    note "$C: opened $pr_url for $old to $new"
  else
    note "$C: refreshed $pr_url"
  fi
  news
  try_merge "$num" "$c" "$sha" "$pr_url"
}

# ------------------------------------------------------------------ main

C=run
if ! sync_clone >"$W/sync.log" 2>&1; then
  note "run: failed: cannot update the clone of $REPO ($(tail -n 1 "$W/sync.log" | scrub))"
  printf 'run: cannot update the clone\n' >"$W/failed"
else
  for C in hermes openrig; do
    set +e
    ( set -eu; process "$C" )
    rc=$?
    set -e
    if [ "$rc" -ne 0 ] && ! grep -q "^$C: failed:" "$W/result"; then
      note "$C: failed: unexpected error"
      [ -s "$W/failed" ] || printf '%s: unexpected error\n' "$C" >"$W/failed"
    fi
  done
fi

# ------------------------------------------------------------------ the result

{
  if [ -s "$W/failed" ]; then
    echo "piabrota-dot failed: $(cat "$W/failed")"
  elif [ -e "$W/news" ]; then
    echo "piabrota-dot: news"
  else
    echo "piabrota-dot: nothing new"
  fi
  echo "time: $(TZ=America/Sao_Paulo date '+%Y-%m-%d %H:%M %Z')"
  cat "$W/result"
} | scrub >"$W/last-run.txt"

if [ "$DRY" = 1 ]; then
  log "dry-run: last-run.txt would be:"
  sed 's/^/dry-run: | /' "$W/last-run.txt"
else
  chmod 0644 "$W/last-run.txt"
  mv "$W/last-run.txt" "$LAST_RUN"
  cat "$LAST_RUN"
fi
