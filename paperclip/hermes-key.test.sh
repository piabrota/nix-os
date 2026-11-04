#!/bin/sh
# Tests of hermes-key.sh on a temporary file. Needs openssl in the PATH.
# Run: sh paperclip/hermes-key.test.sh   (or: just paperclip-test)
set -u

here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'chmod -R u+w "$tmp"; rm -rf "$tmp"' EXIT
fail=0
HERMES_ENV_FILE=$tmp/hermes.env
export HERMES_ENV_FILE

check() {
  if [ "$2" = ok ]; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi
}
key_lines() { grep -c '^API_SERVER_KEY=' "$HERMES_ENV_FILE"; }
key_value() { grep '^API_SERVER_KEY=' "$HERMES_ENV_FILE" | cut -d= -f2-; }

# A file with other lines, and no newline at its end: they stay, the key goes on its own line.
printf 'CLAUDE_CODE_OAUTH_TOKEN=abc\nOTHER=1' >"$HERMES_ENV_FILE"
chmod 640 "$HERMES_ENV_FILE"
out=$(sh "$here/hermes-key.sh"); rc=$?
key=$(key_value)
[ "$rc" -eq 0 ] && [ "$(key_lines)" -eq 1 ] && printf %s "$key" | grep -Eq '^[0-9a-f]{64}$' && r=ok || r=bad
check "creates a key of 64 hex characters" "$r"
head -n 1 "$HERMES_ENV_FILE" | grep -qx 'CLAUDE_CODE_OAUTH_TOKEN=abc' &&
  sed -n 2p "$HERMES_ENV_FILE" | grep -qx 'OTHER=1' && r=ok || r=bad
check "keeps the other lines" "$r"
printf %s "$out" | grep -q "$key" && r=bad || r=ok
check "does not print the key without --show" "$r"
printf %s "$out" | grep -q 'systemctl reload hermes-agent' && r=ok || r=bad
check "prints the next steps" "$r"
[ "$(stat -c %a "$HERMES_ENV_FILE")" = 640 ] && r=ok || r=bad
check "keeps the file mode" "$r"

before=$(cksum <"$HERMES_ENV_FILE")
out=$(sh "$here/hermes-key.sh"); rc=$?
[ "$rc" -eq 0 ] && [ "$(cksum <"$HERMES_ENV_FILE")" = "$before" ] &&
  printf %s "$out" | grep -q 'API_SERVER_KEY is already set' && r=ok || r=bad
check "second run changes nothing" "$r"

out=$(sh "$here/hermes-key.sh" --show)
printf '%s\n' "$out" | grep -qx "$key" && r=ok || r=bad
check "--show prints the key" "$r"

: >"$HERMES_ENV_FILE"
out=$(sh "$here/hermes-key.sh" --show)
[ "$(key_lines)" -eq 1 ] && printf '%s\n' "$out" | grep -qx "$(key_value)" && r=ok || r=bad
check "--show prints a new key" "$r"

echo 'A=1' >"$HERMES_ENV_FILE"
chmod 444 "$HERMES_ENV_FILE"
if [ "$(id -u)" -eq 0 ]; then
  echo "skip read-only file (root ignores the mode)"
else
  sh "$here/hermes-key.sh" >/dev/null 2>"$tmp/err"; rc=$?
  [ "$rc" -eq 2 ] && grep -q 'cannot write' "$tmp/err" && [ "$(cat "$HERMES_ENV_FILE")" = A=1 ] && r=ok || r=bad
  check "read-only file gives exit 2" "$r"
fi

HERMES_ENV_FILE=$tmp/missing sh "$here/hermes-key.sh" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && r=ok || r=bad
check "missing file gives exit 2" "$r"

sh "$here/hermes-key.sh" --nope >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && r=ok || r=bad
check "unknown option gives exit 2" "$r"

exit "$fail"
