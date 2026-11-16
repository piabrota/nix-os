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
- At the top: the sites that answer (green) and those that do not (red), the commits, the deploys,
  the apps installed and the NixOS version ("The headline", below).
- What this generation runs: the counts of "The inventory", below.

How to read the numbers:

- The CPU of a process is the average over the last interval (about 10 s), in percent of ONE vCPU.
  So it can pass 100.
- The process name is `comm` only (up to 15 characters, printable ASCII; the rest becomes `?`).
- On the first run after boot the page says `warming` and CPU is 0.

It does not show: history beyond the samples in the tab (samples come per new file, every 10 s, so
about 10 minutes), disk usage of filesystems other than `/`, network or IO per process or per interface, alerts, command lines.

## The headline: sites, commits, deploys, apps, NixOS

The top of each card has six numbers and a row of sites:

| Label | What it is | Where it comes from |
|---|---|---|
| Domains up | sites that answered, of the host's sites; green when all answer, red when one does not | `piabrota metrics-probe`, every 60 s |
| Visits 24 h | the pages that browsers got from the host's sites in the last 24 hours | nginx's `visits.log`, read by the probe every 60 s (see "Visits") |
| Visitors 24 h | the different addresses that got those pages | the same |
| Commits | commits on `main` of `piabrota/nix-os` | the GitHub API, at most once in 10 minutes |
| Deploys | the generation of `/nix/var/nix/profiles/system`: one for each deploy that changed the system | the collector, from the link `system-<n>-link` |
| Apps installed | the packages of `environment.systemPackages` (the `packages` count of the inventory) | Nix, at build time |
| NixOS | the release, for example 26.05; the full version is in the tooltip | `/run/current-system/nixos-version` |

Under them, each site of the host is a chip: green when it answers, red with the HTTP code (or
"no answer") when it does not. A site is up when it gives any answer below HTTP 500: a 301 or a
401 (a login) is an answer. The probe does not follow a redirect. When the probe's data is more than
5 minutes older than the host's, the chips are grey and the count is not coloured. After the name,
a chip shows the site's visitors of the last 24 hours; its tooltip has the visits.

The sites are the same names that the inventory counts as `sites`: every nginx virtual host but
`_` and the names that only redirect. Nix writes the list (`https://` when the host has TLS). The
probe (`metrics-probe.timer`, oneshot `metrics-probe.service`) asks each name with one `curl` of at
most 6 s, one after the other, and writes `/run/metrics-state/<name>.probe` (not served). The
collector copies it into `domains` and `repo` (metrics/SCHEMA.md). The probe reads the commit count
from the `Link` header of `GET /repos/piabrota/nix-os/commits?per_page=1`: the number of the last
page is the count. Without a token GitHub allows 60 requests an hour from one address; the probe
uses 6. When GitHub does not answer, the last count stays.

## Visits

What counts, with `visits.enable` on (both hosts):

- **A visit** is one page that a browser got: a `GET` that nginx answered with a 200 and an HTML
  type, or with a 304 for a path that ends in `/` or `.html`. An image, a script, the page's JSON
  polls, a redirect, a 404 and a login wall (401) are not visits.
- **Bots are not counted.** A User-Agent that is empty or that has one of the words of
  `notBrowsers` in `metrics.nix` (`bot`, `crawl`, `spider`, `curl`, `python`, `probe`, ...) is a
  program, not a browser. A scraper that sends a browser's User-Agent is counted: this is a filter
  for crawlers that say what they are, as the bot block of robots.txt is.
- **A visitor** is one address that got a page of the site. Two people behind one address are one
  visitor; one person on two sites is a visitor of each, so the card's sum counts them twice.
- **The window** is the last 24 hours, counted by the hour: the oldest hour leaves whole, so the
  window is 24 to 25 hours.

How: nginx writes one line for each visit to `/var/log/nginx/visits.log` (the time, the vhost's
first name and the address; `access_log ... if=$metrics_visit` in `services.nginx.commonHttpConfig`).
Everything else goes on to `access.log` as before: an `access_log` in the `http` block ends nginx's
built-in default, so the module writes that line too. nginx's logrotate rule rotates both weekly.
Each probe run reads only what was added since the last run (at most 16 MiB) and keeps the views by
the hour and the last time of each address in `/run/metrics-state/<name>.visits` (0700, not
served, gone at a reboot). After a reboot or a rotation it reads the file from its start, so a
reboot loses nothing of the week. The probe reads nginx's logs through the group `nginx`
(`SupplementaryGroups`) and writes nothing there. No daemon, no package: the same binary.

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

- The collector is `piabrota metrics-collect` (`scala/metrics/Collect.scala`), a command of the
  scripts' Scala Native binary (`scala/README.md`). The timer `metrics-collect.timer` runs
  it every 10 s (oneshot unit `metrics-collect.service`).
- It writes `/run/metrics-web/<name>.json` atomically. The previous sample is in
  `/run/metrics-state/<name>.state` (not served).
- The names are `piabrota` and `piabrota2` (option `piabrota.metrics.name`). Never the hostname:
  piabrota2's hostname is still `nixos`.
- It reads only `/proc`, `/sys/fs/cgroup`, `/etc/passwd`, `df`, the inventory file in the store, the
  probe's file, the link of the system profile and `/run/current-system/nixos-version`.
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

## For machines: all.json and /metrics

The page's host (piabrota2) also serves every number in two forms that a program reads:

| Address | Format | What is in it |
|---|---|---|
| https://metrics.piabrota.art/data/all.json | JSON | `{"v":1,"ts":..,"stale_after_s":30,"hosts":{"piabrota":{"age_s":..,"fresh":..,"data":{..}},"piabrota2":{..}}}`: each host's file as it is (metrics/SCHEMA.md), with its age |
| https://metrics.piabrota.art/metrics | Prometheus text, version 0.0.4 | the same numbers as series named `piabrota_*`, each with a `host` label |
| https://metrics.piabrota.art/data/piabrota.json, `/data/piabrota2.json` | JSON | one host's file, as before |

`piabrota metrics-export` (`scala/metrics/Export.scala`) writes the first two in one run; the
binary needs only glibc, so no Python or JVM runs on the box (AGENTS.md, "Resource budget", rule 4).
The timer `metrics-export.timer` runs it with the collector's interval, in the collector's sandbox and with no
network: it reads `/run/metrics-web/<name>.json` and writes `all.json` and `metrics.prom`
beside them, each through a temp file and a rename. It leaves out a file that is not a JSON object,
that is over 64 KiB or whose `host` is not its name. A number that is not finite is left out of
`/metrics`. The option is
`piabrota.metrics.export.enable`, on by default where `web.enable` is on.

The Prometheus series:

| Series | Labels | From |
|---|---|---|
| `piabrota_host_fresh`, `piabrota_sample_age_seconds`, `piabrota_sample_timestamp_seconds` | `host` | `ts`; fresh is an age of 30 s or less |
| `piabrota_uptime_seconds`, `piabrota_vcpus`, `piabrota_load` | `window` | `uptime_s`, `vcpus`, `load` |
| `piabrota_cpu_busy_percent` | `cpu` (`total`, `0`, `1`..) | `cpu` |
| `piabrota_memory_bytes` | `kind` | `mem`, `mem_detail` |
| `piabrota_root_filesystem_bytes` | `kind` | `disk` |
| `piabrota_threads`, `piabrota_tasks`, `piabrota_forks_per_second`, `piabrota_context_switches_per_second`, `piabrota_open_files`, `piabrota_processes`, `piabrota_services_running` | `state` | `tasks`, `fds_open`, `procs_total`, `services_running` |
| `piabrota_network_bytes_per_second`, `piabrota_network_bytes_total` | `direction` | `net` |
| `piabrota_sockets` | `kind` | `sockets` |
| `piabrota_disk_bytes_per_second`, `piabrota_disk_bytes_total` | `direction` | `disk_io` |
| `piabrota_pressure_percent` | `resource`, `kind` | `pressure` |
| `piabrota_inventory` | `item` | `inventory` |
| `piabrota_deploy_generation`, `piabrota_nixos_info` | `version` | `system` |
| `piabrota_sites`, `piabrota_probe_timestamp_seconds` | `state` | `domains` |
| `piabrota_site_up`, `piabrota_site_http_code`, `piabrota_site_views_24h`, `piabrota_site_visitors_24h` | `site` | `domains.list` |
| `piabrota_repo_commits` | `repo` | `repo` |
| `piabrota_unit_memory_bytes`, `piabrota_unit_memory_max_bytes`, `piabrota_unit_memory_peak_bytes` | `unit` | `units` |
| `piabrota_hosts`, `piabrota_export_timestamp_seconds` | none | the export itself |

The top processes stay in the JSON only: a pid is a new series at each run. Nothing on the boxes
scrapes `/metrics`; it is there for a Prometheus or a Grafana elsewhere. Both addresses have the
page's rules: public, `no-store`, the rate limit and the agent block.

## What is not measured

- **Google Analytics.** `piabrota.site.analytics.measurementId` (site.nix) puts Google's tag on
  www.piabrota.art, and it is empty on both hosts: no page loads the tag, and Google has no data.
  To turn it on, a person makes a GA4 property and a web data stream for `https://www.piabrota.art`
  at https://analytics.google.com (Admin, Create, Property, then Data streams, Web), and sets the
  `G-...` ID in `hosts/piabrota/default.nix`. Reading its numbers back into this page needs a
  service account with the Viewer role on the property and its JSON key on piabrota2, outside git;
  no reader is in this repository yet. The nginx visits (above) count without it.
- **The sites of other hosts.** GitHub Pages, Cloudflare or any name that nginx on the two boxes
  does not serve is not probed and has no visits.
- **History.** The page keeps the samples in the tab, and the files hold the last sample only. A
  history needs a Prometheus that scrapes `/metrics`.

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
- The export (piabrota2 only), measured in a cloud container on the two live files of 2026-11-13:
  0.04 s of CPU and 13 MB peak RSS a run, so about 0.4 % of one vCPU at 10 s. Not measured on the box.

## Hardening

The units (collector, probe, pull) run as `metrics` with:

- `ProtectSystem=strict`, with `ReadWritePaths` of the two `/run` folders only.
- `MemoryMax=64M`, `NoNewPrivileges`, an empty capability set and a syscall filter.
- The probe is the one unit of a host that opens a connection (the pull is the other, on
  piabrota2): its sandbox is the same, with `AF_INET` and `AF_INET6`.
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
| `probe.enable`, `probe.interval` | the timer that asks each site for an answer (10 to 3600 s, default 60); needs the collector |
| `visits.enable` | nginx logs each page a browser gets, and the probe counts the visits of the last 24 h of each site; needs the probe and nginx |
| `probe.repo`, `probe.branch` | the repository and branch whose commits are counted (default `piabrota/nix-os`, `main`); an empty repo: no count |
| `web.enable`, `web.domain`, `web.htpasswdFile` | the page on nginx, the domain and the optional login file (`null`, the default, means the page is public) |
| `publish.enable`, `publish.allowFrom` | the KVM 1 location and the address that may read it |
| `pull.enable`, `pull.url`, `pull.name` | the timer that fetches the file of the other host |
| `export.enable` | the timer that writes `all.json` and `metrics.prom` ("For machines"); on by default with `web.enable` |
| `inventory.bundledSkillDirs` | folders of skills that ship inside an agent, counted as `skills_bundled`; `hermes.nix` adds Hermes's own |

Today: piabrota2 turns on collector, probe, visits, web, pull and (with web) export. piabrota turns on collector, probe, visits and publish.

## Change the cadence

Change `piabrota.metrics.collector.interval` (in seconds) in the host file. The offline limit of
the page is 30 s, the constant `STALE_S` in `metrics/index.html`. So keep the interval at 10 or
lower, or change that constant too.

## Tests and preview

- `scala/metrics/*.test.scala` (`just scala-test`, and the Nix build of the binary): the collector
  and the probe, with a fixture `/proc` and cgroup tree and a fake curl, and the export: `all.json`
  and `metrics.prom` from the fixtures, checked line by line against the text format.
- `checks.metrics-page` (`metrics/test/page.nix`): the static rules of the page, in pure Nix, and
  the fixtures through jq. `piabrota metrics-preview --check`: an HTTP fetch of the page and its
  data. `just metrics-test` runs these two.
- `checks.metrics`: four VMs (hub, edge, locked, client), plain HTTP, needs KVM:
  `nix build .#checks.x86_64-linux.metrics`.
- Preview of the page with fixtures (healthy, stale, missing, hostile):

  ```console
  nix run .#piabrota -- metrics-preview healthy 8080   # open http://127.0.0.1:8080/
  just metrics-preview healthy
  ```
