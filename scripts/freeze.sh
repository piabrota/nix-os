#!/bin/sh
# Like `pip freeze`, for the running NixOS system: every package in its closure as
# name==version with its size. Store paths with no version (config files, units, scripts)
# are not listed but count in the total on the last line.
#   sh scripts/freeze.sh [--by-size] [system]    (on the box; default /run/current-system)
#   ssh piabrota sh -s < scripts/freeze.sh       (from your machine)
set -eu
key=-k2,2f
if [ "${1:-}" = "--by-size" ]; then key=-k3,3nr; shift; fi
system=${1:-/run/current-system}

# Each line is: group (0 a package, 1 the total), name==version, bytes. Sorting on the group
# first keeps the total last.
nix --extra-experimental-features nix-command path-info --recursive --size "$system" | awk '
{
  n = $1; sub(/^\/nix\/store\/[^-]*-/, "", n)
  total += $2; count++
  # the version starts at the first "-<digit>", as in nixpkgs names: bash-interactive-5.3p9
  if (!match(n, /-[0-9]/)) next
  printf "0\t%s==%s\t%d\n", substr(n, 1, RSTART - 1), substr(n, RSTART + 1), $2
  packages++
}
END { printf "1\t# %d packages, %d store paths\t%d\n", packages, count, total }
' | LC_ALL=C sort -t "$(printf '\t')" -k1,1n "$key" | awk -F '\t' '
function human(b) {
  if (b >= 1073741824) return sprintf("%.2f GiB", b / 1073741824)
  if (b >= 1048576) return sprintf("%.1f MiB", b / 1048576)
  if (b >= 1024) return sprintf("%.1f KiB", b / 1024)
  return b " B"
}
$1 == 1 { printf "%s, %s\n", $2, human($3); next }
{ printf "%-56s %12s\n", $2, human($3) }'
