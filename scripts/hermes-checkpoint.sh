#!/bin/sh
# Run as root on a host by deploy.yml, before the switch:
#
#   hermes-checkpoint.sh NEW_UNIT_SHA256
#
# NEW_UNIT_SHA256 is the sha256 of hermes-agent.service in the system that is about to be activated.
# When it differs from the unit that runs now, the switch reloads or restarts Hermes. A restart
# (a new package changes ExecStart) stops the gateway with SIGTERM and can cut a turn in flight.
# So this script asks Hermes for its own graceful restart first: SIGUSR1 (`systemctl reload`). The
# gateway takes no new work, lets the turns, cron jobs and subagents in flight finish (at most
# restart_after_turn_timeout, 600 s, hermes.nix), closes state.db, and writes its planned-restart
# marker. hermes/scripts/gateway-wrapper.sh then starts it again, and it tells its home channels
# that it is back online. The script waits for that new gateway, so the switch that follows finds
# no work in flight.
#
# It never fails the deploy: every case that it cannot handle prints a line and exits 0.
# Test seams: HERMES_HOME, HC_UNIT (the unit file), HC_TIMEOUT and HC_POLL (seconds).
set -u

unit=hermes-agent.service
home=${HERMES_HOME:-/var/lib/hermes/.hermes}
unit_file=${HC_UNIT:-/etc/systemd/system/$unit}
timeout=${HC_TIMEOUT:-660}
poll=${HC_POLL:-5}

new=${1:-}
case $new in
'' | *[!0-9a-f]*)
    echo "usage: $0 NEW_UNIT_SHA256" >&2
    exit 2
    ;;
esac

if [ ! -e "$unit_file" ]; then
    echo "no $unit on this host: nothing to prepare"
    exit 0
fi

old=$(sha256sum <"$unit_file" | cut -d' ' -f1)
if [ "$old" = "$new" ]; then
    echo "$unit does not change in this deploy: Hermes stays up"
    exit 0
fi

if ! systemctl is-active --quiet "$unit"; then
    echo "$unit changes, but it is not active: nothing in flight"
    exit 0
fi

# The pid in gateway.pid, or nothing. The same read as gateway-wrapper.sh.
read_pid() {
    if command -v jq >/dev/null 2>&1; then
        jq -r '.pid // empty' "$home/gateway.pid" 2>/dev/null
    else
        sed -n 's/^[^0-9]*"pid"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$home/gateway.pid" 2>/dev/null
    fi
}

before=$(read_pid)
case $before in
'' | *[!0-9]*) before= ;;
esac
if [ -z "$before" ] || [ ! -d "/proc/$before" ]; then
    echo "$unit changes, but no gateway runs: nothing in flight"
    exit 0
fi

echo "$unit changes in this deploy: asking the gateway (pid $before) to finish its work and restart"
if ! systemctl reload "$unit"; then
    echo "::warning::systemctl reload $unit failed; the switch goes on without a checkpoint"
    exit 0
fi

waited=0
while [ "$waited" -lt "$timeout" ]; do
    sleep "$poll"
    waited=$((waited + poll))
    now=$(read_pid)
    case $now in
    '' | *[!0-9]*) continue ;;
    esac
    if [ "$now" -ne "$before" ] && [ -d "/proc/$now" ]; then
        echo "checkpoint done after ${waited} s: the gateway (pid $now) is back, with no work in flight"
        exit 0
    fi
done

echo "::warning::the gateway did not restart within ${timeout} s; the switch goes on and may cut a turn"
exit 0
