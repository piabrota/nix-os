#!/bin/sh
# shellcheck disable=SC2086,SC2015,SC2016,SC2012
# SC2086: $RENV, $REEL and $REEL_DASH are command words, split on purpose. SC2015: ok and bad always
# return 0, so `A && ok || bad` is an if-else. SC2016: single quotes keep `$(id)` literal, on purpose.
# SC2012: ls only counts the names of folders this script made.
# reels/test/run.sh: the tests of the toolkit. POSIX sh, no network, no python; ffmpeg, ffprobe, jq
# and the coreutils must be in the PATH. It runs the real `reel` on the 15 s example.
#
#   REEL           the command that runs reel (default: reel)
#   RENV           extra "NAME=value" words for `env -i` that REEL needs (a dev run: PATH, REELS_SHARE)
#   REEL_SCRIPT, REELS_SHARE, REELS_TOOLPATH, REELS_FONTS
#                  for the tests that put a fake ffmpeg first in the PATH: the script, the toolkit's
#                  share folder, the PATH of its tools, its fonts. Those tests are skipped without them.
#   REEL_DASH      optional: a command that runs the same script under dash
#   REELS_SPECS, REELS_OPENRIG_NIX
#                  optional: openrig/specs and openrig.nix, for the checks of the crew's seats. They
#                  default to the paths of a checkout (../../openrig/specs); the checks are skipped
#                  when the specs are not there.
#
# What it proves: the gate (every command that makes a file refuses without a matching approval),
# hostile text, slug rules, the lint, the render and its determinism, the QA with files that must
# fail, publish, 3d shots (with a stub in place of blender: Blender is never run here), the seats
# of the rig, atomicity and the ffmpeg time limit. About six minutes.
set -u

REEL=${REEL:-reel}
# The command that runs reel must exist, or every check fails for that one reason.
set -- $REEL
command -v "$1" >/dev/null 2>&1 || {
  printf 'reels/test/run.sh: cannot run "%s": set REEL (and RENV, for a checkout), see the top of this file\n' "$REEL" >&2
  exit 2
}
RENV=${RENV:-}
T=$(mktemp -d "${TMPDIR:-/tmp}/reels-test.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
RH=$T/rh
OB=$T/outbox
mkdir -p "$T/home" "$T/tmp" "$T/cwd"
N=0
FAILS=0

ok() { N=$((N + 1)); printf 'ok   %s\n' "$*"; }
bad() { N=$((N + 1)); FAILS=$((FAILS + 1)); printf 'FAIL %s\n' "$*"; }
section() { printf '\n== %s\n' "$*"; }

# r <args>: reel in a clean environment, in $T/cwd.
r() {
  (cd "$T/cwd" && env -i $RENV HOME="$T/home" XDG_CACHE_HOME="$T/cache" TMPDIR="$T/tmp" LANG="${TLANG:-C}" \
    REELS_HOME="$RH" REELS_OUTBOX="$OB" $REEL "$@")
}
# rd <args>: the same under dash.
rd() {
  (cd "$T/cwd" && env -i $RENV HOME="$T/home" XDG_CACHE_HOME="$T/cache" TMPDIR="$T/tmp" LANG="${TLANG:-C}" \
    REELS_HOME="$RH" REELS_OUTBOX="$OB" $REEL_DASH "$@")
}
# must_ok <what> <args>
must_ok() {
  _w=$1
  shift
  if _o=$(r "$@" 2>&1); then ok "$_w"; else bad "$_w: $(printf '%s' "$_o" | tail -n 3)"; fi
}
# must_fail <what> <text in the message> <args>: non-zero exit and the text in the output.
must_fail() {
  _w=$1
  _p=$2
  shift 2
  if _o=$(r "$@" 2>&1); then
    bad "$_w: it succeeded"
  elif printf '%s' "$_o" | grep -qF -- "$_p"; then
    ok "$_w"
  else
    bad "$_w: refused, but not with \"$_p\": $(printf '%s' "$_o" | tail -n 2)"
  fi
}

sp() { printf '%s/projects/%s/screenplay.json' "$RH" "$1"; }
proj() { printf '%s/projects/%s' "$RH" "$1"; }
outd() { printf '%s/out/%s' "$RH" "$1"; }
# edit <slug> <jq filter>
edit() { jq "$2" "$(sp "$1")" >"$T/edit.json" && cp "$T/edit.json" "$(sp "$1")"; }
# files <slug>: a signature of every file the project and its output hold.
files() { (cd "$RH" && find projects/"$1" out/"$1" -type f -o -type l | sort | tr '\n' ' ' | cksum); }
# sha <file>
sha() { sha256sum "$1" | cut -d' ' -f1; }
# fresh <slug> <format>: a new example project.
fresh() { r new "$1" "$2" --example >/dev/null 2>&1; }

# ---- slugs ----------------------------------------------------------------------------------
section "slugs"
for s in ../x a/b 'a b' -x '' .hidden Upper a_b 'a;b' 'a$(id)' "$(printf 'a%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42)"; do
  must_fail "reel new '$s' is refused" "slug" new "$s" 30
done
must_fail "reel new x 20 is refused" "15 or 30" new x 20
must_fail "reel new x 30 --bogus is refused" "unknown option" new x 30 --bogus
if [ ! -e "$RH/x" ]; then ok "no folder made by a bad slug"; else bad "a bad slug made a folder"; fi
n=$(ls "$RH/projects" 2>/dev/null | wc -l)
[ "$n" -eq 0 ] && ok "no project made by a bad slug" || bad "a bad slug made $n project(s)"
must_fail "lint ../x is refused" "slug" lint ../x
must_fail "still ../x b01 is refused" "slug" still ../x b01
must_fail "publish a/b is refused" "slug" publish a/b

# ---- the gate -------------------------------------------------------------------------------
section "the gate: no approval, no file"
fresh gate 15
must_ok "the example lints" lint gate
for c in "still gate b01" "scene gate b01" "music gate" "mix gate" "render gate" "shotlist gate" "qa gate" "contact-sheet gate" "publish gate" "blender gate b01"; do
  # shellcheck disable=SC2086
  must_fail "'reel $c' refuses before approval" "not approved" $c
done
[ ! -e "$(outd gate)/reel.mp4" ] && ok "no reel before approval" || bad "a reel exists before approval"
must_ok "approve" approve gate --by tester
must_ok "shotlist" shotlist gate
must_ok "still b02 after approval" still gate b02
cp "$(proj gate)/direction/storyboard/b02.png" "$T/b02-before.png"

# One character changed after approval: every command refuses, and none writes a file.
edit gate '.beats[1].text[0] = "Praia boa hoje!"'
before=$(files gate)
for c in "still gate b01" "scene gate b01" "music gate" "mix gate" "render gate" "shotlist gate --force" "qa gate" "contact-sheet gate" "publish gate" "blender gate b01"; do
  # shellcheck disable=SC2086
  must_fail "'reel $c' refuses after an edit" "changed after its approval" $c
done
after=$(files gate)
[ "$before" = "$after" ] && ok "the refused commands wrote no file" || bad "a refused command wrote a file"

# Forms of approval that must not count.
h=$(sha "$(sp gate)")
ap=$(proj gate)/screenplay.approved
try_approval() {
  printf '%s' "$2" >"$ap"
  must_fail "approval: $1" "approval" still gate b01
}
try_approval "upper case hash" "$(printf '%s' "$h" | tr 'a-f' 'A-F')  screenplay.json
"
try_approval "short hash" "$(printf '%.8s' "$h")  screenplay.json
"
try_approval "another file name" "$h  other.json
"
try_approval "a line before the hash" "approved by me
$h  screenplay.json
"
printf '%s  screenplay.json\r\n' "$h" >"$ap"
must_fail "approval: CRLF" "approval" still gate b01
printf '%s  screenplay.json\napproved by someone\nand more lines\n' "$h" >"$ap"
must_ok "approval: extra lines after the hash are fine" music gate
rm -f "$ap"
cp "$(sp gate)" "$T/copy.json"
printf '%s  screenplay.json\n' "$h" >"$T/real.approved"
ln -s "$T/real.approved" "$ap"
must_fail "approval: a symbolic link" "not approved" still gate b01
rm -f "$ap"
printf '%s  screenplay.json\n' "$h" >"$ap"
mv "$(sp gate)" "$T/moved.json"
ln -s "$T/moved.json" "$(sp gate)"
must_fail "screenplay.json: a symbolic link" "link" still gate b01
rm -f "$(sp gate)"
mv "$T/moved.json" "$(sp gate)"

# Re-approval: a changed beat renders again, and an old shotlist is stale.
must_ok "re-approve after the edit" approve gate
must_fail "a shotlist of the old text is stale" "another version" still gate b01
must_ok "shotlist --force" shotlist gate --force
must_ok "still b02 after re-approval" still gate b02
cmp -s "$(proj gate)/direction/storyboard/b02.png" "$T/b02-before.png" && bad "the changed beat gave the old picture" || ok "the changed beat gives a new picture"
out1=$(r scene gate b02 2>&1)
case "$out1" in *"up to date"*) bad "scene b02 reused a clip after a re-approval" ;; *) ok "scene b02 rendered after the re-approval" ;; esac
c1=$(sha "$(proj gate)/build/scenes/b02.mp4")
out2=$(r scene gate b02 2>&1)
case "$out2" in *"up to date"*) ok "an unchanged beat is reused" ;; *) bad "an unchanged beat was rendered again" ;; esac
edit gate '.beats[1].text[0] = "Praia boa hoje?"'
must_fail "the clip cache does not serve a stale scene" "changed after its approval" scene gate b02
must_ok "approve again" approve gate
must_ok "shotlist --force again" shotlist gate --force
out3=$(r scene gate b02 2>&1)
case "$out3" in *"up to date"*) bad "scene b02 served a stale clip" ;; *) ok "scene b02 rendered again after the text changed back" ;; esac
[ "$(sha "$(proj gate)/build/scenes/b02.mp4")" != "$c1" ] && ok "the clip changed with the text" || bad "the clip did not change with the text"
# a change that touches no beat still voids the cache: the key holds the approved hash
edit gate '.logline = "Another logline for the same beats"'
must_ok "approve the logline change" approve gate
must_ok "shotlist --force after the logline change" shotlist gate --force
out4=$(r scene gate b02 2>&1)
case "$out4" in *"up to date"*) bad "a clip outlived its approval" ;; *) ok "a clip never outlives its approval" ;; esac

# ---- hostile text ---------------------------------------------------------------------------
section "hostile text"
fresh evil 15
edit evil '.beats[1].text = ["it'"'"'s \"ok\": 100%", "a;b,c [x] <y> & *em*"]
  | .beats[2].text = ["$(touch PWN) `id`", "pts eif:1:d %pts"]
  | .beats[3].text = ["São João — ação", "Ünïcödé ñ 🌊"]'
must_ok "hostile text passes the lint" lint evil
must_ok "approve" approve evil
must_ok "shotlist" shotlist evil
for b in b02 b03 b04; do must_ok "still $b with hostile text" still evil $b; done
[ ! -e "$T/cwd/PWN" ] && [ ! -e "$T/PWN" ] && ok "no command ran" || bad "a command in the text ran"
ass=$(proj evil)/build/scenes/b03.ass
# The words of a line are separate runs with their own tags, so each word is looked for on its own.
if grep -qF '$(touch' "$ass" && grep -qF 'PWN)' "$ass" && grep -qF '`id`' "$ass" && grep -qF '%pts' "$ass" && grep -qF 'eif:1:d' "$ass"; then ok "the text is in the captions as it is"; else bad "the captions changed the text"; fi
# every line of the script is a header, a style, an event or empty
if grep -vE '^(Dialogue: [0-9]+,[0-9:.]+,[0-9:.]+,[A-Za-z]+,,0,0,0,,|\[|Format:|Style:|ScriptType:|PlayRes|WrapStyle:|ScaledBorderAndShadow:|; beat|$)' "$ass" | grep -q .; then bad "the script has a line that is not an event"; else ok "the script has events only"; fi
for bad_text in 'a\\nb' 'a\nb' 'a\tb' 'a{\\fs500}b' '%{pts}' '%{eif:1:d}' 'x\\y'; do
  edit evil ".beats[2].text = [\"$bad_text\"]"
  must_fail "text '$bad_text' is refused" "lint" approve evil
done
edit evil '.beats[2].text = [""]'
must_fail "an empty line is refused" "lint" approve evil
edit evil '.beats[2].text = ["*odd", "x"]'
must_fail "an odd * is refused" "lint" approve evil
edit evil '.beats[2].text = ["WWWWWWWWWWWWWWWWWWWWWWWWWWWW"]'
# The screenplay changed, so the shotlist of the example is stale and the lint says so: that is right.
must_fail "a changed screenplay makes the old shotlist stale" "another version" lint evil
must_ok "approve the 28 letters" approve evil
must_ok "new shotlist for the 28 letters" shotlist evil --force
must_ok "28 letters W: lint" lint evil
if _o=$(r still evil b03 2>&1); then ok "a 28 letter word is fitted in the safe area"; else printf '%s' "$_o" | grep -qF "safe area" && ok "a 28 letter word is refused with a line about the safe area" || bad "a 28 letter word: $_o"; fi
# the palette and the style reach SVG and file names
fresh pal 15
edit pal '.look.palette = {accent: "#fff\"/><script>"}'
must_fail "a palette value with markup is refused" "palette" approve pal
edit pal '.look = {style: "../../etc/passwd"}'
must_fail "a style with a path is refused" "style" approve pal
fresh bid 15
edit bid '.beats[1].id = "b02;touch PWN"'
must_fail "a beat id with a command is refused" "id must be b02" approve bid
fresh slugin 15
edit slugin '.slug = "slugin\n"'
must_fail "a slug with a line break is refused" "slug" approve slugin
fresh lay 15
edit lay '.beats[1].visual.scene = "diagram_reveal" | .beats[1].visual.params = {layers: ["direction/svg/../../x.svg"]}'
must_fail "a layer path outside direction/svg is refused" "layer" approve lay
fresh lay2 15
r approve lay2 >/dev/null 2>&1
r shotlist lay2 >/dev/null 2>&1
jq '.shots[1].params = {layers: ["direction/svg/../../../../etc/passwd"]}' "$(proj lay2)/direction/shotlist.json" >"$T/sl.json" && cp "$T/sl.json" "$(proj lay2)/direction/shotlist.json"
must_fail "a layer path in the shotlist is refused" "layer" still lay2 b02

# ---- the lint -------------------------------------------------------------------------------
section "the lint"
fresh lint31 30
edit lint31 '.beats[-1].t_out = 31'
must_fail "a 31 s screenplay fails" "the format is 30 s" lint lint31
fresh lint4 15
edit lint4 '.beats[0].t_out = 4 | .beats[1].t_in = 4'
must_fail "a hook of 4 s fails" "it must end by 3 s" lint lint4
fresh lintlong 15
edit lintlong '.beats[1].text = ["This line is far too long to read in time", "and so is this other one"]'
must_fail "overlong text fails" "characters" lint lintlong
fresh lintvo 15
edit lintvo '.beats[0].vo = "hello"'
must_fail "a vo field fails" "vo (voice-over)" lint lintvo
fresh lintsil 15
edit lintsil '.music = {preset: "none"} | .beats |= map(.sound.sfx = [])'
must_fail "a reel with no sound fails" "no sound at all" lint lintsil
fresh lintjson 15
printf '[1,2]' >"$(sp lintjson)"
must_fail "a screenplay that is not an object fails" "one JSON object" lint lintjson
printf '{"schema": 3}' >"$(sp lintjson)"
must_fail "a screenplay of the wrong shape fails closed" "ERROR" lint lintjson
printf 'not json' >"$(sp lintjson)"
must_fail "a screenplay that is not JSON fails" "not valid JSON" lint lintjson

# ---- other shells and locales ---------------------------------------------------------------
section "shells and locales"
if [ -n "${REEL_DASH:-}" ]; then
  fresh dsh 15
  if rd lint dsh >/dev/null 2>&1 && rd approve dsh >/dev/null 2>&1 && rd shotlist dsh >/dev/null 2>&1 && rd still dsh b02 >/dev/null 2>&1; then ok "lint, approve, shotlist and still run under dash"; else bad "dash run failed"; fi
else
  printf 'skip dash (REEL_DASH is not set)\n'
fi
fresh loc 15
TLANG=C
r approve loc >/dev/null 2>&1
r shotlist loc >/dev/null 2>&1
for l in C C.UTF-8 pt_BR.UTF-8; do
  if TLANG=$l r still loc b03 -o "$T/loc-$l.png" >/dev/null 2>&1; then ok "still with LANG=$l"; else bad "still with LANG=$l"; fi
done
cmp -s "$T/loc-C.png" "$T/loc-C.UTF-8.png" && ok "the picture does not depend on the locale" || bad "the picture changes with the locale"
must_fail "still -o needs .png" ".png" still loc b03 -o "$T/x.mp4"

# ---- render, determinism, QA ----------------------------------------------------------------
section "render and QA (the 15 s example)"
fresh film 15
r approve film >/dev/null 2>&1
r shotlist film >/dev/null 2>&1
t0=$(date +%s)
if r render film >"$T/render.log" 2>&1; then ok "render ($(($(date +%s) - t0)) s)"; else bad "render: $(tail -n 3 "$T/render.log")"; fi
REELF=$(outd film)/reel.mp4
must_ok "qa passes on the render" qa film
must_ok "contact-sheet" contact-sheet film
cp "$REELF" "$T/base.mp4"
h1=$(sha "$REELF")
rm -rf "$(proj film)/build"
mkdir "$(proj film)/build"
r render film >/dev/null 2>&1
h2=$(sha "$REELF")
[ "$h1" = "$h2" ] && ok "two renders from a clean build give the same bytes" || bad "two renders differ: $h1 $h2"
must_ok "qa passes on the second render" qa film

# forge <file> [<render hash override>]: the file as out/film/reel.mp4, with a render.json that names it,
# so that QA judges the file and not its provenance.
forge() {
  cp "$1" "$REELF"
  jq -n --arg a "$(sha "$(sp film)")" --arg b "$(sha "$REELF")" '{screenplay_sha256: $a, reel_sha256: $b}' >"$(outd film)/render.json"
}
# qa_fails <what> <text expected in the output>
qa_fails() {
  if _o=$(r qa film 2>&1); then
    bad "QA accepted: $1"
  elif printf '%s' "$_o" | grep -qF -- "$2"; then
    ok "QA fails: $1"
  else
    bad "QA failed, but not with \"$2\" for: $1: $(printf '%s' "$_o" | grep -E 'FAIL|->' | head -n 3)"
  fi
  if [ -f "$(outd film)/qa.json" ] && jq -e '.pass == false' "$(outd film)/qa.json" >/dev/null 2>&1; then ok "  qa.json says pass false"; fi
  if _p=$(r publish film 2>&1); then bad "  publish accepted: $1"; else ok "  publish refuses: $1"; fi
}
FF="ffmpeg -nostdin -hide_banner -loglevel error -y"
forge "$T/base.mp4"
must_ok "QA passes on the forged copy of a good render" qa film

# Re-encoded, so the length is exact and the faststart check does not add a second failure. (-c copy
# of 14.9 s keeps whole packets and gives 14.967 s, inside the 0.05 s tolerance: it is no short file.)
$FF -i "$T/base.mp4" -t 14.9 -preset ultrafast -movflags +faststart "$T/short.mp4"; forge "$T/short.mp4"
qa_fails "a 14.9 s video" "FAIL  duration"
# 449 frames and 14.95 s of sound: inside the duration tolerance, one frame short: only "frames" sees it.
$FF -i "$T/base.mp4" -frames:v 449 -t 14.95 -preset ultrafast -movflags +faststart "$T/short2.mp4"; forge "$T/short2.mp4"
qa_fails "a 14.95 s video (449 frames)" "FAIL  frames"
$FF -i "$T/base.mp4" -f lavfi -i anullsrc=r=48000:cl=stereo -map 0:v -map 1:a -t 15 -c:v copy -c:a aac "$T/silent.mp4"; forge "$T/silent.mp4"
qa_fails "a silent track" "FAIL  loudness"
$FF -i "$T/base.mp4" -map 0:v -map 0:a -c:v copy -af volume=20dB -c:a aac -b:a 128k -movflags +faststart "$T/clip.mp4"; forge "$T/clip.mp4"
qa_fails "audio that clips" "FAIL  true peak"
$FF -i "$T/base.mp4" -an -c:v copy -movflags +faststart "$T/noaudio.mp4"; forge "$T/noaudio.mp4"
qa_fails "a video with no audio stream" "FAIL  streams"
$FF -i "$T/base.mp4" -vf scale=720:1280 -preset ultrafast -c:a copy -movflags +faststart "$T/small.mp4"; forge "$T/small.mp4"
qa_fails "a 720x1280 video" "FAIL  size"
$FF -i "$T/base.mp4" -r 25 -preset ultrafast -c:a copy -movflags +faststart "$T/fps25.mp4"; forge "$T/fps25.mp4"
qa_fails "a 25 fps video" "FAIL  frame rate"
$FF -i "$T/base.mp4" -c copy "$T/slow.mp4"; forge "$T/slow.mp4"
qa_fails "a video with its moov atom at the end" "FAIL  faststart"
$FF -i "$T/base.mp4" -vf "drawbox=x=100:y=1700:w=800:h=110:color=white:t=fill" -preset ultrafast -c:a copy -movflags +faststart "$T/unsafe.mp4"; forge "$T/unsafe.mp4"
qa_fails "text drawn in the unsafe zone" "leaves the safe area"
$FF -i "$T/base.mp4" -vf "drawbox=x=0:y=0:w=iw:h=ih:color=0x14171f:t=fill:enable='between(t,4.6,5.4)'" -preset ultrafast -c:a copy -movflags +faststart "$T/blank.mp4"; forge "$T/blank.mp4"
qa_fails "a blank frame at a beat" "beat b02: the screenplay has text but the frame"
printf 'this is not a video' >"$T/garbage.mp4"; forge "$T/garbage.mp4"
qa_fails "a file that is not a video" "not a video"
# provenance: a good file that render did not make
forge "$T/base.mp4"
jq '.reel_sha256 = "0000"' "$(outd film)/render.json" >"$T/rj.json" && cp "$T/rj.json" "$(outd film)/render.json"
qa_fails "a file that render did not write" "FAIL  is the file that reel render wrote"
rm -f "$(outd film)/render.json"
qa_fails "a file with no render.json" "FAIL  made from the approved screenplay"

# ---- publish --------------------------------------------------------------------------------
section "publish"
forge "$T/base.mp4"
rm -f "$(outd film)/qa.json"
must_fail "publish with no QA report" "no QA report" publish film
must_ok "qa" qa film
mkdir -p "$OB/other"
printf 'keep' >"$OB/other/keep.txt"
must_ok "publish" publish film
[ -f "$OB/film/reel.mp4" ] && [ -f "$OB/film/qa.json" ] && [ -f "$OB/film/screenplay.json" ] && ok "publish copied reel, qa and screenplay" || bad "publish left files out"
case $(stat -c %A "$OB/film/reel.mp4") in ????r*) ok "the group can read the published file" ;; *) bad "the group cannot read the published file" ;; esac
must_fail "a second publish is refused" "use --replace" publish film
must_ok "publish --replace" publish film --replace
[ "$(cat "$OB/other/keep.txt")" = keep ] && ok "another slug in the outbox is untouched" || bad "another slug changed"
hid=
for h in "$OB"/.[!.]*; do [ -e "$h" ] && hid=1; done
[ -z "$hid" ] && ok "publish left no hidden folder" || bad "publish left a hidden folder in the outbox"
must_fail "publish --bogus is refused" "unknown option" publish film --bogus
mkdir -p "$(proj film)/review"
ln -s /etc/hostname "$(proj film)/review/link.md"
must_fail "a link in review/ is refused" "symbolic link" publish film --replace
rm -f "$(proj film)/review/link.md"
printf 'x' >>"$REELF"
must_fail "publish after the file changed" "not the file that reel render wrote" publish film --replace
forge "$T/base.mp4"
edit film '.logline = "changed after the qa"'
must_fail "publish after the screenplay changed" "changed after its approval" publish film --replace

# ---- 3d shots -------------------------------------------------------------------------------
# The real Blender is never run here. A stub named blender stands in for it: it keeps the arguments
# and the environment it got, writes the PNG sequence the real one would, and ends like the real one
# does on EEVEE (a crash) when the last engine that it was told to use is not CYCLES.
section "3d shots (a stub stands in for blender)"
mkdir -p "$T/stub"
cat >"$T/stub/blender" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >>"$STUB_LOG"
printf 'HOME=%s CONFIG=%s CACHE=%s\n' "$HOME" "${XDG_CONFIG_HOME:-}" "${XDG_CACHE_HOME:-}" >>"$STUB_LOG"
mode='' out='' w='' h='' reel_engine='' engine='' pyfiles=''
while [ $# -gt 0 ]; do
  case $1 in
    --reel-mode) mode=$2 ;;
    --reel-out) out=$2 ;;
    --reel-width) w=$2 ;;
    --reel-height) h=$2 ;;
    --reel-engine) reel_engine=$2 ;;
    --python) pyfiles="$pyfiles $2" ;;
  esac
  shift
done
# The scripts run in the order given: a scene file says its engine, the driver says ours.
for f in $pyfiles; do
  case $f in
    *reel_blender.py) engine=$reel_engine ;;
    *)
      while IFS= read -r line; do
        case $line in
          *"render.engine = '"*)
            e=${line#*"render.engine = '"}
            engine=${e%%"'"*}
            ;;
        esac
      done <"$f"
      ;;
  esac
done
case $mode in
  probe) echo "REEL_FRAMES 1 $STUB_FRAMES" ;;
  render)
    [ -z "${STUB_EXIT:-}" ] || exit "$STUB_EXIT"
    if [ "$engine" != CYCLES ]; then
      echo "EGL error, segmentation fault ($engine)" >&2
      exit 139
    fi
    ffmpeg -nostdin -loglevel error -y -f lavfi -i "color=c=$STUB_COLOR:s=${w}x${h}" -frames:v "$STUB_FRAMES" "${out%####}%04d.png"
    ;;
esac
STUB
chmod +x "$T/stub/blender"
BASEPATH=
for w in $RENV; do case $w in PATH=*) BASEPATH=${w#PATH=} ;; esac; done
SF=24
SC=0x3060a0
SX=
# rb <args>: reel with the stub first in the PATH. SF frames, SC colour, SX exit code of the stub.
rb() {
  (cd "$T/cwd" && env -i $RENV HOME="$T/home" XDG_CACHE_HOME="$T/cache" TMPDIR="$T/tmp" LANG=C \
    REELS_HOME="$RH" REELS_OUTBOX="$OB" PATH="$T/stub${BASEPATH:+:$BASEPATH}" \
    STUB_LOG="$T/stub.log" STUB_FRAMES="$SF" STUB_COLOR="$SC" STUB_EXIT="$SX" $REEL "$@")
}
# rb_ok <what> <args>; rb_fail <what> <text in the message> <args>
rb_ok() {
  _w=$1
  shift
  if _o=$(rb "$@" 2>&1); then ok "$_w"; else bad "$_w: $(printf '%s' "$_o" | tail -n 3)"; fi
}
rb_fail() {
  _w=$1
  _p=$2
  shift 2
  if _o=$(rb "$@" 2>&1); then
    bad "$_w: it succeeded"
  elif printf '%s' "$_o" | grep -qF -- "$_p"; then
    ok "$_w"
  else
    bad "$_w: refused, but not with \"$_p\": $(printf '%s' "$_o" | tail -n 2)"
  fi
}
sl() { printf '%s/direction/shotlist.json' "$(proj "$1")"; }
# edit_sl <slug> <jq filter>
edit_sl() { jq "$2" "$(sl "$1")" >"$T/edit.json" && cp "$T/edit.json" "$(sl "$1")"; }
nframes() {
  _n=0
  for _f in "$1"/*.png; do [ -f "$_f" ] && _n=$((_n + 1)); done
  echo "$_n"
}
# pixel <video> <second>: "r g b" at x=20, y=20 (the captions never reach that corner). The clip is
# yuv420p: the crop filter rounds a 1x1 crop down to the chroma grid (0x0), so convert to rgb24 first.
pixel() {
  ffmpeg -nostdin -loglevel error -ss "$2" -i "$1" -vf format=rgb24,crop=1:1:20:20 -frames:v 1 -f rawvideo -pix_fmt rgb24 - | od -An -tu1 | tr -s ' '
}
# near <"r g b"> <r> <g> <b>: every channel within 10.
near() { printf '%s' "$1" | jq -Re --argjson want "[$2, $3, $4]" 'split(" ") | map(select(length > 0) | tonumber) | [., $want] | transpose | all((.[0] - .[1]) | fabs < 10)' >/dev/null 2>&1; }

fresh td 15
r approve td >/dev/null 2>&1
r shotlist td >/dev/null 2>&1
must_ok "the default shotlist lints with kind flat" lint td
edit_sl td '.shots[2].kind = "3d" | .shots[2].frames = "frames/b03"'
must_ok "a shot of kind 3d with its frames path lints" lint td
edit_sl td '.shots[2].frames = "frames/b02"'
must_fail "a 3d shot with another beat's frames is refused" "frames/b03" lint td
edit_sl td '.shots[2].kind = "4d" | .shots[2].frames = "frames/b03"'
must_fail "a shot kind that is not flat or 3d is refused" "kind is flat or 3d" lint td
edit_sl td '.shots[2].kind = "flat" | .shots[2].frames = "frames/b03"'
must_fail "frames on a flat shot is refused" "kind 3d only" lint td
edit_sl td '.shots[2].kind = "3d" | .shots[2].frames = "frames/b03" | .shots[3].kind = "3d" | .shots[3].frames = "../x"'
must_fail "frames with a path out of frames/ is refused" "frames/b04" lint td
edit_sl td '.shots[3].kind = "flat" | del(.shots[3].frames)'
must_fail "reel blender on a flat shot is refused" "not of kind 3d" blender td b02
must_fail "reel blender with no blender in the PATH" "blender is not in the PATH" blender td b03
rb_fail "reel blender with no scene file" "no scene file" blender td b03
mkdir -p "$(proj td)/blender"
SPIN=${REELS_SHARE:-$(dirname "$0")/..}/examples/blender/spin.py
cp "$SPIN" "$(proj td)/blender/b03.py"
# a scene file that asks for EEVEE, as many scenes do
printf "\nbpy.context.scene.render.engine = 'BLENDER_EEVEE'\n" >>"$(proj td)/blender/b03.py"
: >"$T/stub.log"
SF=241
rb_fail "a scene of 241 frames is refused" "needs 241 frames" blender td b03
SF=300
rb_fail "a scene of 300 frames is refused and the message names the budget" "the budget is 240" blender td b03
[ ! -e "$(proj td)/frames/b03" ] && [ ! -e "$(proj td)/frames/b03.part" ] && ok "a refused scene left no frames" || bad "a refused scene left frames"
[ "$(grep -c -- '--reel-mode render' "$T/stub.log")" -eq 0 ] && ok "a refused scene was never rendered" || bad "a refused scene was rendered"
SF=24
SX=3
rb_fail "a blender that fails ends the command" "blender failed (exit code 3)" blender td b03
[ ! -e "$(proj td)/frames/b03" ] && [ ! -e "$(proj td)/frames/b03.part" ] && ok "a failed blender left no frames" || bad "a failed blender left frames"
SX=
SF=240
rb_ok "a scene of exactly 240 frames is rendered" blender td b03
[ "$(nframes "$(proj td)/frames/b03")" -eq 240 ] && ok "240 PNG files in frames/b03" || bad "frames/b03 holds $(nframes "$(proj td)/frames/b03") files"
SF=24
: >"$T/stub.log"
rb_ok "reel blender renders the 24 frames of the example" blender td b03
[ "$(nframes "$(proj td)/frames/b03")" -eq 24 ] && ok "a new render replaces the old frames" || bad "frames/b03 holds $(nframes "$(proj td)/frames/b03") files"
[ -f "$(proj td)/frames/b03/0001.png" ] && [ ! -e "$(proj td)/frames/b03.part" ] && ok "frames are named %04d.png and no .part is left" || bad "frame names or a .part folder"
# the engine: CYCLES on the CPU, set by the toolkit after the scene file, never EEVEE
grep -q -- '--reel-engine CYCLES --reel-device CPU' "$T/stub.log" && ok "the engine is CYCLES on the CPU" || bad "the toolkit did not ask for CYCLES on the CPU"
[ "$(grep -c EEVEE "$T/stub.log")" -eq 0 ] && ok "EEVEE is never on the command line" || bad "EEVEE is on the command line"
grep -q -- '--python [^ ]*/blender/b03.py --python [^ ]*reel_blender.py' "$T/stub.log" && ok "the scene file loads first, then the toolkit sets the engine" || bad "the toolkit's script does not come after the scene file"
grep -q -- '-b --factory-startup --threads 2 ' "$T/stub.log" && ok "blender runs in the background, on factory settings, with 2 threads" || bad "blender flags"
grep -q -- '--reel-samples 16 --reel-width 1080 --reel-height 1920 --reel-fps 24 ' "$T/stub.log" && ok "samples, size and rate come from profile.json" || bad "samples, size or rate"
case $(grep '^HOME=' "$T/stub.log" | tail -n 1) in
  "HOME=$RH/projects/td/"*" CONFIG=$RH/projects/td/"*" CACHE=$RH/projects/td/"*) ok "HOME, XDG_CONFIG_HOME and XDG_CACHE_HOME are inside the project" ;;
  *) bad "blender ran with a home outside the project: $(grep '^HOME=' "$T/stub.log" | tail -n 1)" ;;
esac
# the picture of the beat is the sequence, and a new sequence makes a new clip
rb_ok "reel scene takes the sequence as the picture" scene td b03
near "$(pixel "$(proj td)/build/scenes/b03.mp4" 1)" 48 96 160 && ok "the clip shows the colour of the frames" || bad "the clip does not show the frames: $(pixel "$(proj td)/build/scenes/b03.mp4" 1)"
out5=$(r scene td b03 2>&1)
case "$out5" in *"up to date"*) ok "an unchanged sequence reuses the clip" ;; *) bad "the clip was rendered again for the same frames" ;; esac
SC=0xa03060
rb_ok "a new sequence" blender td b03
out6=$(r scene td b03 2>&1)
case "$out6" in *"up to date"*) bad "the clip outlived its frames" ;; *) ok "a new sequence makes a new clip" ;; esac
near "$(pixel "$(proj td)/build/scenes/b03.mp4" 1)" 160 48 96 && ok "the new clip shows the new frames" || bad "the new clip shows: $(pixel "$(proj td)/build/scenes/b03.mp4" 1)"
# a 3d beat with no frames yet: a still falls back to the flat picture, a clip is refused
edit_sl td '.shots[3].kind = "3d" | .shots[3].frames = "frames/b04"'
must_fail "a 3d beat with no frames has no clip" "no frames" scene td b04
must_ok "a 3d beat with no frames has a flat still" still td b04 -o "$T/b04-flat.png"
must_fail "render stops at a 3d beat with no frames" "no frames" render td
edit_sl td '.shots[3].kind = "flat" | del(.shots[3].frames)'
ln -s /etc/hostname "$(proj td)/frames/b03/9999.png"
must_fail "a link in the frames is refused" "symbolic link" scene td b03
rm -f "$(proj td)/frames/b03/9999.png"
# the whole reel with one 3d beat
if r render td >"$T/render-td.log" 2>&1; then ok "render with a 3d beat"; else bad "render with a 3d beat: $(tail -n 3 "$T/render-td.log")"; fi
must_ok "qa passes on a reel with a 3d beat" qa td
fresh gate3d 15
r approve gate3d >/dev/null 2>&1
r shotlist gate3d >/dev/null 2>&1
edit_sl gate3d '.shots[2].kind = "3d" | .shots[2].frames = "frames/b03"'
mkdir -p "$(proj gate3d)/blender"
cp "$(proj td)/blender/b03.py" "$(proj gate3d)/blender/b03.py"
edit gate3d '.logline = "Another logline"'
rb_fail "reel blender after the screenplay changed" "changed after its approval" blender gate3d b03

# ---- the crew (specs) -----------------------------------------------------------------------
section "the crew: the seats of the rig and of the specs"
SPECS=${REELS_SPECS:-$(dirname "$0")/../../openrig/specs}
if [ -d "$SPECS/rigs/reels-fabric" ]; then
  RIG=$SPECS/rigs/reels-fabric/rig.yaml
  NIX=${REELS_OPENRIG_NIX:-$SPECS/../../openrig.nix}
  for seat in creative-director producer-editor artist-3d music-director qa; do
    grep -qE "^      - id: $seat\$" "$RIG" && ok "rig.yaml has the seat $seat" || bad "rig.yaml has no seat $seat"
    grep -qF "cwd: /var/lib/openrig/work/reels-fabric/$seat" "$RIG" && ok "the seat $seat has its own cwd" || bad "the seat $seat has no cwd of its own"
    grep -qF "crew-$seat@reels-fabric" "$RIG" && ok "rig.yaml names crew-$seat@reels-fabric" || bad "rig.yaml does not name crew-$seat@reels-fabric"
    grep -qF "agent_ref: \"local:../../agents/reels-$seat\"" "$RIG" && ok "the seat $seat has its agent" || bad "the seat $seat has no agent_ref"
    for f in agent.yaml guidance/role.md startup/context.md; do
      [ -f "$SPECS/agents/reels-$seat/$f" ] && ok "reels-$seat has $f" || bad "reels-$seat has no $f"
    done
    [ "$(wc -l <"$SPECS/agents/reels-$seat/guidance/role.md")" -le 50 ] && ok "the role of $seat is 50 lines or fewer" || bad "the role of $seat is too long"
    if [ -f "$NIX" ]; then
      grep -qF "\"$seat\"" "$NIX" && ok "openrig.nix has a folder for $seat" || bad "openrig.nix has no folder for $seat"
    fi
  done
  [ "$(grep -cE '^      - id: ' "$RIG")" -eq 5 ] && ok "the rig has five seats" || bad "the rig has not five seats"
  [ "$(grep -c 'kind: delegates_to' "$RIG")" -eq 4 ] && ok "the rig has four edges" || bad "the rig has not four edges"
  # no seat of the old rig, in the rig, in the agents or in their norms
  if grep -rnE 'reels-(writer|script-editor|director|maker)|(story|studio)[-.](writer|script-editor|director|maker|qa)' "$SPECS/rigs/reels-fabric" "$SPECS"/agents/reels-* >"$T/oldseats.txt"; then
    bad "a seat of the old rig is still named: $(head -n 2 "$T/oldseats.txt")"
  else
    ok "no seat of the old rig is named in the specs"
  fi
  old=0; for n in writer script-editor director maker; do [ -e "$SPECS/agents/reels-$n" ] && old=1; done
  if [ "$old" = 1 ]; then bad "an agent of the old rig is still there"; else ok "no agent of the old rig is left"; fi
  grep -qiF 'executive producer' "$SPECS/agents/reels-shared/guidance/norms.md" && ok "the norms name the executive producer" || bad "the norms do not name the executive producer"
  if grep -qE '^      - id: executive' "$RIG"; then bad "the executive producer is a seat"; else ok "the executive producer is not a seat"; fi
else
  printf 'skip the crew checks (no specs next to the tests; REELS_SPECS is not set)\n'
fi

# ---- atomicity, recovery and the ffmpeg time limit -----------------------------------------
section "failed ffmpeg, stale lock, time limit"
if [ -n "${REEL_SCRIPT:-}" ] && [ -n "${REELS_SHARE:-}" ] && [ -n "${REELS_TOOLPATH:-}" ]; then
  fresh atom 15
  r approve atom >/dev/null 2>&1
  r shotlist atom >/dev/null 2>&1
  mkdir -p "$T/fake"
  printf '#!/bin/sh\nexit 1\n' >"$T/fake/ffmpeg"
  chmod +x "$T/fake/ffmpeg"
  fk() { (cd "$T/cwd" && env -i PATH="$T/fake:$REELS_TOOLPATH" HOME="$T/home" XDG_CACHE_HOME="$T/cache" TMPDIR="$T/tmp" REELS_SHARE="${FK_SHARE:-$REELS_SHARE}" REELS_FONTS="${REELS_FONTS:-}" REELS_HOME="$RH" REELS_OUTBOX="$OB" /bin/sh "$REEL_SCRIPT" "$@"); }
  mkdir -p "$(outd atom)"
  printf 'old' >"$(outd atom)/reel.mp4"
  printf '{}' >"$(outd atom)/render.json"
  printf '{"pass":true}' >"$(outd atom)/qa.json"
  if _o=$(fk render atom 2>&1); then bad "render with a failing ffmpeg succeeded"; else ok "render with a failing ffmpeg fails: $(printf '%s' "$_o" | tail -n 1)"; fi
  left=$(ls -A "$(outd atom)")
  [ -z "$left" ] && ok "a failed render leaves nothing for qa or publish to accept" || bad "a failed render left files in out/: $left"
  if fk qa atom >/dev/null 2>&1; then bad "qa accepted after a failed render"; else ok "qa refuses after a failed render"; fi
  if fk publish atom >/dev/null 2>&1; then bad "publish accepted after a failed render"; else ok "publish refuses after a failed render"; fi
  # a lock of a dead process is taken over; a lock of a live one is respected
  mkdir -p "$(proj atom)/build/render.lock"
  printf '999999\n' >"$(proj atom)/build/render.lock/pid"
  _o=$(fk render atom 2>&1) || :
  case "$_o" in *"another render"*) bad "a stale lock blocked the render" ;; *) ok "a stale lock is taken over" ;; esac
  sleep 30 &
  lp=$!
  mkdir -p "$(proj atom)/build/render.lock"
  printf '%s\n' "$lp" >"$(proj atom)/build/render.lock/pid"
  _o=$(fk render atom 2>&1) || :
  kill "$lp" 2>/dev/null
  case "$_o" in *"another render"*) ok "a live lock is respected" ;; *) bad "a live lock was ignored" ;; esac
  rm -rf "$(proj atom)/build/render.lock"
  # the time limit: a profile of 2 s and an ffmpeg that sleeps
  mkdir -p "$T/share2"
  cp -R "$REELS_SHARE"/. "$T/share2/"
  chmod -R u+w "$T/share2"
  jq '.limits.ffmpeg_timeout_s = 2' "$REELS_SHARE/profile.json" >"$T/share2/profile.json"
  printf '#!/bin/sh\nexec sleep 60\n' >"$T/fake/ffmpeg"
  s0=$(date +%s)
  _o=$(FK_SHARE="$T/share2" REELS_FONTS="${REELS_FONTS:-$REELS_SHARE/fonts}" fk still atom b01 2>&1) && bad "a hung ffmpeg did not fail" || {
    d=$(($(date +%s) - s0))
    if [ "$d" -le 30 ]; then ok "a hung ffmpeg is stopped after the limit (${d} s)"; else bad "a hung ffmpeg held the run for $d s"; fi
  }
else
  printf 'skip fake-ffmpeg tests (REEL_SCRIPT, REELS_SHARE, REELS_TOOLPATH not set)\n'
fi

printf '\n%s checks, %s failed\n' "$N" "$FAILS"
[ "$FAILS" -eq 0 ]
