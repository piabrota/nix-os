#!/bin/sh
# Print the machine's specs: OS, kernel, CPU, RAM, disk, NixOS generation.
# POSIX sh, reads /proc and calls only coreutils-level tools, so it runs on the VPS as is:
#   sh scripts/specs.sh               (on the box)
#   ssh piabrota sh -s < scripts/specs.sh   (from your machine)

row() { printf '%-12s %s\n' "$1" "$2"; }

if [ -r /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  row os "${PRETTY_NAME:-$NAME}"
fi
command -v nixos-version >/dev/null 2>&1 && row nixos "$(nixos-version)"
row kernel "$(uname -srm)"
row hostname "$(uname -n)"

if [ -r /proc/cpuinfo ]; then
  model=$(sed -n 's/^model name[[:space:]]*:[[:space:]]*//p' /proc/cpuinfo | head -n 1)
  row cpu "${model:-unknown} ($(grep -c '^processor' /proc/cpuinfo) vCPU)"
fi

if [ -r /proc/meminfo ]; then
  awk '
    /^MemTotal:/     { t = $2 }
    /^MemAvailable:/ { a = $2 }
    /^SwapTotal:/    { st = $2 }
    /^SwapFree:/     { sf = $2 }
    END {
      printf "%-12s %.1f GiB total, %.1f GiB available\n", "ram", t/1048576, a/1048576
      printf "%-12s %.1f GiB total, %.1f GiB used\n", "swap", st/1048576, (st-sf)/1048576
    }' /proc/meminfo
fi

for path in / /nix /boot; do
  [ -d "$path" ] || continue
  df -hP "$path" | awk -v p="$path" 'NR == 2 {
    printf "%-12s %s used of %s (%s), %s free, on %s\n", "disk " p, $3, $2, $5, $4, $1 }'
done | awk '!seen[$NF]++'

if [ -r /proc/uptime ]; then
  awk '{ d = int($1/86400); h = int($1%86400/3600); m = int($1%3600/60)
         printf "%-12s %dd %dh %dm\n", "uptime", d, h, m }' /proc/uptime
fi
[ -r /proc/loadavg ] && row load "$(cut -d ' ' -f 1-3 /proc/loadavg)"

if [ -L /nix/var/nix/profiles/system ]; then
  gen=$(readlink /nix/var/nix/profiles/system | sed 's/^system-\([0-9]*\)-link$/\1/')
  count=0
  for link in /nix/var/nix/profiles/system-*-link; do
    [ -e "$link" ] && count=$((count + 1))
  done
  row generation "$gen (of $count kept)"
  row system "$(readlink -f /run/current-system)"
  booted=$(readlink -f /run/booted-system 2>/dev/null)
  [ "$booted" != "$(readlink -f /run/current-system)" ] && row booted "$booted (reboot to boot the current one)"
fi
exit 0
