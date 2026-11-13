#!/usr/bin/env bash
# Each area's latest.json on a marola site, from outside: fails when a board is older than
# MAX_AGE_HOURS (default 12; the box builds every 6 hours) or does not answer.
set -euo pipefail
base=${1:-https://marola.piabrota.art}
max=$(( ${MAX_AGE_HOURS:-12} * 3600 ))
now=$(date -u +%s)
areas=$(curl -fsS "$base/data/areas.json" | jq -r '.areas[].id')
fail=0
for area in $areas; do
  if ! gen=$(curl -fsS "$base/data/$area/latest.json" | jq -er '.generated_at'); then
    echo "| $area | no latest.json | ✗ |"; fail=1; continue
  fi
  age=$(( now - $(date -u -d "$gen" +%s) ))
  if [ "$age" -gt "$max" ]; then mark="✗ older than $(( max / 3600 )) h"; fail=1; else mark="✓"; fi
  echo "| $area | $gen ($(( age / 3600 )) h ago) | $mark |"
done
if [ "$fail" -ne 0 ]; then
  echo "marola boards are stale on $base: journalctl -u marola-boards-build on the box (docs/MAROLA-SITE.md)" >&2
fi
exit "$fail"
