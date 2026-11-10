#!/bin/sh
# One run of the collector: read /proc and the cgroup tree, write one JSON file, atomically.
# POSIX sh and awk, no network, no command line is read (docs/METRICS.md, metrics/SCHEMA.md).
#
# Environment:
#   METRICS_NAME      file name and "host" key: piabrota or piabrota2 (required)
#   METRICS_LABEL     the page's name for the host (default: the name)
#   METRICS_INTERVAL  seconds between runs, written to the file (default 10)
#   OUT_DIR           where <name>.json goes (default /run/metrics-web)
#   STATE_DIR         where the previous sample is kept (default /run/metrics-state)
#   METRICS_INVENTORY a file of "<key> <count>" lines that Nix wrote: what this generation runs
#                     (metrics.nix). Optional; without it the file has no "inventory".
#   PROC_ROOT, CGROUP_ROOT, PASSWD_FILE, DF_PATH: the sources; the tests point them at a fixture.
set -eu
umask 022
export LC_ALL=C

name=${METRICS_NAME:?METRICS_NAME is not set}
case $name in *[!a-z0-9-]* | '') echo "collect: bad METRICS_NAME" >&2; exit 2 ;; esac
label=${METRICS_LABEL:-$name}
interval=${METRICS_INTERVAL:-10}
out_dir=${OUT_DIR:-/run/metrics-web}
state_dir=${STATE_DIR:-/run/metrics-state}
proc=${PROC_ROOT:-/proc}
cgroup=${CGROUP_ROOT:-/sys/fs/cgroup}
passwd=${PASSWD_FILE:-/etc/passwd}
df_path=${DF_PATH:-/}
inventory=${METRICS_INVENTORY:-}

hz=$(getconf CLK_TCK 2>/dev/null || echo 100)
page=$(getconf PAGESIZE 2>/dev/null || echo 4096)
ts=$(date +%s)

mkdir -p "$out_dir" "$state_dir"
out="$out_dir/$name.json"
state="$state_dir/$name.state"
tmp_out="$out.$$.tmp"
tmp_state="$state.$$.tmp"
trap 'rm -f "$tmp_out" "$tmp_state"' EXIT

# The processes, then the services under system.slice, as the program's arguments. A glob that
# matches nothing stays literal; the program skips what is not a number or a unit.
set -- "$proc"/[0-9]*
for unit in "$cgroup"/system.slice/*.service; do
  [ -d "$unit" ] && set -- "$@" "$unit"
done

awk -v NAME="$name" -v LABEL="$label" -v INTERVAL="$interval" -v TS="$ts" \
  -v PROC="$proc" -v PASSWD="$passwd" -v DFPATH="$df_path" -v HZ="$hz" -v PAGE="$page" \
  -v STATE="$state" -v STATE_TMP="$tmp_state" -v INVENTORY="$inventory" '
# The whole file as one string, lines joined by a newline; RDN is the number of lines.
# A file that is gone or unreadable gives RDN 0: getline returns -1 and the loop ends.
function rd(f,   l, s) {
  s = ""; RDN = 0
  while ((getline l < f) > 0) { s = (RDN++ ? s "\n" : "") l }
  close(f)
  return s
}
# Printable ASCII only (anything else becomes ?), then a backslash or a quote gets a backslash.
function esc(s,   out, i, c) {
  gsub(/[^ -~]/, "?", s)
  if (s !~ /[\\"]/) return s
  out = ""
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (c == "\\" || c == "\"") out = out "\\"
    out = out c
  }
  return out
}
# The k best entries of key[1..n] into SEL, the biggest first; ties go to the lower tie[].
function pick(key, tie, n, k,   used, r, i, best) {
  split("", used); SELN = 0
  for (r = 1; r <= k; r++) {
    best = 0
    for (i = 1; i <= n; i++) {
      if (i in used) continue
      if (best == 0 || key[i] > key[best] || (key[i] == key[best] && tie[i] + 0 < tie[best] + 0)) best = i
    }
    if (best == 0) break
    used[best] = 1; SEL[++SELN] = best
  }
}
function plist(key, n,   j, i, s) {
  pick(key, ppid, n, 10)
  s = ""
  for (j = 1; j <= SELN; j++) {
    i = SEL[j]
    s = s (j > 1 ? "," : "") sprintf("{\"pid\":%.0f,\"name\":\"%s\",\"user\":\"%s\",\"rss\":%.0f,\"cpu_pct\":%.1f}", ppid[i], esc(pname[i]), esc(puser[i]), prss[i], pcpu[i])
  }
  return s
}
function pct(x) { return (x < 0 ? 0 : x) }
# A counter per second since the last run; 0 on a first run or when the counter went back.
function rate(cur, prev, has) { return (warming || !has || cur + 0 < prev + 0 ? 0 : (cur - prev) / el) }

BEGIN {
  # The CPU lines of /proc/stat: "cpu" is the total, "cpu0".. are the vCPUs.
  nl = split(rd(PROC "/stat"), L, "\n")
  nc = 0
  for (i = 1; i <= nl; i++) {
    if (L[i] ~ /^(ctxt|processes|procs_running|procs_blocked) /) { split(L[i], f, " "); ks[f[1]] = f[2] + 0; continue }
    if (L[i] !~ /^cpu[0-9]* /) continue
    nf = split(L[i], f, " ")
    t = 0
    for (k = 2; k <= 9 && k <= nf; k++) t += f[k]
    cname[++nc] = f[1]; ctot[f[1]] = t; cidle[f[1]] = f[5] + f[6]
  }
  vcpus = 0
  for (i = 1; i <= nc; i++) if (cname[i] != "cpu") vcpus++
  split(rd(PROC "/uptime"), u, " "); up = u[1] + 0
  split(rd(PROC "/loadavg"), la, " ")
  threads = la[4]; sub(/.*\//, "", threads); threads += 0

  nl = split(rd(PROC "/meminfo"), L, "\n")
  for (i = 1; i <= nl; i++) { split(L[i], f, " "); mi[f[1]] = f[2] * 1024 }
  mem_used = mi["MemTotal:"] - mi["MemAvailable:"]
  swap_used = mi["SwapTotal:"] - mi["SwapFree:"]

  # Pressure stall (PSI), the 10 s averages: "some" (and "full") of cpu, memory and io.
  psi = ""
  split("cpu memory io", pr, " ")
  for (j = 1; j <= 3; j++) {
    nl = split(rd(PROC "/pressure/" pr[j]), L, "\n"); s = ""
    for (i = 1; i <= nl; i++) {
      if (L[i] !~ /^(some|full) avg10=[0-9.]+ /) continue
      split(L[i], f, " "); v = f[2]; sub(/^avg10=/, "", v)
      s = s (s == "" ? "" : ",") sprintf("\"%s\":%.2f", f[1], v + 0)
    }
    if (s != "") psi = psi (psi == "" ? "" : ",") "\"" pr[j] "\":{" s "}"
  }

  split(rd(PROC "/sys/fs/file-nr"), fn, " "); fds = (RDN ? fn[1] + 0 : -1)

  # The network of PID 1, not this unit: the collector runs with PrivateNetwork, and
  # /proc/net is its own empty namespace. The sum over every interface but lo.
  nl = split(rd(PROC "/1/net/dev"), L, "\n"); has_net = 0; rx = 0; tx = 0
  for (i = 1; i <= nl; i++) {
    if (L[i] !~ /:/) continue
    l = L[i]; sub(/:/, " ", l); nf = split(l, f, " ")
    if (nf < 17 || f[1] == "lo") continue
    has_net = 1; rx += f[2]; tx += f[10]
  }
  nl = split(rd(PROC "/1/net/sockstat"), L, "\n"); sock = ""
  for (i = 1; i <= nl; i++) {
    nf = split(L[i], f, " ")
    for (k = 2; k < nf; k += 2) {
      key = ""
      if (f[1] == "TCP:" && f[k] == "inuse") key = "tcp"
      if (f[1] == "TCP:" && f[k] == "tw") key = "tcp_tw"
      if (f[1] == "UDP:" && f[k] == "inuse") key = "udp"
      if (key != "") sock = sock (sock == "" ? "" : ",") sprintf("\"%s\":%d", key, f[k + 1])
    }
  }
  # Whole disks only (not partitions): sectors of 512 bytes read and written.
  nl = split(rd(PROC "/diskstats"), L, "\n"); has_dio = 0; drd = 0; dwr = 0
  for (i = 1; i <= nl; i++) {
    nf = split(L[i], f, " ")
    if (nf < 10 || f[3] !~ /^([sv]d[a-z]+|xvd[a-z]+|nvme[0-9]+n[0-9]+)$/) continue
    has_dio = 1; drd += f[6] * 512; dwr += f[10] * 512
  }

  # The previous sample.
  warming = 1; pup = 0
  nl = split(rd(STATE), L, "\n")
  for (i = 1; i <= nl; i++) {
    nf = split(L[i], f, " ")
    if (f[1] == "T" && nf == 2) { pup = f[2] + 0; warming = 0 }
    else if (f[1] == "C" && nf == 4) { ptot[f[2]] = f[3]; pidle[f[2]] = f[4] }
    else if (f[1] == "P" && nf == 4) { pst[f[2]] = f[3]; pti[f[2]] = f[4] }
    else if (f[1] == "K" && nf == 3) { pk_ctxt = f[2]; pk_fork = f[3]; has_pk = 1 }
    else if (f[1] == "N" && nf == 3) { pn_rx = f[2]; pn_tx = f[3]; has_pn = 1 }
    else if (f[1] == "D" && nf == 3) { pd_rd = f[2]; pd_wr = f[3]; has_pd = 1 }
  }
  el = up - pup
  if (el <= 0) warming = 1

  print "T", up > STATE_TMP
  print "K", ks["ctxt"] + 0, ks["processes"] + 0 > STATE_TMP
  if (has_net) printf "N %.0f %.0f\n", rx, tx > STATE_TMP
  if (has_dio) printf "D %.0f %.0f\n", drd, dwr > STATE_TMP
  for (i = 1; i <= nc; i++) print "C", cname[i], ctot[cname[i]], cidle[cname[i]] > STATE_TMP
  total_pct = 0; cores = ""
  for (i = 1; i <= nc; i++) {
    n = cname[i]; p = 0
    if (!warming && (n in ptot) && ctot[n] > ptot[n]) p = 100 * (1 - (cidle[n] - pidle[n]) / (ctot[n] - ptot[n]))
    p = pct(p)
    if (n == "cpu") total_pct = p
    else cores = cores (cores == "" ? "" : ",") sprintf("%.1f", p)
  }

  nl = split(rd(PASSWD), L, "\n")
  for (i = 1; i <= nl; i++) { split(L[i], f, ":"); if (f[1] != "" && !(f[3] in pw)) pw[f[3]] = f[1] }

  np = 0; nu = 0; nsvc = 0
  for (a = 1; a < ARGC; a++) {
    d = ARGV[a]
    base = d; sub(/.*\//, "", base)
    if (d ~ /\.service$/) {
      # A unit has a cgroup under system.slice while it runs.
      nsvc++
      mx = rd(d "/memory.max")
      if (RDN == 0 || mx !~ /^[0-9]+$/ || mx + 0 == 0) continue
      cur = rd(d "/memory.current") + 0
      pk = rd(d "/memory.peak"); haspk = (RDN > 0 && pk ~ /^[0-9]+$/)
      nu++; uname[nu] = base; umem[nu] = cur; umax[nu] = mx + 0; upk[nu] = (haspk ? pk + 0 : -1)
      uratio[nu] = cur / mx; utie[nu] = nu
      continue
    }
    if (base !~ /^[0-9]+$/) continue
    # A process can end between the listing and these reads: then a file is empty, skip it.
    st = rd(d "/stat"); if (RDN == 0) continue
    sm = rd(d "/statm"); if (RDN == 0) continue
    # The name is between the first ( and the LAST ): it can hold spaces, parentheses, a newline.
    p = index(st, "("); if (!p) continue
    if (!match(st, /\)[^)]*$/)) continue
    comm = substr(st, p + 1, RSTART - p - 1)
    nf = split(substr(st, RSTART + 2), r, " "); if (nf < 20) continue
    ut = r[12] + r[13]; start = r[20] + 0
    split(sm, m, " ")
    uid = ""
    ns = split(rd(d "/status"), S, "\n")
    for (i = 1; i <= ns; i++) if (S[i] ~ /^Uid:/) { split(S[i], f, " "); uid = f[2]; break }

    dt = 0
    if (!warming) {
      if ((base in pst) && pst[base] == start) dt = ut - pti[base]
      else if (start > pup * HZ) dt = ut
    }
    if (dt < 0) dt = 0
    print "P", base, start, ut > STATE_TMP
    np++
    ppid[np] = base + 0; pname[np] = comm
    puser[np] = (uid in pw ? pw[uid] : (uid == "" ? "?" : uid))
    prss[np] = m[2] * PAGE
    pcpu[np] = (warming ? 0 : dt / HZ / el * 100)
    pmem[np] = prss[np]
  }
  close(STATE_TMP)

  # Units: biggest share of their limit first.
  unit_json = ""
  pick(uratio, utie, nu, 12)
  for (j = 1; j <= SELN; j++) {
    i = SEL[j]
    unit_json = unit_json (j > 1 ? "," : "") sprintf("{\"unit\":\"%s\",\"mem\":%.0f,\"max\":%.0f", esc(uname[i]), umem[i], umax[i])
    if (upk[i] >= 0) unit_json = unit_json sprintf(",\"peak\":%.0f", upk[i])
    unit_json = unit_json "}"
  }

  dtot = 0; dused = 0
  cmd = "df -kP " DFPATH " 2>/dev/null"
  if ((cmd | getline hdr) > 0 && (cmd | getline line) > 0) { split(line, f, " "); dtot = f[2] * 1024; dused = f[3] * 1024 }
  close(cmd)

  # The counts of what this generation runs. Nix wrote the file, but each line is still checked:
  # a short lowercase key and a whole number, 24 lines at most, the first of a key wins.
  inv_json = ""; ninv = 0
  if (INVENTORY != "") {
    nl = split(rd(INVENTORY), L, "\n")
    for (i = 1; i <= nl && ninv < 24; i++) {
      if (split(L[i], f, " ") != 2 || f[1] !~ /^[a-z][a-z_]*$/ || length(f[1]) > 24 || f[2] !~ /^[0-9]+$/ || length(f[2]) > 9) continue
      if (f[1] in seen) continue
      seen[f[1]] = 1; ninv++
      inv_json = inv_json (ninv > 1 ? "," : "") sprintf("\"%s\":%d", f[1], f[2])
    }
  }

  top_mem = plist(pmem, np)
  top_cpu = plist(pcpu, np)

  printf "{\"v\":1,\"host\":\"%s\",\"label\":\"%s\",\"ts\":%.0f,\"interval\":%.0f,\"uptime_s\":%.0f,\"vcpus\":%d,", esc(NAME), esc(LABEL), TS, INTERVAL, up, vcpus
  printf "\"load\":[%.2f,%.2f,%.2f],", la[1], la[2], la[3]
  printf "\"cpu\":{\"total_pct\":%.1f,\"cores\":[%s]%s},", total_pct, cores, (warming ? ",\"warming\":true" : "")
  printf "\"mem\":{\"total\":%.0f,\"used\":%.0f,\"available\":%.0f,\"swap_total\":%.0f,\"swap_used\":%.0f},", mi["MemTotal:"], mem_used, mi["MemAvailable:"], mi["SwapTotal:"], swap_used
  printf "\"disk\":{\"root_total\":%.0f,\"root_used\":%.0f},", dtot, dused
  printf "\"mem_detail\":{\"buffers\":%.0f,\"cached\":%.0f,\"shmem\":%.0f,\"dirty\":%.0f},", mi["Buffers:"], mi["Cached:"], mi["Shmem:"], mi["Dirty:"]
  printf "\"tasks\":{\"threads\":%d,\"running\":%d,\"blocked\":%d,\"forks_per_s\":%.1f,\"ctxt_per_s\":%.0f},", threads, ks["procs_running"], ks["procs_blocked"], rate(ks["processes"], pk_fork, has_pk), rate(ks["ctxt"], pk_ctxt, has_pk)
  if (fds >= 0) printf "\"fds_open\":%d,", fds
  if (has_net) printf "\"net\":{\"rx_bps\":%.0f,\"tx_bps\":%.0f,\"rx_total\":%.0f,\"tx_total\":%.0f},", rate(rx, pn_rx, has_pn), rate(tx, pn_tx, has_pn), rx, tx
  if (sock != "") printf "\"sockets\":{%s},", sock
  if (has_dio) printf "\"disk_io\":{\"read_bps\":%.0f,\"write_bps\":%.0f,\"read_total\":%.0f,\"write_total\":%.0f},", rate(drd, pd_rd, has_pd), rate(dwr, pd_wr, has_pd), drd, dwr
  if (psi != "") printf "\"pressure\":{%s},", psi
  printf "\"procs_total\":%d,\"services_running\":%d,", np, nsvc
  if (INVENTORY != "") printf "\"inventory\":{%s},", inv_json
  printf "\"top_mem\":[%s],\"top_cpu\":[%s],\"units\":[%s]}\n", top_mem, top_cpu, unit_json
}
' "$@" > "$tmp_out"

# The state first: a crash between the two moves costs one sample, never a wrong number.
mv -f "$tmp_state" "$state"
mv -f "$tmp_out" "$out"
