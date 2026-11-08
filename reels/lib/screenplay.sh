# screenplay.sh: the commands that read the screenplay and open the gate. Sourced by `reel`.
# shellcheck shell=sh

cmd_new() {
  [ $# -ge 2 ] && [ $# -le 3 ] || die "usage: reel new <slug> <15|30> [--example]"
  example=0
  if [ $# -eq 3 ]; then
    [ "$3" = "--example" ] || die "unknown option: $3"
    example=1
  fi
  slug=$1
  fmt=$2
  check_slug "$slug"
  case "$fmt" in 15 | 30) ;; *) die "format: 15 or 30 seconds" ;; esac
  proj=$(proj_dir "$slug")
  [ ! -e "$proj" ] && [ ! -L "$proj" ] || die "the project exists: $proj"
  # Built in a staging folder and moved into place with one rename: a failure leaves no half project
  # that "the project exists" would then refuse to replace. A slug never starts with a dot.
  stage=$HOME_DIR/projects/.new-$slug
  rm -rf "$stage"
  mkdir -p "$stage/review" "$stage/direction/storyboard" "$stage/direction/svg" "$stage/build" "$(out_dir "$slug")" || die "cannot make $proj"
  if [ "$example" -eq 1 ]; then
    jq --arg slug "$slug" '.slug = $slug' "$SHARE/examples/$fmt/screenplay.json" >"$stage/screenplay.json" || die "cannot copy the example"
    if [ -d "$SHARE/examples/$fmt/svg" ]; then cp "$SHARE/examples/$fmt/svg/"*.svg "$stage/direction/svg/"; fi
    cat >"$stage/brief.md" <<EOF
# Brief: $slug

This project starts from the example screenplay of the toolkit (\`reel new $slug $fmt --example\`).
It is a sample, not a client brief.
EOF
  else
    jq -n --arg slug "$slug" --argjson format "$fmt" -f "$LIB/skeleton.jq" >"$stage/screenplay.json" || die "cannot write the skeleton"
    cat >"$stage/brief.md" <<'EOF'
# Brief

## Audience
Who watches, and where (in the feed, with the sound off, on a phone).

## Promise
What the viewer has after 15 or 30 seconds, in one sentence.

## Constraint
What the reel must not say or show. The format, the language, the look.

## Sources
Every fact the reel states, with its source. Write `own` for what is the author's own claim.
EOF
  fi
  mv "$stage" "$proj" || die "cannot move the project into place: $proj"
  say "new project: $proj"
  say "next: the creative director fills screenplay.json, then: reel lint $slug"
}

cmd_lint() {
  [ $# -eq 1 ] || die "usage: reel lint <slug|file.json>"
  need_tools jq
  sp=$(sp_path "$1")
  valid_json "$sp"
  rc=0
  findings=$(run_lint "$sp")
  print_findings "$findings" || rc=1
  # A project with a shotlist: its lint too, when the screenplay itself is sound.
  case "$1" in
    *.json) ;;
    *)
      shot=$(proj_dir "$1")/direction/shotlist.json
      if [ -f "$shot" ]; then
        valid_json "$shot"
        if [ "$rc" -eq 0 ]; then
          sf=$(shotlist_lint "$sp" "$shot")
          say "shotlist:"
          print_findings "$sf" || rc=1
        else
          say "shotlist: not checked (the screenplay fails)"
        fi
      fi
      ;;
  esac
  if [ "$rc" -eq 0 ]; then say "lint: PASS"; else say "lint: FAIL"; fi
  return "$rc"
}

# shotlist_lint <screenplay file> <shotlist file>: the findings of the shotlist. The screenplay must
# be sound (lint passes).
shotlist_lint() {
  jq -c -L "$LIB" --argjson sp "$(cat "$1")" --argjson style "$(style_json "$1")" \
    --argjson profile "$PJ" --arg hash "$(sha_of "$1")" -f "$LIB/shotlint.jq" "$2" 2>"$TMP/shotlint.err" ||
    jq -n -c --rawfile why "$TMP/shotlint.err" '[{level: "error", rule: "shotlist", beat: null, msg: "the rules cannot read the shotlist: \($why | rtrimstr("\n"))"}]'
}

cmd_screenplay_view() {
  [ $# -eq 1 ] || die "usage: reel screenplay-view <slug|file.json>"
  sp=$(sp_path "$1")
  valid_json "$sp"
  jq -r -L "$LIB" -f "$LIB/view.jq" "$sp" | printable
}

cmd_timing_report() {
  [ $# -eq 1 ] || die "usage: reel timing-report <slug|file.json>"
  sp=$(sp_path "$1")
  valid_json "$sp"
  out=$(jq -r -L "$LIB" --argjson profile "$PJ" -f "$LIB/timing.jq" "$sp" | printable)
  say "$out"
  case "$out" in *"result: FAIL"*) return 1 ;; esac
}

cmd_approve() {
  [ $# -eq 1 ] || { [ $# -eq 3 ] && [ "$2" = "--by" ]; } || die "usage: reel approve <slug> [--by <name>]"
  slug=$1
  by=${3:-unnamed}
  case "$by" in
    '' | *[!A-Za-z0-9._@\ -]*) die "--by: letters, digits, space and . _ @ - only" ;;
  esac
  [ "${#by}" -le 60 ] || die "--by: at most 60 characters"
  check_slug "$slug"
  proj=$(proj_dir "$slug")
  plain_file "$proj/screenplay.json" || die "no screenplay for $slug (a missing file or a link)"
  # One copy is linted and hashed, so the hash is the one of the text that passed.
  cp "$proj/screenplay.json" "$TMP/approve.json" || die "cannot read the screenplay"
  valid_json "$TMP/approve.json"
  findings=$(run_lint "$TMP/approve.json")
  if ! print_findings "$findings"; then die "the lint fails: the screenplay is not approved"; fi
  [ "$(jq -r .slug "$TMP/approve.json")" = "$slug" ] || die "the slug in screenplay.json is not $slug"
  h=$(sha_of "$TMP/approve.json")
  {
    printf '%s  screenplay.json\n' "$h"
    printf 'approved %s by %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$by"
  } >"$proj/screenplay.approved.part"
  mv -f "$proj/screenplay.approved.part" "$proj/screenplay.approved"
  say "approved: $slug (sha256 $h)"
}

# shotlist <slug> [--force]: the default shotlist, for the creative director to refine.
cmd_shotlist() {
  [ $# -ge 1 ] && [ $# -le 2 ] || die "usage: reel shotlist <slug> [--force]"
  [ $# -eq 1 ] || [ "$2" = "--force" ] || die "unknown option: $2"
  require_approved "$1"
  # shellcheck disable=SC2153 # PROJ is set by require_approved
  dest=$PROJ/direction/shotlist.json
  if [ -e "$dest" ] && [ "${2:-}" != "--force" ]; then die "$dest exists: edit it, or use --force to start again"; fi
  mkdir -p "$PROJ/direction"
  jq -L "$LIB" --argjson style "$(style_json "$SP")" --arg hash "$APPROVED_HASH" -f "$LIB/shotlist.jq" "$SP" >"$dest.part"
  mv -f "$dest.part" "$dest"
  say "wrote $dest"
}
