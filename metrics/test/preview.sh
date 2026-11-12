#!/bin/sh
# Serve metrics/index.html with one fixture case, to open it in a browser.
#   sh metrics/test/preview.sh [healthy|stale|missing|hostile] [port]
# Needs python3 and jq. The "ts" in a fixture is seconds from now; this script rewrites it every
# 5 seconds, so a healthy host stays live and a stale one stays stale. Stop with Ctrl-C.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
case=${1:-healthy}
port=${2:-8080}
src="$here/fixtures/$case/data"
[ -d "$src" ] || { echo "no such case: $case (healthy, stale, missing, hostile)" >&2; exit 2; }
dir=$(mktemp -d)
mkdir "$dir/data"
cp "$here/../index.html" "$dir/index.html"

refresh() {
  now=$(date +%s)
  for f in "$src"/*.json; do
    jq -c --argjson now "$now" '.ts += $now | if (.domains.ts | type) == "number" then .domains.ts += $now else . end' "$f" > "$dir/data/.tmp"
    mv "$dir/data/.tmp" "$dir/data/$(basename "$f")"
  done
}
refresh
python3 -m http.server "$port" --bind 127.0.0.1 --directory "$dir" >/dev/null 2>&1 &
server=$!
trap 'kill $server 2>/dev/null; rm -rf "$dir"' EXIT INT TERM
echo "case $case: http://127.0.0.1:$port/ (Ctrl-C stops)"
while kill -0 "$server" 2>/dev/null; do
  sleep 5
  refresh
done
