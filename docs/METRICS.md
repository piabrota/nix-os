# Metrics page

[Português](METRICS.ptBR.md)

A small home-made page shows the metrics of the two machines almost live. It is at
https://metrics.piabrota.art, on piabrota2. The module is `metrics.nix`. Everything is off by
default; each host turns on what is its own. The data file format is in
[metrics/SCHEMA.md](../metrics/SCHEMA.md).

## What it shows and what it does not

The page is a static `metrics/index.html` (under 20 KB, no external request, vanilla JS). Every 5 s
it reads `/data/piabrota.json` and `/data/piabrota2.json` and keeps the last 60 samples in the
memory of the tab only.

It shows, for each host:

- CPU, used memory (MemTotal minus MemAvailable) and the disk of `/`.
- The 10 processes that use the most memory (RSS) and the 10 that use the most CPU.
- The systemd units under `system.slice` that have a numeric `MemoryMax` (hermes-agent 8G,
  hermes-backend 2G, openrig 2G, pgx 256M...), at most 12, sorted by memory over max. `memory.peak`
  is shown when the kernel has it.
- The total of processes (it counts kernel threads), threads, tasks running and blocked, forks
  and context switches per second, open files, and the services that run now (each service with a cgroup under
  `system.slice`).
- The memory detail: page cache, buffers, shmem and dirty pages.
- Network in and out per second (every interface but `lo`), TCP sockets (in use, TIME-WAIT) and UDP
  sockets.
- Disk read and write per second, summed over whole disks (`sda`, `vda`, `nvme0n1`; no
  partitions).
- Pressure stall (PSI) of CPU, memory and IO: the share of the last 10 s that tasks waited
  (`some` / `full`).
- What this generation runs: the counts of "The inventory", below.

How to read the numbers:

- The CPU of a process is the average over the last interval (about 10 s), in percent of ONE vCPU.
  So it can pass 100.
- The process name is `comm` only (up to 15 characters, printable ASCII; the rest becomes `?`).
- On the first run after boot the page says `warming` and CPU is 0.

It does not show: history beyond the samples in the tab (samples come per new file, every 10 s, so
about 10 minutes), disk usage of filesystems other than `/`, network or IO per process or per interface, alerts, command lines.

## The inventory

Each card has a block "What this generation runs". Nix counts it once, when it builds the system,
from the configuration that the host runs; nothing is counted on the box. A deploy changes it.

| Key | Label | What it counts |
|---|---|---|
| `apps` | Loco apps | `piabrota.loco.apps` |
| `sites` | Sites | nginx virtual hosts, without the default `_` and the names that only redirect |
| `rigs` | Rigs | the rig specs in `/etc/openrig/specs/rigs`, when OpenRig is on |
| `agents` | Rig agents | the agent specs in `/etc/openrig/specs/agents`, without the `*shared` folders |
| `skills` | Skills | the `SKILL.md` files in Hermes's skill folders (`skills.external_dirs`) and plugins |
| `skills_bundled` | Bundled skills | the `SKILL.md` files that ship inside Hermes (`piabrota.metrics.inventory.bundledSkillDirs`) |
| `plugins` | Plugins | `settings.plugins.enabled` of Hermes |
| `mcp` | MCP servers | `mcpServers` of Hermes |
| `packages` | Packages | `environment.systemPackages` |
| `timers` | Timers | the systemd timers that are on |

A module that a host does not import counts 0: piabrota has no Hermes and no OpenRig. These are
declared counts. Hermes can also make skills of its own at run time, in `/var/lib/hermes`; the
collector cannot read that folder (its user is not in the `hermes` group, on purpose), so those
skills are not in the count. `metrics.nix` writes the counts to a file in the store and the collector
copies them into `inventory` (metrics/SCHEMA.md).

## The two hosts and who runs what

| Host | Collector | Page (nginx) | Pull | Publish |
|---|---|---|---|---|
| piabrota2 (KVM 4) | yes | yes | yes | no |
| piabrota (KVM 1) | yes | no | no | yes |

- The collector is `metrics/collect.sh` (POSIX sh and awk). The timer `metrics-collect.timer` runs
  it every 10 s (oneshot unit `metrics-collect.service`).
- It writes `/run/metrics-web/<name>.json` atomically. The previous sample is in
  `/run/metrics-state/<name>.state` (not served).
- The names are `piabrota` and `piabrota2` (option `piabrota.metrics.name`). Never the hostname:
  piabrota2's hostname is still `nixos`.
- It reads only `/proc`, `/sys/fs/cgroup`, `/etc/passwd`, `df` and the inventory file in the store.
  Never a command line.
- The JSON file is under 8 KB (schema v1).

## The data path of KVM 1

piabrota has the collector and ONE extra location on the `www.piabrota.art` vhost:
`= /_metrics/piabrota.json`, with `allow 187.41.117.18; deny all;`. That is the public IPv4 of
piabrota2 (option `piabrota.metrics.publish.allowFrom`).

On piabrota2, the timer `metrics-pull.timer` (every 10 s) runs `metrics-pull.service`. It does
`curl -4 -sf --max-time 5 --max-filesize 65536` of
`https://www.piabrota.art/_metrics/piabrota.json`. It checks that the file starts with `{` and says
`"host":"piabrota"`. Then it writes `/run/metrics-web/piabrota.json` atomically.

If the fetch fails, the old file stays (the unit exits 0). The page then goes stale and then
offline.

The allow list is not a secret and is enough, because the file holds no command line, no secret and
no user data beyond process names, user names, and memory and CPU numbers. Its limit: anyone who can
send from piabrota2's address (a process on piabrota2, or a network position that can spoof) can
read the file. IPv4 only. If piabrota2's address changes, change `allowFrom` in
`hosts/piabrota/default.nix`.

## DNS and access

- The DNS of `metrics.piabrota.art` already points at piabrota2: nothing to do.
- nginx on piabrota2 serves the domain with `forceSSL` and ACME.
- The page is public. A visitor needs no login.
- A visitor can read the page and the files in `/data/`. These fields are public:
  - the host name and label, the time of the sample, the uptime, the number of vCPUs and the load;
  - the CPU use (total and for each vCPU), memory and swap (total, used, available) and the disk
    use of `/`;
  - the number of processes and of running services;
  - the inventory: how many Loco apps, sites, rigs, rig agents, skills, plugins, MCP servers,
    packages and timers the configuration declares;
  - for the 10 top processes by memory and the 10 top by CPU: pid, process name (`comm`), user
    name, RSS and CPU percent;
  - for up to 12 systemd units: unit name, memory now, `MemoryMax` and peak memory.
- The data holds no secret and no command line. It does show which services run and how busy the
  host is. That gives no way in, but an attacker can read it.
- `/data/` is served from `/run/metrics-web/` with `Cache-Control: no-store`.
- Limits for each address: 10 requests a second (burst of 30) and 20 open requests. Over a limit,
  nginx answers 429.
- To put the login back, set `piabrota.metrics.web.htpasswdFile` to a path in the host file, for
  example `"/var/lib/hermes-web-secrets/htpasswd"` (the file of the Hermes dashboard). Then every
  request, `/robots.txt` included, needs a login, and a missing file gives a 500. The default is
  `null`: no login.

## robots.txt and bot blocks

- `/robots.txt` comes from one list of named AI and scraper agents, `blockedAgents` in
  `metrics.nix`. For each agent it says `Disallow: /`. The last group, `User-agent: *`, says
  `Disallow: /` too. nginx sends it as `text/plain` with `Cache-Control` of one day. The file is in
  the Nix store.
- nginx reads the same list. It matches the `User-Agent` header and ignores the case. A listed
  agent gets a 403 on every path except `/robots.txt`, so it can still read the file that tells it
  to go away. An empty `User-Agent`, a browser, `curl` and `python-requests` are not blocked.
- Every response has `X-Robots-Tag: noindex, nofollow, noarchive, noimageindex, noai, noimageai`.
- To block one more agent, add its name to `blockedAgents`. One edit changes both the file and the
  nginx rule.
- The names come from [ai-robots-txt/ai.robots.txt](https://github.com/ai-robots-txt/ai.robots.txt)
  (`robots.json`; the commit is in the comment above the list). nginx finds a name anywhere in the
  header, so a name that is a common word (`Code`, `Dot`, `Spider`) is not in the list: it would
  block browsers and other clients. `facebookexternalhit` is not in the list, so link previews
  still work.

These steps stop well-behaved crawlers only. A scraper can change its `User-Agent` and can ignore
`robots.txt`. They are not access control. They do not protect the page from a person who wants
the data. The page is safe to expose because it holds no secret.

## When a host shows offline

The page shows a host as offline when its file is older than 30 s or the fetch fails. It says how
old the data is. To investigate, run:

```console
systemctl status metrics-collect.timer metrics-pull.timer
journalctl -u metrics-collect -u metrics-pull --since -10min
cat /run/metrics-web/piabrota.json | head -c 300      # compare "ts" with: date +%s
```

On piabrota2 look at both timers. On piabrota there is only `metrics-collect.timer`.

For the KVM 1 bridge, run this on piabrota2:

```console
curl -sI https://www.piabrota.art/_metrics/piabrota.json
```

It should say 200. From anywhere else it should say 403.

## Cost (measured)

Measured on piabrota2, with 127 processes:

- One run: 0.03 s wall, about 0.02 s CPU, 5 MB peak RSS.
- Nothing stays resident between runs.
- At a 10 s cadence that is about 0.2 % of one vCPU (about 3 minutes of CPU a day: 8,640 runs).
- On KVM 1 (1 vCPU) there are fewer processes, so it costs less.
- The unit has `MemoryMax=64M` and a fixed system user, `metrics`.

## Hardening

Both units run as `metrics` with:

- `ProtectSystem=strict`, with `ReadWritePaths` of the two `/run` folders only.
- `MemoryMax=64M`, `NoNewPrivileges`, an empty capability set and a syscall filter.
- `PrivateNetwork` on the collector. So it reads the network of PID 1 (`/proc/1/net/dev` and
  `sockstat`), readable by any user, not its own empty `/proc/net`.
- `LogLevelMax=warning`, so a run does not write journal lines.

NOT used: `ProcSubset=pid`, `ProtectProc=invisible` and `PrivateUsers`, because they hide what the
collector must read (with `PrivateUsers` user names would become numbers).

## Options

All are off by default. All live under `piabrota.metrics`:

| Option | What it does |
|---|---|
| `name`, `label` | name of the data file and label on the page |
| `collector.enable` | turns on the collector and the timer |
| `collector.interval` | seconds between runs (2 to 300, default 10) |
| `web.enable`, `web.domain`, `web.htpasswdFile` | the page on nginx, the domain and the optional login file (`null`, the default, means the page is public) |
| `publish.enable`, `publish.allowFrom` | the KVM 1 location and the address that may read it |
| `pull.enable`, `pull.url`, `pull.name` | the timer that fetches the file of the other host |
| `inventory.bundledSkillDirs` | folders of skills that ship inside an agent, counted as `skills_bundled`; `hermes.nix` adds Hermes's own |

Today: piabrota2 turns on collector, web and pull. piabrota turns on collector and publish.

## Change the cadence

Change `piabrota.metrics.collector.interval` (in seconds) in the host file. The offline limit of
the page is 30 s, the constant `STALE_S` in `metrics/index.html`. So keep the interval at 10 or
lower, or change that constant too.

## Tests and preview

- `sh metrics/test/run.sh`: the collector, with a fixture `/proc` and cgroup tree. It prints
  "N checks, M failed".
- `sh metrics/test/page.sh`: the static rules of the page and an HTTP fetch with python3.
- `checks.metrics`: four VMs (hub, edge, locked, client), plain HTTP, needs KVM:
  `nix build .#checks.x86_64-linux.metrics`.
- Preview of the page with fixtures (healthy, stale, missing, hostile):

  ```console
  sh metrics/test/preview.sh healthy 8080     # open http://127.0.0.1:8080/
  just metrics-preview healthy
  ```

  Needs python3 and jq.
