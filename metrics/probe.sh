#!/bin/sh
# One run of the probe: ask each site of this host for a response, and read the commit count of
# the repository from GitHub at most once in PROBE_REPO_EVERY seconds. It writes one file,
# atomically, that the collector puts in the JSON (metrics/SCHEMA.md, "domains" and "repo").
#
# Environment:
#   METRICS_NAME      the host's name (required): the file is <STATE_DIR>/<name>.probe
#   PROBE_SITES       a file of "<domain> <url>" lines that Nix wrote (metrics.nix)
#   PROBE_REPO        owner/name on GitHub; empty: no commit count
#   PROBE_BRANCH      the branch whose commits are counted (default main)
#   PROBE_REPO_EVERY  seconds between two reads of GitHub (default 600: 6 an hour of the 60 that
#                     GitHub gives an address without a token)
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
case $repo in *[!A-Za-z0-9._/-]*) repo="" ;; esac
case $branch in '' | *[!A-Za-z0-9._/-]*) branch=main ;; esac

mkdir -p "$state_dir"
out="$state_dir/$name.probe"
tmp="$out.$$.tmp"
trap 'rm -f "$tmp"' EXIT
now=$(date +%s)
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
} > "$tmp"
mv -f "$tmp" "$out"
