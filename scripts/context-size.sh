#!/bin/sh
# Checks the size of the files Hermes loads into its context: AGENTS.md, hermes/AGENTS.md and
# hermes/SOUL.md. Read-only. Hermes cuts a file that is too long and keeps only its head and tail,
# so the middle, here the safety rules, never reaches the model.
# Run from the repository root: sh scripts/context-size.sh   (or: just context-size)
# Exit 0 when every file is ok or WARN, 1 when a file is over the limit. CI runs it only after a
# merge to main and does not block (a human adds the workflow).

# Hermes cuts a context file at 32000 characters (agent.prompt_builder logs 'Context file X
# TRUNCATED') and drops the middle. Warn from a margin of 2000.
limit=32000
warn=30000

# wc -m counts characters in a UTF-8 locale. In the C locale it counts bytes: an upper bound, fine.
if locale -a 2>/dev/null | grep -qx 'C.UTF-8\|C.utf8'; then LC_ALL=C.UTF-8; export LC_ALL; fi

status=0
for f in AGENTS.md hermes/AGENTS.md hermes/SOUL.md; do
    [ -f "$f" ] || continue
    n=$(wc -m < "$f" | tr -d ' ')
    if [ "$n" -gt "$limit" ]; then
        level=FAIL; text="$n / $limit: Hermes drops the middle"; status=1
    elif [ "$n" -gt "$warn" ]; then
        level=WARN; text="$n / $limit (margin $((limit - warn)))"
    else
        level=ok; text="$n / $limit"
    fi
    printf '%-5s %s  %s\n' "$level" "$f" "$text"
    if [ -n "$GITHUB_ACTIONS" ]; then
        case "$level" in
            WARN) echo "::warning file=$f::$f $text" ;;
            FAIL) echo "::error file=$f::$f $text" ;;
        esac
    fi
done
exit "$status"
