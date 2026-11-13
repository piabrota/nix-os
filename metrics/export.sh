#!/bin/sh
# Every host file of OUT_DIR as one all.json and as metrics.prom, the Prometheus text format
# (docs/METRICS.md, "For machines"). jq does the work (metrics/export.jq); no network.
# A file that is not a JSON object, is over 64 KiB or whose "host" is not its name is left out.
#   OUT_DIR        where the host files are, and the two files go (default /run/metrics-web)
#   METRICS_STALE  seconds after which a host is not fresh (default 30)
#   EXPORT_JQ      the filter (default: export.jq beside this script)
#   METRICS_NOW    Unix seconds to use as now; the tests set it
set -eu
umask 022
export LC_ALL=C

out_dir=${OUT_DIR:-/run/metrics-web}
stale=${METRICS_STALE:-30}
filter=${EXPORT_JQ:-$(dirname "$0")/export.jq}
now=${METRICS_NOW:-$(date +%s)}
case $stale in '' | *[!0-9]*) echo "export: bad METRICS_STALE" >&2; exit 2 ;; esac
case $now in '' | *[!0-9]*) echo "export: bad METRICS_NOW" >&2; exit 2 ;; esac

all="$out_dir/all.json"
prom="$out_dir/metrics.prom"
tmp_all="$out_dir/.all.json.$$.tmp"
tmp_prom="$out_dir/.metrics.prom.$$.tmp"
trap 'rm -f "$tmp_all" "$tmp_all.prom" "$tmp_prom"' EXIT

set --
for f in "$out_dir"/*.json; do
  [ -f "$f" ] || continue
  name=${f##*/}; name=${name%.json}
  case $name in all | metrics | '' | *[!a-z0-9-]*) continue ;; esac
  [ "${#name}" -le 32 ] || continue
  [ "$(wc -c < "$f")" -le 65536 ] || continue
  jq -e --arg n "$name" 'type == "object" and .host == $n' "$f" > /dev/null 2>&1 || continue
  set -- "$@" "$f"
done

# One run: its first line is all.json, the rest is metrics.prom.
jq -n -r --argjson now "$now" --argjson stale "$stale" -f "$filter" "$@" < /dev/null > "$tmp_prom"
head -n 1 "$tmp_prom" > "$tmp_all"
tail -n +2 "$tmp_prom" > "$tmp_all.prom"
mv -f "$tmp_all.prom" "$tmp_prom"
mv -f "$tmp_all" "$all"
mv -f "$tmp_prom" "$prom"
