# core.sh: paths, the gate, the helpers every command uses. Sourced by `reel`.
# shellcheck shell=sh

die() { printf 'reel: %s\n' "$*" >&2; exit 1; }
say() { printf '%s\n' "$*"; }
note() { printf 'reel: %s\n' "$*" >&2; }

# Every tool the scripts call by name, checked once: the wrapper's PATH has no more than these.
for _t in jq mktemp timeout nice sha256sum od cut head tr wc date basename dirname cat rm mv cp mkdir; do
  command -v "$_t" >/dev/null 2>&1 || die "missing tool: $_t"
done

HOME_DIR=${REELS_HOME:-/var/lib/openrig/work/reels-fabric}
OUTBOX=${REELS_OUTBOX:-/var/lib/rig-outbox/reels-fabric}
LIB=$SHARE/lib
FONTS=${REELS_FONTS:-$SHARE/fonts}
PROFILE=$SHARE/profile.json

# A path that reaches an ffmpeg filter graph, a fontconfig file or a Dialogue line is written into a
# syntax with its own special characters (: , ; ' [ ] \ < &). One rule keeps them out, here, instead
# of an escape at each place: these paths hold letters, digits and / . _ - only.
path_ok() {
  case "$1" in
    '' | *[!A-Za-z0-9/._-]*) die "$2: unsupported character in the path $1 (letters, digits and / . _ - only)" ;;
  esac
}
path_ok "$SHARE" REELS_SHARE
path_ok "$FONTS" REELS_FONTS
path_ok "$HOME_DIR" REELS_HOME

# Work files go to a private folder, removed at exit.
TMP=$(mktemp -d "${TMPDIR:-/tmp}/reel.XXXXXX") || die "cannot make a temporary folder"
# LOCK is set by render_lock, and only once this process holds it.
LOCK=
cleanup() {
  rm -rf "$TMP"
  if [ -n "$LOCK" ]; then rm -rf "$LOCK"; fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM
path_ok "$TMP" TMPDIR

# profile.json is read once. Every number of the toolkit is in it.
PJ=$(jq -c . "$PROFILE") || die "cannot read $PROFILE"
pnum() { printf '%s' "$PJ" | jq -r "$1"; }
W=$(pnum .video.width)
H=$(pnum .video.height)
FPS=$(pnum .video.fps)
FF_TIMEOUT=$(pnum .limits.ffmpeg_timeout_s)
RESVG_TIMEOUT=$(pnum .limits.resvg_timeout_s)

need_tools() {
  for t in "$@"; do command -v "$t" >/dev/null 2>&1 || die "missing tool: $t"; done
}

check_slug() {
  case "$1" in
    '' | -* | *[!a-z0-9-]*) die "slug: lowercase letters, digits and - only, and no - first (got: $1)" ;;
  esac
  [ "${#1}" -le 41 ] || die "slug: at most 41 characters"
}

proj_dir() { printf '%s/projects/%s' "$HOME_DIR" "$1"; }
out_dir() { printf '%s/out/%s' "$HOME_DIR" "$1"; }

sha_of() { sha256sum <"$1" | cut -d' ' -f1; }

# plain_file <path>: a regular file that is not a link. The gate reads the screenplay and its
# approval as they are, never through a link that someone can move.
plain_file() { [ -f "$1" ] && [ ! -L "$1" ]; }

# Every ffmpeg runs at low priority, with its threads capped and a time limit (profile limits). A
# stuck ffmpeg ends with a clear line instead of holding the seat. The unit has one memory budget
# for the daemon and all seats (docs/REELS.md, "Limits").
# ff: quiet. ffp: quiet and timed. ffl: its log is the result (loudnorm prints its measurement).
ff() {
  _frc=0
  timeout -k 5 "$FF_TIMEOUT" nice -n 10 ffmpeg -nostdin -hide_banner -loglevel error -y -filter_threads 2 -filter_complex_threads 2 "$@" || _frc=$?
  [ "$_frc" -ne 124 ] || note "ffmpeg stopped: no result after $FF_TIMEOUT s"
  return "$_frc"
}
ffl() {
  _frc=0
  timeout -k 5 "$FF_TIMEOUT" nice -n 10 ffmpeg -nostdin -hide_banner -nostats -loglevel info -y -filter_threads 2 -filter_complex_threads 2 "$@" || _frc=$?
  [ "$_frc" -ne 124 ] || note "ffmpeg stopped: no result after $FF_TIMEOUT s"
  return "$_frc"
}
# resvg: the same limit, with its own time.
svg_to_png() {
  _frc=0
  timeout -k 5 "$RESVG_TIMEOUT" nice -n 10 resvg --skip-system-fonts --use-fonts-dir "$FONTS" "$@" || _frc=$?
  [ "$_frc" -ne 124 ] || note "resvg stopped: no result after $RESVG_TIMEOUT s"
  return "$_frc"
}

# timed <command...>: runs it, appends "seconds peak-KiB" to $TIMES (GNU time, when it exists).
TIMES=$TMP/times
: >"$TIMES"
if env time -f "%e %M" true >/dev/null 2>&1; then
  timed() { env time -f "%e %M" -a -o "$TIMES" "$@"; }
else
  timed() {
    _s=$(date +%s)
    _trc=0
    "$@" || _trc=$?
    echo "$(($(date +%s) - _s)) 0" >>"$TIMES"
    return "$_trc"
  }
fi
ffp() {
  _frc=0
  timed timeout -k 5 "$FF_TIMEOUT" nice -n 10 ffmpeg -nostdin -hide_banner -loglevel error -y -filter_threads 2 -filter_complex_threads 2 "$@" || _frc=$?
  [ "$_frc" -ne 124 ] || note "ffmpeg stopped: no result after $FF_TIMEOUT s"
  return "$_frc"
}

# fontconfig reads only our two fonts, from a cache the user can write.
setup_fonts() {
  [ -d "$FONTS" ] || die "no fonts folder: $FONTS"
  _cache=${XDG_CACHE_HOME:-${HOME:+$HOME/.cache}}
  _cache=${_cache:-$TMP}/reels
  path_ok "$_cache" "the cache folder"
  mkdir -p "$_cache"
  cat >"$_cache/fonts.conf" <<EOF
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <dir>$FONTS</dir>
  <cachedir>$_cache/fontconfig</cachedir>
</fontconfig>
EOF
  FONTCONFIG_FILE=$_cache/fonts.conf
  export FONTCONFIG_FILE
}

# ---- the screenplay and its gate --------------------------------------------------------------

# styles_json: the names of the style files, as a JSON array.
styles_json() {
  for _f in "$SHARE"/styles/*.json; do basename "$_f" .json; done | jq -R . | jq -s -c .
}

# sp_path <slug or file>: where the screenplay is. A path to a .json file is used as it is (lint,
# view and timing work on any file); a slug means the project folder.
sp_path() {
  case "$1" in
    *.json)
      [ -f "$1" ] || die "no such file: $1"
      printf '%s' "$1"
      ;;
    *)
      check_slug "$1"
      [ -f "$(proj_dir "$1")/screenplay.json" ] || die "no screenplay for $1: $(proj_dir "$1")/screenplay.json (reel new $1 <15|30>)"
      printf '%s/screenplay.json' "$(proj_dir "$1")"
      ;;
  esac
}

valid_json() { jq -e . "$1" >/dev/null 2>&1 || die "$1 is not valid JSON"; }

# printable: what a screenplay says reaches a terminal only after the control characters are gone.
printable() { tr -d '\000-\010\013-\037\177'; }

# run_lint <screenplay file>: the findings as a JSON array on stdout. The lint fails closed: a file
# that the rules cannot read is an error, never a pass.
run_lint() {
  jq -c --argjson profile "$PJ" --argjson styles "$(styles_json)" -f "$LIB/lint.jq" "$1" 2>"$TMP/lint.err" ||
    jq -n -c --rawfile why "$TMP/lint.err" '[{level: "error", rule: "lint", beat: null, msg: "the rules cannot read this file: \($why | rtrimstr("\n"))"}]'
}

# print_findings <json array>: one line each, then the count. Returns 1 when there is an error.
print_findings() {
  printf '%s' "$1" | jq -r '.[] | "\(if .level == "error" then "ERROR" else "warn " end)  \(.beat // "--")  [\(.rule)]  \(.msg)"' | printable
  _e=$(printf '%s' "$1" | jq '[.[] | select(.level == "error")] | length')
  _w=$(printf '%s' "$1" | jq '[.[] | select(.level == "warn")] | length')
  say "lint: $_e error(s), $_w warning(s)"
  [ "$_e" -eq 0 ]
}

# require_approved <slug>: the gate of every command that makes a picture, a sound or a file in out/.
# It reads the screenplay and its approval now, at the time of use: nothing is cached from an earlier
# run. Sets SP (a private copy of the screenplay that was hashed, so the file cannot change under a
# render), PROJ and APPROVED_HASH. It refuses when
#   - screenplay.json or screenplay.approved is missing, or is a link;
#   - the first line of the approval is not exactly "<sha256 of screenplay.json>  screenplay.json"
#     (lower case; another case, a short hash or another name does not match);
#   - the lint of the screenplay fails (a hand-written approval does not skip the rules);
#   - the slug in the file is not the folder's.
require_approved() {
  check_slug "$1"
  PROJ=$(proj_dir "$1")
  _spf=$PROJ/screenplay.json
  _apf=$PROJ/screenplay.approved
  plain_file "$_spf" || die "no screenplay for $1 (a missing file or a link): $_spf"
  plain_file "$_apf" || die "the screenplay of $1 is not approved: run reel lint $1, then reel approve $1"
  SP=$TMP/screenplay.json
  cp "$_spf" "$SP" || die "cannot read $_spf"
  APPROVED_HASH=$(sha_of "$SP")
  _want=$(head -n 1 "$_apf")
  if [ "$_want" != "$APPROVED_HASH  screenplay.json" ]; then
    die "screenplay.json of $1 changed after its approval, or the approval is not in the form of reel approve (now $(printf '%.8s' "$APPROVED_HASH")): the creative director fixes it, then lint and approve again"
  fi
  jq -e . "$SP" >/dev/null 2>&1 || die "screenplay.json of $1 is not valid JSON"
  _lf=$(run_lint "$SP")
  if ! _lo=$(print_findings "$_lf"); then
    printf '%s\n' "$_lo" >&2
    die "the lint of $1 fails: the approval does not count"
  fi
  [ "$(jq -r '.slug' "$SP")" = "$1" ] || die "the slug in screenplay.json is not $1"
}

# style_json <screenplay file>: the style of the screenplay, with its palette overrides, as JSON.
style_json() {
  _name=$(jq -r '.look.style' "$1")
  case "$_name" in '' | null | *[!a-z0-9-]*) die "no style: $_name" ;; esac
  [ -f "$SHARE/styles/$_name.json" ] || die "no style $_name"
  jq -c --slurpfile sp "$1" '. * {colors: (($sp[0].look.palette) // {})}' "$SHARE/styles/$_name.json"
}
