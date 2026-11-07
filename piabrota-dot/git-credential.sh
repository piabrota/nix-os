#!/bin/sh
# git credential helper of piabrota-dot: hands out the one-hour token that the unit
# piabrota-dot-token wrote. git calls it with `get`, `store` or `erase`; only `get` answers. The token
# goes from the file to git's pipe, never into a URL, a log line or a command line.
[ "${1:-}" = get ] || exit 0
file=${DOT_TOKEN_FILE:-/run/piabrota-dot/token}
[ -r "$file" ] || exit 0
echo username=x-access-token
printf 'password=%s\n' "$(cat "$file")"
