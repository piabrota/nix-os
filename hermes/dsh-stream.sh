# shellcheck shell=bash
# dsh-stream: the JSON lines of `dsh --profile headless --json` to plain lines,
# as OmpStream does for omp, so Hermes can show a running DSH task in the chat.
# Reads stdin only. A line that is not JSON is a `dsh:` diagnostic and prints as
# `dsh stderr:`. Keys and tokens are redacted.

while IFS= read -r line; do
  [ -n "$line" ] || continue
  if out=$(printf '%s\n' "$line" | jq -r '
    if .type == "session" then "dsh: start in \(.cwd)"
    elif .type == "tool_call" then "> \(.tool): \((.input | tostring) | .[0:200])"
    elif .type == "tool_result" then "< \(.status): \((.result // "") | .[0:1000])"
    elif .type == "text" then "dsh says: \(.text | .[0:1500])"
    elif .type == "final" then "dsh: done (\(.reason.kind // "no reason"))"
    elif .type == "error" then "dsh error: \(.message)"
    else empty end
  ' 2>/dev/null); then
    [ -n "$out" ] && printf '%s\n' "$out"
  else
    printf 'dsh stderr: %s\n' "${line:0:300}"
  fi
done | sed -E \
  -e 's/sk-[A-Za-z0-9_-]+/[redacted]/g' \
  -e 's/gh[pousr]_[A-Za-z0-9]+/[redacted]/g' \
  -e 's/github_pat_[A-Za-z0-9_]+/[redacted]/g'
