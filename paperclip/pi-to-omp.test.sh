#!/usr/bin/env bash
# Tests of pi-to-omp.sh with a fake `omp` that prints its arguments, NUL separated.
# Run: bash paperclip/pi-to-omp.test.sh   (or: just paperclip-test)
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin"
printf '#!%s\nprintf "%%s\\0" "$@"\n' "$BASH" >"$tmp/bin/omp"
chmod +x "$tmp/bin/omp"
export PATH="$tmp/bin:$PATH"

fail=0
got=()
run() {
  got=()
  while IFS= read -r -d '' a; do got+=("$a"); done < <(bash "$here/pi-to-omp.sh" "$@")
}
expect() {
  local name=$1 i ok=1 want
  shift
  want=("$@")
  [ "${#got[@]}" -eq "$#" ] || ok=0
  if [ "$ok" -eq 1 ]; then
    for ((i = 0; i < $#; i++)); do
      [ "${got[i]}" = "${want[i]}" ] || ok=0
    done
  fi
  if [ "$ok" -eq 1 ]; then
    echo "ok   $name"
  else
    echo "FAIL $name"
    printf '  want: %q\n' "$@"
    printf '  got:  %q\n' "${got[@]}"
    fail=1
  fi
}

run --mode json -p --append-system-prompt SYS --provider anthropic --model claude-haiku-4-5 --thinking off 'do it'
expect "provider and model join" --mode json -p --append-system-prompt SYS --model anthropic/claude-haiku-4-5 --thinking off 'do it'

run --model anthropic/claude-sonnet-5-5 'do it'
expect "model alone" --model anthropic/claude-sonnet-5-5 'do it'

run --provider anthropic --model anthropic/claude-sonnet-5-5 'do it'
expect "model with a slash keeps itself" --model anthropic/claude-sonnet-5-5 'do it'

run --model claude-sonnet-5-5 --provider anthropic 'do it'
expect "provider after model" --model anthropic/claude-sonnet-5-5 'do it'

run --tools read,bash,edit,write,grep,find,ls 'do it'
expect "tools drop find and ls" --tools read,bash,edit,write,grep 'do it'

run --tools ls,find 'do it'
expect "tools never empty" --tools read 'do it'

run --tools grep,ls,read,grep 'do it'
expect "tools keep order, no duplicate" --tools grep,read 'do it'

run --session "$tmp/none.jsonl" 'do it'
expect "session becomes no-session" --no-session 'do it'

mkdir -p "$tmp/skills-in/alpha" "$tmp/skills-in/beta" "$tmp/agent"
touch "$tmp/skills-in/not-a-dir"
PI_CODING_AGENT_DIR="$tmp/agent" run --skill "$tmp/skills-in" 'do it'
expect "skill is dropped" 'do it'
if [ "$(readlink "$tmp/agent/skills/alpha")" = "$tmp/skills-in/alpha" ] &&
  [ "$(readlink "$tmp/agent/skills/beta")" = "$tmp/skills-in/beta" ] &&
  [ ! -e "$tmp/agent/skills/not-a-dir" ]; then
  echo "ok   skill folders are linked"
else
  echo "FAIL skill folders are linked"
  fail=1
fi

PI_CODING_AGENT_DIR="$tmp/agent" run --skill "$tmp/agent/skills" 'do it'
if [ ! -e "$tmp/agent/skills/alpha/alpha" ] && [ -L "$tmp/agent/skills/alpha" ]; then
  echo "ok   skill folder that is the target makes no nested link"
else
  echo "FAIL skill folder that is the target makes no nested link"
  fail=1
fi

PI_CODING_AGENT_DIR='' run --skill "$tmp/skills-in" 'do it'
expect "skill without an agent dir" 'do it'

prompt=$'fix it, please\n--tools ls\n--session x  and a "quote" $(touch '"$tmp"'/pwned)'
run --mode json -p --tools read,ls --session s --provider p --model m "$prompt"
expect "prompt stays one last argument" --mode json -p --tools read --model p/m --no-session "$prompt"
[ ! -e "$tmp/pwned" ] || { echo "FAIL prompt was run"; fail=1; }

run -p --model m --tools
expect "prompt that looks like a flag" -p --model m --tools

run --list-models
list=("${got[@]}")
rows=$(bash "$here/pi-to-omp.sh" --list-models | awk -F' {2,}' 'NR == 1 && /provider/ { next } NF >= 2 { print $1 "|" $2 }')
if [ "${#list[@]}" -eq 0 ] && [ "$rows" = $'anthropic|claude-sonnet-5-5\nanthropic|claude-haiku-4-5' ]; then
  echo "ok   list-models parses, omp not called"
else
  echo "FAIL list-models parses, omp not called: $rows"
  fail=1
fi

run --version
expect "--version passes" --version
run -v
expect "-v passes" -v

exit "$fail"
