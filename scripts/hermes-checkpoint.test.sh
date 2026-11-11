#!/bin/sh
# Tests of hermes-checkpoint.sh with a stub systemctl and a fixture gateway.pid, all offline. It
# needs no Nix, no systemd and no hermes:
#   sh scripts/hermes-checkpoint.test.sh      (or: just hermes-checkpoint-test)
# A live pid is this shell's own ($$) or a `sleep` started here; nothing is signalled.
set -u
here=$(cd "$(dirname "$0")" && pwd)
script=${HC_SCRIPT:-$here/hermes-checkpoint.sh}
work=$(mktemp -d)
sleeper=
trap '[ -n "$sleeper" ] && kill "$sleeper" 2>/dev/null; rm -rf "$work"' EXIT
mkdir "$work/bin" "$work/home"
LOG=$work/calls.log
export LOG

# systemctl: STUB_ACTIVE=0 makes is-active fail; STUB_RELOAD_FAIL=1 makes reload fail; a reload
# writes STUB_NEW_PID into gateway.pid, as the restarted gateway does.
cat >"$work/bin/systemctl" <<'EOF'
#!/bin/sh
echo "systemctl $*" >>"$LOG"
case $1 in
  is-active) [ "${STUB_ACTIVE:-1}" = 1 ]; exit ;;
  reload)
    [ "${STUB_RELOAD_FAIL:-0}" = 1 ] && exit 1
    [ -n "${STUB_NEW_PID:-}" ] && printf '{"pid": %s, "kind": "hermes-gateway"}\n' "$STUB_NEW_PID" >"$HERMES_HOME/gateway.pid"
    exit 0 ;;
esac
exit 0
EOF
chmod +x "$work/bin/systemctl"

export PATH="$work/bin:$PATH" HERMES_HOME="$work/home" HC_UNIT="$work/hermes-agent.service" HC_POLL=1 HC_TIMEOUT=3
echo "[Service]" >"$HC_UNIT"
same=$(sha256sum <"$HC_UNIT" | cut -d' ' -f1)
other=0000000000000000000000000000000000000000000000000000000000000000

sleep 60 &
sleeper=$!

fails=0
run() {
    : >"$LOG"
    out=$(sh "$script" "$@" 2>&1)
    status=$?
}
check() {
    # check NAME EXPECTED_STATUS PATTERN_IN_OUTPUT RELOADED(yes|no)
    ok=1
    [ "$status" -eq "$2" ] || ok=0
    case $out in *"$3"*) ;; *) ok=0 ;; esac
    if grep -q '^systemctl reload' "$LOG"; then r=yes; else r=no; fi
    [ "$r" = "$4" ] || ok=0
    if [ "$ok" -eq 1 ]; then
        echo "ok   $1"
    else
        echo "FAIL $1 (status $status, reload $r): $out"
        fails=$((fails + 1))
    fi
}
pidfile() { printf '{"pid": %s, "kind": "hermes-gateway"}\n' "$1" >"$HERMES_HOME/gateway.pid"; }

run
check "no argument is a usage error" 2 usage no

run not-a-hash
check "a bad hash is a usage error" 2 usage no

HC_UNIT=$work/missing run "$other"
check "a host without Hermes is left alone" 0 "no hermes-agent.service" no

pidfile $$
run "$same"
check "an unchanged unit is left alone" 0 "does not change" no

STUB_ACTIVE=0 run "$other"
check "an inactive unit is left alone" 0 "not active" no

rm -f "$HERMES_HOME/gateway.pid"
run "$other"
check "no gateway.pid: nothing in flight" 0 "no gateway runs" no

pidfile 999999999
run "$other"
check "a dead pid: nothing in flight" 0 "no gateway runs" no

pidfile $$
STUB_NEW_PID=$sleeper run "$other"
check "a changed unit is reloaded and waited for" 0 "checkpoint done" yes

pidfile $$
run "$other"
check "a gateway that never comes back times out, exit 0" 0 "did not restart within 3 s" yes

pidfile $$
STUB_RELOAD_FAIL=1 run "$other"
check "a failed reload warns, exit 0" 0 "reload hermes-agent.service failed" yes

if [ "$fails" -ne 0 ]; then
    echo "$fails test(s) failed"
    exit 1
fi
echo "all tests passed"
