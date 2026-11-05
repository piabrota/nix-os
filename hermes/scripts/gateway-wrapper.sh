#!/bin/sh
# The main process of the unit hermes-agent (hermes.nix). Usage:
#
#   gateway-wrapper.sh COMMAND [ARGUMENT...]
#
# COMMAND is the gateway, for example `hermes gateway run --external-supervisor`.
#
# The wrapper does these things:
#   - It passes SIGUSR1 (a reload) and SIGTERM or SIGINT (a stop) to the gateway.
#   - The gateway exits 75 after a reload. The wrapper starts it again at once and stays up, so
#     the unit never leaves "active" and `RestartSec` is not part of a reload. More than
#     GATEWAY_WRAPPER_MAX_RELOADS exits of 75 in GATEWAY_WRAPPER_RELOAD_WINDOW seconds: exit 1,
#     and systemd then restarts the unit and counts it.
#   - A gateway that exits 0 within GATEWAY_WRAPPER_FAST_EXIT_SECS seconds of its start, while
#     $HERMES_HOME/gateway.pid names another live process, means that another gateway serves the
#     host. The dashboard's Chat tab starts one when it finds none for a few seconds. The wrapper
#     does not exit then (Restart=always would loop and count). It waits for that process to end,
#     and then starts the gateway again.
#   - Any other exit status is the status of the wrapper.

home=${HERMES_HOME:-/var/lib/hermes/.hermes}
fast_exit=${GATEWAY_WRAPPER_FAST_EXIT_SECS:-20}
poll=${GATEWAY_WRAPPER_POLL_SECS:-5}
max_reloads=${GATEWAY_WRAPPER_MAX_RELOADS:-5}
reload_window=${GATEWAY_WRAPPER_RELOAD_WINDOW:-60}

if [ "$#" -eq 0 ]; then
    echo "usage: $0 COMMAND [ARGUMENT...]" >&2
    exit 2
fi

# `child` is the gateway now running, or empty. The traps read it when the signal comes, so they
# always name the current gateway. `sleeper` is the pause of the waiting state.
child=
sleeper=
stopping=0

trap '[ -n "$child" ] && kill -USR1 "$child" 2>/dev/null' USR1
trap 'stopping=1; [ -n "$child" ] && kill -TERM "$child" 2>/dev/null; [ -n "$sleeper" ] && kill "$sleeper" 2>/dev/null' TERM INT

# Print the pid in gateway.pid, or nothing when the file is missing or unreadable.
read_pid() {
    if command -v jq >/dev/null 2>&1; then
        jq -r '.pid // empty' "$home/gateway.pid" 2>/dev/null
    else
        sed -n 's/^[^0-9]*"pid"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$home/gateway.pid" 2>/dev/null
    fi
}

reloads=
while :; do
    [ "$stopping" -eq 1 ] && exit 0
    "$@" &
    child=$!
    [ "$stopping" -eq 1 ] && kill -TERM "$child" 2>/dev/null
    started=$(date +%s)
    # A trapped signal ends `wait` early: wait again until the gateway has exited.
    while :; do
        wait "$child"
        status=$?
        kill -0 "$child" 2>/dev/null || break
    done
    gone=$child
    child=
    ended=$(date +%s)

    if [ "$stopping" -eq 1 ]; then
        [ "$status" -eq 75 ] && exit 0
        exit "$status"
    fi

    if [ "$status" -eq 75 ]; then
        kept=
        for t in $reloads; do
            [ $((ended - t)) -lt "$reload_window" ] && kept="$kept $t"
        done
        reloads="$kept $ended"
        count=0
        for t in $reloads; do count=$((count + 1)); done
        if [ "$count" -gt "$max_reloads" ]; then
            echo "gateway exited 75 $count times in $reload_window s: giving up" >&2
            exit 1
        fi
        echo "gateway exited 75 (reload): starting it again" >&2
        continue
    fi

    if [ "$status" -eq 0 ] && [ $((ended - started)) -lt "$fast_exit" ]; then
        other=$(read_pid)
        case $other in
        '' | *[!0-9]*) exit "$status" ;;
        esac
        if [ "$other" -eq "$gone" ] || [ ! -d "/proc/$other" ]; then
            exit "$status"
        fi
        echo "another gateway (pid $other) serves this host: waiting for it to exit" >&2
        while [ -d "/proc/$other" ] && [ "$stopping" -eq 0 ]; do
            sleep "$poll" &
            sleeper=$!
            wait "$sleeper"
        done
        sleeper=
        [ "$stopping" -eq 1 ] && exit 0
        echo "the other gateway (pid $other) has exited: starting our own" >&2
        continue
    fi

    exit "$status"
done
