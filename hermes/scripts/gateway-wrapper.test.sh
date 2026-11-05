#!/bin/sh
# Tests of gateway-wrapper.sh with a stub gateway. Needs no Nix and no hermes: `sh
# hermes/scripts/gateway-wrapper.test.sh`. It runs for about 50 seconds and prints PASS or FAIL
# for each check. The stub is a shell script. Its plan, in STUB_PLAN, says what each start does:
#   exit:N      exit with status N at once
#   sleep:S:N   sleep S seconds, then exit with status N
#   run         run until a signal: log USR1, and exit 0 on TERM
# The last word of the plan repeats for every later start.

here=$(cd "$(dirname "$0")" && pwd)
wrapper=$here/gateway-wrapper.sh
T=$(mktemp -d)
trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$T"' EXIT

passed=0
failed=0

pass() { passed=$((passed + 1)); echo "PASS $1"; }
fail() { failed=$((failed + 1)); echo "FAIL $1"; }
check() { # check NAME COMMAND...
    name=$1
    shift
    if "$@"; then pass "$name"; else fail "$name"; fi
}

cat >"$T/stub.sh" <<'EOF'
#!/bin/sh
now() { date +%s.%N; }
echo "$(now) start $$" >>"$STUB_LOG"
n=$(grep -c ' start ' "$STUB_LOG")
set -- $STUB_PLAN
[ "$n" -gt "$#" ] && n=$#
eval "step=\${$n}"
case $step in
exit:*)
    echo "$(now) exit $$" >>"$STUB_LOG"
    exit "${step#exit:}"
    ;;
sleep:*)
    rest=${step#sleep:}
    sleep "${rest%%:*}"
    echo "$(now) exit $$" >>"$STUB_LOG"
    exit "${rest#*:}"
    ;;
run)
    sleeper=
    trap 'echo "$(now) usr1 $$" >>"$STUB_LOG"' USR1
    trap 'echo "$(now) term $$" >>"$STUB_LOG"; [ -n "$sleeper" ] && kill "$sleeper"; exit 0' TERM INT
    sleep 1000 &
    sleeper=$!
    while kill -0 "$sleeper" 2>/dev/null; do
        wait "$sleeper"
    done
    ;;
esac
EOF
chmod +x "$T/stub.sh"

# Environment of every case. The limits are short so that the test is short.
export HERMES_HOME="$T/home"
export GATEWAY_WRAPPER_FAST_EXIT_SECS=2
export GATEWAY_WRAPPER_POLL_SECS=1
export STUB_LOG="$T/stub.log"
mkdir -p "$HERMES_HOME"

# new_case PLAN: clean state, set the plan.
new_case() {
    : >"$STUB_LOG"
    : >"$T/err"
    rm -f "$HERMES_HOME/gateway.pid"
    STUB_PLAN=$1
    export STUB_PLAN
}

# start_wrapper: start the wrapper in the background; $wp is its pid. WPATH, if set, is its PATH.
start_wrapper() {
    PATH=${WPATH:-$PATH} /bin/sh "$wrapper" "$T/stub.sh" 2>>"$T/err" &
    wp=$!
}

# wait_for SECONDS COMMAND...: poll the command every 0.1 s.
wait_for() {
    limit=$(($1 * 10))
    shift
    i=0
    while [ "$i" -lt "$limit" ]; do
        "$@" && return 0
        sleep 0.1
        i=$((i + 1))
    done
    return 1
}

starts() { grep -c ' start ' "$STUB_LOG"; }
has_log() { grep -q "$1" "$STUB_LOG"; }
has_err() { grep -q "$1" "$T/err"; }
alive() { kill -0 "$1" 2>/dev/null; }
now() { date +%s.%N; }
starts_is() { [ "$(starts)" -eq "$1" ]; }
starts_ge() { [ "$(starts)" -ge "$1" ]; }
# lt A B: A < B for decimal numbers.
lt() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a < b) }'; }
# Seconds from the first line with the word $1 to the next line with the word $2.
gap() { awk -v a="$1" -v b="$2" '$2 == a && !t { t = $1 } $2 == b && t { print $1 - t; exit }' "$STUB_LOG"; }

# stop_wrapper: send TERM, wait, set $rc.
stop_wrapper() {
    kill -TERM "$wp" 2>/dev/null
    wait "$wp"
    rc=$?
}

# A foreign gateway: a sleeper named in gateway.pid.
start_foreign() {
    sleep 1000 &
    foreign=$!
    printf '{"pid": %s, "kind": "hermes-gateway"}\n' "$foreign" >"$HERMES_HOME/gateway.pid"
}
end_foreign() {
    kill "$foreign" 2>/dev/null
    wait "$foreign" 2>/dev/null
}

echo "== a: exit 75 restarts the gateway at once and the wrapper stays up"
new_case "exit:75 run"
start_wrapper
wait_for 5 starts_ge 2
g=$(gap exit start)
echo "   gap between the exit of the first gateway and the start of the second: $g s"
echo "   first lines of the stub log (epoch seconds):"
sed -n 1,4p "$STUB_LOG" | sed 's/^/   /'
check "a: second start under 1 s after the exit" lt "$g" 1
check "a: the wrapper keeps running" alive "$wp"
check "a: the journal line is logged" has_err 'gateway exited 75 (reload): starting it again'
# The traps must name the second gateway now.
kill -USR1 "$wp"
check "a: SIGUSR1 reaches the restarted gateway" wait_for 3 has_log ' usr1 '
stop_wrapper
check "a: TERM ends the wrapper with 0" test "$rc" -eq 0

echo "== b: 6 exits of 75 within 60 s"
new_case "exit:75"
start_wrapper
wait "$wp"
rc=$?
check "b: the wrapper exits 1" test "$rc" -eq 1
check "b: the gateway ran 6 times" starts_is 6

echo "== c: exit 7"
new_case "exit:7"
start_wrapper
wait "$wp"
rc=$?
check "c: the wrapper exits 7" test "$rc" -eq 7
check "c: the gateway ran once" starts_is 1

echo "== d: exit 0 after the fast-exit limit, no other gateway"
new_case "sleep:3:0"
start_wrapper
wait "$wp"
rc=$?
check "d: the wrapper exits 0" test "$rc" -eq 0
check "d: the gateway ran once" starts_is 1

echo "== d2: fast exit 0, the pid file is missing, stale, or garbage"
for body in none '{"pid": 999999999}' 'not json' '{"pid": "x"}'; do
    new_case "exit:0"
    [ "$body" = none ] || printf '%s\n' "$body" >"$HERMES_HOME/gateway.pid"
    start_wrapper
    wait "$wp"
    rc=$?
    check "d2: pid file '$body': the wrapper exits 0" test "$rc" -eq 0
    check "d2: pid file '$body': no restart" starts_is 1
done

echo "== e: fast exit 0 while another gateway lives (15 s without a restart storm)"
new_case "exit:0 run"
start_foreign
GATEWAY_WRAPPER_POLL_SECS=5
start_wrapper
GATEWAY_WRAPPER_POLL_SECS=1
check "e: the waiting line is logged" wait_for 3 has_err "another gateway (pid $foreign) serves this host: waiting for it to exit"
sleep 15
check "e: the wrapper is alive after 15 s" alive "$wp"
check "e: the gateway started exactly once" starts_is 1
kill "$foreign"
wait "$foreign" 2>/dev/null
t0=$(now)
wait_for 8 starts_is 2
t1=$(now)
echo "   the stub started again $(awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%.1f", b - a }') s after the other gateway ended"
check "e: the gateway starts again within 6 s of the other's exit" lt "$(awk -v a="$t0" -v b="$t1" 'BEGIN { print b - a }')" 6.5
check "e: the takeover is logged" has_err 'has exited: starting our own'
check "e: the wrapper is alive" alive "$wp"
stop_wrapper

echo "== f: TERM while it waits for the other gateway"
new_case "exit:0 run"
start_foreign
start_wrapper
wait_for 3 has_err 'waiting for it to exit'
kill -USR1 "$wp"
sleep 0.5
check "f: USR1 does not end the wait" alive "$wp"
t0=$(now)
stop_wrapper
t1=$(now)
d=$(awk -v a="$t0" -v b="$t1" 'BEGIN { print b - a }')
echo "   the wrapper ended $d s after TERM"
check "f: the wrapper ends within 1 s" lt "$d" 1
check "f: the wrapper exits 0" test "$rc" -eq 0
check "f: the other gateway is still alive" alive "$foreign"
check "f: no second start" starts_is 1
end_foreign

echo "== g: SIGUSR1 reaches the gateway"
new_case "run"
start_wrapper
wait_for 3 starts_ge 1
kill -USR1 "$wp"
check "g: the stub saw USR1" wait_for 3 has_log ' usr1 '
check "g: the wrapper keeps running" alive "$wp"
stop_wrapper

echo "== h: TERM reaches the gateway"
new_case "run"
start_wrapper
wait_for 3 starts_ge 1
stop_wrapper
check "h: the stub saw TERM" has_log ' term '
check "h: the wrapper exits 0" test "$rc" -eq 0

echo "== i: the same as e, with no jq on the PATH (sed reads the pid)"
mkdir "$T/bin"
for tool in sleep date sed grep awk wc; do
    ln -s "$(command -v "$tool")" "$T/bin/$tool"
done
check "i: jq is not on that PATH" test -z "$(PATH=$T/bin command -v jq)"
new_case "exit:0 run"
start_foreign
WPATH=$T/bin
start_wrapper
WPATH=
check "i: the waiting line is logged" wait_for 3 has_err "another gateway (pid $foreign) serves this host"
sleep 2
check "i: the gateway started exactly once" starts_is 1
end_foreign
check "i: the gateway starts again after the other's exit" wait_for 4 starts_is 2
stop_wrapper

echo "$((passed + failed)) checks, $failed failed"
[ "$failed" -eq 0 ]
