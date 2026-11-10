#!/bin/sh
# Check on the box that the Hermes add-ons of the last deploy are live: the unit restarted after
# the deploy, the plugins of hermes.nix are linked and loaded, the hermes-omp, kvm4-health and
# hermes-manim skills are found, and omp, yt-dlp, manim and kvm4-health answer. Read-only. Run it
# as h0ffmann (passwordless sudo), not root: it reads the Hermes home and calls hermes through
# `sudo -n -u hermes`, as h0ffmann is not in the hermes group:
#   sh scripts/hermes-check.sh                       (on the box)
#   ssh h0ffmann@piabrota.art sh -s < scripts/hermes-check.sh   (just remote-hermes-check)
# It never reads /var/lib/hermes-secrets or the .env, and prints no environment. Keep the two
# lists below in step with extraPlugins and ownPlugins in hermes.nix.

community="custom-dangerous-patterns tripwire public-holidays inbox telegram-business
workflow-record github-copilot error-ledger aux-ledger approval-ledger stop-ledger
progress-squash gh-ref wiki-ref memory-rewind hermes-guide hermes-plugin-guard"
own="pirsig-notes pirsig-videos"

home=/var/lib/hermes/.hermes
as_hermes() { sudo -n -u hermes "$@"; }
bin=/etc/profiles/per-user/hermes/bin
fails=0
ok() { printf 'ok    %s\n' "$1"; }
bad() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }
section() { printf '\n== %s\n' "$1"; }

section "unit"
state=$(systemctl is-active hermes-agent)
if [ "$state" = active ]; then ok "hermes-agent is active"; else bad "hermes-agent is $state"; fi
started=$(systemctl show hermes-agent -p ActiveEnterTimestamp --value)
printf '      unit started  %s\n' "$started"
printf '      last switch   %s\n' "$(stat -c %y /nix/var/nix/profiles/system 2>/dev/null)"
printf '      system        %s\n' "$(readlink /run/current-system)"
printf '      memory peak   %s\n' "$(systemctl show hermes-agent -p MemoryPeak --value)"

section "plugins linked by activation ($home/plugins)"
for p in $community $own; do
  if as_hermes test -f "$home/plugins/nix-managed-$p/plugin.yaml"; then ok "$p"; else bad "$p: no nix-managed-$p"; fi
done

section "plugins enabled (hermes plugins list --enabled)"
if command -v hermes >/dev/null 2>&1; then
  list=$(as_hermes hermes plugins list --enabled --plain 2>&1)
  for p in $community $own; do
    if printf '%s\n' "$list" | grep -qw -- "$p"; then ok "$p"; else bad "$p: not in the enabled list"; fi
  done
else
  bad "no hermes CLI on PATH"
fi

section "skills"
if command -v hermes >/dev/null 2>&1; then
  skills=$(as_hermes hermes skills list 2>&1)
  for s in hermes-omp kvm4-health hermes-manim hermes-cron evidence-ledger-research; do
    if printf '%s\n' "$skills" | grep -qw -- "$s"; then ok "$s"; else bad "$s: not in hermes skills list"; fi
  done
fi
if as_hermes test -f "$home/scripts/kvm4-health-alert.sh"; then ok "kvm4-health-alert.sh in $home/scripts"; else bad "no $home/scripts/kvm4-health-alert.sh"; fi
if as_hermes test -d /var/lib/hermes/workspace/omp-tasks; then ok "omp-tasks directory"; else bad "no /var/lib/hermes/workspace/omp-tasks"; fi

section "tools on Hermes's PATH ($bin)"
v=$("$bin/omp" --version 2>&1 | head -n 1)
case "$v" in *18.16.0*) ok "omp: $v" ;; *) bad "omp: ${v:-no output}" ;; esac
v=$("$bin/yt-dlp" --version 2>&1 | head -n 1)
if [ -n "$v" ]; then ok "yt-dlp: $v"; else bad "yt-dlp: no output"; fi
v=$("$bin/manim" --version 2>&1 | head -n 1)
case "$v" in "Manim Community"*) ok "manim: $v" ;; *) bad "manim: ${v:-no output}" ;; esac
# kvm4-health exits 1 on a finding; that is the report, not a failure of this check.
v=$("$bin/kvm4-health" 2>&1 | tail -n 1)
case "$v" in kvm4-health:*) ok "$v" ;; *) bad "kvm4-health: ${v:-no output}" ;; esac

section "plugin warnings and errors since the unit started"
journalctl -u hermes-agent --since "$started" --no-pager -o cat 2>/dev/null |
  grep -iE 'plugin' | grep -iE 'error|fail|warn|traceback|cannot|skipp' |
  grep -v 'integrity hash' | tail -n 20

if [ "$fails" -eq 0 ]; then printf '\nhermes-check: all live\n'; else printf '\nhermes-check: %s failed\n' "$fails"; exit 1; fi
