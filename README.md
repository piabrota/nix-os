<div align="center">

<img alt="无 (mu, no thing) brushed in its four strokes, drawn from Desmos equations, by @h0ffmann" src="docs/drawings/mu.svg" width="200"/>

# nix-os

<sub>无 · <i>mu</i> · the piabrota VPSs · <a href="#in-one-minute">in one minute</a> · <a href="#every-piabrotaart-address">addresses</a> · <a href="docs/DEPLOY.md">deploy</a> · <a href="#structure">structure</a> · <a href="#flake-outputs">flake outputs</a> · <a href="docs/drawings/README.md">the drawing</a> · <a href="#license">license</a></sub>

[![ci](https://github.com/piabrota/nix-os/actions/workflows/ci.yml/badge.svg)](https://github.com/piabrota/nix-os/actions/workflows/ci.yml)
[![deploy](https://github.com/piabrota/nix-os/actions/workflows/deploy.yml/badge.svg?branch=main)](https://github.com/piabrota/nix-os/actions/workflows/deploy.yml)
[![NixOS 26.05](https://img.shields.io/badge/NixOS-26.05-1682D4?style=flat-square&logo=nixos&logoColor=white)](#what-it-pins)
[![license: MPL-2.0](https://img.shields.io/badge/license-MPL--2.0-1682D4?style=flat-square)](#license)
[![Ask DeepWiki](https://img.shields.io/badge/Ask-DeepWiki-1682D4?style=flat-square)](https://deepwiki.com/piabrota/nix-os)
[![Hermes Agent v0.22.7](https://img.shields.io/badge/Hermes_Agent-v0.22.7-1682D4?style=flat-square)](docs/HERMES.md)
[![hosts: piabrota + piabrota2](https://img.shields.io/badge/hosts-piabrota_%2B_piabrota2-1682D4?style=flat-square)](https://www.piabrota.art/hosts)

</div>

## In one minute

- nix-os is the NixOS configuration of two live Hostinger VPSs, one flake with a system per host
  in `hosts/`: **KVM 1** (`piabrota`) serves the public web, [piabrota.art](https://piabrota.art);
  **KVM 4** (`piabrota2`) runs [Hermes Agent](https://github.com/NousResearch/hermes-agent), its
  dashboard, and [OpenRig](docs/OPENRIG.md) with its UI. [www.piabrota.art/hosts](https://www.piabrota.art/hosts)
  shows who does what.
- OpenRig is the engine of the open software factory behind piabrota: a builder seat and a reviewer
  seat that will build and review the changes, while Hermes routes the work and a human merges
  ([`docs/OPENRIG.md`](docs/OPENRIG.md), "The software factory"). The seats have not run a task yet.
- Every change goes through GitHub. A merge to `main` builds both systems and deploys each one.
  The GitHub runner builds, [deploy-rs](https://github.com/serokell/deploy-rs)
  copies the result over SSH and switches the VPS, and the VPS rolls back by itself if SSH stops
  answering. The VPS compiles nothing. [`docs/DEPLOY.md`](docs/DEPLOY.md) has the one-time setup.
- KVM 1 is small (1 vCPU, 4 GB RAM, 50 GB disk). KVM 4 has 4 vCPU, 15.6 GiB RAM and 197 GB disk
  (measured 2026-11-04); its Hermes unit is capped at 8 GB. Every change is judged by what it adds
  to the closure and to memory ([`AGENTS.md`](AGENTS.md), "Resource budget").
- It is ready to host [Loco](https://loco.rs) apps (Rust and SQLite) behind nginx with HTTPS:
  declare an app and the merge deploys it ([`docs/LOCO.md`](docs/LOCO.md)). Until then it adds
  nothing to the system.
- The layout of this README comes from [picasso](https://github.com/h0ffmann/picasso), which took it
  from [Gabriel Volpe's `nix-config`](https://github.com/gvolpe/nix-config).

## Every piabrota.art address

Every name under piabrota.art that this repository serves, with its status on 2026-11-05
(`metrics` and `room` on 2026-11-06). The status is that of the first request: no redirect is
followed.

| Address | What it is | Host | Access | Source |
|---|---|---|---|---|
| [`piabrota.art`](https://piabrota.art) | 301 to `https://www.piabrota.art/`, same path | KVM 1 | public | `site.nix` |
| [`www.piabrota.art/hermes/`](https://www.piabrota.art/hermes/) | Hermes's configuration as plain YAML, no secret. 200; `/hermes` gives 301 | KVM 1 | public | `site.nix`, `site/hermes.nix` |
| [`www.piabrota.art/skills/`](https://www.piabrota.art/skills/) | The skills website. 200 | KVM 1 | public | `skills-site/` |
| [`www.piabrota.art/figures/`](https://www.piabrota.art/figures/) | The figures as interactive pages, English and pt-BR. New: it goes live with the deploy of the pull request that adds it, so its status is not checked yet ⚠ | KVM 1 | public | `figures-site/` |
| [`www.piabrota.art/notes`](https://www.piabrota.art/notes) | The Loco app `notes`. 303 to `/notes/login` | KVM 1 | one password | `apps.nix`, `apps/notes/` |
| [`www.piabrota.art/nixos`](https://www.piabrota.art/nixos) | 302 to [this repository](https://github.com/piabrota/nix-os) | KVM 1 | public | `site.nix` |
| [`hermes.piabrota.art`](https://hermes.piabrota.art/) | The Hermes dashboard. 401 without the login | KVM 4 | basic auth | `hermes-web.nix` |
| [`rig.piabrota.art`](https://rig.piabrota.art/) | The OpenRig web UI. 401 without the login. Its terminal can type into the seats | KVM 4 | basic auth, the dashboard's login file | `openrig.nix`, `hosts/piabrota2/default.nix`, [`docs/OPENRIG.md`](docs/OPENRIG.md) |
| [`metrics.piabrota.art`](https://metrics.piabrota.art/) | The metrics page: CPU, memory, disk and the top processes of both hosts. 401 without the login | KVM 4 | basic auth, the dashboard's login file | `metrics.nix`, `metrics/`, [`docs/METRICS.md`](docs/METRICS.md) |
| [`room.piabrota.art`](https://room.piabrota.art/) | The 3D room, piabrota/room at a pinned commit, with its radio. 200; `/live/radio` is the live listeners count (server-sent events) | KVM 4 | public | `room.nix`, `room-site/` |
| `paperclip.piabrota.art` | Paperclip. Off since 2026-11-04: no answer | KVM 4 | none while off | `paperclip.nix`, [`docs/PAPERCLIP.md`](docs/PAPERCLIP.md) |

`app.piabrota.art` and `example.piabrota.art` appear only as examples (`loco.nix`, `flake.nix`).
They are not addresses of piabrota.

## How it works

![Two hosts: a visitor's browser asks Porkbun DNS, whose A records send www.piabrota.art to VPS 1 (KVM 1), which serves the site, /hermes, /figures and the /notes Loco app, and hermes.piabrota.art and rig.piabrota.art to VPS 2 (KVM 4); there the dashboard behind basic auth shares its state with the hermes-agent gateway, which drives the openrig unit with its two omp seats; the OpenRig UI behind basic auth proxies to openrig; the gateway polls the owner's Telegram and Discord chats.](docs/img/two-hosts.png)

Interactive page: <https://www.piabrota.art/figures/two-hosts/>

<details open>
<summary>How to read this figure</summary>

**Takeaway.** KVM 1 serves the public web and nothing else; everything Hermes and OpenRig is on KVM 4.

**How to read.** Top to bottom, one lane per place: visitor, DNS, each VPS, owner. DNS turns each name into a host. On KVM 4, read the row from left to right: the dashboard shares state with the gateway, the gateway drives openrig, and the OpenRig UI proxies to it. The gateway reaches out to the chats; they do not call it. The red border marks what is outside the two boxes.

**Not shown.** The deploy and the pull requests (the figures "How nix-os works" and "The software factory" show them), PGX on KVM 4 (Paperclip is off for now), the ACME certificates, the secrets on each box, and the clones the seats work in.

**Evidence.** [`docs/archify/two-hosts.json`](docs/archify/two-hosts.json), the source of the figure; `hosts/piabrota/default.nix`, `hosts/piabrota2/default.nix`, `hermes-web.nix`, `openrig.nix`, [`docs/OPENRIG.md`](docs/OPENRIG.md), [`docs/MIGRATION-KVM4.md`](docs/MIGRATION-KVM4.md).

</details>

[OpenRig](https://github.com/mvschwarz/openrig) is the engine of the open software factory behind
piabrota. The rig `piabrota-dev` has two seats on `omp`: a builder and a reviewer. The builder will
write the change and the reviewer will check it. Hermes routes the task and checks the result, then
opens the pull request on a `hermes/*` branch. A human merges, always, and the merge deploys.

**Status today.** OpenRig 0.7.7 runs on KVM 4. The rig is specified and the UI is on. The seats are
idle: no task has gone through the builder and reviewer loop. Today Hermes makes a pull request by
running `omp` itself (skill `hermes-omp`). The guardrails stay: humans merge, the deny list and
`hermes/omp.yml` apply, no secret goes in a spec or a task, at most two seats run at once, and the UI
is behind basic auth and TLS.

![The software factory: the owner sends a task to Hermes on VPS 2; Hermes sends it to the builder seat of the OpenRig rig piabrota-dev, which delegates its diff to the reviewer seat, and the verdict goes back to Hermes; Hermes commits, pushes a hermes/* branch and opens a pull request on GitHub; a human merges it, always; deploy.yml then deploys the two VPSs with deploy-rs and magic rollback.](docs/img/software-factory.png)

Interactive page: <https://www.piabrota.art/figures/software-factory/>

<details open>
<summary>How to read this figure</summary>

**Takeaway.** The rig will do the build and the review, Hermes routes and checks, and only a human merges.

**How to read.** Top to bottom, one lane per stage: people, Hermes, the rig, GitHub, deploy. Arrows say what goes next; the red border marks where a person comes in.

**Not shown.** The skills `/triage` and `/mip` that come before the task, the watchers after the deploy (`kvm4-health`), the deny list, and the token of the seats.

**Evidence.** [`docs/archify/software-factory.json`](docs/archify/software-factory.json), the source of the figure; `openrig/specs/rigs/piabrota-dev/rig.yaml`, [`docs/OPENRIG.md`](docs/OPENRIG.md), `.github/workflows/deploy.yml`, the skills `hermes-rig` and `hermes-omp`. ⚠ No task has gone through the rig yet: the seats, the verdict arrow and the pull request from a seat's diff are the plan, not a run.

</details>

The rig `wave-forecaster-thesis` is a second rig on the same engine. Six Claude Code seats write a
final-year project of the Escola Politécnica of UFRJ in Portuguese, one independent section at a
time, and the command `thesis` (no model, no network) claims the sections, runs four gates and builds
the PDF. It is off at piabrota2, and no seat has run it ([`docs/THESIS.md`](docs/THESIS.md)).

![The thesis rig: the owner gives the brief to the editor, which writes thesis.json; the librarian keeps the sources and refs.bib; three writers each take one section with thesis fetch and hand it in with thesis submit; the thesis toolkit, with pandoc, the Lua filter, the template and pdfLaTeX, runs the gates; the reviewer records the verdict with a hash; assemble builds the PDF and runs pdf-qa and ufrj-check; publish puts the PDF in the outbox, where Hermes and the owner read it; the six seats run on Claude Code in the openrig unit of 2G.](docs/img/thesis-rig.png)

Interactive page: <https://www.piabrota.art/figures/thesis-rig/>

<details open>
<summary>How to read this figure</summary>

**Takeaway.** Six Claude Code seats write independent sections, a toolkit with no model checks and builds them, and one PDF leaves in an outbox that the owner reads.

**How to read.** Top to bottom and left to right, one lane for each role. The top strip marks the five phases. The red border marks where a person comes in. Each arrow carries the command or the file that passes from one part to the next.

**Not shown.** The three writers are one box. Also the four gates, the project files and the consent prompt of Claude Code.

**Evidence.** [`docs/archify/thesis-rig.json`](docs/archify/thesis-rig.json), the source of the figure; `openrig/specs/rigs/wave-forecaster-thesis/rig.yaml`, [`docs/THESIS.md`](docs/THESIS.md). ⚠ No seat has run this rig: the arrows are the design, not a run.

</details>

![How nix-os works: a pull request runs ci.yml on every push; a merge to main runs deploy.yml, which builds the system on the GitHub runner; deploy-rs copies the closure to the VPS over SSH and switches it, the VPS fetching store paths from cache.nixos.org; if SSH falls silent for 60 s, magic rollback restores the old system; after the switch, freeze.yml lists the VPS's packages, and cves.yml reports vulnix on the same push.](docs/img/how-nix-os-works.png)

Interactive page: <https://www.piabrota.art/figures/how-nix-os-works/>

<details open>
<summary>How to read this figure</summary>

**Takeaway.** Nobody deploys by hand: merging a pull request is the deploy, and a switch that cuts SSH undoes itself.

**How to read.** Top to bottom, one lane per place where the work runs. Arrows say what flows or what comes next; the red border marks where you come in.

**Not shown.** The secrets and the `prod` environment, `wiki.yml`, the Markdown-only pushes that skip the build, and the deploy by hand (`just deploy`).

**Evidence.** [`docs/archify/how-nix-os-works.json`](docs/archify/how-nix-os-works.json), the source of the figure; `.github/workflows/`, `flake.nix` (`deploy.nodes.piabrota`, `magicRollback`), [`docs/DEPLOY.md`](docs/DEPLOY.md).

</details>

![piabrota.art: a browser resolves the two A records on Porkbun, which point at the VPS; nginx answers piabrota.art with a 301 to https://www and serves www.piabrota.art over HTTP and HTTPS, with /nixos a 302 to the repository and a Let's Encrypt certificate per name; the page was built before the deploy, site/ in Gleam prerendered by Nix into /nix/store as three pages and style.css, which is nginx's root.](docs/img/piabrota-art.png)

Interactive page: <https://www.piabrota.art/figures/piabrota-art/>

<details open>
<summary>How to read this figure</summary>

**Takeaway.** The VPS serves a few small files from the store; Gleam, node and the build never reach it.

**How to read.** Top to bottom: the visitor, DNS, nginx on the VPS, and what was built before the deploy. Arrows say what a request is sent to, or what goes into what.

**Not shown.** The ACME HTTP-01 challenge, the `httpsOnly` switch, and the Loco apps that would share nginx.

**Evidence.** [`docs/archify/piabrota-art.json`](docs/archify/piabrota-art.json), the source of the figure; `site.nix`, `site/default.nix`, [`docs/SITE.md`](docs/SITE.md).

</details>

`just figure` draws them again with the pinned [archify](https://github.com/tt-a1i/archify)
(`vendor/archify`), the same way as piabrota/pirsig and piabrota/gramatico; `just figure-check` says
whether a PNG is stale. The `figure` skill (`.claude/skills/figure/`) has the rules.

## Use it for your own VPS

Fork it. The guide lists what to change and the manual steps on Hostinger and GitHub (a NixOS
VPS, a deploy key, three secrets, one first deploy):

- [`docs/FORK.ptBR.md`](docs/FORK.ptBR.md), em português
- [`docs/FORK.md`](docs/FORK.md), in English

To let a Claude Project work on your fork (pull requests only; a merge still deploys), set it up
with:

- [`docs/CLAUDE_PROJECT.ptBR.md`](docs/CLAUDE_PROJECT.ptBR.md), em português
- [`docs/CLAUDE_PROJECT.md`](docs/CLAUDE_PROJECT.md), in English

[Hermes Agent](https://github.com/NousResearch/hermes-agent), Nous Research's agent, runs on KVM 4 as a
NixOS service (`hermes.nix`), on Claude through the owner's subscription, with its web dashboard at
hermes.piabrota.art (`hermes-web.nix`). How it is set up, its secrets, and how to check it (the move
from KVM 1 is [`docs/MIGRATION-KVM4.md`](docs/MIGRATION-KVM4.md)):

- [`docs/HERMES.ptBR.md`](docs/HERMES.ptBR.md), em português
- [`docs/HERMES.md`](docs/HERMES.md), in English

[OpenRig](https://github.com/mvschwarz/openrig) runs on KVM 4 as the unit `openrig`, with its web UI at
rig.piabrota.art (`openrig.nix`). Its rig `piabrota-dev` is the engine of the software factory that
Hermes operates. How it is set up, its limits and its status are in [`docs/OPENRIG.md`](docs/OPENRIG.md),
in English.

PGX, a Postgres-compatible engine in one process, runs on KVM 4 for the next workload that needs
Postgres, instead of a PostgreSQL server or Docker (`pgx.nix`): what it is, its cost and its limits:

- [`docs/PGX.ptBR.md`](docs/PGX.ptBR.md), em português
- [`docs/PGX.md`](docs/PGX.md), in English

[Paperclip](https://github.com/paperclipai/paperclip), a control plane for a team of AI agents, is
off for now (`piabrota.paperclip.enable = false;`). When on, it runs on KVM 4 at paperclip.piabrota.art
with Hermes as its agent (`paperclip.nix`): how they talk, the setup on the box, the cost and how to
turn it on are in [`docs/PAPERCLIP.md`](docs/PAPERCLIP.md), in English.

## Recipes

```console
just build          # build the system here, without deploying it
just check          # what CI runs: nix flake check, nixpkgs-fmt, statix, deadnix, shellcheck
just deploy         # deploy by hand, as CI does (DEPLOY_HOST=<ip>; a human only)
just specs          # CPU, RAM, disk, kernel and NixOS generation of this machine
just remote-specs   # the same, of the VPS, over SSH
just remote-hermes-check  # Hermes's add-ons are live on KVM 4 (DEPLOY_HOST=<its address>)
just cves           # CVE report of the system closure (vulnix; a report, not a gate)
just freeze         # every package of the running system with its size, like pip freeze
just remote-freeze  # the same, of the VPS, over SSH
just drawing        # write docs/drawings/ again from drawings/
```

Every justfile here runs on the `just` that Ubuntu 24.04 ships through apt (1.21.0); CI parses it
with that version.

<details>
<summary id="what-it-pins">What it pins</summary>

| Input | Pinned at | What for |
|---|---|---|
| [nixpkgs](https://github.com/NixOS/nixpkgs/tree/nixos-26.05) `nixos-26.05` | [`9bb5222`](https://github.com/NixOS/nixpkgs/commit/9bb52223f4f6a0cc606fd0852d8784f896c137d5) (2026-11-01) | the system; `system.stateVersion` is 26.05 |
| [deploy-rs](https://github.com/serokell/deploy-rs) | [`1cec052`](https://github.com/serokell/deploy-rs/commit/1cec0527bd09074bbee6d4461900ce5d58267217) (2026-10-19) | the activation and its rollback; the `deploy` binary comes from nixpkgs, so CI does not compile it |
| [hermes-agent](https://github.com/NousResearch/hermes-agent) [`v0.22.7`](https://github.com/NousResearch/hermes-agent/releases/tag/v0.22.7) | [`b200f5b`](https://github.com/NousResearch/hermes-agent/commit/b200f5bc60e31588ba2cb60e288029c4a54ba5fa) (2026-11-03) | Hermes Agent's package and NixOS module (`hermes.nix`); it keeps its own nixpkgs (unstable), for which its build is made |

`flake.lock` is the truth; this table is what it held on 2026-11-04. The Hermes badge at the top is
edited by hand: change it with the pin. Update with `nix flake update` in a pull request.

</details>

## Structure

```
.
├── flake.nix, flake.lock    a system and a deploy-rs node per host, the checks
├── configuration.nix        what every host shares: the Hostinger KVM base and the common modules
├── hosts/piabrota/          KVM 1: the public web only
├── hosts/piabrota2/         KVM 4: the full Hermes, its GitHub App and dashboard, OpenRig, PGX; Paperclip off for now (docs/DEPLOY.md)
├── piabrota.nix             the user h0ffmann and the base packages
├── tools.nix                light CLI tools, and the size and memory limits
├── deploy.nix               the deploy user that CI logs in as, GC, boot generation limit
├── loco.nix                 Loco apps: a sandboxed service each, SQLite, backups, nginx + ACME
├── apps.nix, apps/notes/    the Loco apps: a notes CRUD demo at www.piabrota.art/notes (docs/LOCO.md)
├── site.nix, site/          the static site on www.piabrota.art (Gleam + Lustre, prerendered by Nix)
├── pgx.nix, pgx/            PGX, a Postgres-compatible engine, its package and its VM test
├── paperclip.nix, paperclip/ Paperclip, its npm package and lock, with Hermes as its agent
├── hermes.nix               Hermes Agent, from its flake's NixOS module (docs/HERMES.md)
├── hermes-github.nix        Hermes's GitHub App: hermes/* branches and pull requests
├── hermes-web.nix           Hermes's dashboard on hermes.piabrota.art, behind nginx and basic auth
├── hermes-web/docs/         the page the dashboard's Documentation tab shows
├── openrig.nix, openrig/    OpenRig, the engine of the software factory: its package, its rig specs and its UI (docs/OPENRIG.md)
├── thesis/                  the `thesis` toolkit of the thesis rig: POSIX sh, pandoc, TeX; its tests (docs/THESIS.md)
├── kubesolo-purge.nix       a oneshot that clears an old install from the box; delete once it ran
├── keys/deploy.pub          the public key of the CI deploy key
├── scripts/specs.sh         prints the machine's specs (POSIX sh)
├── scripts/freeze.sh        every package of the system with its size, like pip freeze
├── scripts/hermes-check.sh  checks on the box that Hermes's add-ons of the last deploy are live
├── drawings/                the pen and the drawing, in Nix, that draw docs/drawings/mu.svg
├── mockups/                 three mockups of the piabrota.art homepage, SVG in pure Nix (docs/MOCKUPS.md)
├── docs/archify/, docs/img/ the figures' archify sources and PNGs; vendor/archify is the pinned archify
├── docs/DEPLOY.md           how a merge reaches the VPSs, and the one-time setup
├── docs/MIGRATION-KVM4.md   the checklist that moves Hermes from KVM 1 to KVM 4
├── docs/LOCO.md             how to add a Loco app
├── docs/SITE.md             how to turn the static site on
├── docs/MOCKUPS.ptBR.md     the homepage mockups, in Portuguese
├── docs/MOCKUPS.md          the same, in English
├── docs/FORK.ptBR.md        how to run your own VPS from a fork, in Portuguese
├── docs/FORK.md             the same, in English
├── docs/CLAUDE_PROJECT.ptBR.md  a Claude Project for a fork, in Portuguese
├── docs/CLAUDE_PROJECT.md   the same, in English
├── docs/HERMES.ptBR.md      Hermes Agent here: setup, secrets, checks, in Portuguese
├── docs/HERMES.md         the same, in English
├── docs/PGX.ptBR.md         PGX here: cost, limits, use, in Portuguese
├── docs/PGX.md            the same, in English
├── docs/PAPERCLIP.md      Paperclip and Hermes here: setup, cost, updating
├── docs/OPENRIG.md        OpenRig and the software factory here: setup, UI, status, guardrails
├── docs/THESIS.ptBR.md    the thesis rig: parts, gates, UFRJ rules, deployment notes, in Portuguese
├── docs/THESIS.md         the same, in English
├── docs/drawings/           the README drawing and its Desmos state
├── .github/workflows/       ci.yml (every PR beyond Markdown: lints and the justfile parse; the full flake check by hand), cves.yml (push to main beyond Markdown, and weekly), deploy.yml (push to main beyond Markdown), freeze.yml (after each deploy), wiki.yml (copies wiki/ to the GitHub wiki), code-smell-report.yml (every PR and push to main: a code smell score, not a gate), flake-update.yml (weekly: a nix flake update PR with its closure diff)
├── .github/dependabot.yml   one PR a week that bumps the actions the workflows use
├── wiki/                    the GitHub wiki's pages, in Portuguese and English
├── .claude/skills/          vendored skills for agents, four Nix, three frontend, figure and archify (their README); .mcp.json: mcp-nixos, OpenPencil, DeepWiki
├── .devin/wiki.json         how DeepWiki writes this repository's wiki (deepwiki.com/piabrota/nix-os); scripts/deepwiki-check.jq checks it in CI
├── justfile
└── AGENTS.md                the rules for AI agents working here
```

## Flake outputs

```console
$ nix flake show
├───checks
│   └───x86_64-linux
│       ├───deploy-activate: derivation 'deploy-rs-check-activate'
│       ├───deploy-schema: derivation 'jsonschema-deploy-system'
│       ├───drawing: derivation 'mu-art-check'
│       ├───loco-example: derivation 'nixos-system-nixos-26.05.20261028.08d3a97'
│       ├───mockups: derivation 'mockups-check'
│       ├───toplevel: derivation 'nixos-system-srv2108887-26.05.20261101.9bb5222'
│       └───toplevel-kvm4: derivation 'nixos-system-kvm4-26.05.20261101.9bb5222'
├───deploy: unknown
├───devShells
│   └───x86_64-linux
│       ├───default: development environment 'nix-shell'
│       └───site: development environment 'nix-shell'
├───formatter
│   └───x86_64-linux: package 'nixpkgs-fmt-1.3.0'
├───nixosConfigurations
│   ├───kvm4: NixOS configuration
│   └───piabrota: NixOS configuration
└───packages
    └───x86_64-linux
        ├───deploy-rs: package 'deploy-rs-1.0.0'
        ├───mockups: package 'mockups'
        ├───mu-art: package 'mu-art'
        └───site: package 'piabrota-site-1.0.0'
```

This block was taken before the rename of `kvm4` to `piabrota2`: the host, its system and its check now carry the new name.

## Credits

- The README layout follows [picasso](https://github.com/h0ffmann/picasso), and through it
  [gvolpe/nix-config](https://github.com/gvolpe/nix-config). Several tools in `tools.nix` come from
  gvolpe's list.
- The drawing is made the way [pirsig](https://github.com/h0ffmann/pirsig)'s 無 is: `drawings/pen.nix`
  is pirsig's pen, ported from Rust to Nix (MPL-2.0, by the same author). See
  [docs/drawings](docs/drawings/README.md).
- The stroke order of 无 follows [KanjiVG](https://kanjivg.tagaini.net/) (© Ulrich Apel,
  CC BY-SA 3.0), used as a reference only.

## License

| What | License |
|---|---|
| Everything in this repository, the drawing included | [MPL-2.0](LICENSE) |
| `drawings/pen.nix` | MPL-2.0, ported from [h0ffmann/pirsig](https://github.com/h0ffmann/pirsig)'s Rust pen at `450e4da` |
| `.claude/skills/*/` | MIT, or Apache-2.0 for `frontend-design`, each from its upstream at a pinned commit ([`.claude/skills/README.md`](.claude/skills/README.md)); texts in `.claude/skills/LICENSES/` |
