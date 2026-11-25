# shellcheck shell=bash
# dsh-run: one background DeepSeek Harness task, and a way to stop it.
#
#   dsh-run <name> [dsh flags]   runs `dsh --profile headless --json
#                                [flags] - < dsh-tasks/<name>.md` through
#                                dsh-stream, then prints how the run ended and
#                                dsh-tasks/<name>.progress
#   dsh-run --stop <name>        stops that run and waits until it has ended
#
# Hermes starts a background command as `bash -lic`, with no terminal. Like
# omp-run, this script takes the signals, passes SIGTERM to the run's process
# group and exits with a code, so a stop is not a failure and bash prints no
# tcsetattr line. DSH_TASKS is the task folder, by default
# /var/lib/hermes/workspace/dsh-tasks.
#
# The sandbox is DSH's: the wrapper sets DSH_PERMISSION_MODE=workspace-write, so
# writes are confined to the working tree, and the task file carries the same
# prohibitions as hermes/dsh-append-system.md. The 0.2.1 headless profile has no
# --permission-mode or --approval-policy flag; the sandbox is the policy. DSH has
# no omp-style bash deny list; Hermes's deny list sees only this command.

usage="usage: dsh-run <name> [dsh flags] | dsh-run --stop <name>"
tasks="${DSH_TASKS:-/var/lib/hermes/workspace/dsh-tasks}"
name="${1:-}"
[ -n "$name" ] || { echo "$usage" >&2; exit 2; }

case "$name" in
  --stop)
    name="${2:-}"
    [ -n "$name" ] || { echo "$usage" >&2; exit 2; }
    ;;
  -*)
    echo "$usage" >&2
    exit 2
    ;;
esac

[[ "$name" =~ ^[a-z0-9][a-z0-9-]*$ ]] || { echo "dsh-run: bad task name: $name" >&2; exit 2; }
task="$tasks/$name.md"
pidfile="$tasks/$name.pid"
stopfile="$tasks/$name.stop"
progress="$tasks/$name.progress"

read_pid() {
  [ -f "$pidfile" ] || return 1
  head -n 1 "$pidfile" | tr -dc '0-9'
}

is_alive() {
  [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null
}

stop() {
  local pid
  pid="$(read_pid)" || { echo "dsh-run: no run named $name" >&2; exit 1; }
  if ! is_alive "$pid"; then
    rm -f "$pidfile" "$stopfile"
    echo "dsh-run: $name is not running"
    return 1
  fi
  : >"$stopfile"
  kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
  for _ in $(seq 1 45); do
    is_alive "$pid" || break
    sleep 1
  done
  if is_alive "$pid"; then
    echo "dsh-run: $name still runs 45 s after SIGTERM (pid $pid)" >&2
    exit 1
  fi
  rm -f "$pidfile" "$stopfile"
  echo "dsh-run: stopped $name"
}

if [ "${1:-}" = "--stop" ]; then
  stop
  exit 0
fi

if [ ! -r "$task" ]; then
  echo "dsh-run: no task file $task" >&2
  exit 1
fi

if pid="$(read_pid)" && is_alive "$pid"; then
  echo "dsh-run: $name already runs (pid $pid); stop it with: dsh-run --stop $name" >&2
  exit 1
fi

rm -f "$stopfile" "$pidfile"
fifo="$(mktemp -u "$tasks/.dsh-run.XXXXXX.fifo")"
mkfifo "$fifo"

shift
args=(--profile headless --json)

dsh-stream <"$fifo" &
stream_pid=$!
setsid "${DSH_BIN:-dsh}" "${args[@]}" "$@" - <"$task" >"$fifo" 2>&1 &
run_pid=$!
echo "$run_pid" >"$pidfile"

on_signal() {
  : >"$stopfile"
  kill -TERM -- "-$run_pid" 2>/dev/null || kill -TERM "$run_pid" 2>/dev/null || true
}
trap on_signal TERM INT HUP

wait "$run_pid"
status=$?
wait "$stream_pid" || true
trap - TERM INT HUP

rm -f "$pidfile" "$fifo"
if [ -f "$stopfile" ]; then
  rm -f "$stopfile"
  echo "dsh-run: stopped on request"
  exit 0
fi
if [ "$status" -eq 124 ] || [ "$status" -eq 137 ]; then
  echo "dsh-run: stopped by the time limit" >&2
fi
if [ -r "$progress" ]; then
  echo "dsh-run: progress file $progress:"
  cat "$progress"
fi
exit "$status"
