---
name: kvm4-health
description: "Check kvm4's memory, disk, CPU and the Hermes units (MemoryPeak against MemoryMax, growth with no restart), and set up the silent watchdog that alerts when the box bloats."
version: 1.0.0
author: piabrota
license: MPL-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [DevOps, Monitoring, VPS, systemd]
    related_skills: [hermes-cron]
---

# kvm4-health

You run on kvm4, a Hostinger KVM 4 VPS: 4 vCPU, 16 GB RAM, 200 GB disk by the plan (piabrota/nix-os
`AGENTS.md`, "Resource budget"). systemd caps your unit, `hermes-agent`, at `MemoryMax=8G` and
`CPUWeight=50` (nix-os `hosts/kvm4/default.nix`), the dashboard, `hermes-backend`, at 2G, and OpenRig,
`openrig`, at 3G for its daemon, tmux and every seat (nix-os `openrig.nix`). Cron
jobs run in transient scopes under the `hermes` user's slice, not in `hermes-agent`: the script
counts that slice too. Above the cap the kernel kills a process of the unit, omp first.

The script reads the numbers. It is read-only: `/proc`, `systemctl show`, `df`, `du`
and the journal. It calls no model and no network. `--record` writes one line to
`$HERMES_HOME/plugin-data/kvm4-health/samples.tsv` (two weeks, about 50 KB).

## When to Use

- The owner asks how the box is, whether Hermes is bloating, or why a turn was slow or killed.
- Before a heavy task: a large clone, a long omp run, many subagents. Check that there is room.
- The watchdog below posted a finding.
- Once, to set up the watchdog, if `hermes cron list` has no job named `kvm4-health`.

## Run it

```bash
kvm4-health            # the full report, with the sizes in HERMES_HOME
kvm4-health --alert    # only findings (what the watchdog posts)
```

`kvm4-health` is `scripts/kvm4-health.sh` of this skill, on your `PATH` with the tools it needs
(nix-os `hermes.nix`).

Each line starts with `ok`, `WARN` or `CRIT`. Exit 1 means at least one finding. Thresholds are
environment variables at the top of the script (`KH_DISK_WARN=80` and the like); set one on the
command line to test (`KH_DISK_WARN=1 kvm4-health`), never in a file. The restart count of each unit
(`NRestarts`, since the unit started) is WARN above `KH_RESTARTS_WARN=3` and CRIT above
`KH_RESTARTS_CRIT=50`. The journal is WARN above `KH_JOURNAL_MIB=220`: journald caps it at 200 MiB
(`tools.nix`), so a journal near the cap is normal and only one above it is a finding. A unit that
the box does not run (KVM 1 has none of the Hermes units) is skipped, not a finding.

The owner runs it from his computer with `just remote-health`: KVM 1 (`piabrota.art`, or
`DEPLOY_HOST`), or `just remote-health h0ffmann <address>` for another box. Exit 1 means a `WARN` or
`CRIT` line. `hermes/skills/kvm4-health/scripts/kvm4-health.test.sh` (`just health-test`) tests the
journal line and the exit status with a stub `journalctl`.

## What a finding means

| Finding | Usual cause | What to do |
|---|---|---|
| `hermes-agent: ... now (80 %+)` | Many subagents, a large clone in the page cache, an omp run | Say so. Do not start new heavy work. Do not restart the unit: `systemctl restart` is blocked, and a deploy reloads it |
| `peak ... near the limit` | A spike since the unit started. It is history, not the current state | Name the task that ran then (the sessions of that hour). Propose a lower fan-out or a smaller clone |
| `hermes-agent grew ... with no restart` | Growth over 24 h with the same process: a leak, or a cache that does not shrink | Report the figure and the uptime. A nix-os PR can lower a cache limit; the owner decides |
| `restarted N times since it started` | A deploy reloads the unit, or the unit is in a restart loop (CRIT) | Say it. Do not hide it. Run `hermes doctor` and `hermes gateway status`, read `journalctl -u <unit> --since -1h`, tell the owner. The fix is a nix-os PR |
| `RAM available` low, `swap`, `memory pressure` | The box, not only Hermes | Read the `units` lines to find the unit that holds the memory |
| `OOM kill lines` | The kernel killed a process in 24 h | `journalctl -k --since -24h \| grep -i -A3 'killed process'` names it |
| `load`, `I/O pressure`, `used ... % of one core` | A busy run, or a loop | The `sessions` and `cron` of that hour |
| `/ used`, `/ grows ... a day` | Clones in the workspace, sessions, logs, the Nix store before GC | The sizes in the full report. Remove only your own old clones in `/var/lib/hermes/workspace`. GC and sessions pruning are automatic |
| `journal` | A unit logs in a loop | `journalctl --since -1h -o cat \| sort \| uniq -c \| sort -rn \| head` |
| `failed units` | A unit failed | `systemctl status <unit>` and its journal. Fix it with a PR, not on the box |

Freeing disk does not free memory. Say which of the two the finding is about.

## The watchdog (set up once)

A `no_agent` cron job runs a script and posts its output. Empty output posts nothing, so a healthy
tick costs no model call and no message. nix-os installs the job's script as
`~/.hermes/scripts/kvm4-health-alert.sh` (it runs this script with `--alert --record`). The script
speaks when the set of findings changes, repeats it every 6 hours while it lasts, and says once
when the box is healthy again.

Check with the `hermes-cron` skill that no job does this already. Then create it with the cron
tool, from the home channel (so that the delivery target is that channel): name `kvm4-health`,
schedule `every 30m`, `no_agent: true`, `script: kvm4-health-alert.sh`, no prompt. The CLI form
needs the target written out:

```bash
hermes cron create "every 30m" --name kvm4-health --no-agent --script kvm4-health-alert.sh --deliver <platform:chat_id>
hermes cron run <id>    # one real run: it must post nothing on a healthy box
```

Read the job back (`hermes cron list`). To test the alert path once, ask the
owner first: a threshold changed for one run (`KH_DISK_WARN=1 kvm4-health --alert`) shows the
message without the cron job.

The daily VPS check of `AGENTS.md` (07:00) can use the full report as its input: run the script
first and write the summary from its `WARN` and `CRIT` lines only.

## Pitfalls

- `MemoryPeak` is the peak since the unit last started. A deploy that reloads Hermes resets it.
- The `growth` lines need 6 hours of samples. Before that, the report says so.
- `du` in the full report reads the workspace. On a big workspace it takes some seconds; the
  `--alert` mode does not run it.
- Never read `/var/lib/hermes-secrets` or the env file to "check the box". The script does not.
