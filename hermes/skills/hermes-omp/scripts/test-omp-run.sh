#!/usr/bin/env bash
# Test of omp-run.sh with a fake omp, in `bash -lic` with no terminal, as Hermes starts a background
# command: a normal run, a stop with --stop, a SIGTERM to the process group (Hermes's own kill), a
# SIGTERM to omp only, and a missing task file. Needs bash, jq and setsid.
# Run: bash test-omp-run.sh. Exit 1 on a failure.
dir=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin" "$tmp/tasks"
export OMP_TASKS="$tmp/tasks" PATH="$tmp/bin:$PATH"
fail=0

cat >"$tmp/bin/omp" <<'EOF'
#!/bin/sh
cat >/dev/null
echo '{"type":"session","cwd":"/work"}'
[ "${FAKE_SLEEP:-0}" = 0 ] || exec sleep "$FAKE_SLEEP"
echo '{"type":"agent_end"}'
EOF
printf '#!/bin/sh\nexec sh %s/omp-stream.sh\n' "$dir" >"$tmp/bin/omp-stream"
printf '#!/bin/sh\nexec sh %s/omp-run.sh "$@"\n' "$dir" >"$tmp/bin/omp-run"
chmod +x "$tmp/bin/omp" "$tmp/bin/omp-stream" "$tmp/bin/omp-run"
echo "task" >"$tmp/tasks/t.md"
echo "step 1 done" >"$tmp/tasks/t.progress"

ok() { echo "ok   $1"; }
bad() {
  echo "FAIL $1"
  sed 's/^/    /' "$tmp/out"
  fail=1
}
# start: omp-run t in the background, as Hermes runs it (bash -lic, no terminal, own session).
start() {
  FAKE_SLEEP=$1 setsid bash -lic "set +m; omp-run t" </dev/null >"$tmp/out" 2>&1 &
  bg=$!
  i=0
  while [ ! -s "$tmp/tasks/t.pid" ] && [ "$i" -lt 50 ]; do
    sleep 0.1
    i=$((i + 1))
  done
  sleep 0.3
}
# expect <name> <code> <text...>: the run ended with <code>, printed each text and no tcsetattr.
expect() {
  name=$1 want=$2
  shift 2
  wait "$bg"
  rc=$?
  for t in "$@"; do grep -qF -- "$t" "$tmp/out" || { bad "$name: no line '$t'" && return; }; done
  if grep -q tcsetattr "$tmp/out"; then bad "$name: tcsetattr"; return; fi
  if [ -e "$tmp/tasks/t.pid" ] || [ -e "$tmp/tasks/.t.fifo" ]; then bad "$name: pid or fifo left"; return; fi
  if [ "$rc" != "$want" ]; then bad "$name: exit $rc, not $want"; return; fi
  ok "$name"
}

start 0
expect "normal run" 0 "omp: start in /work" "omp: done, 0 turns" "step 1 done"

start 30
omp-run --stop t >"$tmp/stop" 2>&1
grep -qF "omp-run: stopped t" "$tmp/stop" || { cp "$tmp/stop" "$tmp/out" && bad "--stop answer"; }
expect "--stop" 0 "omp: start in /work" "stopped on request" "step 1 done"

start 30
kill -TERM -- "-$bg"
expect "SIGTERM to the group" 143 "omp: start in /work" "stopped by SIGTERM, not by omp-run --stop" "step 1 done"

start 30
kill -TERM "$(cat "$tmp/tasks/t.pid")"
expect "SIGTERM to omp" 143 "omp was stopped by signal 15"

rm "$tmp/tasks/t.md"
FAKE_SLEEP=0 setsid bash -lic "set +m; omp-run t" </dev/null >"$tmp/out" 2>&1 &
bg=$!
expect "no task file" 1 "omp-run: no task file"

exit "$fail"
