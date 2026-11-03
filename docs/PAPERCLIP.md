# Paperclip on this VPS

A check of the cost of self-hosting [Paperclip](https://github.com/paperclipai/paperclip) on the
KVM 1 box. Research only: nothing here is installed. This file is in English only, by the owner's order.

Read on 2026-11-03.

## Answer

Do not run Paperclip on this box. It would fit on paper, with a thin margin. It breaks three rules of
this repository, and I could not measure its real cost.

If you want it, run it on a second small VPS or on your own computer. Hermes can be one of its agents.

Confidence: medium on the answer. High on the facts about the box. Low on any number about Paperclip,
because I did not run it.

## What it is

- A Node.js server and a React UI that run a "company" of AI agents: goals, org chart, budgets,
  tasks, and a heartbeat that wakes agents. MIT licence.
  Source: [README](https://github.com/paperclipai/paperclip). At the time of reading: about 110,000 stars,
  last push 2026-11-03, newest release `v2026.1023.0` (2026-10-24).
- It is not an agent. It starts agents of other makers as child processes of its server. The Hermes
  adapter `hermes_local` runs `hermes chat -q` on the same machine
  ([adapter docs](https://docs.paperclip.ing/reference/adapters/hermes/)). Hermes must be installed there.

## What it needs

From the official docs ([installation](https://github.com/paperclipai/paperclip-docs/blob/main/docs/guides/getting-started/installation.md),
[deploy to a VPS](https://github.com/paperclipai/paperclip-docs/blob/main/docs/how-to/deploy-to-vps-or-fly.md),
[database](https://github.com/paperclipai/paperclip-docs/blob/main/docs/reference/deploy/database.md)):

| Need | Value |
|---|---|
| Runtime | Node.js 24.11 or newer. pnpm 9.15 or newer to build from source. |
| Size, as the docs say | "Any Linux VPS with 1 vCPU and 2 GB of RAM is enough to get started." |
| Database | Embedded PostgreSQL for a local test. A hosted PostgreSQL for production. |
| Public use | A domain, HTTPS, nginx in front, and the app bound to `127.0.0.1:3100`. |
| Official VPS path | A Docker image. The container holds the API, the UI and the agent processes. |
| Secrets | `PAPERCLIP_AGENT_JWT_SECRET`, and a model key for each agent kind. |

The docs give the 2 GB figure for a start, for the platform alone. They do not give a figure for
agents that run at the same time.

## What the box has

Measured on 2026-11-03 (`free -m`, `systemctl show`, the cgroup of `hermes-agent`):

| Item | Value |
|---|---|
| CPU | 1 vCPU |
| RAM | 3916 MiB in total, about 3100 MiB available (this includes cache that the kernel can free) |
| Swap | 1957 MiB (compressed, in RAM). 269 to 333 MiB used at the two readings. |
| Disk | 42 GB free of 50 GB |
| Hermes | Cap 1024 MiB. About 380 MiB of program memory in use. A past peak of 996 MiB. |
| Other units | nginx about 6 MiB. PGX about 26 MiB. |
| Memory pressure | `avg300` about 9%. A short spike to `avg10` 48% happened while I evaluated nixpkgs once. I stopped it. |

The spike is a warning: this box slows down when one more heavy job runs on it.

## The cost, in numbers that I can support

- **Platform alone:** the docs say 2 GB of RAM is "enough to get started". The box has about 3.1 GiB
  available. After a 2 GB platform, about 1.1 GiB stays free for everything else.
- **One agent run:** each `hermes_local` run starts a new Hermes process. I did not measure this.
  The gateway process of Hermes uses about 380 MiB, so a run of the same size would take a large
  part of the 1.1 GiB.
- **CPU:** 1 vCPU, shared with nginx, the apps and the Hermes gateway. A Node server, a database
  and an agent run at the same time would compete for it.
- **I did not measure Paperclip itself.** I would need to install it from npm, and to get Node 24
  and the embedded database. The deny list blocks installs, and this repository has no Node on the host.
  Treat any figure for its real use as unknown.

## Where it breaks the rules of this repository

`AGENTS.md` and `docs/AWESOME-HERMES.md` of this repository set these rules:

1. **No heavy runtime for a small job** (`AGENTS.md`, resource budget, rule 4). The yardstick of
   `AWESOME-HERMES.md` leaves out "anything that needs Node, Go, Docker or a browser on the box".
   Paperclip is a Node 24 server.
2. **No PostgreSQL server for an app** (`AGENTS.md`, "Do not break the machine"). The docs ask for a
   real PostgreSQL in production. PGX is on this box, but it is "for data you can lose", and I did
   not check if Paperclip works on it.
3. **No Docker on the box** (the same yardstick). The official VPS path is a Docker image.
4. **No resident daemon unless the host needs it** (`AGENTS.md`, resource budget, rule 5).
   Paperclip adds a server and a database that run all the time.

Other open points, not checked:

- **Credentials.** The docs show `ANTHROPIC_API_KEY` for its agents. This box uses the owner's
  Claude subscription and no API key. I did not check if Paperclip can use the subscription.
- **Guardrails.** The deny list is a plugin of the Hermes gateway process. I did not check if a
  `hermes chat -q` child of Paperclip loads it. If it does not, that child runs with fewer limits than I do.
- **Nix package.** I did not confirm if nixpkgs has a Paperclip package. A search was too heavy for this box.

## If you still want it

1. Run it off this box: a second VPS with at least 2 vCPU and 4 GB, or your computer on Tailscale.
2. Use the Docker path there, with a hosted or separate PostgreSQL.
3. Keep Hermes on this box. Paperclip can call it over the `hermes_local` adapter only on the same
   machine, so the second host needs its own Hermes install.
4. Measure it first: `systemd-cgtop` or `docker stats` for a day, with two agents at the same time.

## What Hermes already has for the same job

Hermes has profiles, a kanban board, scheduled jobs and subagents on this box, at no extra cost
([upstream docs](https://hermes-agent.nousresearch.com/docs/user-guide/profiles)). For one owner, these cover most of what Paperclip adds.
Paperclip adds a UI, budgets for each agent and an org chart.
