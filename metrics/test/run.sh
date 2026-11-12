#!/bin/sh
# Tests of metrics/collect.sh against a fixture tree for /proc, /sys/fs/cgroup and /etc/passwd.
# POSIX sh and jq. Prints "N checks, M failed"; exits 1 on a failure. `sh metrics/test/run.sh`.
# AWK may name another awk (for example mawk or busybox awk) to run the collector with.
set -u
here=$(cd "$(dirname "$0")" && pwd)
collect="$here/../collect.sh"
work=$(mktemp -d)
trap 'chmod -R u+rwx "$work" 2>/dev/null; rm -rf "$work"' EXIT

if [ "$(getconf CLK_TCK)" != 100 ] || [ "$(getconf PAGESIZE)" != 4096 ]; then
  echo "the fixtures assume CLK_TCK 100 and a 4096 byte page" >&2; exit 2
fi
if [ -n "${AWK:-}" ]; then
  mkdir "$work/bin"; ln -s "$(command -v "$AWK")" "$work/bin/awk"; PATH="$work/bin:$PATH"
fi

checks=0 failed=0
check() { # description, got, want
  checks=$((checks + 1))
  if [ "$2" != "$3" ]; then failed=$((failed + 1)); printf 'FAIL %s: got [%s], want [%s]\n' "$1" "$2" "$3"; fi
}
ok() { # description, command...
  desc=$1; shift
  checks=$((checks + 1))
  if ! "$@" >/dev/null 2>&1; then failed=$((failed + 1)); printf 'FAIL %s\n' "$desc"; fi
}
# jq 1.7 keeps the literal 30.0; the arithmetic makes every number canonical (30).
val() { jq -c "$1 | (.. | numbers) |= . + 0" "$out/piabrota2.json"; }

proc="$work/proc" cg="$work/cg" out="$work/out" st="$work/st"
mkdir -p "$out" "$st"
printf 'root:x:0:0::/root:/bin/sh\nalice:x:1000:100::/home/alice:/bin/sh\n' > "$work/passwd"

run() { # runs the collector as the box does, on the fixture
  METRICS_NAME=piabrota2 METRICS_LABEL='piabrota2 (KVM 4)' OUT_DIR="$out" STATE_DIR="$st" METRICS_INVENTORY="${inv:-}" \
    METRICS_PROBE="${probef:-}" METRICS_REPO="${repo:-}" SYSTEM_PROFILE="${profile:-$work/none}" NIXOS_VERSION_FILE="${nver:-$work/none}" \
    PROC_ROOT="$proc" CGROUP_ROOT="$cg" PASSWD_FILE="$work/passwd" sh "${1:-$collect}" 2>"$work/err"
}

# proc ROOT PID COMM UTIME STIME START RSS_PAGES UID: one process. COMM goes in verbatim.
proc_add() {
  mkdir -p "$1/$2"
  printf '%s (%s) S 1 %s %s 0 -1 4194560 100 0 0 0 %s %s 0 0 20 0 1 0 %s 1000000 %s 18446744073709551615 1 1 0 0 0 0 0 0 0 0 0 0 17 0 0 0 0 0 0\n' \
    "$2" "$3" "$2" "$2" "$4" "$5" "$6" "$7" > "$1/$2/stat"
  printf '5000 %s 100 10 0 100 0\n' "$7" > "$1/$2/statm"
  printf 'Name:\tx\nUid:\t%s\t%s\t%s\t%s\n' "$8" "$8" "$8" "$8" > "$1/$2/status"
}
# The system files of one sample: UPTIME, then the per-CPU lines (user nice system idle iowait).
sys_add() {
  mkdir -p "$proc"
  printf '%s 5000.00\n' "$1" > "$proc/uptime"
  printf '0.50 0.25 0.10 1/100 999\n' > "$proc/loadavg"
  printf 'MemTotal:        8000000 kB\nMemFree:          100000 kB\nMemAvailable:    3000000 kB\nSwapTotal:       1000000 kB\nSwapFree:         400000 kB\n' > "$proc/meminfo"
  printf 'cpu  %s 0 %s %s %s 0 0 0 0 0\ncpu0 %s 0 %s %s %s 0 0 0 0 0\ncpu1 %s 0 %s %s %s 0 0 0 0 0\nintr 1\n' "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}" "${11}" "${12}" "${13}" > "$proc/stat"
}
# The counters of one sample, after sys_add: CTXT FORKS RX TX SECTORS_READ SECTORS_WRITTEN.
# The network is PID 1's (/proc/1/net); a partition (sda1) and lo must not count.
io_add() {
  printf 'ctxt %s\nprocesses %s\nprocs_running 3\nprocs_blocked 1\n' "$1" "$2" >> "$proc/stat"
  printf 'MemTotal:        8000000 kB\nMemFree:          100000 kB\nMemAvailable:    3000000 kB\nBuffers:           10000 kB\nCached:          2000000 kB\nSwapTotal:       1000000 kB\nSwapFree:         400000 kB\nShmem:             50000 kB\nDirty:               300 kB\n' > "$proc/meminfo"
  printf '0.50 0.25 0.10 2/345 999\n' > "$proc/loadavg"
  mkdir -p "$proc/1/net" "$proc/pressure" "$proc/sys/fs"
  printf 'Inter-|   Receive                            |  Transmit\n face |bytes packets errs drop fifo frame compressed multicast|bytes packets errs drop fifo colls carrier compressed\n    lo: 99999 9 0 0 0 0 0 0 99999 9 0 0 0 0 0 0\n  eth0: %s 10 0 0 0 0 0 0 %s 10 0 0 0 0 0 0\n' "$3" "$4" > "$proc/1/net/dev"
  printf 'sockets: used 40\nTCP: inuse 7 orphan 0 tw 3 alloc 9 mem 2\nUDP: inuse 4 mem 1\n' > "$proc/1/net/sockstat"
  printf '   8       0 sda 100 0 %s 50 200 0 %s 60 0 70 110\n   8       1 sda1 100 0 %s 50 200 0 %s 60 0 70 110\n   7       0 loop0 1 0 999 1 0 0 999 0 0 1 1\n' "$5" "$6" "$5" "$6" > "$proc/diskstats"
  printf '1234\t0\t9223372036854775807\n' > "$proc/sys/fs/file-nr"
  printf 'some avg10=1.50 avg60=1.00 avg300=0.50 total=100\nfull avg10=0.00 avg60=0.00 avg300=0.00 total=0\n' > "$proc/pressure/cpu"
  printf 'some avg10=0.25 avg60=0.10 avg300=0.00 total=10\nfull avg10=0.10 avg60=0.00 avg300=0.00 total=5\n' > "$proc/pressure/memory"
  printf 'some avg10=4.00 avg60=2.00 avg300=1.00 total=900\nfull avg10=3.00 avg60=1.00 avg300=0.50 total=800\n' > "$proc/pressure/io"
}
cg_add() { # unit max current peak (peak "-" for none)
  mkdir -p "$cg/system.slice/$1"
  printf '%s\n' "$2" > "$cg/system.slice/$1/memory.max"
  printf '%s\n' "$3" > "$cg/system.slice/$1/memory.current"
  [ "$4" = - ] || printf '%s\n' "$4" > "$cg/system.slice/$1/memory.peak"
}

hostile='a"b\c</scr<img>'
nl_name='nl
x'

# Sample 1, at uptime 1000 s. cpu0 and cpu1 each: 500/250 user/system, 4000 idle, 250 iowait.
sys_add 1000.00 1000 500 8000 500 500 250 4000 250 500 250 4000 250
io_add 10000 500 1000000 500000 2000 4000
proc_add "$proc" 100 alpha 100 50 10 1000 1000
proc_add "$proc" 200 'my proc (x)' 10 0 20 3000 0
proc_add "$proc" 300 "$hostile" 5 0 30 500 4242
proc_add "$proc" 500 "$nl_name" 1 0 40 100 1000
mkdir -p "$proc/400"                       # a process that ended while it was read: no files
mkdir -p "$proc/600"; : > "$proc/600/stat" # an empty stat
mkdir -p "$proc/self" "$proc/sys"          # not processes
cg_add a.service 1000 500 700
cg_add b.service max 900 -
cg_add c.service 2000 1900 -
mkdir -p "$cg/system.slice/d.service"      # no memory.max at all
mkdir -p "$cg/system.slice/sub.slice"      # not a service

echo "# first run: nothing to compare with"
ok "first run exits 0" run
cat "$work/err" >&2
ok "first run is valid JSON" jq -e . "$out/piabrota2.json"
check "first run warming" "$(val .cpu.warming)" true
check "first run cpu is 0" "$(val '[.cpu.total_pct, .cpu.cores[0]]')" '[0,0]'
check "first run process cpu is 0" "$(val '[.top_cpu[].cpu_pct] | add')" 0
check "first run rates are 0" "$(val '[.tasks.forks_per_s, .tasks.ctxt_per_s, .net.rx_bps, .net.tx_bps, .disk_io.read_bps, .disk_io.write_bps]')" '[0,0,0,0,0,0]'
check "state file written" "$(test -s "$st/piabrota2.state" && echo yes)" yes
check "no temp file left" "$(find "$out" "$st" -name '*.tmp' | grep -c .)" 0
check "file mode is 0644" "$(stat -c %a "$out/piabrota2.json")" 644

echo "# second run, 10 s later"
sys_add 1010.00 1500 600 9300 600 800 300 4600 300 700 300 4700 300
io_add 15000 520 2000000 600000 2200 6000
proc_add "$proc" 100 alpha 200 100 10 1000 1000
proc_add "$proc" 200 'my proc (x)' 310 0 20 3000 0
proc_add "$proc" 300 "$hostile" 5 0 30 500 4242
proc_add "$proc" 500 "$nl_name" 1 0 40 100 1000
proc_add "$proc" 700 newbie 50 0 100550 50 1000     # started at 1005.5 s, inside the window
cg_add c.service 2000 1950 1990
ok "second run exits 0" run
cat "$work/err" >&2
ok "second run is valid JSON" jq -e . "$out/piabrota2.json"
check "schema version" "$(val .v)" 1
check "host" "$(val .host)" '"piabrota2"'
check "label" "$(val .label)" '"piabrota2 (KVM 4)"'
check "interval" "$(val .interval)" 10
check "ts is a recent unix time" "$(val '.ts > 1700000000')" true
check "uptime" "$(val .uptime_s)" 1010
check "vcpus" "$(val .vcpus)" 2
check "load" "$(val .load)" '[0.5,0.25,0.1]'
check "warming is gone" "$(val '.cpu | has("warming")')" false
check "cpu total" "$(val .cpu.total_pct)" 30
check "cpu cores" "$(val .cpu.cores)" '[35,25]'
check "mem total" "$(val .mem.total)" 8192000000
check "mem used is total minus available" "$(val .mem.used)" 5120000000
check "mem available" "$(val .mem.available)" 3072000000
check "swap" "$(val '[.mem.swap_total, .mem.swap_used]')" '[1024000000,614400000]'
check "disk is numbers" "$(val '(.disk.root_total > 0) and (.disk.root_used > 0)')" true
check "mem detail" "$(val .mem_detail)" '{"buffers":10240000,"cached":2048000000,"shmem":51200000,"dirty":307200}'
check "tasks" "$(val .tasks)" '{"threads":345,"running":3,"blocked":1,"forks_per_s":2,"ctxt_per_s":500}'
check "open files" "$(val .fds_open)" 1234
check "network of PID 1, without lo" "$(val .net)" '{"rx_bps":100000,"tx_bps":10000,"rx_total":2000000,"tx_total":600000}'
check "sockets" "$(val .sockets)" '{"tcp":7,"tcp_tw":3,"udp":4}'
check "disk io of whole disks only" "$(val .disk_io)" '{"read_bps":10240,"write_bps":102400,"read_total":1126400,"write_total":3072000}'
check "pressure" "$(val .pressure)" '{"cpu":{"some":1.5,"full":0},"memory":{"some":0.25,"full":0.1},"io":{"some":4,"full":3}}'
check "procs_total skips the ones that ended" "$(val .procs_total)" 5
check "top_mem order" "$(val '[.top_mem[].pid]')" '[200,100,300,500,700]'
check "top_cpu order, ties by pid" "$(val '[.top_cpu[].pid]')" '[200,100,700,300,500]'
check "cpu of a process" "$(val '[.top_cpu[0].cpu_pct, .top_cpu[1].cpu_pct]')" '[30,15]'
check "cpu of a process that started in the window" "$(val '.top_cpu[2].cpu_pct')" 5
check "rss in bytes" "$(val '.top_mem[0].rss')" 12288000
check "user from passwd" "$(val '[.top_mem[0].user, .top_mem[1].user]')" '["root","alice"]'
check "unknown uid stays a number" "$(val '.top_mem[2].user')" '"4242"'
check "name with spaces and a parenthesis" "$(val '.top_mem[0].name')" '"my proc (x)"'
check "hostile name round-trips" "$(val '.top_mem[2].name')" '"a\"b\\c</scr<img>"'
check "newline in a name becomes ?" "$(val '.top_mem[3].name')" '"nl?x"'
check "units sorted by share of the limit" "$(val '[.units[].unit]')" '["c.service","a.service"]'
check "unit numbers with a peak" "$(val '.units[1]')" '{"unit":"a.service","mem":500,"max":1000,"peak":700}'
check "unit numbers" "$(val '.units[0]')" '{"unit":"c.service","mem":1950,"max":2000,"peak":1990}'
check "the file stays under 8 KB" "$([ "$(wc -c < "$out/piabrota2.json")" -lt 8192 ] && echo yes)" yes
check "no command line in the file" "$(grep -c -e '/bin/' -e cmdline "$out/piabrota2.json")" 0
check "services running: every unit with a cgroup" "$(val .services_running)" 4
check "no inventory without the file" "$(val 'has("inventory")')" false

echo "# the inventory"
inv="$work/inventory"
printf 'apps 1\nsites 7\nskills 120\n' > "$inv"
# Lines the collector must drop: a quote, a capital, a negative, a fraction, three fields, a key
# that is too long, a number that is too long, a repeated key, an empty line.
printf 'x"y 1\nApps 2\nrigs -1\nmcp 1.5\nplugins 1 2\n%s 1\ntimers 1234567890\napps 9\n\n' \
  aaaaaaaaaaaaaaaaaaaaaaaaa >> "$inv"
ok "run with an inventory" run
ok "the inventory run is valid JSON" jq -e . "$out/piabrota2.json"
check "inventory keeps the good lines, in order" "$(val .inventory)" '{"apps":1,"sites":7,"skills":120}'
i=0; : > "$inv"; while [ $i -lt 30 ]; do printf 'k%s 1\n' "$(echo $i | tr 0-9 a-j)" >> "$inv"; i=$((i + 1)); done
ok "run with a long inventory" run
check "24 inventory keys at most" "$(val '.inventory | length')" 24
: > "$inv"
ok "run with an empty inventory" run
check "an empty inventory is an empty object" "$(val .inventory)" '{}'
inv="$work/nope"
ok "run with an inventory file that is missing" run
check "a missing inventory file is an empty object" "$(val .inventory)" '{}'
inv=""

echo "# the system, the probe file and the repository"
check "an empty system without its files" "$(val .system)" '{}'
check "no domains and no repo without a probe file" "$(val 'has("domains") or has("repo")')" false
ln -s system-42-link "$work/system"; printf '26.05.20261101.abcdef0' > "$work/nixos-version"
profile="$work/system" nver="$work/nixos-version" probef="$work/probe" repo=piabrota/nix-os
# Lines the collector must drop: a capital and a quote in a name, a code of 4 digits, a count
# that is not a number.
printf 'ts 1700000000\ndomain www.piabrota.art 200\ndomain metrics.piabrota.art 401\ndomain down.piabrota.art 000\ndomain bad.piabrota.art 502\ndomain B"x 200\ndomain long 2000\nrepo 230 1699999000\nrepo x 1\n' > "$probef"
ok "run with a probe file" run
ok "the probe run is valid JSON" jq -e . "$out/piabrota2.json"
check "the version and the generation" "$(val .system)" '{"nixos":"26.05.20261101.abcdef0","generation":42}'
check "an answer below 500 is up" "$(val '[.domains.list[] | [.name, .code, .up]]')" \
  '[["www.piabrota.art",200,true],["metrics.piabrota.art",401,true],["down.piabrota.art",0,false],["bad.piabrota.art",502,false]]'
check "the counts of the sites" "$(val '[.domains.ts, .domains.up, .domains.total]')" '[1700000000,2,4]'
check "the repository" "$(val .repo)" '{"name":"piabrota/nix-os","commits":230,"ts":1699999000}'
printf 'not a "version"' > "$nver"; ln -sf system-x-link "$profile"
i=0; : > "$probef"; while [ $i -lt 30 ]; do echo "domain d$i.example 200" >> "$probef"; i=$((i + 1)); done
echo "ts 1700000000" >> "$probef"
ok "run with bad system files and many sites" run
check "a bad version and a bad generation are left out" "$(val .system)" '{}'
check "24 sites at most" "$(val '.domains.total')" 24
check "no repo without its line" "$(val 'has("repo")')" false
probef="$work/nope"
ok "run with a probe file that is missing" run
check "a missing probe file gives no domains" "$(val 'has("domains")')" false
profile="" nver="" probef="" repo=""

echo "# the probe"
probe="$here/../probe.sh" pst="$work/pst"
mkdir -p "$work/fake"
# A curl that answers by the host in the address; the GitHub address gets FAKE_LINK as its Link.
cat > "$work/fake/curl" <<'FAKE'
#!/bin/sh
for a; do url=$a; done
echo "$url" >> "$FAKE_LOG"
case $url in
  */commits\?*) [ -n "$FAKE_LINK" ] || exit 7; printf 'HTTP/2 200\r\nlink: %s\r\n\r\n' "$FAKE_LINK" ;;
  https://up.example/) printf 200 ;;
  http://auth.example/) printf 401 ;;
  *) printf 000; exit 7 ;;
esac
FAKE
chmod +x "$work/fake/curl"
printf 'up.example https://up.example/\nauth.example http://auth.example/\ndown.example https://down.example/\nBad.example https://x/\nno-url.example ftp://x/\n' > "$work/sites"
probe_run() {
  PATH="$work/fake:$PATH" FAKE_LOG="$work/curl.log" METRICS_NAME=piabrota2 STATE_DIR="$pst" PROBE_SITES="$work/sites" \
    PROBE_REPO=piabrota/nix-os GITHUB_API=https://api.test PROBE_REPO_EVERY="${every:-600}" sh "$probe" 2>"$work/err"
}
pline() { grep "^$1 " "$pst/piabrota2.probe" | cut -d' ' -f2- | tr '\n' '|'; }
: > "$work/curl.log"
# shellcheck disable=SC2089,SC2090 # the quotes are the header's, read as text by the fake curl
FAKE_LINK='<https://api.test/repositories/1/commits?per_page=1&sha=main&page=2>; rel="next", <https://api.test/repositories/1/commits?per_page=1&sha=main&page=230>; rel="last"'
# shellcheck disable=SC2090
export FAKE_LINK
ok "the probe runs" probe_run
check "a code for each good site, 000 when nothing answers" "$(pline domain)" 'up.example 200|auth.example 401|down.example 000|'
check "the count is the last page" "$(pline repo | cut -d' ' -f1)" 230
check "GitHub is asked for one commit a page" "$(grep -c 'api.test/repos/piabrota/nix-os/commits?per_page=1&sha=main$' "$work/curl.log")" 1
FAKE_LINK='<https://api.test/x?page=999>; rel="last"'
ok "a second run" probe_run
check "GitHub is not asked again within PROBE_REPO_EVERY" "$(grep -c api.test "$work/curl.log")" 1
check "and the count stays" "$(pline repo | cut -d' ' -f1)" 230
FAKE_LINK=""
every=0 probe_run
check "a GitHub that does not answer keeps the old count" "$(pline repo | cut -d' ' -f1)" 230
check "and the time it was asked" "$(pline asked | grep -c .)" 1
FAKE_LINK='<https://api.test/x?page=999>; rel="last"'
every=0 probe_run
check "a new count when it answers" "$(pline repo | cut -d' ' -f1)" 999
check "nothing on stderr" "$(cat "$work/err")" ""
check "the probe file is not in the served folder" "$(find "$out" -name '*probe*' | grep -c .)" 0
probef="$pst/piabrota2.probe" repo=piabrota/nix-os
ok "the collector reads the probe file" run
check "the collector shows what the probe found" "$(val '[.domains.up, .domains.total, .repo.commits]')" '[2,3,999]'
probef="" repo=""
METRICS_NAME='../x' STATE_DIR="$pst" sh "$probe" 2>/dev/null
check "bad METRICS_NAME exits 2 in the probe" "$?" 2

echo "# the caps"
i=1000
while [ $i -lt 1030 ]; do
  proc_add "$proc" $i "p$i" 1 0 50 $((i - 900)) 1000
  cg_add "u$i.service" 100 $((i - 900)) -
  i=$((i + 1))
done
sys_add 1020.00 1500 600 9300 600 800 300 4600 300 700 300 4700 300
ok "run with many processes" run
check "10 processes in each list" "$(val '[(.top_mem | length), (.top_cpu | length)]')" '[10,10]'
check "12 units at most" "$(val '.units | length')" 12
check "the cap run is under 8 KB" "$([ "$(wc -c < "$out/piabrota2.json")" -lt 8192 ] && echo yes)" yes
i=1000; while [ $i -lt 1030 ]; do rm -rf "${proc:?}/$i" "$cg/system.slice/u$i.service"; i=$((i + 1)); done

echo "# a process that cannot be read, and a missing cgroup tree"
if [ "$(id -u)" != 0 ]; then
  proc_add "$proc" 800 locked 1 0 60 100 1000
  chmod 000 "$proc/800/stat"
  sys_add 1030.00 1500 600 9300 600 800 300 4600 300 700 300 4700 300
  ok "run with an unreadable stat" run
  check "the unreadable process is skipped" "$(val '[.top_mem[].pid] | index(800)')" null
  check "and nothing on stderr" "$(cat "$work/err")" ""
  chmod 644 "$proc/800/stat"; rm -rf "${proc:?}/800"
fi
sys_add 1040.00 1500 600 9300 600 800 300 4600 300 700 300 4700 300
CGROUP_ROOT="$work/none"; export CGROUP_ROOT
cg="$work/none"
ok "run with no cgroup tree" run
check "units is empty" "$(val .units)" '[]'
ok "still valid JSON" jq -e . "$out/piabrota2.json"
check "nothing on stderr" "$(cat "$work/err")" ""

echo "# a clock that went back or a garbled state counts as a first run"
printf 'garbage\nT notanumber\n' > "$st/piabrota2.state"
ok "run with a garbled state" run
ok "valid JSON" jq -e . "$out/piabrota2.json"
sys_add 10.00 1500 600 9300 600 800 300 4600 300 700 300 4700 300
printf 'T 5000\n' > "$st/piabrota2.state"
ok "run after a reboot" run
check "warming after a reboot" "$(val .cpu.warming)" true

echo "# the escaper: a naive one breaks the JSON, so these checks can fail"
naive="$work/naive.sh"
sed 's/c == "\\\\" || //' "$collect" > "$naive"
check "the mutation changed the script" "$(cmp -s "$naive" "$collect" && echo same || echo changed)" changed
sys_add 1050.00 1500 600 9300 600 800 300 4600 300 700 300 4700 300
run "$naive"
check "a naive escaper makes invalid JSON" "$(jq -e . "$out/piabrota2.json" >/dev/null 2>&1 && echo valid || echo broken)" broken
run
check "the real escaper makes valid JSON" "$(jq -e . "$out/piabrota2.json" >/dev/null 2>&1 && echo valid || echo broken)" valid

echo "# a bad name is refused"
METRICS_NAME='../x' OUT_DIR="$out" STATE_DIR="$st" sh "$collect" 2>/dev/null
check "bad METRICS_NAME exits 2" "$?" 2

printf '%s checks, %s failed\n' "$checks" "$failed"
[ "$failed" = 0 ]
