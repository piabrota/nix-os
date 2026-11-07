#!/bin/sh
# Tests of kvm4-health.sh with a stub journalctl and systemctl: the journal line and the exit status.
# Needs no Nix, no systemd and no hermes: `sh hermes/skills/kvm4-health/scripts/kvm4-health.test.sh`.
# KH_SCRIPT names another copy of the script to run (to prove a test red on an old one).
# The other thresholds are set so that this machine's own memory, load and disk cannot warn: the
# exit status then belongs to the journal line alone.
set -u
here=$(cd "$(dirname "$0")" && pwd)
script=${KH_SCRIPT:-$here/kvm4-health.sh}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin" "$work/home"

# journalctl prints what JOURNAL_USAGE says for --disk-usage, as journald does, and no kernel lines.
cat >"$work/bin/journalctl" <<'EOF'
#!/bin/sh
for arg in "$@"; do
  if [ "$arg" = --disk-usage ]; then
    echo "Archived and active journals take up $JOURNAL_USAGE in the file system."
  fi
done
exit 0
EOF
# systemctl: no unit is loaded and none has failed, as on piabrota (KVM 1).
cat >"$work/bin/systemctl" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$work/bin/journalctl" "$work/bin/systemctl"

checks=0 failed=0
check() { # description, got, want
  checks=$((checks + 1))
  if [ "$2" != "$3" ]; then failed=$((failed + 1)); printf 'FAIL %s: got [%s], want [%s]\n' "$1" "$2" "$3"; fi
}

run() { # usage -> sets $report and $status
  report=$(PATH="$work/bin:$PATH" HERMES_HOME="$work/home" JOURNAL_USAGE="$1" \
    KH_MEMAVAIL_WARN=0 KH_MEMAVAIL_CRIT=0 KH_SWAP_WARN=101 KH_PSI_MEM_WARN=100000 KH_PSI_IO_WARN=100000 \
    KH_LOAD_WARN=100000 KH_DISK_WARN=101 KH_DISK_CRIT=101 KH_DISK_GROWTH_GIB=100000 sh "$script" 2>&1)
  status=$?
}
journal_line() { printf '%s\n' "$report" | grep -E '^(ok|WARN|CRIT) +journal' | tr -s ' '; }

# A journal that journald keeps within its own 200 MiB cap is healthy.
run 182.3M
check "182.3M is ok" "$(journal_line)" "ok journal 182.3MiB"
check "182.3M exits 0" "$status" 0
run 200.0M
check "200.0M (the cap) is ok" "$(journal_line)" "ok journal 200.0MiB"
check "200.0M exits 0" "$status" 0
# A journal above the cap is the finding.
run 230.1M
check "230.1M warns" "$(journal_line)" "WARN journal 230.1MiB"
check "230.1M exits 1" "$status" 1
run 1.2G
check "1.2G warns" "$(journal_line)" "WARN journal 1.2G (journald keeps 200 MiB)"
check "1.2G exits 1" "$status" 1

# On a box with none of the Hermes units the units section has no unit line, and no finding.
run 100.0M
check "no unit line without the units" "$(printf '%s\n' "$report" | sed -n '/^== units/,/^== disk/p' | grep -cE '^(ok|WARN|CRIT) +(hermes|pgx|paperclip|postgresql|openrig|user-)')" 0
check "the units section says no failed unit" "$(printf '%s\n' "$report" | grep -c '^ok .*no failed unit')" 1
check "the first line names the host" "$(printf '%s\n' "$report" | sed -n 1p | cut -d' ' -f1-3)" "kvm4-health on $(uname -n)"

printf '%s checks, %s failed\n' "$checks" "$failed"
[ "$failed" = 0 ]
