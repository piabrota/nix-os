<div align="center">

<img alt="无 (mu, no thing) brushed in its four strokes, drawn from Desmos equations, by @h0ffmann" src="docs/drawings/mu.svg" width="200"/>

# nix-os

<sub>无 · <i>mu</i> · the piabrota VPSs · <a href="#in-one-minute">in one minute</a> · <a href="docs/DEPLOY.md">deploy</a> · <a href="#structure">structure</a> · <a href="#flake-outputs">flake outputs</a> · <a href="docs/drawings/README.md">the drawing</a> · <a href="#license">license</a></sub>

[![ci](https://github.com/piabrota/nix-os/actions/workflows/ci.yml/badge.svg)](https://github.com/piabrota/nix-os/actions/workflows/ci.yml)
[![deploy](https://github.com/piabrota/nix-os/actions/workflows/deploy.yml/badge.svg?branch=main)](https://github.com/piabrota/nix-os/actions/workflows/deploy.yml)
[![NixOS 26.05](https://img.shields.io/badge/NixOS-26.05-1682D4?style=flat-square&logo=nixos&logoColor=white)](#what-it-pins)
[![license: MPL-2.0](https://img.shields.io/badge/license-MPL--2.0-1682D4?style=flat-square)](#license)
[![Ask DeepWiki](https://img.shields.io/badge/Ask-DeepWiki-1682D4?style=flat-square)](https://deepwiki.com/piabrota/nix-os)
[![Hermes Agent v0.22.7](https://img.shields.io/badge/Hermes_Agent-v0.22.7-1682D4?style=flat-square)](docs/HERMES.md)

</div>

## In one minute

- nix-os is the NixOS configuration of two live Hostinger VPSs, one flake with a system per host
  in `hosts/`: **KVM 1** (`piabrota`) serves the public web, [piabrota.art](https://piabrota.art);
  **KVM 4** (`piabrota2`) runs [Hermes Agent](https://github.com/NousResearch/hermes-agent) and its
  dashboard. [www.piabrota.art/hosts](https://www.piabrota.art/hosts) shows who does what.
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

## How it works

![Two hosts: Porkbun DNS sends www.piabrota.art to VPS 1 (KVM 1), which serves the site, /hermes, /hosts and the /notes Loco app, and hermes.piabrota.art to VPS 2 (KVM 4), where the dashboard behind basic auth shares its state with the hermes-agent gateway; the owner's Telegram and Discord chats reach the gateway by polling, and it opens pull requests on hermes/* branches as piabrota-hermes[bot]; deploy.yml builds both systems and deploys each on a merge.](docs/img/two-hosts.png)

<details open>
<summary>How to read this figure</summary>

**Takeaway.** KVM 1 serves the public web and nothing else; everything Hermes is on KVM 4.

**How to read.** Top to bottom, one lane per place: people, DNS, each VPS, GitHub. Arrows say where a request or a deploy goes; the red border marks what is outside the two boxes.

**Not shown.** PGX on KVM 4, the ACME certificates, the secrets on each box, and the deploy by hand.

**Evidence.** [`docs/archify/two-hosts.json`](docs/archify/two-hosts.json), the source of the figure; `hosts/piabrota/default.nix`, `hosts/piabrota2/default.nix`, `hermes-web.nix`, [`docs/MIGRATION-KVM4.md`](docs/MIGRATION-KVM4.md).

</details>

![How nix-os works: a pull request runs ci.yml on every push; a merge to main runs deploy.yml, which builds the system on the GitHub runner; deploy-rs copies the closure to the VPS over SSH and switches it, the VPS fetching store paths from cache.nixos.org; if SSH falls silent for 60 s, magic rollback restores the old system; after the switch, freeze.yml lists the VPS's packages, and cves.yml reports vulnix on the same push.](docs/img/how-nix-os-works.png)

<details open>
<summary>How to read this figure</summary>

**Takeaway.** Nobody deploys by hand: merging a pull request is the deploy, and a switch that cuts SSH undoes itself.

**How to read.** Top to bottom, one lane per place where the work runs. Arrows say what flows or what comes next; the red border marks where you come in.

**Not shown.** The secrets and the `prod` environment, `wiki.yml`, the Markdown-only pushes that skip the build, and the deploy by hand (`just deploy`).

**Evidence.** [`docs/archify/how-nix-os-works.json`](docs/archify/how-nix-os-works.json), the source of the figure; `.github/workflows/`, `flake.nix` (`deploy.nodes.piabrota`, `magicRollback`), [`docs/DEPLOY.md`](docs/DEPLOY.md).

</details>

![piabrota.art: a browser resolves the two A records on Porkbun, which point at the VPS; nginx answers piabrota.art with a 301 to https://www and serves www.piabrota.art over HTTP and HTTPS, with /nixos a 302 to the repository and a Let's Encrypt certificate per name; the page was built before the deploy, site/ in Gleam prerendered by Nix into /nix/store as three pages and style.css, which is nginx's root.](docs/img/piabrota-art.png)

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

Kubernetes on this machine: a survey of k3s, k0s, MicroK8s and KubeSolo against the KVM 1 plan,
with podman and Nomad for comparison. The short answer is not for now:

- [`docs/KUBERNETES.ptBR.md`](docs/KUBERNETES.ptBR.md), em português
- [`docs/KUBERNETES.md`](docs/KUBERNETES.md), in English

The next step is a test of MicroK8s, with the node declared here and the workloads deployed
apart:

- [`docs/MICROK8S.ptBR.md`](docs/MICROK8S.ptBR.md), em português
- [`docs/MICROK8S.md`](docs/MICROK8S.md), in English

KubeSolo ran here from 2026-10-30 to 2026-11-02 and was then removed; `kubesolo-purge.nix`
clears what it left on the box, once. Git history has its module and its doc.

[Hermes Agent](https://github.com/NousResearch/hermes-agent), Nous Research's agent, runs on KVM 4 as a
NixOS service (`hermes.nix`), on Claude through the owner's subscription, with its web dashboard at
hermes.piabrota.art (`hermes-web.nix`). How it is set up, its secrets, and how to check it (the move
from KVM 1 is [`docs/MIGRATION-KVM4.md`](docs/MIGRATION-KVM4.md)):

- [`docs/HERMES.ptBR.md`](docs/HERMES.ptBR.md), em português
- [`docs/HERMES.md`](docs/HERMES.md), in English

PGX, a Postgres-compatible engine in one process, runs on KVM 4 for the next workload that needs
Postgres, instead of a PostgreSQL server or Docker (`pgx.nix`): what it is, its cost and its limits:

- [`docs/PGX.ptBR.md`](docs/PGX.ptBR.md), em português
- [`docs/PGX.md`](docs/PGX.md), in English

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
├── hosts/piabrota2/         KVM 4: the full Hermes, its GitHub App and dashboard, PGX (docs/DEPLOY.md)
├── piabrota.nix             the user h0ffmann and the base packages
├── tools.nix                light CLI tools, and the size and memory limits
├── deploy.nix               the deploy user that CI logs in as, GC, boot generation limit
├── loco.nix                 Loco apps: a sandboxed service each, SQLite, backups, nginx + ACME
├── apps.nix, apps/notes/    the Loco apps: a notes CRUD demo at www.piabrota.art/notes (docs/LOCO.md)
├── site.nix, site/          the static site on www.piabrota.art (Gleam + Lustre, prerendered by Nix)
├── pgx.nix, pgx/            PGX, a Postgres-compatible engine, its package and its VM test
├── hermes.nix               Hermes Agent, from its flake's NixOS module (docs/HERMES.md)
├── hermes-github.nix        Hermes's GitHub App: hermes/* branches and pull requests
├── hermes-web.nix           Hermes's dashboard on hermes.piabrota.art, behind nginx and basic auth
├── hermes-web/docs/         the page the dashboard's Documentation tab shows
├── kubesolo-purge.nix       a oneshot that clears what KubeSolo left on the box; delete once it ran
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
├── docs/KUBERNETES.ptBR.md  a survey of small Kubernetes for this VPS, in Portuguese
├── docs/KUBERNETES.md     the same, in English
├── docs/MICROK8S.ptBR.md    a plan for testing MicroK8s here, in Portuguese
├── docs/MICROK8S.md       the same, in English
├── docs/HERMES.ptBR.md      Hermes Agent here: setup, secrets, checks, in Portuguese
├── docs/HERMES.md         the same, in English
├── docs/PGX.ptBR.md         PGX here: cost, limits, use, in Portuguese
├── docs/PGX.md            the same, in English
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
