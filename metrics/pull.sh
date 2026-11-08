#!/bin/sh
# Fetch another host's metrics file (piabrota, on KVM 1) and keep it as OUT_DIR/<name>.json.
# A failed fetch, a body that is not this host's JSON object, or a body over 64 KB leaves the old
# file, so the page shows the host going stale and then offline. Exit 0 either way: a host that is
# down is a state of the page, not a failed unit.
#   METRICS_PULL_URL   the address of the file (required)
#   METRICS_PULL_NAME  the host's name, as in its "host" key (required)
#   OUT_DIR            where <name>.json goes (default /run/metrics-web)
set -eu
umask 022

url=${METRICS_PULL_URL:?METRICS_PULL_URL is not set}
name=${METRICS_PULL_NAME:?METRICS_PULL_NAME is not set}
case $name in *[!a-z0-9-]* | '') echo "pull: bad METRICS_PULL_NAME" >&2; exit 2 ;; esac
out_dir=${OUT_DIR:-/run/metrics-web}
out="$out_dir/$name.json"
tmp="$out.$$.tmp"
trap 'rm -f "$tmp"' EXIT

# -4: the other host allows this host's IPv4 address only.
if ! curl -4 -sf --max-time 5 --max-filesize 65536 -o "$tmp" "$url"; then
  echo "pull: fetch of $url failed; the old file stays" >&2
  exit 0
fi
# Cheap check, no parser: a JSON object that says it is the host we asked for.
if [ "$(head -c 1 "$tmp")" != "{" ] || ! grep -q "\"host\":\"$name\"" "$tmp"; then
  echo "pull: $url did not return the file of $name; the old file stays" >&2
  exit 0
fi
if cmp -s "$tmp" "$out" 2>/dev/null; then
  exit 0
fi
mv -f "$tmp" "$out"
