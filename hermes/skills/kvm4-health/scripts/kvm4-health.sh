#!/bin/sh
# The health of kvm4 and of the Hermes units: memory, swap, pressure, load, disk, the journal, and
# for each unit its memory now, its peak against its MemoryMax, its tasks and its restarts (NRestarts,
# where a restart loop shows). Read-only on the system: it reads /proc, `systemctl show`, `df`, `du`
# and the journal, and changes nothing.
#
#   kvm4-health.sh            the full report; exit 1 when a line is WARN or CRIT
#   kvm4-health.sh --alert    only the findings, and only when they change or every 6 h; prints
#                             nothing when healthy (a no_agent cron job: empty output is silent)
#   kvm4-health.sh --record   also appends one sample, for growth per day (only the hermes user,
#                             in HERMES_HOME/plugin-data/kvm4-health)
#
# Thresholds are environment variables (KH_*, below). The plan's figures: 4 vCPU, 16 GB RAM,
# 200 GB disk (AGENTS.md, "Resource budget"); the script reads the real ones.

set -u

alert=0
record=0
for arg in "$@"; do
  case "$arg" in
    --alert) alert=1 ;;
    --record) record=1 ;;
    *) echo "usage: kvm4-health.sh [--alert] [--record]" >&2; exit 2 ;;
  esac
done

: "${KH_UNIT_MEM_WARN:=80}"     # % of a unit's MemoryMax in use now
: "${KH_UNIT_PEAK_WARN:=90}"    # % of a unit's MemoryMax reached since it started
: "${KH_UNIT_NOMAX_GIB:=4}"     # GiB in use by a unit that has no MemoryMax
: "${KH_MEMAVAIL_WARN:=15}"     # % of RAM available, under it: WARN
: "${KH_MEMAVAIL_CRIT:=5}"      # under it: CRIT
: "${KH_SWAP_WARN:=50}"         # % of swap (zram) in use
: "${KH_PSI_MEM_WARN:=10}"      # memory pressure, `some` avg60, %
: "${KH_PSI_IO_WARN:=20}"       # I/O pressure, `some` avg60, %
: "${KH_LOAD_WARN:=1.5}"        # 15-minute load per core
: "${KH_DISK_WARN:=80}"         # % of / used
: "${KH_DISK_CRIT:=90}"
: "${KH_DISK_GROWTH_GIB:=5}"    # GiB a day that / grows by
: "${KH_AGENT_GROWTH_GIB:=1}"   # GiB that hermes-agent grew by in 24 h, with no restart
: "${KH_RESTARTS_WARN:=3}"      # restarts of a unit since it started, above it: WARN
: "${KH_RESTARTS_CRIT:=50}"     # above it: CRIT (a restart loop)
: "${KH_AGENT_CPU_WARN:=200}"   # % of one core, hermes-agent's average since the last sample
: "${KH_JOURNAL_MIB:=180}"      # journald keeps at most 200 MiB (tools.nix)
: "${KH_REPEAT_HOURS:=6}"       # --alert repeats the same findings after this many hours

units="hermes-agent hermes-backend pgx"
home=${HERMES_HOME:-/var/lib/hermes/.hermes}
state=$home/plugin-data/kvm4-health
now=$(date +%s)
cores=$(nproc 2>/dev/null || echo 1)
findings=""
keys=""

out() { [ "$alert" -eq 1 ] || printf '%s\n' "$1"; }
flag() { # flag LEVEL KEY TEXT
  findings="$findings$(printf '%-5s %s' "$1" "$3")
"
  keys="$keys $2"
  out "$(printf '%-5s %s' "$1" "$3")"
}
ok() { out "$(printf 'ok    %s' "$1")"; }
section() { out ""; out "== $1"; }
human() { # bytes -> MiB or GiB
  awk -v b="$1" 'BEGIN { if (b >= 1073741824) printf "%.1f GiB", b / 1073741824; else printf "%.0f MiB", b / 1048576 }'
}
pct() { awk -v a="$1" -v b="$2" 'BEGIN { if (b > 0) printf "%.0f", 100 * a / b; else print 0 }'; }
gt() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a > b) }'; }
num() { case "$1" in '' | *[!0-9]*) echo 0 ;; *) echo "$1" ;; esac; }
meminfo() { awk -v k="$1:" '$1 == k { print $2 * 1024 }' /proc/meminfo; }
psi() { # psi memory|io|cpu -> some avg60
  awk '$1 == "some" { sub("avg60=", "", $3); print $3 }' "/proc/pressure/$1" 2>/dev/null
}
prop() { systemctl show "$1" -p "$2" --value 2>/dev/null; }

out "kvm4-health on $(uname -n) at $(date '+%Y-%m-%d %H:%M %Z'), $cores cores"

section "memory"
total=$(meminfo MemTotal)
avail=$(meminfo MemAvailable)
p=$(pct "$avail" "$total")
line="RAM available $(human "$avail") of $(human "$total") ($p %)"
if [ "$p" -lt "$KH_MEMAVAIL_CRIT" ]; then flag CRIT mem-avail "$line"
elif [ "$p" -lt "$KH_MEMAVAIL_WARN" ]; then flag WARN mem-avail "$line"
else ok "$line"; fi
swap_total=$(meminfo SwapTotal)
swap_used=$(($(num "$swap_total") - $(num "$(meminfo SwapFree)")))
if [ "$(num "$swap_total")" -gt 0 ]; then
  p=$(pct "$swap_used" "$swap_total")
  line="swap used $(human "$swap_used") of $(human "$swap_total") ($p %)"
  if [ "$p" -ge "$KH_SWAP_WARN" ]; then flag WARN swap "$line"; else ok "$line"; fi
fi
v=$(psi memory)
if [ -n "$v" ]; then
  line="memory pressure $v % (some, avg60)"
  if gt "$v" "$KH_PSI_MEM_WARN"; then flag WARN psi-mem "$line"; else ok "$line"; fi
fi
if command -v journalctl >/dev/null 2>&1; then
  n=$(journalctl -k --since "-24h" -o cat --no-pager 2>/dev/null | grep -ciE 'out of memory|oom-kill')
  if [ "$(num "$n")" -gt 0 ]; then flag WARN oom "$n OOM kill lines in the kernel log in 24 h"; else ok "no OOM kill in 24 h"; fi
fi

section "cpu"
read -r l1 l5 l15 _ </proc/loadavg
per=$(awk -v l="$l15" -v c="$cores" 'BEGIN { printf "%.2f", l / c }')
line="load $l1 $l5 $l15 (15 min: $per per core)"
if gt "$per" "$KH_LOAD_WARN"; then flag WARN load "$line"; else ok "$line"; fi
for r in cpu io; do
  v=$(psi "$r")
  [ -n "$v" ] || continue
  if [ "$r" = io ] && gt "$v" "$KH_PSI_IO_WARN"; then flag WARN psi-io "I/O pressure $v % (some, avg60)"
  else ok "$r pressure $v % (some, avg60)"; fi
done

section "units"
agent_mem=0
agent_cpu=0
agent_start=0
for u in $units "user-$(id -u hermes 2>/dev/null || echo 0).slice"; do
  [ "$(prop "$u" LoadState)" = loaded ] || continue
  active=$(prop "$u" ActiveState)
  cur=$(num "$(prop "$u" MemoryCurrent)")
  peak=$(num "$(prop "$u" MemoryPeak)")
  max=$(prop "$u" MemoryMax)
  tasks=$(num "$(prop "$u" TasksCurrent)")
  restarts=$(num "$(prop "$u" NRestarts)")
  if [ "$u" = hermes-agent ]; then
    agent_mem=$cur
    agent_cpu=$(num "$(prop "$u" CPUUsageNSec)")
    agent_start=$(num "$(prop "$u" ActiveEnterTimestampMonotonic)")
  fi
  case "$u" in user-*) name="$u (cron workers)" ;; *) name=$u ;; esac
  if [ "$restarts" -gt "$KH_RESTARTS_CRIT" ]; then flag CRIT "restarts-crit-$u" "$u restarted $restarts times since it started"
  elif [ "$restarts" -gt "$KH_RESTARTS_WARN" ]; then flag WARN "restarts-$u" "$u restarted $restarts times since it started"; fi
  if [ "$active" != active ]; then
    case "$u" in user-*) ;; *) flag WARN "down-$u" "$name is $active" ;; esac
    continue
  fi
  case "$max" in
    '' | infinity)
      line="$name: $(human "$cur") now, peak $(human "$peak"), no MemoryMax, $tasks tasks, $restarts restarts"
      if gt "$cur" "$((KH_UNIT_NOMAX_GIB * 1073741824))"; then flag WARN "mem-$u" "$line"; else ok "$line"; fi
      ;;
    *)
      pc=$(pct "$cur" "$max")
      pp=$(pct "$peak" "$max")
      line="$name: $(human "$cur") now ($pc %), peak $(human "$peak") ($pp %) of $(human "$max"), $tasks tasks, $restarts restarts"
      if [ "$pc" -ge "$KH_UNIT_MEM_WARN" ]; then flag WARN "mem-$u" "$line"
      elif [ "$pp" -ge "$KH_UNIT_PEAK_WARN" ]; then flag WARN "peak-$u" "$line (the peak was near the limit)"
      else ok "$line"; fi
      ;;
  esac
done
failed=$(systemctl --failed --plain --no-legend 2>/dev/null | awk '{ print $1 }' | tr '\n' ' ')
if [ -n "$failed" ]; then flag WARN failed "failed units: $failed"; else ok "no failed unit"; fi

section "disk"
# shellcheck disable=SC2046 # three numbers, split on purpose
set -- $(df -P -B1 / | awk 'NR == 2 { print $2, $3, $4 }')
root_size=$1 root_used=$2 root_avail=$3
p=$(pct "$root_used" "$root_size")
line="/ used $(human "$root_used") of $(human "$root_size") ($p %), $(human "$root_avail") free"
if [ "$p" -ge "$KH_DISK_CRIT" ]; then flag CRIT disk "$line"
elif [ "$p" -ge "$KH_DISK_WARN" ]; then flag WARN disk "$line"
else ok "$line"; fi
if command -v journalctl >/dev/null 2>&1; then
  j=$(journalctl --disk-usage 2>/dev/null | grep -oE '[0-9.]+[KMGT]' | head -n 1)
  case "$j" in
    *G | *T) flag WARN journal "journal $j (journald keeps 200 MiB)" ;;
    *M) if gt "${j%M}" "$KH_JOURNAL_MIB"; then flag WARN journal "journal ${j}iB"; else ok "journal ${j}iB"; fi ;;
    ?*) ok "journal $j" ;;
  esac
fi
if [ "$alert" -eq 0 ] && [ -r "$home" ]; then
  for d in state.db sessions logs plugin-data cache skills; do
    [ -e "$home/$d" ] || continue
    k=$(du -sxk "$home/$d" 2>/dev/null | awk '{ print $1 }')
    out "      $(printf '%-16s' "$d") $(human "$(($(num "$k") * 1024))")"
  done
  for d in /var/lib/hermes/workspace /var/lib/pgx; do
    [ -r "$d" ] || continue
    k=$(du -sxk "$d" 2>/dev/null | awk '{ print $1 }')
    out "      $(printf '%-16s' "${d##*/}") $(human "$(($(num "$k") * 1024))")"
  done
fi

# Growth: against the oldest sample of the last 24 h (one sample every 30 min from the cron job).
samples=$state/samples.tsv
if [ -r "$samples" ]; then
  section "growth"
  # shellcheck disable=SC2046 # the fields of one sample
  set -- $(awk -v t="$((now - 86400))" -F '\t' '$1 >= t { print; exit }' "$samples")
  if [ $# -ge 5 ] && [ $((now - $1)) -ge 21600 ]; then
    age=$((now - $1))
    rate=$(awk -v a="$root_used" -v b="$4" -v s="$age" 'BEGIN { printf "%.2f", (a - b) * 86400 / s / 1073741824 }')
    line="/ grows $rate GiB a day (over $((age / 3600)) h)"
    if gt "$rate" "$KH_DISK_GROWTH_GIB"; then flag WARN disk-growth "$line"; else ok "$line"; fi
    if [ "$2" = "$agent_start" ] && [ "$agent_start" != 0 ]; then
      grew=$((agent_mem - $3))
      line="hermes-agent grew $(human "$grew") in $((age / 3600)) h with no restart"
      if gt "$grew" "$((KH_AGENT_GROWTH_GIB * 1073741824))"; then flag WARN agent-growth "$line (a leak, or a cache that does not shrink)"
      else ok "$line"; fi
    fi
  else
    ok "less than 6 h of samples: no rate yet"
  fi
  # shellcheck disable=SC2046
  set -- $(tail -n 1 "$samples")
  if [ $# -ge 5 ] && [ "$agent_start" != 0 ] && [ "$2" = "$agent_start" ] && [ $((now - $1)) -gt 0 ]; then
    c=$(awk -v a="$agent_cpu" -v b="$5" -v s="$((now - $1))" 'BEGIN { printf "%.0f", (a - b) / 1e9 / s * 100 }')
    line="hermes-agent used $c % of one core since the last sample"
    if [ "$c" -ge "$KH_AGENT_CPU_WARN" ]; then flag WARN agent-cpu "$line"; else ok "$line"; fi
  fi
fi

if [ "$record" -eq 1 ] && mkdir -p "$state" 2>/dev/null && [ -w "$state" ]; then
  printf '%s\t%s\t%s\t%s\t%s\n' "$now" "$agent_start" "$agent_mem" "$root_used" "$agent_cpu" >>"$samples"
  # Two weeks at one sample every 30 min.
  tail -n 700 "$samples" >"$samples.new" && mv "$samples.new" "$samples"
fi

if [ "$alert" -eq 0 ]; then
  if [ -z "$findings" ]; then printf '\nkvm4-health: healthy\n'; exit 0; fi
  printf '\nkvm4-health: %s finding(s)\n' "$(printf '%s' "$findings" | grep -c .)"
  exit 1
fi

# --alert: speak when the set of findings changes, again after KH_REPEAT_HOURS, and once on recovery.
last=$state/last-alert
sig=$(printf '%s\n' "$keys" | tr ' ' '\n' | sort -u | tr '\n' ' ')
prev_sig=""
prev_t=0
if [ -r "$last" ]; then
  prev_t=$(num "$(head -n 1 "$last")")
  prev_sig=$(sed -n 2p "$last")
fi
remember() { [ -w "$state" ] && printf '%s\n%s\n' "$now" "$1" >"$last"; }
if [ -z "$findings" ]; then
  if [ -n "$(printf '%s' "$prev_sig" | tr -d ' ')" ]; then
    printf 'kvm4 is healthy again (%s).\n' "$(uname -n)"
    remember ""
  fi
  exit 0
fi
if [ "$sig" = "$prev_sig" ] && [ $((now - prev_t)) -lt $((KH_REPEAT_HOURS * 3600)) ]; then exit 0; fi
printf 'kvm4-health: %s finding(s) on %s\n%s' "$(printf '%s' "$findings" | grep -c .)" "$(uname -n)" "$findings"
printf 'Ask for /kvm4-health for the full report.\n'
remember "$sig"
exit 0
