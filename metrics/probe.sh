#!/bin/sh
# One run of the probe: ask each site of this host for a response, count each site's visits of the
# last 24 h from nginx's log, and read the commit count of the repository from GitHub at most once
# in PROBE_REPO_EVERY seconds. It writes one file, atomically, that the collector puts in the JSON
# (metrics/SCHEMA.md, "domains" and "repo").
#
# Environment:
#   METRICS_NAME      the host's name (required): the file is <STATE_DIR>/<name>.probe
#   PROBE_SITES       a file of "<domain> <url>" lines that Nix wrote (metrics.nix)
#   PROBE_REPO        owner/name on GitHub; empty: no commit count
#   PROBE_BRANCH      the branch whose commits are counted (default main)
#   PROBE_REPO_EVERY  seconds between two reads of GitHub (default 600: 6 an hour of the 60 that
#                     GitHub gives an address without a token)
#   PROBE_VISITS_LOG  the pages nginx logged, "<msec> <server_name> <address>" a line (metrics.nix);
#                     empty or unreadable: no visits. What was read, and the last 24 h, are kept in
#                     <STATE_DIR>/<name>.visits
#   PROBE_NOW         the time, Unix seconds (default now; the tests set it)
#   STATE_DIR         default /run/metrics-state
#   GITHUB_API        default https://api.github.com; the tests point it at nothing
set -eu
umask 022
export LC_ALL=C

name=${METRICS_NAME:?METRICS_NAME is not set}
case $name in *[!a-z0-9-]* | '') echo "probe: bad METRICS_NAME" >&2; exit 2 ;; esac
sites=${PROBE_SITES:-/dev/null}
repo=${PROBE_REPO:-}
branch=${PROBE_BRANCH:-main}
every=${PROBE_REPO_EVERY:-600}
state_dir=${STATE_DIR:-/run/metrics-state}
api=${GITHUB_API:-https://api.github.com}
visits_log=${PROBE_VISITS_LOG:-}
case $repo in *[!A-Za-z0-9._/-]*) repo="" ;; esac
case $branch in '' | *[!A-Za-z0-9._/-]*) branch=main ;; esac

mkdir -p "$state_dir"
out="$state_dir/$name.probe"
tmp="$out.$$.tmp"
vstate="$state_dir/$name.visits"
vtmp="$vstate.$$.tmp"
trap 'rm -f "$tmp" "$vtmp"' EXIT
now=${PROBE_NOW:-$(date +%s)}
case $now in '' | *[!0-9]*) now=$(date +%s) ;; esac
ua="piabrota-metrics-probe"

# The last count, kept when GitHub is not asked or does not answer ("repo <commits> <ts>"), and
# when GitHub was last asked ("asked <ts>"), so a GitHub that fails is not asked every run.
old_n="" old_ts=0 asked=0
if [ -r "$out" ]; then
  while read -r key n ts _; do
    case $key in
      repo) case "$n$ts" in *[!0-9]* | '') ;; *) old_n=$n old_ts=$ts ;; esac ;;
      asked) case $n in *[!0-9]* | '') ;; *) asked=$n ;; esac ;;
    esac
  done < "$out"
fi

# The visits (docs/METRICS.md, "Visits"): read what nginx added to the log since the last run, at
# most 16 MiB, and keep the views by the hour and the last time of each address, for 24 h. A new
# file (logrotate) is read from its start; a line that nginx has not finished is read next run.
visits=""
vsize=""
if [ -n "$visits_log" ] && [ -r "$visits_log" ]; then
  vstat=$(stat -L -c '%i %s' "$visits_log" 2>/dev/null) || vstat=""
  vino=${vstat% *} vsize=${vstat#* }
  case "$vino$vsize" in '' | *[!0-9]*) vsize="" ;; esac
fi
if [ -n "$vsize" ]; then
  ino=0 off=0
  if [ -r "$vstate" ]; then
    read -r key i o _ < "$vstate" || true
    if [ "${key:-}" = pos ]; then
      case "${i:-x}${o:-x}" in *[!0-9]*) ;; *) ino=$i off=$o ;; esac
    fi
  fi
  if [ "$ino" != "$vino" ] || [ "$off" -gt "$vsize" ]; then off=0; fi
  skip=0
  if [ $((vsize - off)) -gt 16777216 ]; then off=$((vsize - 16777216)) skip=1; fi
  nl=0
  if [ "$vsize" -gt "$off" ] && [ "$(tail -c +"$vsize" "$visits_log" | head -c 1 | od -An -tx1 | tr -d ' ')" = 0a ]; then nl=1; fi
  visits=$(
    if [ "$vsize" -gt "$off" ]; then tail -c +$((off + 1)) "$visits_log" | head -c $((vsize - off)); fi |
      awk -v NOW="$now" -v INO="$vino" -v OFF="$off" -v SKIP="$skip" -v NL="$nl" \
        -v SITES="$sites" -v STATE="$vstate" -v OUT="$vtmp" '
# Each line read is held until the next one: the last counts only when the read ended on a newline.
function take(l,   f, ts, k) {
  used += length(l) + 1
  if (SKIP && !skipped) { skipped = 1; return }
  if (split(l, f, " ") != 3 || f[1] !~ /^[0-9]+(\.[0-9]+)?$/ || !(f[2] in known) || f[3] !~ /^[0-9A-Fa-f.:]+$/ || length(f[3]) > 45) return
  ts = int(f[1])
  if (ts <= from || ts > NOW + 60) return
  H[(ts - ts % 3600) " " f[2]]++
  k = f[2] " " f[3]
  if (!(k in U)) { if (nu >= 50000) return; nu++; U[k] = 0 }
  if (ts > U[k]) U[k] = ts
}
BEGIN {
  from = NOW - 86400
  while ((getline l < SITES) > 0) {
    split(l, f, " ")
    if (f[1] ~ /^[a-z0-9.-]+$/ && f[2] ~ /^https?:\/\// && !(f[1] in known) && ns < 24) { known[f[1]] = 1; order[++ns] = f[1] }
  }
  close(SITES)
  while ((getline l < STATE) > 0) {
    n = split(l, f, " ")
    if (n != 4 || f[4] !~ /^[0-9]+$/) continue
    if (f[1] == "h" && f[2] ~ /^[0-9]+$/ && f[2] + 3600 > from && (f[3] in known)) H[f[2] " " f[3]] += f[4]
    else if (f[1] == "u" && (f[2] in known) && f[3] ~ /^[0-9A-Fa-f.:]+$/ && f[4] > from) {
      k = f[2] " " f[3]
      if (!(k in U)) { nu++; U[k] = 0 }
      if (f[4] + 0 > U[k]) U[k] = f[4] + 0
    }
  }
  close(STATE)
}
{ if (have) take(prev); prev = $0; have = 1 }
END {
  if (have && NL) take(prev)
  printf "pos %s %.0f\n", INO, OFF + used > OUT
  for (k in H) { printf "h %s %d\n", k, H[k] > OUT; split(k, f, " "); V[f[2]] += H[k] }
  for (k in U) { printf "u %s %d\n", k, U[k] > OUT; split(k, f, " "); P[f[1]]++ }
  close(OUT)
  for (i = 1; i <= ns; i++) printf "visits %s %d %d\n", order[i], V[order[i]], P[order[i]]
}'
  ) || visits=""
  if [ -s "$vtmp" ]; then mv -f "$vtmp" "$vstate"; fi
fi

{
  echo "ts $now"
  n=0
  while read -r domain url _; do
    case $domain in '' | *[!a-z0-9.-]*) continue ;; esac
    case $url in http://* | https://*) ;; *) continue ;; esac
    [ "$n" -lt 24 ] || break
    # No redirect is followed: a 301 is an answer. curl prints 000 when nothing answers.
    code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 3 --max-time 6 -A "$ua" "$url" 2>/dev/null) || true
    case $code in [0-9][0-9][0-9]) ;; *) code=000 ;; esac
    echo "domain $domain $code"
    n=$((n + 1))
  done < "$sites"

  commits=$old_n stamp=$old_ts
  if [ -n "$repo" ] && [ $((now - asked)) -ge "$every" ]; then
    asked=$now
    # One commit a page: the page number of rel="last" is the count.
    link=$(curl -s -o /dev/null -D - --max-time 10 -A "$ua" -H 'Accept: application/vnd.github+json' \
      "$api/repos/$repo/commits?per_page=1&sha=$branch" 2>/dev/null | tr -d '\r' | grep -i '^link:') || true
    last=$(printf '%s\n' "$link" | sed -n 's/.*[?&]page=\([0-9][0-9]*\)>; rel="last".*/\1/p')
    if [ -n "$last" ] && [ "${#last}" -le 9 ]; then commits=$last stamp=$now; fi
  fi
  if [ -n "$commits" ]; then echo "repo $commits $stamp"; fi
  if [ -n "$repo" ]; then echo "asked $asked"; fi
  if [ -n "$visits" ]; then printf '%s\n' "$visits"; fi
} > "$tmp"
mv -f "$tmp" "$out"
