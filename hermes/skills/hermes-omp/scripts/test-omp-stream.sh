#!/bin/sh
# Test of omp-stream.sh: the recorded run in fixtures/, and three inline cases (a line that is not
# JSON, a tool error, a secret). Needs jq and diff. Run: sh test-omp-stream.sh. Exit 1 on a difference.
dir=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
fail=0

# check <name> <expected file>: stdin goes through omp-stream.sh and must equal the file.
check() {
  if sh "$dir/omp-stream.sh" | diff -u "$2" - >"$tmp/diff"; then
    echo "ok   $1"
  else
    echo "FAIL $1"
    cat "$tmp/diff"
    fail=1
  fi
}

check "recorded run" "$dir/fixtures/sample-run.expected" <"$dir/fixtures/sample-run.jsonl"

printf '%s\n' 'omp stderr: Error: no such model' >"$tmp/want"
printf '%s\n' 'Error: no such model' | check "line that is not JSON" "$tmp/want"

printf '%s\n' '< bash ERROR (12 ms)' '    boom' >"$tmp/want"
printf '%s\n' '{"type":"tool_execution_end","toolName":"bash","isError":true,"result":{"content":[{"type":"text","text":"boom\n"}],"details":{"wallTimeMs":12.4}}}' |
  check "tool error" "$tmp/want"

printf '%s\n' 'omp says: key [redacted] and [redacted]' >"$tmp/want"
printf '%s\n' '{"type":"message_update","assistantMessageEvent":{"type":"text_end","content":"key sk-ant-oat01-ABC and ghp_abc123"}}' |
  check "secret" "$tmp/want"

exit "$fail"
