# core.sh: paths, validation, locks and helpers every command uses. Sourced by `thesis`.
# shellcheck shell=sh
# shellcheck disable=SC2034,SC2329,SC2015,SC2129,SC2016
# (SC2034 and SC2329: the libraries share variables and functions through `thesis`, which sources them all;
# SC2015: the `A && B || C` forms end in a die; SC2016: sh -c and awk programs in single quotes are meant.)

die() { printf 'thesis: %s\n' "$*" >&2; exit 1; }
say() { printf '%s\n' "$*"; }
note() { printf 'thesis: %s\n' "$*" >&2; }

# Every tool the scripts call by name, checked once: the wrapper's PATH has no more than these.
for _t in jq pandoc pdflatex pdfinfo pdftotext pdffonts pdftohtml awk sed grep mktemp timeout nice sha256sum od cut head tail tr wc date basename dirname cat rm mv cp mkdir sort uniq find diff ln; do
  command -v "$_t" >/dev/null 2>&1 || die "missing tool: $_t"
done

HOME_DIR=${THESIS_HOME:-/var/lib/openrig/work/wave-forecaster-thesis}
OUTBOX=${THESIS_OUTBOX:-/var/lib/rig-outbox/wave-forecaster-thesis}
LIB=$SHARE/lib
PROFILE=$SHARE/profile.json
FILTERS=$SHARE/filters
export THESIS_PROFILE="$PROFILE"

# Work files go to a private folder, removed at exit.
TMP=$(mktemp -d "${TMPDIR:-/tmp}/thesis.XXXXXX") || die "cannot make a temporary folder"
# LOCKS holds the lock folders of this process, one per line; they are removed at exit.
LOCKS=$TMP/locks-held
: >"$LOCKS"
cleanup() {
  if [ -f "$LOCKS" ]; then
    while IFS= read -r _l; do [ -n "$_l" ] && rm -rf "$_l"; done <"$LOCKS"
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# profile.json: every number of the toolkit is in it. pn <jq filter> prints the raw value.
pn() { jq -r "$1" "$PROFILE"; }
PANDOC_TIMEOUT=$(pn .limits.pandoc_timeout_s)
TEX_TIMEOUT=$(pn .limits.tex_timeout_s)
POPPLER_TIMEOUT=$(pn .limits.poppler_timeout_s)
ABBR=$(pn '.lists.abbreviations | join(" ")')

need_tools() {
  for _t in "$@"; do command -v "$_t" >/dev/null 2>&1 || die "missing tool: $_t"; done
}

# An id, a slug or a seat name: letters, digits, - and _; no leading -, no ., no /, no space.
check_name() {
  _what=$1
  _val=$2
  _max=$3
  case "$_val" in
    '' | -* | *[!A-Za-z0-9_-]*) die "$_what: letters, digits, - and _ only, and no - first (got: $_val)" ;;
  esac
  [ "${#_val}" -le "$_max" ] || die "$_what: at most $_max characters"
}
check_slug() { check_name slug "$1" "$(pn .limits.slug_max)"; }
check_id() { check_name "section id" "$1" "$(pn .limits.id_max)"; }
check_seat() { check_name seat "$1" "$(pn .limits.id_max)"; }

proj_dir() { printf '%s/projects/%s' "$HOME_DIR" "$1"; }
out_dir() { printf '%s/out/%s' "$HOME_DIR" "$1"; }

# need_project <slug>: sets P (the project folder) and checks that thesis.json is there.
need_project() {
  check_slug "$1"
  P=$(proj_dir "$1")
  [ -d "$P" ] || die "no project $1 (looked in $P)"
  [ -f "$P/thesis.json" ] && [ ! -L "$P/thesis.json" ] || die "$1: thesis.json is missing or a link"
  jq -e . "$P/thesis.json" >/dev/null 2>&1 || die "$1: thesis.json is not valid JSON"
  SLUG=$1
}

# need_section <id>: checks the id, that thesis.json has it, and sets SEC (a compact JSON object).
need_section() {
  check_id "$1"
  SEC=$(jq -c --arg id "$1" '.sections[] | select(.id == $id)' "$P/thesis.json")
  [ -n "$SEC" ] || die "$SLUG: thesis.json has no section $1"
  [ "$(printf '%s\n' "$SEC" | wc -l)" -eq 1 ] || die "$SLUG: the section id $1 is in thesis.json twice"
  SID=$1
}
sec() { printf '%s' "$SEC" | jq -r "$1"; }

# log <message>: one line to the project log (notes/thesis.log) and to stderr.
log() {
  _line="$(date -u +%Y-%m-%dT%H:%M:%SZ) ${SEAT:-?} $*"
  note "$*"
  if [ -n "${P:-}" ] && [ -d "$P/notes" ]; then printf '%s\n' "$_line" >>"$P/notes/thesis.log" 2>/dev/null || true; fi
}

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
now_s() { date +%s; }
sha_of() { sha256sum <"$1" | cut -d' ' -f1; }

# plain_file <path>: a regular file that is not a link. The gates read the sections as they are,
# never through a link that someone can move.
plain_file() { [ -f "$1" ] && [ ! -L "$1" ]; }

# seat_name: --as, THESIS_SEAT, or the member folder the caller stands in.
seat_name() {
  if [ -n "${1:-}" ]; then
    check_seat "$1"
    printf '%s' "$1"
    return 0
  fi
  if [ -n "${THESIS_SEAT:-}" ]; then
    check_seat "$THESIS_SEAT"
    printf '%s' "$THESIS_SEAT"
    return 0
  fi
  _here=$(pwd -P)
  case "$_here" in
    "$HOME_DIR"/projects | "$HOME_DIR"/projects/* | "$HOME_DIR"/out | "$HOME_DIR"/out/*) ;;
    "$HOME_DIR"/*)
      _m=${_here#"$HOME_DIR"/}
      _m=${_m%%/*}
      check_seat "$_m"
      printf '%s' "$_m"
      return 0
      ;;
  esac
  die "who are you? give --as <seat>, or set THESIS_SEAT, or run from your member folder under $HOME_DIR"
}

# lock <name>: a lock folder in the project (mkdir is atomic). Waits up to ~20 s. It is removed at
# exit, by cleanup, and by unlock.
lock() {
  _ld="$P/.lock-$1"
  _n=0
  while ! mkdir "$_ld" 2>/dev/null; do
    # A lock folder older than 120 s belongs to a process that died.
    if [ -d "$_ld" ] && [ -n "$(find "$_ld" -maxdepth 0 -mmin +2 2>/dev/null)" ]; then rm -rf "$_ld"; continue; fi
    _n=$((_n + 1))
    [ "$_n" -le 200 ] || die "$SLUG: the lock $1 is held by another run"
    sleep 0.1
  done
  printf '%s\n' "$_ld" >>"$LOCKS"
}
unlock() {
  rm -rf "$P/.lock-$1"
}

# atomic_write <file>: the standard input to a temp name in the same folder, then rename.
atomic_write() {
  _tmp=$(mktemp "$(dirname -- "$1")/.tmp.XXXXXX") || die "cannot write in $(dirname -- "$1")"
  cat >"$_tmp" || {
    rm -f "$_tmp"
    die "cannot write $1"
  }
  chmod 0644 "$_tmp"
  mv -f "$_tmp" "$1"
}

# run_timeout <seconds> <label> <command...>: stops the command after the time, with a clear line.
run_timeout() {
  _secs=$1
  _label=$2
  shift 2
  _rc=0
  timeout -k 5 "$_secs" "$@" || _rc=$?
  if [ "$_rc" -eq 124 ] || [ "$_rc" -eq 137 ]; then note "$_label stopped: no result after $_secs s"; fi
  return "$_rc"
}

# The state of a section lives in state/<id>.json, one file a section, so two writers never rewrite
# the same file (thesis.json is shared and only the editor edits it).
state_file() { printf '%s/state/%s.json' "$P" "$1"; }
state_get() { # <id> <jq filter on the state object>
  _sf=$(state_file "$1")
  if [ -f "$_sf" ]; then jq -r "$2" "$_sf"; else printf 'null\n'; fi
}
state_put() { # <id> <jq expression that edits the state object>; arguments after: jq --arg pairs
  _id=$1
  _expr=$2
  shift 2
  _sf=$(state_file "$_id")
  mkdir -p "$P/state"
  if [ -f "$_sf" ]; then _old=$(cat "$_sf"); else _old='{}'; fi
  printf '%s' "$_old" | jq "$@" "$_expr" | atomic_write "$_sf"
}

# The text of a section file with the CRLF of a Windows editor kept out of the checks.
section_file() { printf '%s/sections/%s.md' "$P" "$1"; }

# UTF-8 upper case for what jq cannot: the Latin-1 letters of Portuguese.
JQ_UPCASE='def upcase: explode | map(if (. >= 97 and . <= 122) or (. >= 224 and . <= 254 and . != 247) then . - 32 else . end) | implode;'
