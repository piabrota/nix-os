#!/bin/sh
# Restart the services of a piabrota box by hand. For the OWNER only: an agent never runs it
# (docs/DEPLOY.md, "Restarting the services by hand"). Run it as root on the box:
#   sudo sh scripts/restart-services.sh [GROUP] [--yes] [--dry-run]     (on the box)
#   just remote-restart [what] [user] [target]                         (from your machine, over SSH)
#
# GROUP: all (the default), metrics, web, pgx, room, loco, rig, hermes, or `list`.
#   list       print the plan and change nothing
#   --dry-run  print the plan and the exact commands, and change nothing
#   --yes      do not ask `Proceed? [y/N]`
# A group acts only on the units the box has (`systemctl cat`), so one command serves piabrota
# (KVM 1) and piabrota2 (KVM 4). A group the box lacks gives one `skip` line, not an error.
#
# The group table below is the allow list: no unit that `allowed` does not name is ever
# touched, so sshd, the network, systemd-*, acme-*, nix-daemon, deploy, qemu-guest-agent and
# cloud-init are never restarted. Units go to systemctl as quoted arguments, never through eval.
#
# `all` runs metrics, web, pgx, room, loco, rig, hermes IN THAT ORDER. The unit that holds the
# agent's own session (hermes-agent) is last, so a failure on the way is reported while the
# owner's session still lives.
#
# The prompt reads ${RESTART_TTY:-/dev/tty}, never stdin, so the script can arrive as the
# argument of `sh -c` and still ask (see the recipe `remote-restart`). It prints no environment
# and no journal line (a line can hold a secret): it prints the journalctl command instead.
# Exit 0: every unit is as wanted. 1: a unit is not, or a stray gateway runs. 2: usage, no root
# for a real run, or the prompt was refused or has no terminal.
# For tests only: RESTART_PROC (default /proc), RESTART_TTY, RESTART_TMUX_DIR (default
# /run/openrig), RESTART_WAIT_STEP (2 s) and RESTART_WAIT_TRIES (30: 60 s) of the hermes wait.

set -u

proc=${RESTART_PROC:-/proc}
tty=${RESTART_TTY:-/dev/tty}
tmux_dir=${RESTART_TMUX_DIR:-/run/openrig}
step=${RESTART_WAIT_STEP:-2}
tries=${RESTART_WAIT_TRIES:-30}

usage() {
  printf 'usage: %s [all|list|metrics|web|pgx|room|loco|rig|hermes] [--yes] [--dry-run]\n' "$0" >&2
}

# The allow list. A fixed name, or a loco app: loco-NAME.service, but not the nightly backup
# oneshot loco-NAME-backup.service (loco.nix), which a restart would only run again.
allowed() {
  case $1 in
    metrics-collect.timer | metrics-pull.timer | metrics-collect.service | metrics-pull.service) return 0 ;;
    nginx.service | pgx.service | room-listeners.service | openrig.service) return 0 ;;
    hermes-agent.service | hermes-backend.service) return 0 ;;
    loco-*-backup.service) return 1 ;;
  esac
  printf '%s\n' "$1" | grep -Eq '^loco-[A-Za-z0-9_.-]+\.service$'
}

# The plan: one record per line, `verb|unit|want|consequence`. want is `active`, or `oneshot`
# for a service that runs once and ends (active or inactive is fine, failed is not).
plan=
nplan=0
add() {
  allowed "$2" || { printf 'internal error: %s is not on the allow list\n' "$2" >&2; exit 2; }
  systemctl cat "$2" >/dev/null 2>&1 || return 0
  plan="$plan$1|$2|$3|$4
"
  nplan=$((nplan + 1))
}

live_seats() { # the tmux sessions of OpenRig (one per seat), read-only; rig is not called (it can start a daemon)
  n=0
  for sock in "$tmux_dir"/tmux-*/default; do
    [ -e "$sock" ] || continue
    c=$(tmux -S "$sock" list-sessions 2>/dev/null | wc -l)
    n=$((n + c))
  done
  printf '%s' "$n"
}

group_metrics() {
  # No metrics daemon: two timers fire oneshot services. Restart the timers, then run each oneshot once.
  add restart metrics-collect.timer active "none"
  add restart metrics-pull.timer active "none"
  add start metrics-collect.service oneshot "none: runs once now, the page gets fresh data"
  add start metrics-pull.service oneshot "none: runs once now, the page gets fresh data"
}
# nginx.service has ExecReload = `nginx -t` then `kill -HUP` on NixOS, so a reload tests the
# config first and keeps the old workers when the test fails: no second test here.
group_web() { add reload nginx.service active "no connection dropped; the unit tests the config first"; }
group_pgx() { add restart pgx.service active "drops the open database connections"; }
group_room() { add restart room-listeners.service active "the live listeners count restarts from zero"; }
group_loco() {
  units=$(systemctl list-units 'loco-*.service' --all --no-legend --plain 2>/dev/null | awk '{print $1}')
  for u in $units; do
    allowed "$u" || continue
    add restart "$u" active "the app is down for a few seconds"
  done
}
group_rig() {
  before=$nplan
  add restart openrig.service active "ends every live seat"
  if [ "$nplan" -gt "$before" ]; then
    seats=$(live_seats)
    [ "$seats" -eq 0 ] || seat_note="$seats live tmux session(s) of OpenRig: they end with this restart"
  fi
}
# hermes-agent first, hermes-backend only after the agent is active: a dashboard that starts
# while no gateway runs can start a second gateway of its own (the loop of 2026-11-05).
group_hermes() {
  add restart hermes-agent.service active "ends running agent tasks, a coding run the agent started included"
  add restart hermes-backend.service active "closes the dashboard for a few seconds"
}

seat_note=
group() {
  before=$nplan
  case $1 in
    metrics) group_metrics ;;
    web) group_web ;;
    pgx) group_pgx ;;
    room) group_room ;;
    loco) group_loco ;;
    rig) group_rig ;;
    hermes) group_hermes ;;
  esac
  [ "$nplan" -gt "$before" ] || printf 'skip: %s: not on this box\n' "$1"
}
# The wait after hermes-agent: `active` for at most tries * step seconds.
wait_active() {
  i=0
  while [ "$i" -lt "$tries" ]; do
    [ "$(systemctl is-active "$1" 2>/dev/null)" = active ] && return 0
    sleep "$step"
    i=$((i + 1))
  done
  [ "$(systemctl is-active "$1" 2>/dev/null)" = active ]
}

# Exactly the processes whose argv holds the two words `gateway` and `run` in a row are
# gateways. Read from /proc by argv, not by `pgrep -f`: pgrep would also match this script's
# own `sh -c` text, sudo and ssh, whose command lines hold it. The unit's wrapper has the same
# argv as the gateway, so every match must sit in the cgroup of hermes-agent.service.
gateway_check() {
  found=0
  stray=0
  for d in "$proc"/[0-9]*; do
    [ -r "$d/cmdline" ] || continue
    tr '\0' '\n' <"$d/cmdline" 2>/dev/null | awk 'g && $0 == "run" { f = 1 } { g = ($0 == "gateway") } END { exit !f }' || continue
    found=$((found + 1))
    cg=$(cat "$d/cgroup" 2>/dev/null)
    case $cg in
      */hermes-agent.service | */hermes-agent.service/*) ;;
      *)
        stray=$((stray + 1))
        where=$(printf '%s\n' "$cg" | sed -n '1s/^[0-9]*:[^:]*://p')
        printf 'WARN stray gateway pid %s in %s: run: sudo systemctl restart hermes-backend\n' "${d##*/}" "${where:-unknown cgroup}"
        ;;
    esac
  done
  if [ "$found" -eq 0 ]; then
    printf 'WARN no gateway process found: read: journalctl -u hermes-agent -n 50\n'
    return 1
  fi
  [ "$stray" -eq 0 ] || return 1
  printf 'ok    gateway: %s process(es) (the wrapper and the gateway), all in hermes-agent.service\n' "$found"
}

what=
yes=0
dry=0
for a in "$@"; do
  case $a in
    --yes | -y) yes=1 ;;
    --dry-run | -n) dry=1 ;;
    -h | --help) usage; exit 0 ;;
    all | list | metrics | web | pgx | room | loco | rig | hermes)
      [ -z "$what" ] || { printf 'restart-services: one group only (got %s and %s)\n' "$what" "$a" >&2; usage; exit 2; }
      what=$a
      ;;
    *) printf 'restart-services: unknown group or option: %s\n' "$a" >&2; usage; exit 2 ;;
  esac
done
what=${what:-all}

case $what in
  list | all) groups="metrics web pgx room loco rig hermes" ;;
  *) groups=$what ;;
esac
for g in $groups; do group "$g"; done

printf '\nplan:\n'
IFS='|'
while read -r verb unit want why; do
  [ -n "$verb" ] || continue
  printf '  %-8s %-26s %s\n' "$verb" "$unit" "$why"
done <<EOF
$plan
EOF
unset IFS
[ -z "$seat_note" ] || printf '  note: %s\n' "$seat_note"
[ "$nplan" -gt 0 ] || { printf 'nothing to do on this box\n'; exit 0; }

if [ "$what" = list ]; then exit 0; fi

if [ "$dry" -eq 1 ]; then
  printf '\ncommands (dry run, nothing changed):\n'
  IFS='|'
  while read -r verb unit want why; do
    [ -n "$verb" ] || continue
    printf '  systemctl %s %s\n' "$verb" "$unit"
    [ "$unit" != hermes-agent.service ] || printf '  (wait up to %s s until hermes-agent.service is active, then go on)\n' "$((tries * step))"
  done <<EOF
$plan
EOF
  unset IFS
  exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
  printf 'restart-services: run it as root (sudo)\n' >&2
  exit 2
fi

if [ "$yes" -ne 1 ]; then
  if ! ( exec <"$tty" ) 2>/dev/null; then
    printf 'restart-services: no terminal to ask on and no --yes: refusing\n' >&2
    exit 2
  fi
  printf '\nProceed? [y/N] '
  ans=
  read -r ans <"$tty"
  case $ans in
    y | Y | yes | YES | Yes) ;;
    *) printf 'aborted: nothing restarted\n'; exit 2 ;;
  esac
fi

printf '\n'
touched=
skip_backend=0
IFS='|'
while read -r verb unit want why; do
  [ -n "$verb" ] || continue
  if [ "$unit" = hermes-backend.service ] && [ "$skip_backend" -eq 1 ]; then
    printf 'skip: %s: hermes-agent.service is not active\n' "$unit"
    touched="$touched$unit|$want
"
    continue
  fi
  printf '%s %s\n' "$verb" "$unit"
  systemctl "$verb" "$unit" </dev/null || printf 'systemctl %s %s failed\n' "$verb" "$unit"
  touched="$touched$unit|$want
"
  if [ "$unit" = hermes-agent.service ]; then
    if wait_active "$unit"; then
      printf 'hermes-agent.service is active\n'
    else
      printf 'hermes-agent.service is not active after %s s: hermes-backend.service stays as it is\n' "$((tries * step))"
      skip_backend=1
    fi
  fi
done <<EOF
$plan
EOF
unset IFS

status=0
case $plan in
  *"|hermes-agent.service|"*) [ "$skip_backend" -eq 1 ] || gateway_check || status=1 ;;
esac

printf '\n%-28s %-10s %-9s %s\n' unit active NRestarts ActiveEnterTimestamp
bad=
IFS='|'
while read -r unit want; do
  [ -n "$unit" ] || continue
  state=$(systemctl is-active "$unit" 2>/dev/null)
  nr=$(systemctl show -p NRestarts --value "$unit" 2>/dev/null)
  ts=$(systemctl show -p ActiveEnterTimestamp --value "$unit" 2>/dev/null)
  printf '%-28s %-10s %-9s %s\n' "$unit" "${state:-unknown}" "${nr:--}" "${ts:--}"
  case $want:$state in
    active:active | oneshot:active | oneshot:inactive) ;;
    *) bad="$bad $unit" ;;
  esac
done <<EOF
$touched
EOF
unset IFS

if [ -n "$bad" ]; then
  for u in $bad; do
    printf 'FAIL %s is not as wanted: read: journalctl -u %s -n 50\n' "$u" "$u"
  done
  status=1
fi
[ "$status" -eq 0 ] && printf '\nrestart-services: every unit is as wanted\n'
exit "$status"
