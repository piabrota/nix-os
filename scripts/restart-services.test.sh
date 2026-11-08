#!/bin/sh
# Tests of restart-services.sh with stub systemctl, tmux, nginx, rig, id and journalctl and a
# fixture /proc, all offline. It needs no Nix, no systemd and no hermes:
#   sh scripts/restart-services.test.sh      (or: just restart-test)
# RS_SCRIPT names another copy of the script (to prove a test red on a naive one).
# No stub is a real unit: nothing here restarts anything.
set -u
here=$(cd "$(dirname "$0")" && pwd)
script=${RS_SCRIPT:-$here/restart-services.sh}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin" "$work/state"
LOG=$work/calls.log
export LOG

# systemctl: STUB_UNITS are the units that exist; STUB_LIST is what `list-units 'loco-*'` prints;
# STUB_FAIL_UNIT is `failed`; STUB_SLOW=N makes hermes-agent say `activating` N times first.
# Oneshot services are `inactive` after their run, as systemd reports a finished oneshot.
# `cat` prints a secret, as a unit with Environment= could: the script must never show it.
cat >"$work/bin/systemctl" <<'EOF'
#!/bin/sh
echo "systemctl $*" >>"$LOG"
case $1 in
  cat)
    case " $STUB_UNITS " in *" $2 "*) echo "Environment=UNIT_SECRET=hunter2"; exit 0 ;; esac
    exit 1 ;;
  is-active)
    if [ "$2" = "${STUB_FAIL_UNIT:-}" ]; then echo failed; exit 3; fi
    if [ "$2" = hermes-agent.service ] && [ -n "${STUB_SLOW:-}" ]; then
      n=$(cat "$STUB_STATE/n" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" >"$STUB_STATE/n"
      if [ "$n" -le "$STUB_SLOW" ]; then echo activating; exit 3; fi
    fi
    case $2 in metrics-*.service) echo inactive; exit 3 ;; esac
    echo active ;;
  show)
    case $3 in NRestarts) echo 0 ;; ActiveEnterTimestamp) echo "Sat 2026-11-07 10:00:00 UTC" ;; esac ;;
  list-units) printf '%s\n' "$STUB_LIST" ;;
esac
exit 0
EOF
cat >"$work/bin/tmux" <<'EOF'
#!/bin/sh
echo "tmux $*" >>"$LOG"
printf 'seat-a: 1 windows\nseat-b: 1 windows\n'
EOF
cat >"$work/bin/id" <<'EOF'
#!/bin/sh
echo "${STUB_UID:-0}"
EOF
for t in nginx rig journalctl; do
  cat >"$work/bin/$t" <<EOF
#!/bin/sh
echo "$t \$*" >>"\$LOG"
echo "SECRET-JOURNAL-LINE"
EOF
done
cat >"$work/bin/sudo" <<'EOF'
#!/bin/sh
exec "$@"
EOF
chmod +x "$work/bin/"*

# Fixture /proc. ok: the wrapper and the gateway of the unit, and a decoy: an ssh session's
# `sh -c` whose single argument holds the words (not a gateway). stray: a gateway of the
# dashboard's cgroup.
mkproc() { # dir pid cgroup argv...
  mkdir -p "$1/$2"
  printf '%s\n' "$3" >"$1/$2/cgroup"
  d=$1 p=$2
  shift 3
  : >"$d/$p/cmdline"
  for a in "$@"; do printf '%s\0' "$a" >>"$d/$p/cmdline"; done
}
unit_cg='0::/system.slice/hermes-agent.service'
mkproc "$work/proc-ok" 100 "$unit_cg" sh /nix/store/x-hermes-gateway /nix/store/x/bin/hermes gateway run --external-supervisor
mkproc "$work/proc-ok" 101 "$unit_cg" /nix/store/x/bin/python hermes gateway run --external-supervisor
mkproc "$work/proc-ok" 300 '0::/user.slice/session-4.scope' sudo sh -c 'echo gateway run
restart' restart-services hermes
cp -R "$work/proc-ok" "$work/proc-stray"
mkproc "$work/proc-stray" 200 '0::/system.slice/hermes-backend.service' /nix/store/x/bin/hermes gateway run
mkdir "$work/proc-none"

echo y >"$work/tty-y"
echo n >"$work/tty-n"
mkdir -p "$work/run-openrig/tmux-999"
: >"$work/run-openrig/tmux-999/default"

box2="metrics-collect.timer metrics-pull.timer metrics-collect.service metrics-pull.service nginx.service pgx.service room-listeners.service openrig.service hermes-agent.service hermes-backend.service loco-notes.service loco-notes-backup.service sshd.service loco-evil;rm.service systemd-networkd.service acme-www.service"
box1="metrics-collect.timer metrics-collect.service nginx.service sshd.service"
list='loco-notes.service loaded active running Loco app notes
loco-notes-backup.service loaded inactive dead Back up notes
sshd.service loaded active running OpenSSH
loco-evil;rm.service loaded active running evil
systemd-networkd.service loaded active running net'

checks=0 failed=0
check() { # description, got, want
  checks=$((checks + 1))
  if [ "$2" != "$3" ]; then failed=$((failed + 1)); printf 'FAIL %s: got [%s], want [%s]\n' "$1" "$2" "$3"; fi
}

# run ARGS...: sets $out, $status and $changes (the systemctl calls that change a unit).
run() {
  : >"$LOG"
  rm -f "$work/state/n"
  out=$(PATH="$work/bin:$PATH" STUB_UNITS="${UNITS:-$box2}" STUB_LIST="$list" STUB_STATE="$work/state" \
    RESTART_PROC="${PROC:-$work/proc-ok}" RESTART_TTY="${TTY:-$work/tty-y}" \
    RESTART_TMUX_DIR="${TMUXDIR:-$work/none}" RESTART_WAIT_STEP=0 RESTART_WAIT_TRIES=5 \
    STUB_UID="${STUB_UID:-0}" STUB_SLOW="${STUB_SLOW:-}" STUB_FAIL_UNIT="${STUB_FAIL_UNIT:-}" \
    RESTART_SECRET=hunter2 sh "$script" "$@" 2>&1)
  status=$?
  changes=$(grep -E '^systemctl (restart|reload|start) ' "$LOG" | cut -d' ' -f2-)
  unset UNITS PROC TTY TMUXDIR STUB_UID STUB_SLOW STUB_FAIL_UNIT
}
has() { case $out in *"$1"*) echo yes ;; *) echo no ;; esac; }
unset UNITS PROC TTY TMUXDIR

# list and --dry-run change nothing, ask nothing and need no root and no terminal.
UNITS=$box2 TTY=$work/missing STUB_UID=1000 run list
check "list: no change call" "$changes" ""
check "list: exit 0" "$status" 0
check "list prints the plan" "$(has 'restart  hermes-agent.service')" yes
check "list says what hermes-agent costs" "$(has 'ends running agent tasks')" yes
check "list says nginx is a reload" "$(has 'reload   nginx.service')" yes
TTY=$work/missing STUB_UID=1000 run all --dry-run
check "dry run: no change call" "$changes" ""
check "dry run: exit 0" "$status" 0
check "dry run prints the exact command" "$(has 'systemctl restart hermes-agent.service')" yes
check "dry run prints the nginx reload" "$(has 'systemctl reload nginx.service')" yes
check "dry run does not prompt" "$(has 'Proceed?')" no

# hermes: the agent first, the dashboard only after the agent is active.
STUB_SLOW=2 run hermes
check "hermes: both units, agent first" "$changes" "restart hermes-agent.service
restart hermes-backend.service"
polls=$(awk '/^systemctl restart hermes-backend/ { exit } /^systemctl is-active hermes-agent.service/ { n++ } END { print n + 0 }' "$LOG")
check "hermes: polled until active (3 polls) before the dashboard" "$polls" 3
check "hermes: exit 0" "$status" 0
check "hermes: one gateway cgroup ok" "$(has 'ok    gateway: 2 process(es)')" yes
check "hermes: a decoy sh -c is no stray" "$(has 'WARN')" no
check "hermes: prints NRestarts" "$(has 'NRestarts')" yes
PROC=$work/proc-stray run hermes
check "stray gateway: WARN names pid, cgroup and the fix" "$(printf '%s\n' "$out" | grep -c 'WARN stray gateway pid 200 in /system.slice/hermes-backend.service: run: sudo systemctl restart hermes-backend$')" 1
check "stray gateway: exactly one WARN" "$(printf '%s\n' "$out" | grep -c '^WARN')" 1
check "stray gateway: exit 1" "$status" 1
PROC=$work/proc-none run hermes
check "no gateway: WARN" "$(has 'WARN no gateway process found')" yes
STUB_SLOW=999 run hermes
check "agent never active: the dashboard is not touched" "$changes" "restart hermes-agent.service"
check "agent never active: exit 1" "$status" 1

# rig: the live seats are counted from tmux, read-only; rig itself is never called.
TMUXDIR=$work/run-openrig run rig
check "rig: restarts openrig" "$changes" "restart openrig.service"
check "rig: counts the live seats" "$(has '2 live tmux session(s) of OpenRig: they end with this restart')" yes
check "rig: never calls rig" "$(grep -c '^rig ' "$LOG")" 0
run rig
check "rig without seats: no seat note" "$(has 'live tmux')" no

# metrics: both timers restarted, both oneshots started; no daemon.
run metrics
check "metrics" "$changes" "restart metrics-collect.timer
restart metrics-pull.timer
start metrics-collect.service
start metrics-pull.service"
check "metrics: a finished oneshot is ok" "$status" 0

# web: a reload, never a restart, and no second config test.
run web
check "web: reload only" "$changes" "reload nginx.service"
check "web: no nginx call of its own" "$(grep -c '^nginx ' "$LOG")" 0
run pgx
check "pgx" "$changes" "restart pgx.service"
run room
check "room" "$changes" "restart room-listeners.service"

# all: this order, and no unit outside the table (sshd, systemd-*, acme-*, the evil name, the
# backup oneshot are on the box and in list-units, and must stay untouched).
run all
check "all: order and allow list" "$changes" "restart metrics-collect.timer
restart metrics-pull.timer
start metrics-collect.service
start metrics-pull.service
reload nginx.service
restart pgx.service
restart room-listeners.service
restart loco-notes.service
restart openrig.service
restart hermes-agent.service
restart hermes-backend.service"
check "all: exit 0" "$status" 0
check "all: the table has one row per unit" "$(printf '%s\n' "$out" | grep -cE '^[a-z-]+\.(service|timer) +(active|inactive) +0 ')" 11
run loco
check "loco: the regex, not a glob" "$changes" "restart loco-notes.service"

# A box like piabrota (KVM 1): the groups it lacks are skipped, not an error.
UNITS=$box1 run all
check "KVM 1: only its units" "$changes" "restart metrics-collect.timer
start metrics-collect.service
reload nginx.service"
check "KVM 1: five skip lines" "$(printf '%s\n' "$out" | grep -c '^skip: .*: not on this box$')" 5
check "KVM 1: exit 0" "$status" 0
UNITS=$box1 run hermes
check "KVM 1 hermes: skip line" "$(has 'skip: hermes: not on this box')" yes
check "KVM 1 hermes: no change, exit 0" "$changes:$status" ":0"

# The prompt reads the terminal, not stdin.
TTY=$work/tty-y run web
check "y: proceeds" "$changes" "reload nginx.service"
check "y: the prompt was shown" "$(has 'Proceed? [y/N]')" yes
TTY=$work/tty-n run all
check "n: nothing restarted" "$changes" ""
check "n: exit 2" "$status" 2
TTY=$work/missing run web
check "no terminal and no --yes: refuses" "$changes:$status" ":2"
check "no terminal: says why" "$(has 'no terminal to ask on and no --yes')" yes
TTY=$work/missing run web --yes
check "--yes: no prompt, restarts" "$changes:$(has 'Proceed?')" "reload nginx.service:no"
STUB_UID=1000 run web --yes
check "not root: refuses a real run" "$changes:$status" ":2"

# Failure: a unit that stays failed gives exit 1, names the unit and the command to read the journal.
STUB_FAIL_UNIT=pgx.service run pgx
check "failed unit: exit 1" "$status" 1
check "failed unit: named with the journalctl command" "$(has 'FAIL pgx.service is not as wanted: read: journalctl -u pgx.service -n 50')" yes
check "failed unit: journalctl is not run" "$(grep -c '^journalctl ' "$LOG")" 0

# Usage errors.
run nonsense
check "unknown group: exit 2" "$status" 2
run web pgx
check "two groups: exit 2" "$status" 2
run web --force
check "unknown option: exit 2" "$status" 2
check "usage errors change nothing" "$changes" ""

# No secret and no journal text, whatever happened.
TMUXDIR=$work/run-openrig run all
check "no env value in the output" "$(has hunter2)" no
check "no unit text in the output" "$(has UNIT_SECRET)" no
check "no journal text in the output" "$(has SECRET-JOURNAL)" no
check "no environment dump in the output" "$(has 'PATH=')" no

# The transport of the recipe: the script text rides base64 in the argument of `sh -c`, so stdin
# stays free for the prompt; the quoting must survive a shell that parses the command line.
b64=$(base64 <"$script" | tr -d '\n')
: >"$LOG"
out=$(PATH="$work/bin:$PATH" STUB_UNITS="$box2" STUB_LIST="$list" STUB_STATE="$work/state" RESTART_TTY="$work/tty-y" \
  RESTART_PROC="$work/proc-ok" RESTART_WAIT_STEP=0 sh -c "sudo sh -c \"\$(echo $b64 | base64 -d)\" restart-services web </dev/null" 2>&1)
check "transport: base64 in sh -c, prompt on the tty, not stdin" "$(has 'Proceed? [y/N]')$(grep -c '^systemctl reload nginx.service' "$LOG")" yes1

printf '%s checks, %s failed\n' "$checks" "$failed"
[ "$failed" = 0 ]
