<div align="center">

<img alt="无 (mu, no thing) brushed in its four strokes, drawn from Desmos equations, by @h0ffmann" src="docs/drawings/mu.svg" width="200"/>

# nix-os

<sub>无 · <i>mu</i> · the piabrota VPS · <a href="#in-one-minute">in one minute</a> · <a href="docs/DEPLOY.md">deploy</a> · <a href="#structure">structure</a> · <a href="#flake-outputs">flake outputs</a> · <a href="docs/drawings/README.md">the drawing</a> · <a href="#license">license</a></sub>

[![ci](https://github.com/piabrota/nix-os/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/piabrota/nix-os/actions/workflows/ci.yml)
[![deploy](https://github.com/piabrota/nix-os/actions/workflows/deploy.yml/badge.svg?branch=main)](https://github.com/piabrota/nix-os/actions/workflows/deploy.yml)
[![NixOS 26.05](https://img.shields.io/badge/NixOS-26.05-1682D4?style=flat-square&logo=nixos&logoColor=white)](#what-it-pins)
[![license: MPL-2.0](https://img.shields.io/badge/license-MPL--2.0-1682D4?style=flat-square)](#license)

</div>

## In one minute

- nix-os is the NixOS configuration of one small, live VPS: a Hostinger KVM guest that serves
  [piabrota.art/nixos](https://piabrota.art/nixos). It is a flake with one system,
  `nixosConfigurations.piabrota`.
- Every change goes through GitHub. A pull request builds the whole system in CI; a merge to
  `main` deploys it. The GitHub runner builds, [deploy-rs](https://github.com/serokell/deploy-rs)
  copies the result over SSH and switches the VPS, and the VPS rolls back by itself if SSH stops
  answering. The VPS compiles nothing. [`docs/DEPLOY.md`](docs/DEPLOY.md) has the one-time setup.
- The machine is small: Hostinger's **KVM 1** plan, with 1 vCPU core, 4 GB RAM, a 50 GB disk
  and 4 TB of bandwidth a month (hPanel, 2026-10-29). Every change is judged by what it adds to
  the closure and to memory ([`AGENTS.md`](AGENTS.md), "Resource budget").
- It is ready to host [Loco](https://loco.rs) apps (Rust and SQLite) behind nginx with HTTPS:
  declare an app and the merge deploys it ([`docs/LOCO.md`](docs/LOCO.md)). Until then it adds
  nothing to the system.
- The layout of this README comes from [picasso](https://github.com/h0ffmann/picasso), which took it
  from [Gabriel Volpe's `nix-config`](https://github.com/gvolpe/nix-config).

## How it works

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

`just figure` draws both again with the pinned [archify](https://github.com/tt-a1i/archify)
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

## Recipes

```console
just build          # build the system here, without deploying it
just check          # what CI runs: nix flake check, nixpkgs-fmt, statix, deadnix, shellcheck
just deploy         # deploy by hand, as CI does (DEPLOY_HOST=<ip>; a human only)
just specs          # CPU, RAM, disk, kernel and NixOS generation of this machine
just remote-specs   # the same, of the VPS, over SSH
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
| [nixpkgs](https://github.com/NixOS/nixpkgs/tree/nixos-26.05) `nixos-26.05` | [`08d3a97`](https://github.com/NixOS/nixpkgs/commit/08d3a97586f6b6343b3b5e799980773629432610) (2026-10-28) | the system; `system.stateVersion` is 26.05 |
| [deploy-rs](https://github.com/serokell/deploy-rs) | [`1cec052`](https://github.com/serokell/deploy-rs/commit/1cec0527bd09074bbee6d4461900ce5d58267217) (2026-10-19) | the activation and its rollback; the `deploy` binary comes from nixpkgs, so CI does not compile it |

`flake.lock` is the truth; this table is what it held on 2026-10-29. Update with
`nix flake update` in a pull request.

</details>

## Structure

```
.
├── flake.nix, flake.lock    the system, the deploy-rs node, the checks
├── configuration.nix        the Hostinger KVM base: boot, disk, cloud-init, guest agent, SSH
├── piabrota.nix             the user h0ffmann and the base packages
├── tools.nix                light CLI tools, and the size and memory limits
├── deploy.nix               the deploy user that CI logs in as, GC, boot generation limit
├── loco.nix                 Loco apps: a sandboxed service each, SQLite, backups, nginx + ACME
├── site.nix, site/          the static site on www.piabrota.art (Gleam + Lustre, prerendered by Nix)
├── keys/deploy.pub          the public key of the CI deploy key
├── scripts/specs.sh         prints the machine's specs (POSIX sh)
├── scripts/freeze.sh        every package of the system with its size, like pip freeze
├── drawings/                the pen and the drawing, in Nix, that draw docs/drawings/mu.svg
├── mockups/                 three mockups of the piabrota.art homepage, SVG in pure Nix (docs/MOCKUPS.md)
├── docs/archify/, docs/img/ the figures' archify sources and PNGs; vendor/archify is the pinned archify
├── docs/DEPLOY.md           how a merge reaches the VPS, and the one-time setup
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
├── docs/drawings/           the README drawing and its Desmos state
├── .github/workflows/       ci.yml (every PR and push beyond Markdown), cves.yml (push to main beyond Markdown, and weekly), deploy.yml (push to main beyond Markdown), freeze.yml (after each deploy), wiki.yml (copies wiki/ to the GitHub wiki)
├── .github/dependabot.yml   one PR a week that bumps the actions the workflows use
├── wiki/                    the GitHub wiki's pages, in Portuguese and English
├── .claude/skills/          vendored skills for agents, four Nix, three frontend, figure and archify (their README); .mcp.json: mcp-nixos, OpenPencil
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
│       └───toplevel: derivation 'nixos-system-nixos-26.05.20261028.08d3a97'
├───deploy: unknown
├───devShells
│   └───x86_64-linux
│       ├───default: development environment 'nix-shell'
│       └───site: development environment 'nix-shell'
├───formatter
│   └───x86_64-linux: package 'nixpkgs-fmt-1.3.0'
├───nixosConfigurations
│   └───piabrota: NixOS configuration
└───packages
    └───x86_64-linux
        ├───deploy-rs: package 'deploy-rs-1.0.0'
        ├───mockups: package 'mockups'
        ├───mu-art: package 'mu-art'
        └───site: package 'piabrota-site-1.0.0'
```

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
