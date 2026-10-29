---
name: ultimate-nixos
description: "Comprehensive Nix ecosystem guidance covering NixOS system configuration, nixpkgs packaging and maintainer workflow, nix-darwin macOS management, Home Manager, flakes, derivations, NixOS module design, security hardening, and community processes. Use when writing Nix expressions, packaging software for nixpkgs, configuring NixOS or nix-darwin systems, designing NixOS modules, reviewing or merging nixpkgs PRs, managing secrets, hardening systems, working with flakes and overlays, or when the user mentions Nix, NixOS, nixpkgs, nix-darwin, Home Manager, flake, derivation, overlay, OfBorg, nixpkgs-review, or darwin-rebuild."
---

> Vendored from [kaynetik/skills](https://github.com/kaynetik/skills/blob/3ecbe1424cd5357bbb171e19cf27e2fc8dd83994/ultimate-nixos/SKILL.md) at `3ecbe1424cd5` (MIT, see
> `.claude/skills/LICENSES/`), with its `reference/` folder. Only this note was added; the text below is the upstream's.
>
> In this repo: one NixOS 26.05 host, `nixosConfigurations.piabrota`, a small VPS; prefer that release's option names, and judge every change by its closure size (AGENTS.md, "Resource budget").

# Nix ecosystem (NixOS, nixpkgs, nix-darwin)

Think in layers: **Nix language** evaluates expressions into **derivations**, which build into **store paths**. Everything else -- NixOS, nix-darwin, Home Manager, flakes -- is configuration that produces derivations.

## Reference files

| Topic | File | When to read |
| :--- | :--- | :--- |
| nix-darwin (macOS) | [reference/nix-darwin.md](reference/nix-darwin.md) | macOS system config, `darwin-rebuild`, Homebrew casks, launchd, Home Manager on macOS |
| Nixpkgs maintainers | [reference/maintainers.md](reference/maintainers.md) | PR workflow, OfBorg, merge bot, `nixpkgs-review`, r-ryantm, staging, backports, review norms |
| Derivations and packaging | [reference/derivations.md](reference/derivations.md) | `stdenv.mkDerivation`, `pkgs/by-name`, fetchers, language builders, `meta`, cross-compilation |
| Security | [reference/security.md](reference/security.md) | Hardened profile, firewall, AppArmor, systemd sandboxing, secrets (sops-nix, agenix), secure boot |
| Module system and modularity | [reference/modularity.md](reference/modularity.md) | NixOS/nix-darwin modules, `mkOption`, overlays, `specialArgs`, shared modules, anti-patterns |
| Flakes | [reference/flakes.md](reference/flakes.md) | Flake anatomy, `follows`, outputs, flake-parts, dev shells, ecosystem tools, Nix vs Lix, release channels |
| Community and governance | [reference/community.md](reference/community.md) | Communication channels, RFC process, release schedule, documentation hubs, reporting security issues |

Read the relevant reference before giving version-specific flags, option names, or configuration snippets. Prefer the user's NixOS/nixpkgs version when answers differ across releases.

## Mental model

```text
                    Nix language
                         |
                    evaluates to
                         |
                    derivations
                    /    |    \
               NixOS  nix-darwin  standalone
                |        |           |
            nixos-rebuild  darwin-rebuild  nix build / nix develop
                |        |           |
            /etc/nixos   flake.nix   flake.nix
                \        |          /
                 \       |         /
                  nixpkgs (package set)
                         |
                   Home Manager (user env, any host)
```

- **Nix** (or **Lix**): the language and package manager. Evaluates `.nix` files into derivations. Lix is a compatible fork; both are supported by nix-darwin and NixOS.
- **nixpkgs**: the package repository (100k+ packages). Provides `stdenv`, builders, NixOS modules, and library functions.
- **NixOS**: a Linux distribution configured entirely through Nix modules. Config lives in `/etc/nixos/` or a flake. Applied with `nixos-rebuild switch`.
- **nix-darwin**: the macOS equivalent of NixOS. Manages system settings, services, Homebrew, and launchd through Nix modules. Applied with `darwin-rebuild switch`.
- **Home Manager**: user-level environment management. Works standalone or as a module inside NixOS/nix-darwin. Manages dotfiles, shell config, user services.
- **Flakes**: the input/output schema for reproducible Nix projects. Pins dependencies via `flake.lock`. Still marked experimental in upstream Nix but universally adopted.

## Red flags (stop and verify)

- Guessing attribute names, option names, or builder arguments instead of checking docs or evaluating locally.
- Pushing untested changes that break nixpkgs evaluation (blocks OfBorg and Hydra for all PRs).
- Targeting the wrong branch (`staging` vs `master` vs `release-YY.MM`).
- Using `with pkgs;` at the top of a file (pollutes scope, hides where names come from).
- Using `rec { }` where `let ... in` would suffice (rec introduces subtle evaluation issues).
- Using `<nixpkgs>` lookup paths in flake-based setups (breaks reproducibility).
- Placing overlays inside `home.nix` when Home Manager runs with `useGlobalPkgs = true` (overlays are silently ignored; they belong in the host system config).
- Baking secrets into the Nix store (store paths are world-readable).
- Assuming `nix-darwin` modules and NixOS modules are interchangeable (they share patterns but have different option trees).

## Principles

### Reproducibility

Pin all inputs. Use flake locks or fixed hashes. Avoid mutable state (`nix-channel`, `<nixpkgs>`, `builtins.fetchTarball` without hash). The same config on the same inputs must produce the same system.

### Declarative configuration

Describe the desired state, not imperative steps. Prefer NixOS/nix-darwin module options over post-activation scripts. If an option does not exist, write a module rather than a shell script.

### Modularity

Split configuration by concern. Each module declares its options and activates conditionally (`lib.mkIf cfg.enable`). Compose modules through imports and `specialArgs`. Share modules across NixOS and nix-darwin where the option trees overlap.

### Security first

Use the hardened profile as a baseline. Manage secrets with sops-nix or agenix, never plain text in the store. Sandbox services with systemd options. Pin and audit dependencies. See [reference/security.md](reference/security.md).

### Minimal rebuilds

Understand the rebuild cost of changes. Layer cache-friendly operations. Use `nixos-rebuild build` or `darwin-rebuild build` to test before switching. For nixpkgs PRs, check rebuild counts before choosing `master` vs `staging`.

## Quick task map

| Task | Where to look |
| :--- | :--- |
| Package new software for nixpkgs | [reference/derivations.md](reference/derivations.md) |
| Configure a NixOS system | [reference/modularity.md](reference/modularity.md), [reference/flakes.md](reference/flakes.md) |
| Configure macOS with nix-darwin | [reference/nix-darwin.md](reference/nix-darwin.md) |
| Harden a NixOS system | [reference/security.md](reference/security.md) |
| Review or merge a nixpkgs PR | [reference/maintainers.md](reference/maintainers.md) |
| Set up a flake-based project | [reference/flakes.md](reference/flakes.md) |
| Write a NixOS/nix-darwin module | [reference/modularity.md](reference/modularity.md) |
| Manage user dotfiles | Home Manager docs + [reference/modularity.md](reference/modularity.md) (overlay scope) |
| Manage secrets | [reference/security.md](reference/security.md) |
| Find community help or report issues | [reference/community.md](reference/community.md) |
| Understand release channels and branches | [reference/flakes.md](reference/flakes.md), [reference/community.md](reference/community.md) |

## Workflow: packaging for nixpkgs

1. Determine the build system (autotools, cmake, cargo, go modules, npm, python setuptools/poetry, etc.).
2. Choose the right builder (`stdenv.mkDerivation`, `buildRustPackage`, `buildGoModule`, `buildNpmPackage`, `buildPythonPackage`).
3. Place the package in `pkgs/by-name/${shard}/${name}/package.nix` (RFC 140).
4. Add yourself to `maintainers/maintainer-list.nix` if not already there (separate commit).
5. Fill in `meta` with `description`, `homepage`, `license`, `maintainers`, `platforms`, and `mainProgram`.
6. Run `nix-build -A <attr>` locally; run `nixpkgs-review wip` to catch dependent breakage.
7. Open PR against `master` (or `staging` if rebuild count > 500).

See [reference/derivations.md](reference/derivations.md) and [reference/maintainers.md](reference/maintainers.md).

## Workflow: system configuration (NixOS or nix-darwin)

1. Initialize a flake with `nixosConfigurations` or `darwinConfigurations`.
2. Structure modules by feature (networking, desktop, services, users).
3. Use `specialArgs = { inherit inputs; }` to pass flake inputs into modules.
4. Apply overlays at the system level (`nixpkgs.overlays`), not inside Home Manager when `useGlobalPkgs = true`.
5. Manage secrets with sops-nix or agenix -- never commit plaintext secrets.
6. Build first (`nixos-rebuild build` / `darwin-rebuild build`), then switch.
7. Pin nixpkgs to a release branch (`nixos-25.11`) for stability, or `nixpkgs-unstable` for latest packages.

See [reference/flakes.md](reference/flakes.md), [reference/modularity.md](reference/modularity.md), and [reference/nix-darwin.md](reference/nix-darwin.md).

## Workflow: reviewing a nixpkgs PR

1. Check the target branch (`master`, `staging`, `release-YY.MM`).
2. Read the diff for correctness, meta completeness, and commit message convention.
3. Run `nixpkgs-review pr <NUMBER>` to build affected packages locally.
4. If OfBorg has not built, trigger with `@ofborg build attr1 attr2` (one command per line).
5. For `pkgs/by-name` changes by a maintainer: consider `@NixOS/nixpkgs-merge-bot merge`.
6. Give maintainers roughly one week before merging changes they have not endorsed.

See [reference/maintainers.md](reference/maintainers.md).
