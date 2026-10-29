<div align="center">

<img alt="无 (mu, no thing) brushed in its four strokes, drawn from Desmos equations, by @h0ffmann" src="docs/drawings/mu.svg" width="200"/>

# nix-os

<sub>无 · <i>mu</i> · the piabrota VPS · <a href="#in-one-minute">in one minute</a> · <a href="docs/DEPLOY.md">deploy</a> · <a href="#structure">structure</a> · <a href="#flake-outputs">flake outputs</a> · <a href="docs/drawings/README.md">the drawing</a> · <a href="#license">license</a></sub>

[![ci](https://github.com/piabrota/nix-os/actions/workflows/ci.yml/badge.svg)](https://github.com/piabrota/nix-os/actions/workflows/ci.yml)
[![deploy](https://github.com/piabrota/nix-os/actions/workflows/deploy.yml/badge.svg)](https://github.com/piabrota/nix-os/actions/workflows/deploy.yml)
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
- The machine is small, so every change is judged by what it adds to the closure and to memory
  ([`AGENTS.md`](AGENTS.md), "Resource budget").
- The layout of this README comes from [picasso](https://github.com/h0ffmann/picasso), which took it
  from [Gabriel Volpe's `nix-config`](https://github.com/gvolpe/nix-config).

## Recipes

```console
just build          # build the system here, without deploying it
just check          # what CI runs: nix flake check, nixpkgs-fmt, shellcheck
just deploy         # deploy by hand, as CI does (DEPLOY_HOST=<ip>; a human only)
just specs          # CPU, RAM, disk, kernel and NixOS generation of this machine
just remote-specs   # the same, of the VPS, over SSH
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
├── keys/deploy.pub          the public key of the CI deploy key
├── scripts/specs.sh         prints the machine's specs (POSIX sh)
├── scripts/freeze.sh        every package of the system with its size, like pip freeze
├── drawings/                the Rust crate that draws docs/drawings/mu.svg
├── docs/DEPLOY.md           how a merge reaches the VPS, and the one-time setup
├── docs/drawings/           the README drawing and its Desmos state
├── .github/workflows/       ci.yml (every PR and push), deploy.yml (push to main), freeze.yml (after each deploy)
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
│       ├───drawing: derivation 'mu-art-0.1.0'
│       └───toplevel: derivation 'nixos-system-nixos-26.05.20261028.08d3a97'
├───deploy: unknown
├───devShells
│   └───x86_64-linux
│       └───default: development environment 'nix-shell'
├───formatter
│   └───x86_64-linux: package 'nixpkgs-fmt-1.3.0'
├───nixosConfigurations
│   └───piabrota: NixOS configuration
└───packages
    └───x86_64-linux
        ├───deploy-rs: package 'deploy-rs-1.0.0'
        └───mu-art: package 'mu-art-0.1.0'
```

## Credits

- The README layout follows [picasso](https://github.com/h0ffmann/picasso), and through it
  [gvolpe/nix-config](https://github.com/gvolpe/nix-config). Several tools in `tools.nix` come from
  gvolpe's list.
- The drawing is made the way [pirsig](https://github.com/h0ffmann/pirsig)'s 無 is: `drawings/src/pen.rs`
  is pirsig's pen, copied unchanged (MPL-2.0, by the same author). See
  [docs/drawings](docs/drawings/README.md).
- The stroke order of 无 follows [KanjiVG](https://kanjivg.tagaini.net/) (© Ulrich Apel,
  CC BY-SA 3.0), used as a reference only.

## License

| What | License |
|---|---|
| Everything in this repository, the drawing included | [MPL-2.0](LICENSE) |
| `drawings/src/pen.rs` | MPL-2.0, from [h0ffmann/pirsig](https://github.com/h0ffmann/pirsig) at `450e4da` |
