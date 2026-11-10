# The metrics file, schema version 1

`collect.sh` writes one file for each host, `/run/metrics-web/<name>.json`, every 10 seconds, and
never a half file: it writes a temp file in the same folder and renames it. The page reads it at
`/data/<name>.json`. The file stays under 8 KB.

A reader must ignore keys it does not know and survive keys that are missing. A new key that old
readers can ignore does not change `v`. A change of meaning, or a key that must go, makes `v` 2.

```json
{
  "v": 1,
  "host": "piabrota2",
  "label": "piabrota2 (KVM 4)",
  "ts": 1793925130,
  "interval": 10,
  "uptime_s": 175741,
  "vcpus": 4,
  "load": [0.61, 0.27, 0.10],
  "cpu": { "total_pct": 1.2, "cores": [1.8, 0.4, 1.1, 1.5] },
  "mem": { "total": 16770539520, "used": 2028146688, "available": 14742392832,
           "swap_total": 8384933888, "swap_used": 3432448 },
  "disk": { "root_total": 211280117760, "root_used": 46531555328 },
  "mem_detail": { "buffers": 192512000, "cached": 1600000000, "shmem": 9306112, "dirty": 2640000 },
  "tasks": { "threads": 412, "running": 2, "blocked": 0, "forks_per_s": 3.1, "ctxt_per_s": 2140 },
  "fds_open": 2816,
  "net": { "rx_bps": 48200, "tx_bps": 131000, "rx_total": 91000000000, "tx_total": 240000000000 },
  "sockets": { "tcp": 58, "tcp_tw": 21, "udp": 6 },
  "disk_io": { "read_bps": 4096, "write_bps": 286720, "read_total": 19000000000, "write_total": 42000000000 },
  "pressure": { "cpu": { "some": 1.2, "full": 0 }, "memory": { "some": 0, "full": 0 },
                "io": { "some": 0.4, "full": 0.3 } },
  "procs_total": 127,
  "top_mem": [ { "pid": 826708, "name": "hermes", "user": "hermes", "rss": 431386624, "cpu_pct": 0.3 } ],
  "top_cpu": [ { "pid": 826708, "name": "hermes", "user": "hermes", "rss": 431386624, "cpu_pct": 0.3 } ],
  "units": [ { "unit": "hermes-agent.service", "mem": 432435200, "max": 8589934592, "peak": 448835584 } ]
}
```

| Key | Meaning |
|---|---|
| `v` | Schema version, 1. |
| `host` | The name the file is for: `piabrota` or `piabrota2` (`piabrota.metrics.name`). Not the hostname. |
| `label` | What the page calls the host. |
| `ts` | Unix seconds when the run started. The page marks the host offline when this is more than 30 s old. |
| `interval` | Seconds between runs, as set by `piabrota.metrics.collector.interval`. |
| `uptime_s` | Seconds since boot (`/proc/uptime`). |
| `vcpus` | Number of `cpuN` lines in `/proc/stat`. |
| `load` | 1, 5 and 15 minute load average. |
| `cpu.total_pct` | Busy share of all vCPUs together, 0 to 100, between this run and the last. Busy is everything but idle and iowait. |
| `cpu.cores` | The same for each vCPU, in order. |
| `cpu.warming` | `true` only on the first run after a boot or a lost state: the CPU numbers are 0 then. Absent otherwise. |
| `mem.total`, `mem.available` | `MemTotal` and `MemAvailable`, in bytes. |
| `mem.used` | `MemTotal` minus `MemAvailable`, in bytes. |
| `mem.swap_total`, `mem.swap_used` | Swap, in bytes. |
| `disk.root_total`, `disk.root_used` | The filesystem of `/`, in bytes (`df`). |
| `mem_detail.buffers`, `.cached`, `.shmem`, `.dirty` | `Buffers`, `Cached`, `Shmem` and `Dirty` of `/proc/meminfo`, in bytes (0 when absent). |
| `tasks.threads` | Threads and processes the kernel schedules (the total of field 4 of `/proc/loadavg`). |
| `tasks.running`, `tasks.blocked` | `procs_running` and `procs_blocked` of `/proc/stat`. |
| `tasks.forks_per_s`, `tasks.ctxt_per_s` | New processes and context switches per second since the last run (`processes`, `ctxt` of `/proc/stat`). 0 on a first run. |
| `fds_open` | Open file handles of the system (first field of `/proc/sys/fs/file-nr`). Absent when it cannot be read. |
| `net.rx_bps`, `net.tx_bps` | Bytes per second received and sent since the last run, summed over every interface but `lo`, from `/proc/1/net/dev` (PID 1's namespace: the collector has `PrivateNetwork`). 0 on a first run or after a counter went back. |
| `net.rx_total`, `net.tx_total` | The same counters since boot, in bytes. `net` is absent when the file cannot be read. |
| `sockets.tcp`, `sockets.tcp_tw`, `sockets.udp` | TCP sockets in use and in TIME-WAIT, UDP sockets in use (`/proc/1/net/sockstat`). Absent when it cannot be read. |
| `disk_io.read_bps`, `disk_io.write_bps` | Bytes per second read and written since the last run, summed over whole disks (`sd*`, `vd*`, `xvd*`, `nvme*n*`; partitions and loops do not count), from `/proc/diskstats` sectors of 512 bytes. |
| `disk_io.read_total`, `disk_io.write_total` | The same since boot. `disk_io` is absent when no whole disk is listed. |
| `pressure.cpu`, `.memory`, `.io` | Pressure stall information: `some` (and `full`) is the `avg10` of `/proc/pressure/<name>`, the percent of the last 10 s that some (all) tasks waited for it. Absent when the kernel has no PSI. |
| `procs_total` | Processes read this run. It counts kernel threads. |
| `top_mem` | The 10 processes with the largest resident memory, biggest first; a tie goes to the lower pid. |
| `top_cpu` | The 10 processes with the largest `cpu_pct`, same order rule. |
| `top_*[].pid` | Process id. |
| `top_*[].name` | `comm` only, at most 15 characters. Printable ASCII: any other byte is `?`. Never a command line. |
| `top_*[].user` | The user name from `/etc/passwd`, else the uid as text, else `?`. |
| `top_*[].rss` | Resident memory in bytes (`statm`, pages times page size). |
| `top_*[].cpu_pct` | CPU time (user and system) used since the last run, as a percent of **one** vCPU: it can pass 100 on a busy multi-core process. An average over the interval, not an instant value. A process that began inside the interval counts all its time; the first run shows 0. |
| `units` | Services of `system.slice` that have a numeric `MemoryMax`, at most 12, the largest `mem/max` first. `[]` when the cgroup tree cannot be read. |
| `units[].unit` | The unit name. |
| `units[].mem`, `units[].max` | `memory.current` and `memory.max`, in bytes. |
| `units[].peak` | `memory.peak` in bytes. Absent when the kernel has no such file. |

## How the collector computes the numbers

- Rates (forks, context switches, network, disk IO): the counters of the last run are kept in the same
  state file (lines `K`, `N`, `D`), divided by the seconds between the runs.
- CPU: two samples of `/proc/stat`. The first is kept in `/run/metrics-state/<name>.state`, so a run
  never sleeps.
- Per process: the difference of `utime + stime` (fields 14 and 15 of `/proc/<pid>/stat`) divided by
  the clock ticks (`getconf CLK_TCK`) and by the seconds between the runs (from `/proc/uptime`). The
  key is the pid and the start time (field 22), so a reused pid starts at 0. The line is parsed after
  its LAST `)`, because a name can hold spaces and parentheses.
- A process that ends while it is read has an empty file: it is skipped, with no error.
- Every string goes through `esc` in `collect.sh`: a backslash or a quote gets a backslash, and any
  byte outside printable ASCII becomes `?`. `test/run.sh` has a check that a naive escaper breaks
  the JSON.
