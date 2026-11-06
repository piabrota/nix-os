#!/bin/sh
# Checks of metrics/index.html. Static rules always; a real HTTP fetch of the page and of the
# fixtures when python3 and curl exist. Prints "N checks, M failed". `sh metrics/test/page.sh`.
set -u
here=$(cd "$(dirname "$0")" && pwd)
page="$here/../index.html"
checks=0 failed=0
check() { # description, got, want
  checks=$((checks + 1))
  if [ "$2" != "$3" ]; then failed=$((failed + 1)); printf 'FAIL %s: got [%s], want [%s]\n' "$1" "$2" "$3"; fi
}

check "page is under 20 KB" "$([ "$(wc -c < "$page")" -lt 20480 ] && echo yes)" yes
# The page may name http://www.w3.org/2000/svg: it is an XML namespace, not a request.
check "no URL to another host" "$(grep -Eo 'https?://[^"'"'"' )]+' "$page" | grep -vc '^http://www\.w3\.org/2000/svg$')" 0
check "no protocol-relative URL" "$(grep -cE '(src|href)="//' "$page")" 0
check "no innerHTML" "$(grep -c 'innerHTML' "$page")" 0
check "no outerHTML or insertAdjacentHTML" "$(grep -cE 'outerHTML|insertAdjacentHTML' "$page")" 0
check "no eval" "$(grep -cE '\beval\(|new Function' "$page")" 0
check "no document.write" "$(grep -c 'document\.write' "$page")" 0
check "no external script, stylesheet or font" "$(grep -cE '<script[^>]+src=|<link[^>]+href=|@import|@font-face' "$page")" 0
check "no storage" "$(grep -cE 'localStorage|sessionStorage|indexedDB|document\.cookie' "$page")" 0
check "fetches only data/" "$(grep -o 'fetch([^,)]*' "$page" | grep -vc 'fetch("data/"')" 0
check "a policy forbids other requests" "$(grep -c "connect-src 'self'" "$page")" 1

for f in "$here"/fixtures/*/data/*.json; do
  check "fixture is JSON: ${f#"$here"/fixtures/}" "$(jq -e . "$f" >/dev/null 2>&1 && echo yes)" yes
done
check "four fixture cases" "$(find "$here/fixtures" -mindepth 1 -maxdepth 1 -type d | grep -c .)" 4

if command -v python3 >/dev/null 2>&1 && command -v curl >/dev/null 2>&1; then
  dir=$(mktemp -d)
  trap 'kill $server 2>/dev/null; rm -rf "$dir"' EXIT
  mkdir "$dir/data"
  cp "$page" "$dir/index.html"
  now=$(date +%s)
  for f in "$here"/fixtures/healthy/data/*.json; do
    jq -c --argjson now "$now" '.ts += $now' "$f" > "$dir/data/$(basename "$f")"
  done
  port=$(( $$ % 20000 + 20000 ))
  python3 -m http.server "$port" --bind 127.0.0.1 --directory "$dir" >/dev/null 2>&1 &
  server=$!
  n=0
  until curl -sf "http://127.0.0.1:$port/" >/dev/null 2>&1 || [ $n -ge 50 ]; do n=$((n + 1)); sleep 0.1; done
  check "GET / gives the page" "$(curl -s "http://127.0.0.1:$port/" | cmp -s - "$page" && echo same)" same
  check "GET /data/piabrota2.json is fresh JSON" "$(curl -s "http://127.0.0.1:$port/data/piabrota2.json" | jq -r '.ts >= '"$now"' - 10 and .host == "piabrota2"')" true
  check "GET /data/piabrota.json" "$(curl -s "http://127.0.0.1:$port/data/piabrota.json" | jq -r .host)" piabrota
  check "a missing host is a 404" "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port/data/nope.json")" 404
else
  echo "skipped: the HTTP fetch needs python3 and curl"
fi

printf '%s checks, %s failed\n' "$checks" "$failed"
[ "$failed" = 0 ]
