<div align="center">

<img alt="无 (mu, no thing) brushed in its four strokes, drawn from Desmos equations, by @h0ffmann" src="docs/drawings/mu.svg" width="200"/>

# nix-os

<sub>无 · <i>mu</i> · the piabrota VPSs · <a href="#every-piabrotaart-address">addresses</a> · <a href="#reproduce-it">reproduce</a> · <a href="docs/DEPLOY.md">deploy</a> · <a href="docs/STRUCTURE.md">structure</a> · <a href="docs/FIGURES.md">figures</a> · <a href="#related-repositories">related</a> · <a href="llms.txt">llms.txt</a> · <a href="#license">license</a></sub>

[![ci](https://github.com/piabrota/nix-os/actions/workflows/ci.yml/badge.svg)](https://github.com/piabrota/nix-os/actions/workflows/ci.yml)
[![deploy](https://github.com/piabrota/nix-os/actions/workflows/deploy.yml/badge.svg?branch=main)](https://github.com/piabrota/nix-os/actions/workflows/deploy.yml)
[![NixOS 26.05](https://img.shields.io/badge/NixOS-26.05-1682D4?style=flat-square&logo=nixos&logoColor=white)](docs/STRUCTURE.md#what-it-pins)
[![license: MPL-2.0](https://img.shields.io/badge/license-MPL--2.0-1682D4?style=flat-square)](#license)
[![Ask DeepWiki](https://img.shields.io/badge/Ask-DeepWiki-1682D4?style=flat-square)](https://deepwiki.com/piabrota/nix-os)
[![Hermes Agent v0.23.1](https://img.shields.io/badge/Hermes_Agent-v0.23.1-1682D4?style=flat-square)](docs/HERMES.md)
[![hosts: piabrota + piabrota2](https://img.shields.io/badge/hosts-piabrota_%2B_piabrota2-1682D4?style=flat-square)](https://www.piabrota.art/hosts)
[![llms.txt: all the work of h0ffmann](https://img.shields.io/badge/llms.txt-all_the_work_of_h0ffmann-1682D4?style=flat-square)](llms.txt)
[![XERJ Corpus Hub contributor](https://hub.xerj.org/contributors/h0ffmann/badge.svg)](https://hub.xerj.org/contributors/h0ffmann)

</div>

> The NixOS configuration of the two Hostinger VPSs that serve piabrota.art.

This repository has one flake with one system for each host:

- **KVM 1** (`piabrota`, 1 vCPU, 4 GB) serves the public site.
- **KVM 4** (`piabrota2`, 4 vCPU, 16 GB) runs [Hermes Agent](https://github.com/NousResearch/hermes-agent), [OpenRig](https://github.com/mvschwarz/openrig) and the other web services.

Each change is a pull request. A merge to `main` builds the two systems and deploys them with [deploy-rs](https://github.com/serokell/deploy-rs). If SSH stops after a deploy, the host rolls back automatically.

[`llms.txt`](llms.txt) is an index of all the public work of [h0ffmann](https://github.com/h0ffmann), for AI agents and visitors. The site's [`/llms.txt`](https://www.piabrota.art/llms.txt) is the index of Piabrota only.

## Every piabrota.art address

| Address | What it is | Host |
|---|---|---|
| [`www.piabrota.art`](https://www.piabrota.art/) | The site, with [`/figures/`](https://www.piabrota.art/figures/), [`/llms.txt`](https://www.piabrota.art/llms.txt) and `/hermes/`. `piabrota.art` sends you here. | KVM 1 |
| [`skills.piabrota.art`](https://skills.piabrota.art/) | The skills website, from [piabrota/skills](https://github.com/piabrota/skills). | KVM 1 |
| [`hermes.piabrota.art`](https://hermes.piabrota.art/) | The Hermes dashboard ([specs](docs/HERMES.md)). | KVM 4 |
| [`rig.piabrota.art`](https://rig.piabrota.art/) | The OpenRig web UI ([specs](docs/OPENRIG.md)). | KVM 4 |
| [`metrics.piabrota.art`](https://metrics.piabrota.art/) | The metrics of the two hosts ([specs](docs/METRICS.md)). | KVM 4 |
| [`room.piabrota.art`](https://room.piabrota.art/) | A 3D room with a radio, from [piabrota/room](https://github.com/piabrota/room). | KVM 4 |
| [`grid.piabrota.art`](https://grid.piabrota.art/) | The same room, on its grid view. | KVM 4 |
| [`proof.piabrota.art`](https://proof.piabrota.art/) | The HTML pages of [h0ffmann/proof](https://github.com/h0ffmann/proof). | KVM 4 |
| [`pirsig.piabrota.art`](https://pirsig.piabrota.art/) | The video notes and figures of [piabrota/pirsig](https://github.com/piabrota/pirsig). | KVM 4 |
| [`wave.piabrota.art`](https://wave.piabrota.art/) | The website of [h0ffmann/ww3-gpu](https://github.com/h0ffmann/ww3-gpu). | KVM 4 |
| [`closed.piabrota.art`](https://closed.piabrota.art/) | The website of [h0ffmann/closed-source](https://github.com/h0ffmann/closed-source). | KVM 4 |
| [`marola.piabrota.art`](https://marola.piabrota.art/) | The marola website, until it moves to [marola.dev](https://marola.dev). | KVM 4 |

## Reproduce it

You need Nix with flakes, a GitHub account and one or two Hostinger KVM VPSs with the NixOS template.

1. Fork this repository. Then do the steps in [`docs/FORK.md`](docs/FORK.md) ([pt-BR](docs/FORK.ptBR.md)).
2. Build a host on your computer. This step does not deploy.

   ```console
   just build piabrota2   # build one host
   just check             # the checks that CI runs
   ```

3. Point the DNS A records of `hermes`, `rig` and `metrics` to KVM 4 before the deploy. If you do not, the TLS certificates fail.
4. On KVM 4, make the login file and the Hermes secrets file. [`docs/HERMES.md`](docs/HERMES.md) gives the commands.
5. Merge to `main`. [`docs/DEPLOY.md`](docs/DEPLOY.md) tells how the deploy and the rollback work.
6. Examine the hosts with `just remote-hermes-check` and `just remote-health`. Set `DEPLOY_HOST=<address>` first.

## Documentation

| Page | What it tells |
|---|---|
| [`docs/HERMES.md`](docs/HERMES.md), [`pt-BR`](docs/HERMES.ptBR.md) | How Hermes runs here: setup, secrets, dashboard, checks and updates. |
| [`docs/OPENRIG.md`](docs/OPENRIG.md) | OpenRig, the software factory, its UI and its guardrails. |
| [`docs/METRICS.md`](docs/METRICS.md), [`pt-BR`](docs/METRICS.ptBR.md) | The metrics page: the collector, the page and the tests. |
| [`docs/LOFI.md`](docs/LOFI.md), [`pt-BR`](docs/LOFI.ptBR.md) | The lofi bot in the Marola Discord. |
| [`docs/DEPLOY.md`](docs/DEPLOY.md) | How a merge gets to the VPSs, and the one-time setup. |
| [`docs/FORK.md`](docs/FORK.md), [`pt-BR`](docs/FORK.ptBR.md) | How to run your own VPS from a fork. |
| [`docs/STRUCTURE.md`](docs/STRUCTURE.md) | The pins, the file tree, the flake outputs and the `just` recipes. |
| [`docs/FIGURES.md`](docs/FIGURES.md) | The figures of the system, and how to read them. |
| [`docs/PGX.md`](docs/PGX.md), [`docs/LOCO.md`](docs/LOCO.md), [`docs/SITE.md`](docs/SITE.md), [`docs/THESIS.md`](docs/THESIS.md) | PGX, the Loco apps, the static site and the thesis rig. |
| [`AGENTS.md`](AGENTS.md) | The rules for AI agents that work here. |
| [Wiki](https://github.com/piabrota/nix-os/wiki) | A map of the system, in Portuguese and English. |

## Related repositories

Stars and commits on 2026-11-07.

| Project | Description | ⭐ Stars | Last commit | Commits in 2026 |
|---|---|---:|---|---:|
| [piabrota/room](https://github.com/piabrota/room) | A personal site that is a 3D room: switch camera shots, play VHS tapes, listen to lofi radio. Served here at room.piabrota.art. | 1 | 2026-11-07 | 49 |
| [h0ffmann/chaceon](https://github.com/h0ffmann/chaceon) | CPU and GPU wave modeling in pure agentic Rust. | 0 | 2026-11-04 | 108 |
| [marola-dev/marola](https://github.com/marola-dev/marola) | The umbrella of the [marola-dev](https://github.com/marola-dev) software fabric: a friendly guide to the sea near you, with water quality first. Site at [marola.dev](https://marola.dev). | 19 | 2026-10-29 | 604 |

## Credits

- The README layout follows [h0ffmann/awesome-neurosymbolic-ai](https://github.com/h0ffmann/awesome-neurosymbolic-ai), and before it [picasso](https://github.com/h0ffmann/picasso), which took it from [gvolpe/nix-config](https://github.com/gvolpe/nix-config). Several tools in `tools.nix` come from gvolpe's list.
- The drawing is made the way [pirsig](https://github.com/h0ffmann/pirsig)'s 無 is: `drawings/pen.nix` is pirsig's pen, ported from Rust to Nix (MPL-2.0, by the same author). See [docs/drawings](docs/drawings/README.md).
- The stroke order of 无 follows [KanjiVG](https://kanjivg.tagaini.net/) (© Ulrich Apel, CC BY-SA 3.0), used as a reference only.

## License

| What | License |
|---|---|
| Everything in this repository, the drawing included | [MPL-2.0](LICENSE) |
| `drawings/pen.nix` | MPL-2.0, ported from [h0ffmann/pirsig](https://github.com/h0ffmann/pirsig)'s Rust pen at `450e4da` |
| `.agents/skills/*/` | MIT, or Apache-2.0 for `frontend-design`, each from its upstream at a pinned commit ([`.agents/skills/README.md`](.agents/skills/README.md)); texts in `.agents/skills/LICENSES/` |
