#!/bin/sh
# omp-run: runs one omp task in the background of Hermes's terminal, and stops one.
#
#   omp-run <name> [omp flags]   runs `omp -p --mode json --no-title [flags] < omp-tasks/<name>.md`
#                                through omp-stream, then prints how the run ended and the
#                                progress file omp-tasks/<name>.progress
#   omp-run --stop <name>        stops that run and waits until it has ended
#
# Hermes starts a background command as `bash -lic`, with no terminal. When a signal kills the last
# command of that shell, bash prints "tcsetattr: Inappropriate ioctl for device" and the task ends
# as a failure with exit 143. omp-run is never killed by a signal: it catches SIGTERM, SIGINT and
# SIGHUP, passes SIGTERM to omp, lets omp-stream print the last lines and exits with a code. A stop
# with --stop ends with 0, so it is not reported as a failure. omp-tasks is OMP_TASKS, by default
# /var/lib/hermes/workspace/omp-tasks. Test: bash test-omp-run.sh.
set -u
tasks=${OMP_TASKS:-/var/lib/hermes/workspace/omp-tasks}

usage() {
  echo "usage: omp-run <name> [omp flags] | omp-run --stop <name>" >&2
  exit 2
}
check_name() {
  case $1 in '' | */* | .* | -*) usage ;; esac
}

[ $# -ge 1 ] || usage

if [ "$1" = --stop ]; then
  [ $# -eq 2 ] || usage
  check_name "$2"
  pid=$(cat "$tasks/$2.pid" 2>/dev/null) || {
    echo "omp-run: no run named $2"
    exit 1
  }
  : >"$tasks/$2.stop"
  if ! kill -TERM "$pid" 2>/dev/null; then
    rm -f "$tasks/$2.pid" "$tasks/$2.stop"
    echo "omp-run: $2 is not running"
    exit 1
  fi
  # The wrapper's timeout sends SIGKILL 30 seconds after SIGTERM: 45 seconds covers it.
  i=0
  while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 45 ]; do
    sleep 1
    i=$((i + 1))
  done
  if kill -0 "$pid" 2>/dev/null; then
    echo "omp-run: $2 still runs 45 s after SIGTERM (pid $pid)"
    exit 1
  fi
  echo "omp-run: stopped $2"
  exit 0
fi

name=$1
shift
check_name "$name"
task="$tasks/$name.md"
pidf="$tasks/$name.pid"
[ -r "$task" ] || {
  echo "omp-run: no task file $task"
  exit 1
}
if old=$(cat "$pidf" 2>/dev/null) && kill -0 "$old" 2>/dev/null; then
  echo "omp-run: $name already runs (pid $old); stop it with: omp-run --stop $name"
  exit 1
fi
rm -f "$tasks/$name.stop"

fifo="$tasks/.$name.fifo"
rm -f "$fifo"
mkfifo "$fifo" || exit 1
# omp-stream ignores the signals, so it reads to the end of omp's output and prints the last lines.
(
  trap '' TERM INT HUP
  exec omp-stream
) <"$fifo" &
spid=$!
omp -p --mode json --no-title "$@" <"$task" >"$fifo" 2>&1 &
opid=$!
echo "$opid" >"$pidf"

signal=
trap 'signal=TERM; kill -TERM "$opid" 2>/dev/null' TERM
trap 'signal=INT; kill -TERM "$opid" 2>/dev/null' INT
trap 'signal=HUP; kill -TERM "$opid" 2>/dev/null' HUP
wait "$opid"
rc=$?
# A signal ends wait before omp ends: wait until omp has ended. The code is set below then.
while [ -n "$signal" ] && kill -0 "$opid" 2>/dev/null; do
  wait "$opid"
done
wait "$spid"
rm -f "$fifo" "$pidf"

if [ -e "$tasks/$name.stop" ]; then
  rm -f "$tasks/$name.stop"
  echo "omp-run: stopped on request (omp-run --stop $name)"
  rc=0
elif [ -n "$signal" ]; then
  echo "omp-run: stopped by SIG$signal, not by omp-run --stop: a restart of the unit, a deploy or a kill of the background process"
  rc=143
elif [ "$rc" -eq 124 ]; then
  echo "omp-run: stopped by the time limit (--max-time, or the wrapper's ceiling)"
elif [ "$rc" -eq 137 ]; then
  echo "omp-run: omp was killed (SIGKILL: out of memory, or 30 s after the time limit)"
elif [ "$rc" -gt 128 ]; then
  echo "omp-run: omp was stopped by signal $((rc - 128))"
elif [ "$rc" -ne 0 ]; then
  echo "omp-run: omp exited with $rc"
fi
if [ -r "$tasks/$name.progress" ]; then
  echo "omp-run: progress file $tasks/$name.progress:"
  cat "$tasks/$name.progress"
fi
exit "$rc"
