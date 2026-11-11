#!/bin/sh
# Tests the logic of the openrig-wf-keeper script (openrig.nix) against a fake `rig`.
# Usage: sh scripts/test-wf-keeper.sh /nix/store/...-openrig-wf-keeper/bin/openrig-wf-keeper
# `jq` must be on PATH. The script's own PATH line is removed, so the fake `rig` wins.
set -eu

keeper=${1:?usage: test-wf-keeper.sh <path of the keeper script>}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin" "$tmp/state"
grep -v '^export PATH=' "$keeper" >"$tmp/keeper"
chmod +x "$tmp/keeper"

# The fake `rig`: answers from files in $FAKE, and logs each `up` in $FAKE/calls.
cat >"$tmp/bin/rig" <<'EOF'
#!/bin/sh
case "$*" in
  status) cat "$FAKE/status"; exit 0 ;;
  "ps --json") cat "$FAKE/ps.json" ;;
  "ps --nodes --rig wave-forecaster-dev --json") cat "$FAKE/nodes.json" ;;
  "up wave-forecaster-dev --existing") echo existing >>"$FAKE/calls"; exit "$(cat "$FAKE/existing.rc")" ;;
  "up /etc/openrig/specs/rigs/wave-forecaster-dev/rig.yaml") echo spec >>"$FAKE/calls"; exit "$(cat "$FAKE/spec.rc")" ;;
  *) echo "fake rig: unexpected call: $*" >&2; exit 99 ;;
esac
EOF
chmod +x "$tmp/bin/rig"

fails=0
# case <name> <rig json> <nodes json> <existing rc> <spec rc> <attempts> <exit> <calls> <output pattern>
case_() {
  name=$1 rigs=$2 nodes=$3 erc=$4 src=$5 att=$6 want_exit=$7 want_calls=$8 want_out=$9
  FAKE="$tmp/fake"
  export FAKE STATE_DIRECTORY="$tmp/state"
  rm -rf "$FAKE" "$STATE_DIRECTORY/attempts"
  mkdir "$FAKE"
  : >"$FAKE/calls"
  echo "Daemon running on port 7433" >"$FAKE/status"
  printf '%s' "$rigs" >"$FAKE/ps.json"
  printf '%s' "$nodes" >"$FAKE/nodes.json"
  echo "$erc" >"$FAKE/existing.rc"
  echo "$src" >"$FAKE/spec.rc"
  [ "$att" = - ] || printf '%s' "$att" >"$STATE_DIRECTORY/attempts"
  if [ "$name" = "daemon down" ]; then echo "Daemon not running." >"$FAKE/status"; fi
  rc=0
  PATH="$tmp/bin:$PATH" "$tmp/keeper" >"$tmp/out" 2>&1 || rc=$?
  calls=$(tr '\n' ' ' <"$FAKE/calls")
  if [ "$rc" = "$want_exit" ] && [ "$calls" = "$want_calls" ] && grep -q -- "$want_out" "$tmp/out"; then
    echo "ok   $name"
  else
    echo "FAIL $name: exit $rc (want $want_exit), calls '$calls' (want '$want_calls'), output:"
    sed 's/^/     /' "$tmp/out"
    fails=$((fails + 1))
  fi
}

now=$(date +%s)
old=$((now - 7200))
recent=$((now - 600))
port() { printf '[{"name":"wave-forecaster-dev","status":"%s","attentionCount":%s,"isArchived":false,"runningCount":%s}]' "$1" "$2" "$3"; }
three=$(printf '%s\n%s\n%s\n' "$recent" "$recent" "$recent")
stopped_nodes='[{"logicalId":"port.porter","lifecycleState":"stopped","intentionallyStopped":false},{"logicalId":"port.auditor","lifecycleState":"stopped"}]'

case_ "daemon down"                 '[]'                                   '[]' 0 0 -      0 ""              "daemon not running"
case_ "running"                     "$(port running 0 2)"                  '[]' 0 0 -      0 ""              "runs"
case_ "running, attention"          "$(port running 2 2)"                  '[]' 0 0 -      0 ""              "<4>"
case_ "partial"                     "$(port partial 0 1)"                  '[{"logicalId":"port.auditor","lifecycleState":"stopped"},{"logicalId":"port.porter","lifecycleState":"running"}]' 0 0 - 0 "" "port.auditor=stopped"
case_ "stopped, snapshot"           "$(port stopped 0 0)"                  "$stopped_nodes" 0 1 - 0 "existing "       "restored"
case_ "stopped, existing fails"     "$(port stopped 0 0)"                  "$stopped_nodes" 1 0 - 0 "existing spec "  "started from"
case_ "stopped, both fail"          "$(port stopped 0 0)"                  "$stopped_nodes" 1 1 - 1 "existing spec "  "<3>"
case_ "stopped on purpose"          "$(port stopped 0 0)"                  '[{"logicalId":"a","intentionallyStopped":true},{"logicalId":"b","intentionallyStopped":true}]' 0 0 - 0 "" "on purpose"
case_ "no rig of that name"         '[]'                                   '[]' 1 0 -      0 "spec "          "started from"
case_ "archived rig is ignored"     '[{"name":"wave-forecaster-dev","status":"running","isArchived":true,"runningCount":2}]' '[]' 1 0 - 0 "spec " "started from"
case_ "another rig runs"            '[{"name":"piabrota-dev","status":"running","isArchived":false,"runningCount":2},{"name":"wave-forecaster-dev","status":"stopped","isArchived":false,"runningCount":0}]' "$stopped_nodes" 0 0 - 0 "" "another rig runs: piabrota-dev, skipped"
case_ "3 attempts in the last hour" "$(port stopped 0 0)"                  "$stopped_nodes" 0 0 "$three" 1 "" "<3>"
case_ "old attempts are dropped"    "$(port stopped 0 0)"                  "$stopped_nodes" 0 0 "$(printf '%s\n%s\n%s\n' "$old" "$old" "$old")" 0 "existing " "restored"

# The attempts file keeps the recent lines and adds one; the old ones go.
STATE_DIRECTORY="$tmp/state"
printf '%s\n%s\n' "$old" "$recent" >"$STATE_DIRECTORY/attempts"
FAKE="$tmp/fake"
echo 0 >"$FAKE/existing.rc"
export FAKE STATE_DIRECTORY
PATH="$tmp/bin:$PATH" "$tmp/keeper" >/dev/null 2>&1 || true
lines=$(wc -l <"$STATE_DIRECTORY/attempts")
if [ "$lines" = 2 ] && ! grep -q "^$old\$" "$STATE_DIRECTORY/attempts"; then
  echo "ok   attempts file is trimmed and appended"
else
  echo "FAIL attempts file: $(tr '\n' ' ' <"$STATE_DIRECTORY/attempts")"
  fails=$((fails + 1))
fi

[ "$fails" = 0 ] || { echo "$fails failed"; exit 1; }
echo "all passed"
