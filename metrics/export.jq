# Every host's file as one all.json (the first line out) and as the Prometheus text format, 0.0.4
# (the rest). The inputs are the host files that export.sh checked: each a JSON object whose "host" is
# its file name. Any key may be missing or of the wrong type; a number that is not finite is left out.
# Arguments: $now and $stale (numbers). Run with -r.

def ok: type == "number" and (isinfinite | not) and (isnan | not);
def o($k): (if type == "object" then .[$k] else null end) | if type == "object" then . else {} end;
def a($k): (if type == "object" then .[$k] else null end) | if type == "array" then map(select(type == "object")) else [] end;
def flag: if . == true then 1 elif . == false then 0 else null end;
def text: tostring | .[0:128] | gsub("\\\\"; "\\\\") | gsub("\""; "\\\"") | gsub("\n"; "\\n");

# One sample: name, type, help, labels, value. Nothing when the value is not a finite number.
def s($n; $t; $h; $l; $v): if ($v | ok) then {n: ("piabrota_" + $n), t: $t, h: $h, l: $l, v: $v} else empty end;
def g($n; $h; $l; $v): s($n; "gauge"; $h; $l; $v);

def age: (.ts | if ok then ([0, ($now - .)] | max | floor) else null end);

def series($host):
  . as $d | {host: $host} as $h | ($d | age) as $age |
  g("host_fresh"; "1 when the host's file is newer than the stale limit"; $h; (if $age == null then 0 elif $age <= $stale then 1 else 0 end)),
  g("sample_age_seconds"; "Seconds since the host's last sample"; $h; $age),
  g("sample_timestamp_seconds"; "Unix time of the host's last sample"; $h; $d.ts),
  g("uptime_seconds"; "Seconds since boot"; $h; $d.uptime_s),
  g("vcpus"; "Number of vCPUs"; $h; $d.vcpus),
  (($d.load | if type == "array" then . else [] end) as $l
    | range(0; [3, ($l | length)] | min) as $i
    | g("load"; "Load average"; $h + {window: (["1m", "5m", "15m"][$i])}; $l[$i])),
  ($d | o("cpu")) as $c
  | g("cpu_busy_percent"; "Busy share of the vCPUs over the last interval"; $h + {cpu: "total"}; $c.total_pct),
    (($c.cores | if type == "array" then . else [] end) | to_entries[]
      | g("cpu_busy_percent"; "Busy share of the vCPUs over the last interval"; $h + {cpu: (.key | tostring)}; .value)),
  ((($d | o("mem")) + ($d | o("mem_detail"))) | to_entries[]
    | g("memory_bytes"; "Memory and swap, from /proc/meminfo"; $h + {kind: .key}; .value)),
  (($d | o("disk")) as $k
    | g("root_filesystem_bytes"; "The filesystem of /"; $h + {kind: "total"}; $k.root_total),
      g("root_filesystem_bytes"; "The filesystem of /"; $h + {kind: "used"}; $k.root_used)),
  (($d | o("tasks")) as $k
    | g("threads"; "Threads and processes the kernel schedules"; $h; $k.threads),
      g("tasks"; "Tasks running or blocked"; $h + {state: "running"}; $k.running),
      g("tasks"; "Tasks running or blocked"; $h + {state: "blocked"}; $k.blocked),
      g("forks_per_second"; "New processes per second"; $h; $k.forks_per_s),
      g("context_switches_per_second"; "Context switches per second"; $h; $k.ctxt_per_s)),
  g("open_files"; "Open file handles"; $h; $d.fds_open),
  g("processes"; "Processes, kernel threads included"; $h; $d.procs_total),
  g("services_running"; "Services with a cgroup under system.slice"; $h; $d.services_running),
  (($d | o("net")) as $k | ("rx", "tx") as $x
    | g("network_bytes_per_second"; "Network bytes per second, every interface but lo"; $h + {direction: $x}; $k[$x + "_bps"]),
      s("network_bytes_total"; "counter"; "Network bytes since boot, every interface but lo"; $h + {direction: $x}; $k[$x + "_total"])),
  (($d | o("sockets")) | to_entries[]
    | g("sockets"; "Sockets: tcp in use, tcp in TIME-WAIT, udp in use"; $h + {kind: .key}; .value)),
  (($d | o("disk_io")) as $k | ("read", "write") as $x
    | g("disk_bytes_per_second"; "Disk bytes per second, whole disks"; $h + {direction: $x}; $k[$x + "_bps"]),
      s("disk_bytes_total"; "counter"; "Disk bytes since boot, whole disks"; $h + {direction: $x}; $k[$x + "_total"])),
  (($d | o("pressure")) | to_entries[] | .key as $r | (.value | if type == "object" then . else {} end) | to_entries[]
    | g("pressure_percent"; "Pressure stall, avg10"; $h + {resource: $r, kind: .key}; .value)),
  (($d | o("inventory")) | to_entries[]
    | g("inventory"; "What the deployed configuration declares"; $h + {item: .key}; .value)),
  (($d | o("system")) as $k
    | g("deploy_generation"; "Generation of the system profile: one per deploy"; $h; $k.generation),
      (if ($k.nixos | type) == "string" then g("nixos_info"; "The NixOS version, as a label"; $h + {version: $k.nixos}; 1) else empty end)),
  (($d | o("domains")) as $k
    | g("sites"; "Sites of the host: total and up"; $h + {state: "total"}; $k.total),
      g("sites"; "Sites of the host: total and up"; $h + {state: "up"}; $k.up),
      g("probe_timestamp_seconds"; "Unix time of the last probe"; $h; $k.ts),
      ($k | a("list")[] | ($h + {site: (.name // "?")}) as $l
        | g("site_up"; "1 when the site answered below HTTP 500"; $l; (.up | flag)),
          g("site_http_code"; "The site's HTTP code, 0 for no answer"; $l; .code),
          g("site_views_24h"; "Pages browsers got from the site in the last 24 h"; $l; .views),
          g("site_visitors_24h"; "Distinct addresses that got a page in the last 24 h"; $l; .visitors))),
  (($d | o("repo")) as $k
    | if ($k.name | type) == "string" then g("repo_commits"; "Commits on the counted branch"; $h + {repo: $k.name}; $k.commits) else empty end),
  ($d | a("units")[] | ($h + {unit: (.unit // "?")}) as $l
    | g("unit_memory_bytes"; "memory.current of a unit with a MemoryMax"; $l; .mem),
      g("unit_memory_max_bytes"; "MemoryMax of the unit"; $l; .max),
      g("unit_memory_peak_bytes"; "memory.peak of the unit"; $l; .peak));

def line: .n + (if (.l | length) > 0 then "{" + (.l | to_entries | map("\(.key)=\"\(.value | text)\"") | join(",")) + "}" else "" end) + " " + (.v | tostring);

reduce inputs as $d ({}; .[$d.host] = $d)
| . as $hosts
# Line 1: all.json, compact. The rest: the Prometheus text.
| ({v: 1, ts: ($now | floor), stale_after_s: $stale,
     hosts: (with_entries(.value |= ((. | age) as $age | {age_s: $age, fresh: ($age != null and $age <= $stale), data: .})))}
   | tojson),
  ([($hosts | to_entries[] | .key as $n | .value | series($n)),
     g("hosts"; "Host files read"; {}; ($hosts | length)),
     g("export_timestamp_seconds"; "Unix time this file was written"; {}; ($now | floor))]
    | group_by(.n)
    | map("# HELP \(.[0].n) \(.[0].h)\n# TYPE \(.[0].n) \(.[0].t)\n" + (map(line) | join("\n")))
    | join("\n"))
