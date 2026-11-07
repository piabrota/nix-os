# AGENTS.md

Instructions for any AI coding agent working in this repository. Read this file before you change
or run anything. Humans should read it too.

## What this repo is

The NixOS configuration of one small, live VPS: a Hostinger KVM guest on Proxmox that hosts
piabrota.art/nixos. The machine has little RAM and a small disk, so every change is judged by what
it adds to the system closure and to memory use. Nothing here is a desktop: no GUI, no fonts, no
display server.

Agents do not run on the VPS. You work in a clone elsewhere and open a PR. A merge to `main` is
the deploy: GitHub Actions builds the system and switches the VPS to it ([docs/DEPLOY.md](docs/DEPLOY.md)).

## Files

| File | Is |
|---|---|
| `flake.nix`, `flake.lock` | The flake: one system per host, `nixosConfigurations.piabrota` and `nixosConfigurations.piabrota2` (`mkHost`, from `hosts/<name>`), on `nixos-26.05`; the input `hermes-agent` reaches the modules as `specialArgs`; a deploy-rs node per host (`mkNode`); `checks` (both systems, the deploy-rs checks, `checks.pgx`); `packages.deploy-rs`, `.pgx`, `.site`, `.mockups`; `devShells.site` (gleam and node, for `site/` only). |
| `configuration.nix` | What every host has in common: the Hostinger KVM template (GRUB on `/dev/sda` (BIOS, MBR), root on the `nixos` label with auto-resize, serial console, QEMU guest agent, cloud-init (NoCloud, ConfigDrive), OpenSSH) and the modules every host imports (users, tools, deploy, observer, the Loco and site modules, PGX off, the KubeSolo purge). No host name and no role: those are in `hosts/`. |
| `hosts/<name>/` | One directory per host; `default.nix` imports `configuration.nix`, sets `networking.hostName` and imports the host's roles. One name stands for one VPS: the VPS name in hPanel = `hosts/<name>/` = `nixosConfigurations.<name>` = `deploy.nodes.<name>`; KVM 1's `hostName` is the exception, Hostinger's own `srv2108887`. A new host takes the VPS name as its directory, configuration and deploy node, and as its pair in the address map of `deploy.yml` and `freeze.yml`; `kvm4` in those two workflows is the old name (an alias node in `flake.nix`) until a human edits them. `piabrota` (KVM 1): the public web only (`site.nix`, `apps.nix`). `piabrota2` (KVM 4): the full Hermes (`hermes-github.nix`, `hermes-web.nix`; DNS of `hermes.piabrota.art` points at it), Paperclip and PGX (the move: `docs/MIGRATION-KVM4.md`). |
| `piabrota.nix` | Users and Nix settings: the `h0ffmann` user (SSH key only, passwordless sudo), flakes on, the base packages. `allowUnfree` is off. |
| `unfree.nix` | Unfree packages by name (`allowUnfree` stays off), imported by `openrig.nix`: only `claude-code` (owner, 2026-11-05). Add a name only with the owner's yes. |
| `tools.nix` | Light CLI tools and defaults taken from [gvolpe/nix-config](https://github.com/gvolpe/nix-config), plus the size and memory limits. See "Resource budget". |
| `deploy.nix` | The `deploy` user that CI logs in as (key from `keys/deploy.pub`), garbage collection, store optimisation, the boot generation limit, `max-jobs`/`cores`. |
| `loco.nix` | `piabrota.loco.apps.<name>`: a [Loco](https://loco.rs) app as the sandboxed service `loco-<name>` with SQLite in `/var/lib/loco-<name>`, a daily `sqlite3 .backup`, nginx with ACME, ports 80 and 443. With no app it adds nothing. An app is on its own `domain` or on a `path` of the site's host. |
| `apps.nix`, `apps/notes/` | The Loco apps this box runs. Today one: `notes`, a sample CRUD on SQLite at `www.piabrota.art/notes` behind one password (`NOTES_PASSWORD` in `/var/lib/loco-secrets/notes.env` on the box, never here), built by `apps/notes/default.nix`. |
| `site.nix`, `site/` | `piabrota.site`: the site in `site/`, three pages (design A at `/`, B at `/index/`, C at `/paths/`) from the facts in `mockups/data.nix`, and `/hermes` (Hermes's configuration as plain YAML, no secret), in Gleam and [Lustre](https://lustre.build), prerendered at build time, on `www.piabrota.art` with nginx and ACME; `piabrota.art` redirects to `www`, `/nixos` to this repository, and `/skills` serves `skills-site/`. On in `configuration.nix`; both names must point at the VPS. The derivation has `allowedReferences = [ ]`: only the pages, `site/static/` and `mu.svg` reach the VPS. `site/DESIGN.md` holds the look's rules: change it with the look. `site/design/` holds OpenPencil drafts, never built. See [docs/SITE.md](docs/SITE.md). |
| `skills-site/` | The skills website at `www.piabrota.art/skills/` (`piabrota.site.skills`), moved from `www/` of [piabrota/skills](https://github.com/piabrota/skills). `src/`, `gleam.toml` and `manifest.toml` are that Gleam program, edited here for the look (`site/DESIGN.md`); content and behaviour stay. `default.nix` builds it on the builder from a pinned commit of piabrota/skills (`rev`, `hash`: a new commit shows only after a PR moves the pin). `just skills-site` builds it. `hermes.nix` has its own pin. |
| `room.nix`, `room-site/` | piabrota/room, pinned by commit, on piabrota2 at `room.piabrota.art`, with its radio's live listeners count behind `/live/` (see `room.nix`). |
| `figures-site/` | Figures as archify pages at `/figures/` (`piabrota.site.figures`), built by Nix from `docs/archify/` at a pinned archify. No HTML committed. |
| `hermes.nix` | [Hermes Agent](https://github.com/NousResearch/hermes-agent) as the unit `hermes-agent`, from the NixOS module of its flake (the input `hermes-agent`, pinned to a release tag in `flake.nix`; a bump is by hand). Native mode, not a container; the `full` package on piabrota2 with the `anthropic` and `messaging` extras; Claude through the owner's subscription (`CLAUDE_CODE_OAUTH_TOKEN`), never an API key: Sonnet (`claude-sonnet-5-5`) as the main model, Haiku (`claude-haiku-5-5`) for subagents and side tasks. `MemoryMax=8G` and `CPUWeight=50` on piabrota2 (`hosts/piabrota2`); state in `/var/lib/hermes`. The `hermes` CLI for `h0ffmann` is `sudo -u hermes hermes ...`: he is not in the `hermes` group, or upstream refuses the gateway control socket and the dashboard Chat tab cannot attach. Its secrets live only in `/var/lib/hermes-secrets/hermes.env` on the box, which activation copies into its `.env`; without the file it starts with no platform. Activation installs `hermes/SOUL.md` (identity and rules) and `hermes/AGENTS.md` (the owner's projects, sources and jobs) on every run. All add-ons are declared there and listed in [docs/HERMES.md](docs/HERMES.md): MCP servers, the owner's skills and community plugins (pinned by commit), among them a deny-list plugin with its list in `hermes/dangerous-patterns.yaml` (no merges, no push except to `hermes/*`, no secrets, no `sudo`, no installs). Its coding worker is [oh-my-pi](https://github.com/can1357/oh-my-pi) (`omp`, `omp/package.nix`), on its PATH only as a wrapper that loads `hermes/omp.yml` and appends `hermes/omp-append-system.md`; every task that writes or reviews code goes through the `hermes-omp` skill, which starts and stops each run with `omp-run` and pipes its output through `omp-stream` ([docs/HERMES-OMP.md](docs/HERMES-OMP.md)). `hermes/scripts/export-skills.sh` is the daily skills export (cron). |
| `hermes/scripts/gateway-wrapper.sh` | The unit's main process: on exit 75 it restarts the gateway at once. Its `.test.sh` tests it. |
| `hermes-github.nix` | Hermes's write access to GitHub as its own App, piabrota-hermes[bot]: the App's key stays root-only on the box (`/var/lib/hermes-secrets/github-app.env`); the unit `hermes-github-token` mints one-hour installation tokens every 45 minutes (contents, pull requests and issues; not workflows) for piabrota, marola-dev and h0ffmann, for `git` (a credential helper, by the repository's owner) and `gh`. Hermes pushes only `hermes/*` branches and opens pull requests when the owner asks; the deny list and a ruleset on each default branch block the rest. Without the key file it does nothing. |
| `hermes-web.nix` | `piabrota.hermesWeb.enable`, on: Hermes's web dashboard (`hermes dashboard`) as the unit `hermes-backend` on `127.0.0.1:9119` only (`MemoryMax=2G`), on piabrota2, behind nginx at `hermes.piabrota.art` with ACME and HTTP basic auth against `/var/lib/hermes-web-secrets/htpasswd` (written by hand on the box; without it every request is a 500). nginx refuses `/api/env/reveal`, `/api/audio/voice-config` and writes to `/api/env`, so no secret reaches the browser. `checks.hermes-docs-url` fails if a Hermes bump renames the docs address that nginx swaps or one of those two routes. The DNS record must point at the box before it is on. See [docs/HERMES.md](docs/HERMES.md), "The web dashboard". |
| `hermes/plugins/` | The owner's two Hermes plugins, `pirsig-notes` and `pirsig-videos`, which open pull requests to piabrota/pirsig on `hermes/*` branches; `common/brain.py` is shared and copied into each at build time (`ownPlugin` in `hermes.nix`); `tests/` runs in `checks.hermes-plugins` and `just hermes-plugins-test`. Python, because Hermes plugins are Python. See [docs/HERMES-PLUGINS.md](docs/HERMES-PLUGINS.md). |
| `hermes/feeds/` | The owner's personal feed: `build_feed.py` (stdlib Python, no agent) scores RSS, Atom, GitHub and podcast sources from `feeds.toml`. `tests/` run offline. `hermes.nix` installs it. See docs/FEEDS.md. |
| `hermes/dashboard-themes/`, `hermes/skins/` | Dashboard theme and TUI skin in the look of `site/DESIGN.md`. |
| `kubesolo-purge.nix` | Temporary oneshot that clears an old install from the box. It runs only while `/var/lib/kubesolo` exists. A human deletes it later. |
| `pgx.nix`, `pgx/` | `piabrota.pgx.enable`, on: [PGX](https://pgx.dev), a Postgres-compatible engine in Rust (v0.1, AGPL-3.0), as the unit `pgx` (state in `/var/lib/pgx`, port 5432 with no port opened in the firewall, `MemoryMax=256M`), from its release (`pgx/package.nix`; not in nixpkgs). For data you can lose, never an app's own data; nothing uses it. `checks.pgx` (`pgx/test.nix`) boots it in a VM. |
| `metrics.nix`, `metrics/`, `docs/METRICS.ptBR.md`, `docs/METRICS.md` | `piabrota.metrics`, off by default: a processes, memory and vCPU page at `metrics.piabrota.art`. A 10 s timer runs `metrics/collect.sh` (sh, awk) on both hosts into `/run/metrics-web/`; piabrota2 serves `metrics/index.html` behind the Hermes dashboard's login and pulls piabrota's file from one location of the www vhost. `checks.metrics`: three VMs. |
| `paperclip.nix`, `paperclip/` | `piabrota.paperclip.enable`, **off** on piabrota2 since 2026-11-04 (the import stays). When on: the unit `paperclip`, PostgreSQL 17, nginx at `paperclip.piabrota.art`, Hermes as its agent. |
| `openrig.nix`, `openrig/`, `docs/OPENRIG.md` | `piabrota.openrig.enable`, on at piabrota2: OpenRig 0.7.7 as the unit `openrig`, the engine of the software factory (builder and reviewer seats; Hermes routes, a human merges), loopback only with its web UI (`piabrota.openrig.web`: basic-auth vhost at rig.piabrota.art, on), `MemoryMax=2G`; seats run `omp` (`omp/wrapper.nix`) or Claude Code. Hermes runs `rig` and the skill hermes-rig. `openrig/specs/` is in `/etc/openrig/specs`: the rigs piabrota-dev, wave-forecaster-dev and wave-forecaster-dev-integrate for h0ffmann/chaceon (`piabrota.openrig.waveForecaster.enable`, off: a definition only; on, it adds Rust tools, a read-only token from `hermes-github.nix` and the outbox `/var/lib/rig-outbox`), and wave-forecaster-thesis (`piabrota.openrig.thesis.enable`, off; see `thesis/`). Either option adds `claude` and `managed-settings.json`. |
| `thesis/`, `docs/THESIS.ptBR.md`, `docs/THESIS.md`, `openrig/specs/rigs/wave-forecaster-thesis/` | The thesis rig: six Claude Code seats write one UFRJ Poli final project in pt-BR, one section each, with `thesis` (POSIX sh, jq, pandoc, a small TeX set; no model, no network): claims, four gates (readability, slop, UFRJ rules, citations; local heuristics, no AI detector), verdicts by hash, `publish` to `/var/lib/rig-outbox/wave-forecaster-thesis`. The doc has the deployment notes; change both languages together, and with `thesis/profile.json`. |
| `docs/VIDEO-PIPELINE.md`, `video-lab/` | Spec of the faceless video pipeline (English only). `just video-dummy` makes a 28 s test video from `ffmpeg` alone; the output is not in git. |
| `keys/deploy.pub` | The public half of the CI deploy key. Never a private key. |
| `observer.nix`, `keys/observer.pub` | The `observer` account: SSH key only, no sudo, not a Nix trusted user, in `systemd-journal`. A coding agent's session logs in with it (`ssh piabrota-observer`, the private key on the owner's computer) to read logs and unit states while it debugs. It only reads. |
| `scripts/specs.sh` | POSIX sh: prints OS, kernel, CPU, RAM, swap, disk, uptime and the NixOS generation. |
| `scripts/hermes-check.sh` | POSIX sh, read-only, run as `h0ffmann` on the box (`just remote-hermes-check`): the unit, its plugins and skills, the `omp` and `yt-dlp` versions, and plugin errors in the journal since the start. It never reads the secrets or prints the environment. Its two plugin lists follow `extraPlugins` and `ownPlugins` in `hermes.nix`: change them together. |
| `scripts/freeze.sh` | POSIX sh, like `pip freeze`: every package of the running system as `name==version` with its size. `--by-size` sorts by size. |
| `scripts/context-size.sh` | POSIX sh, read-only: the size of the three context files against Hermes's 32000-character cut. Warns at 30000, fails above 32000. `just context-size`. |
| `.github/workflows/freeze.yml` | After each deploy and by hand: `scripts/freeze.sh` on the VPS, into the run summary and one artifact per host. |
| `justfile` | The recipes: `just --list`. |
| `mockups/`, `docs/mockups/`, `wiki/mockups/` | Three mockups of the piabrota.art homepage (fabric, index, paths) as SVG in pure Nix, at 1280 and 390 px; the facts in `mockups/data.nix` come from the org profile. `checks.mockups` fails if their tests fail or a committed SVG is not their output; run `just mockups` after a change. They are never built into the system. |
| `docs/archify/`, `docs/img/`, `wiki/img/`, `vendor/archify` | The README's and the wiki's figures, drawn by [archify](https://github.com/tt-a1i/archify) (a submodule) with piabrota's look: English sources in `docs/archify/*.json`, pt-BR mirrors in `docs/archify/pt/`, PNGs in `docs/img/` copied to `wiki/img/`. `just figure` draws them; `just figure-check` (also in CI) fails on a stale or missing PNG. The `figure` skill has the rules. |
| `drawings/`, `docs/drawings/` | The README drawing, 无 (*mu*), in pure Nix: `pen.nix`, `mu.nix` (the strokes) and `default.nix` (their tests). `packages.mu-art` writes `mu.svg`, its Desmos state and the check render. `checks.drawing` fails if a test fails or the committed files are not its output; run `just drawing` after changing `drawings/mu.nix`. |
| `.github/workflows/cves.yml` | On every push to `main` that changes more than Markdown (not on PRs), and each Monday: `vulnix --closure` on the built system, into the run summary. A report, not a gate: name matching gives false matches. |
| `.claude/skills/`, `.mcp.json` | Vendored skills at pinned commits (four Nix, three frontend, three writing skills for `site/locale/`, `figure`, and `archify` as a link into `vendor/archify`); their README lists them and their licences. Refresh a skill by recopying upstream, never by editing its body. `.mcp.json`: the mcp-nixos, OpenPencil (limited to `site/design/`) and DeepWiki (remote, public repositories only) MCP servers; they run where the agent runs, never on the VPS. |
| `.github/workflows/code-smell-report.yml` | On every PR, not after a merge: an MIT-licensed [analyzer](https://github.com/Done-0/fuck-u-code) scores the Python, Rust and shell from 0 (best) to 100, in the run summary and in one PR comment that each run updates (merge below 55, refactor first above). A report, not a gate. It does not read Nix or Gleam. |
| `.github/workflows/ci.yml` | On every PR that changes more than Markdown (a new push cancels the PR's older run): `nixpkgs-fmt`, `statix` (rules in `statix.toml`), `deadnix`, `shellcheck`, the DeepWiki and figure checks, the tests of `omp-stream` and `omp-run` (`just omp-test`), the justfile parse with Ubuntu's `just`. They build nothing. `nix flake check` (about 10 minutes) runs only by hand (`gh workflow run ci.yml --ref <branch>`), by the owner's choice of 2026-11-03; `deploy.yml` builds each merge before it touches the VPS. |
| `.github/dependabot.yml` | One grouped PR a week that bumps the GitHub Actions the workflows use. Not nixpkgs: that is `nix flake update` in its own PR. |
| `wiki/`, `.github/workflows/wiki.yml` | The GitHub wiki's pages, in pt-BR first with English mirrors, and their images (`img/`, `mockups/`), which `just figure` and `just mockups` write. `wiki.yml` copies `wiki/` to the wiki after a merge that changes it; never edit the wiki directly. Change each page and its mirror together. |
| `.github/workflows/deploy.yml` | On a push to `main` that changes more than Markdown: deploy-rs to the VPS, then `scripts/specs.sh` into the run summary. Run by hand on another branch, it only builds (a drill): `gh workflow run deploy.yml --ref drill/<name>`; the VPS is never touched, and piabrota/agents' deploy-doctor proposes the fix against that branch. |
| `.github/workflows/deploy-doctor.yml` | When `deploy` fails: piabrota/agents' deploy-doctor on a GitHub runner, as piabrota-ops; the only doctor (nothing of piabrota/agents runs on the box). Needs the repository secret `CLAUDE_CODE_OAUTH_TOKEN` besides `OPS_BOT_APP_ID` and `OPS_BOT_KEY`; without them it warns and the failure goes undiagnosed. |
| `.github/workflows/flake-update.yml` | Each Monday and by hand: `nix flake update`, the system built before and after, and a PR in English labelled `flake-update` with the `dix` closure difference, opened as piabrota-ops (`OPS_BOT_APP_ID`, `OPS_BOT_KEY`) so CI runs on it. It merges nothing. |
| `docs/LOCO.md` | How to add a Loco app: package it in its own flake, DNS, secrets on the box, declare it here. |
| `docs/MIGRATION-KVM4.md` | The checklist that moves Hermes, its App, its dashboard and PGX from piabrota (KVM 1) to piabrota2 (KVM 4): setup and first deploy, cutover of state and secrets, clean-up on piabrota. English only. |
| `docs/DEPLOY.md` | How the deploy works and its one-time setup (key, secrets, firewall, first deploy). |
| `docs/FORK.ptBR.md`, `docs/FORK.md` | How to run your own VPS from a fork: what to change, and the manual steps on Hostinger and GitHub. pt-BR first, English mirror; change both when a file they name changes. |
| `docs/MOCKUPS.ptBR.md`, `docs/MOCKUPS.md` | The homepage mockups and how to change them; the wiki's `Maquetes` and `Mockups` pages are the same. pt-BR first, English mirror; change them together. |
| `docs/SITE.md` | How to point DNS at the VPS and turn the static site on. |
| `docs/PGX.ptBR.md`, `docs/PGX.md` | PGX here: what it is and is not, cost, `pgx.nix`, use, backups, updating, turning it off. pt-BR first, English mirror; change both together, and with `pgx.nix`. |
| `docs/HERMES.ptBR.md`, `docs/HERMES.md` | Hermes Agent here: what `hermes.nix` picks, the setup of its secrets on the box, checking, updating, turning it off. pt-BR first, English mirror; change both together, and with `hermes.nix`. |
| `docs/HERMES-OMP.ptBR.md`, `docs/HERMES-OMP.md` | omp, the default coding worker: every task that writes or reviews code goes through it; the eight layers the owner can edit and which wins; omp as an OpenRig seat. pt-BR first, English mirror; change both together, and with `hermes/omp.yml`, the wrapper and the skill. |
| `docs/RUNTIMES.ptBR.md`, `docs/RUNTIMES.md` | The OpenRig runtimes compared; the wiki's `Runtimes` pages match. pt-BR first, English mirror; change both together, and with `openrig.nix`. |
| `docs/AWESOME-HERMES.ptBR.md`, `docs/AWESOME-HERMES.md` | What exists for Hermes judged against this box (in use, worth a test, left out and why), and the gaps piabrota must write; each setting is checked at the pinned commit. pt-BR first, English mirror; change both together, and with `hermes.nix`. |
| `docs/HERMES-FORKS.md` | Should piabrota fork Hermes (2026-11-03): tailor upstream from outside, patch files in nix-os, or a fork; the cost of each and the signals for a fork. Today: no fork. English only, by the owner's order. |
| `docs/HERMES-SKILLS.md` | The owner's skills in Hermes: 29 commands, 22 left out and why, and why h0ffmann/skills is a pin by commit, not a submodule. English only, by the owner's order. Change it with `ownerSkillPaths` in `hermes.nix`. |
| `docs/FEEDS.ptBR.md`, `docs/FEEDS.md` | The personal feed: how to run it, the outputs, the score, the interests, the sources left out. pt-BR first, English mirror; change both together, and with `feeds.toml`. |
| `docs/PAPERCLIP.md` | Paperclip on piabrota2, **off** (`enable = false`): turn it on, data on the disk, erase it; Hermes link, setup, cost, updating. English only, by the owner's order. |
| `docs/CLAUDE_PROJECT.ptBR.md`, `docs/CLAUDE_PROJECT.md` | How to set up a Claude Project on a fork. pt-BR first, English mirror; change both together. For people only: an agent working here does not act on them. |
| `.devin/wiki.json`, `scripts/deepwiki-check.jq` | How [DeepWiki](https://deepwiki.com/piabrota/nix-os) writes this repository's wiki: notes on what it must know and its pages. Add or change a page when a module or a doc it names changes. CI's `jq` check keeps DeepWiki's limits (at most 30 pages, unique titles, existing parents, 100 notes of 10,000 characters). |
| `LICENSE` | MPL-2.0. |

`configuration.nix` refers to an `image.nix` that builds the qcow2 template. That file is not in
this repository.

## Do not break the machine

The VPS is running. A bad switch can lock everyone out. These settings keep it reachable and
provisionable; do not remove or weaken them:

- `services.qemuGuest.enable` and the `PATH` override on `qemu-guest-agent`. Hostinger's panel
  runs bare commands (`sh`, `cloud-init`, `chpasswd`, `dig`) through the guest agent.
- `services.cloud-init.*` and `networking.useDHCP = mkForce false`. cloud-init owns the network.
- `cloud-init`, `dnsutils`, `nettools`, `curl`, `wget` in `environment.systemPackages`: the
  panel's checks call them by name.
- `services.openssh.enable`, the `h0ffmann` authorized key and `PasswordAuthentication = false`.
- `boot.loader.grub.device = "/dev/sda"` and `fileSystems."/"`.
- The `deploy` user, its key and `nix.settings.trusted-users` in `deploy.nix`, and
  `magicRollback` in `flake.nix`: without them CI cannot deploy, or cannot undo a switch that
  breaks SSH.

Never change `system.stateVersion`.

Loco apps: never put a secret in `piabrota.loco.apps.<name>.environment` (it lands in the world-readable
store); secrets go in the `environmentFile` on the box. Add an app only after its DNS record points at
the VPS, or the ACME order fails on the deploy. Do not add a PostgreSQL server or Redis for an app: SQLite and
in-process workers (docs/LOCO.md); Paperclip's PostgreSQL is the owner's exception. PGX (`pgx.nix`) is for data you can lose, such as a task queue;
an app's own data stays in SQLite.

## Resource budget

`piabrota` is on Hostinger's **KVM 1** plan (hPanel, 2026-10-29, from the owner). `piabrota2` is on
the **KVM 4** plan (the owner, 2026-11-03); its row is Hostinger's plan list, not yet read on the
machine:

| Host | CPU | RAM | Disk | Bandwidth |
|---|---|---|---|---|
| piabrota | 1 vCPU core | 4 GB | 50 GB | 4 TB a month |
| piabrota2 | 4 vCPU cores ⚠ | 16 GB ⚠ | 200 GB ⚠ | not checked |

The rules below hold on both hosts; piabrota2 has room for the full Hermes, not for heavy tools on
every host. A tool only one host needs goes in that host's directory.

These are the plan's figures. What the system can use is less (the kernel, zram, the root
partition). Read the machine's own numbers (`just remote-specs`, or the summary of the last
`deploy` run) before you rely on a number, and change this table when the plan changes.

Rules for anything you add:

1. **Measure the closure.** Build the old and the new system and compare them with `dix` (see
   "Build"). Put the size difference in the PR. A tool that adds more than a few MiB needs a
   reason.
2. **Watch what gets built, not only what gets installed.** `nix build --dry-run` lists the
   derivations to build and the paths to fetch. A derivation that is not in the binary cache is
   compiled on the machine that builds, with its whole toolchain. Example: `programs.tmux`
   enables `utempter` by default, a setuid wrapper built from source with a musl gcc (about
   290 MiB to fetch). `tools.nix` sets `withUtempter = false`.
3. **No GUI, no fonts, no desktop services**, nothing that pulls Qt, GTK, X11 or Wayland
   libraries.
4. **No heavy runtimes for small jobs.** Prefer one static Rust or Go binary over a tool that
   needs Python, Perl modules, Haskell or a JVM. `tig`, `diff-so-fancy`, `lnav` and
   `nix-output-monitor` from gvolpe's list were left out for this reason. Hermes Agent
   (`hermes.nix`) is a Python runtime the owner asked for, not a small job: it gets its own
   `MemoryMax`. OpenRig (`openrig.nix`) is the owner's exception for Node 24, with its own limit.
5. **No resident daemons** unless the host needs them. Each service costs RAM all the time.
6. Prefer NixOS `programs.<name>` options over a bare package when the option only writes a file
   in `/etc` (tmux, git, htop): the cost is the same, and the defaults are in the repo.

What `tools.nix` does for the budget:

- `documentation.nixos.enable = false` and `documentation.doc.enable = false` remove the NixOS
  manual, `options.json` and a copy of the nixpkgs source (about 95 MiB). Man pages stay.
- `services.journald` keeps at most 200 MiB of logs, for at most one month.
- `zramSwap` gives compressed swap in RAM, up to 50 % of memory.
- `programs.command-not-found` is off: it needs a channel database.

Measured against nixos-26.05 (13050.08d3a97586f6) on 2026-10-29, adding `tools.nix` made the
system closure 25.9 MiB smaller (1.49 GiB to 1.46 GiB): the tools add about 38 MiB, the removed
documentation saves more.

`deploy.nix` sets garbage collection (weekly, paths older than 14 days, and when free disk falls under 2 GiB), a weekly store optimisation,
five boot generations and `max-jobs = 1`, `cores = 1`. Change them there, not in a second module.

## Build

The configuration is a flake. From the repository root, on any machine with Nix (it does not
need NixOS):

```console
just build        # nix build .#nixosConfigurations.piabrota.config.system.build.toplevel
just build piabrota2   # the same for the KVM 4 host
just check        # what CI runs: nix flake check, nixpkgs-fmt, statix, deadnix, shellcheck
```

Add `--dry-run` to the `nix build` to see what would be built and fetched. Compare two builds:

```console
nix run nixpkgs#dix -- diff <old-system-path> <new-system-path>
```

Lint the Nix files you changed:

```console
nix run nixpkgs#nixpkgs-fmt -- --check <file>.nix
nix run nixpkgs#statix -- check <file>.nix
nix run nixpkgs#deadnix -- --fail <file>.nix
```

Update nixpkgs with `nix flake update` in its own PR; CI runs with `--no-update-lock-file`.

## Deploy

An agent never deploys and never runs `just deploy`. To look at the box while debugging, it may log in as `observer` (`observer.nix`) and run read-only commands; it never asks the owner for root access to fix something there: the fix goes in a PR. It prepares the change and its PR; the merge
to `main` deploys it ([docs/DEPLOY.md](docs/DEPLOY.md)).

`deploy.yml` builds the system on the GitHub runner, and deploy-rs copies it to the VPS over SSH
as the `deploy` user and activates it. The VPS compiles nothing; it fetches from
`cache.nixos.org` what the cache has. If SSH does not answer within 60 seconds after the switch,
deploy-rs rolls the VPS back (magic rollback). It does this for each host (a matrix job per
node): a host's failure does not stop the other's deploy. The secrets are `DEPLOY_SSH_KEY` (one key
for both hosts), `DEPLOY_HOST` (piabrota's address), `DEPLOY_HOST_KVM4` and `DEPLOY_KNOWN_HOSTS`
(one line per host) in the `prod` environment. Until `DEPLOY_HOST_KVM4` exists, piabrota2's job is
skipped with a notice.

A human can deploy by hand with the same tool, for example the first time, before the `deploy`
user exists: `DEPLOY_HOST=<ip> just deploy h0ffmann piabrota2`, or **Run workflow** with the host
`kvm4` (the name `deploy.yml` still uses for `piabrota2`) and the SSH user `h0ffmann`. To undo a bad switch on the VPS:
`sudo nixos-rebuild switch --rollback`, or pick an older generation in the GRUB menu on the
serial console; then revert the commit on `main`, or the next deploy brings it back.

## Justfiles

A justfile in this repository must run on the `just` that `apt install just` gives on Ubuntu
24.04 LTS (just 1.21.0). Do not use syntax that version does not know, such as the
`[group(...)]` or `[positional-arguments]` attributes; use `set positional-arguments` instead.
CI's `justfiles parse with Ubuntu's just` job (`ci.yml`, on `ubuntu-24.04`) parses every
justfile with that version (`just --justfile <file> --summary`). Do not move it to a newer
Ubuntu while 24.04 is supported.

## Commits and PRs

- **Hard rule: every PR is in English only** (the owner, 2026-11-03). The title, the body, the
  commit messages, issues and review comments are in English, with no pt-BR half and no mirror.
  Write the body with the sections of the `bipr` skill of
  [h0ffmann/ptbr-writer](https://github.com/h0ffmann/ptbr-writer/blob/main/skills/bipr/SKILL.md)
  (**Summary**, **Tested**, **What changed**), in English only, and leave out the skill's
  `footer.md`. Where the skill or any other tool asks for a pt-BR title or a pt-BR half, this rule
  wins. The pull requests of piabrota-hermes (`hermes/...` branches) are also in ASD-STE100
  Simplified Technical English. A doc that this repository keeps in two languages still changes
  in both files: that is file content, not PR text.
- **Hard rule: no agent trail.** No commit, PR, issue, comment or file carries a mark of Claude or of
  any other agent or tool: no `Co-Authored-By:` agent trailer, no "Generated with" or "Generated by"
  line (the bipr footer included), no agent name as the commit author, no link to an agent session
  or project thread. A tool that appends such a line on its own: remove the line after it does.
  **The one exception:** what piabrota/agents does here as piabrota-ops, and what Hermes does as
  piabrota-hermes (GitHub Apps, never a person). Its reports, reviews and replies on issues and pull requests carry a signature that names
  the agent, the model and Claude Code's version, and where it ran, so a reader knows a machine
  wrote it and with what. Its own pull requests (fixes and mirrors on `agents/...` branches, and Hermes's on `hermes/...`
  branches) are committed and opened as `piabrota-ops[bot]` or `piabrota-hermes[bot]`; their commits and descriptions carry no signature
  (it goes in a comment) and follow the other rules here, English only included. No agent working on this
  repository for a person may use the exception: the rule above holds for that.
- Work on a branch and open a PR. Do not push to `main`.
- Name an agent's branch `claude/<project>-<goal-slug>`: the project, then the goal of the work in a
  few lowercase words joined by `-`, for example `claude/nix-os-gitops-deploys`. Never use a branch
  name made from a thread or session id, such as `claude/project-thread-wchbf1`.
  Hermes (piabrota-hermes[bot]) names its branches `hermes/<goal-slug>` instead: its deny list and
  its App's tokens allow no other.
- Never commit a secret, a private key or an `.age` file (`.gitignore` blocks the usual names).
- The PR says what changed in the closure (the `dix` summary) and whether the build was run.
