#!/bin/sh
# Delivers the result of piabrota-dot to Discord. A no_agent cron job runs it at 14:15 (the bot's
# own unit runs at 14:00, as another user: docs/PIABROTA-DOT.md). It prints the contents of
# /var/lib/piabrota-dot/last-run.txt once, when they changed since the last delivery, and prints
# nothing otherwise, so a quiet day sends no message. "piabrota-dot: nothing new" is quiet too.
# The "time:" line is left out of the comparison, so a run with the same result stays quiet.
#
# Environment (all optional):
#   LAST_RUN     the file that the bot writes     (/var/lib/piabrota-dot/last-run.txt)
#   HERMES_HOME  the home of Hermes               ($HOME/.hermes)
set -eu

# Cron gives this script the PATH of the hermes-agent unit: add the system profile at the end.
PATH="$PATH:/run/current-system/sw/bin"
export PATH

LAST_RUN=${LAST_RUN:-/var/lib/piabrota-dot/last-run.txt}
HERMES_HOME=${HERMES_HOME:-$HOME/.hermes}
MARK=$HERMES_HOME/piabrota-dot-delivered

# No file: the bot has not run yet (or is off). Nothing to say.
[ -e "$LAST_RUN" ] || exit 0
if [ ! -r "$LAST_RUN" ]; then
  echo "piabrota-dot report failed: cannot read $LAST_RUN"
  exit 1
fi

cur=$(grep -v '^time:' "$LAST_RUN" || true)
old=
if [ -r "$MARK" ]; then old=$(cat "$MARK"); fi
[ "$cur" != "$old" ] || exit 0

printf '%s\n' "$cur" >"$MARK"
case $cur in
  "piabrota-dot: nothing new"*) exit 0 ;;
esac
cat "$LAST_RUN"
