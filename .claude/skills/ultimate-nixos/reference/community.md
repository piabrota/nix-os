# Nix community and governance

Communication channels, RFC process, release cadence, documentation hubs, and community norms.

## Communication channels

| Platform | Channel | Purpose |
| :--- | :--- | :--- |
| Matrix | [#nix:nixos.org](https://matrix.to/#/#nix:nixos.org) | General Nix discussion |
| Matrix | [#nixos:nixos.org](https://matrix.to/#/#nixos:nixos.org) | NixOS configuration help |
| Matrix | [#macos:nixos.org](https://matrix.to/#/#macos:nixos.org) | macOS / nix-darwin questions |
| Matrix | [#nix-darwin-dev:nixos.org](https://matrix.to/#/#nix-darwin-dev:nixos.org) | nix-darwin development |
| Matrix | [#nix-dev:nixos.org](https://matrix.to/#/#nix-dev:nixos.org) | Nix language and tooling development |
| Discourse | [discourse.nixos.org](https://discourse.nixos.org/) | Long-form discussions, announcements, help |
| GitHub | [NixOS/nixpkgs](https://github.com/NixOS/nixpkgs) | Package repository (issues, PRs) |
| GitHub | [NixOS/nix](https://github.com/NixOS/nix) | Nix implementation |
| GitHub | [nix-darwin/nix-darwin](https://github.com/nix-darwin/nix-darwin) | macOS system management |

## RFC process

Significant changes to the Nix ecosystem go through the RFC process:

1. **Draft**: author writes an RFC in [NixOS/rfcs](https://github.com/NixOS/rfcs).
2. **Shepherds**: a team of community members is assigned to steward the RFC.
3. **Discussion**: community feedback on the PR.
4. **FCP (Final Comment Period)**: shepherds call for final comments before deciding.
5. **Accepted/Rejected**: shepherds merge or close.

Notable RFCs:
- RFC 140: `pkgs/by-name` package paths
- RFC 172: nixpkgs-merge-bot

Browse RFCs: [github.com/NixOS/rfcs](https://github.com/NixOS/rfcs).

## NixOS release schedule

NixOS follows a fixed six-month release cycle:

| Release | Date | Codename | Support ends |
| :--- | :--- | :--- | :--- |
| 25.05 | May 2025 | Warbler | December 2025 |
| 25.11 | November 2025 | Xantusia | June 2026 |
| 26.05 | May 2026 | Yarara | December 2026 |

Each release is supported for approximately 7 months (until one month after the next release). The `nixos-unstable` channel rolls continuously from `master`.

### Release highlights (25.11 "Xantusia")

- nixos-rebuild-ng (Python rewrite) enabled by default
- nixos-init (Rust-based systemd initrd)
- FirewallD support
- Limine secure boot support
- rEFInd bootloader support
- COSMIC DE beta
- PostgreSQL default version 17
- LLVM 21, GCC 14, Linux kernel 6.12
- 25,252 packages updated, 7,002 new packages, 107 new modules

### Upcoming (26.05 "Yarara")

- Linux kernel 6.18
- New modules: Meshtastic, knot-resolver 6, ImmichFrame, and more

## Key repositories

| Repository | Purpose |
| :--- | :--- |
| [NixOS/nixpkgs](https://github.com/NixOS/nixpkgs) | Package set, NixOS modules, lib |
| [NixOS/nix](https://github.com/NixOS/nix) | Nix package manager (upstream/CppNix) |
| [lix-project/lix](https://git.lix.systems/) | Lix (community fork of Nix) |
| [nix-darwin/nix-darwin](https://github.com/nix-darwin/nix-darwin) | macOS system management |
| [nix-community/home-manager](https://github.com/nix-community/home-manager) | User environment management |
| [NixOS/rfcs](https://github.com/NixOS/rfcs) | RFC proposals |
| [NixOS/nixpkgs-committers](https://github.com/NixOS/nixpkgs-committers) | Committer nominations |
| [NixOS/ofborg](https://github.com/NixOS/ofborg) | CI builder bot |
| [NixOS/nixpkgs-vet](https://github.com/NixOS/nixpkgs-vet) | `pkgs/by-name` validation |
| [Mic92/nixpkgs-review](https://github.com/Mic92/nixpkgs-review) | Local PR review tool |
| [nix-community/*](https://github.com/nix-community) | Community-maintained tools and modules |

## Documentation hubs

| Resource | URL | Content |
| :--- | :--- | :--- |
| nix.dev | [nix.dev](https://nix.dev/) | Tutorials, guides, best practices |
| NixOS manual | [nixos.org/manual/nixos/stable](https://nixos.org/manual/nixos/stable/) | NixOS configuration reference |
| Nixpkgs manual | [nixos.org/manual/nixpkgs/stable](https://nixos.org/manual/nixpkgs/stable/) | Packaging reference |
| Nix manual | [nixos.org/manual/nix/stable](https://nixos.org/manual/nix/stable/) | Nix language and CLI reference |
| NixOS options search | [search.nixos.org](https://search.nixos.org/) | Search packages and options |
| Nix function search | [noogle.dev](https://noogle.dev/) | Search `lib` and `builtins` functions |
| MyNixOS | [mynixos.com](https://mynixos.com/) | Browse options with examples |
| NixOS wiki | [wiki.nixos.org](https://wiki.nixos.org/) | Community wiki (official) |
| NixOS & Flakes Book | [nixos-and-flakes.thiscute.world](https://nixos-and-flakes.thiscute.world/) | Community flakes tutorial |
| Home Manager manual | [nix-community.github.io/home-manager](https://nix-community.github.io/home-manager/) | Home Manager options reference |
| nix-darwin manual | [nix-darwin.github.io/nix-darwin/manual](https://nix-darwin.github.io/nix-darwin/manual/) | nix-darwin options reference |

## Lix

Lix is a community fork of CppNix (diverged from release 2.18). Key facts:

- Fully compatible with existing Nix/NixOS/nix-darwin configurations and flakes.
- Independent governance and funding, not under the NixOS Foundation.
- Uses Meson build system; plans gradual Rust adoption.
- "Lix on main" program invites users to daily-drive latest changes with rapid support.
- Repository: [git.lix.systems](https://git.lix.systems/)
- FAQ: [lix.systems/faq](https://lix.systems/faq)

Switch to Lix in your system config:

```nix
nix.package = pkgs.lix;
```

## Reporting security issues

- **nixpkgs packages**: open a GitHub issue on [NixOS/nixpkgs](https://github.com/NixOS/nixpkgs/issues) with the `1.severity: security` label. For embargoed CVEs, follow the process in [CONTRIBUTING.md security section](https://github.com/NixOS/nixpkgs/blob/master/CONTRIBUTING.md).
- **Nix implementation**: report to the Nix security team via the process documented in the [Nix repository](https://github.com/NixOS/nix).
- **NixOS infrastructure**: contact the NixOS infrastructure team via Matrix or Discourse.

## Community norms

- **Conventional comments**: use prefixes like `suggestion:`, `nitpick:`, `question:` to signal intent and avoid implicit blockers.
- **Maintainer courtesy**: give maintainers roughly one week before merging changes they have not endorsed (exceptions: security fixes, `ci/OWNERS` packages).
- **Non-blocking default**: feedback is non-blocking unless you use GitHub "Request changes".
- **Be specific**: link to docs, provide examples, cite test results. Avoid vague concerns.
- **Review bots responsibly**: do not trigger expensive OfBorg builds or mass rebuilds without reviewing the diff first.

## Key references

- [NixOS Discourse](https://discourse.nixos.org/)
- [NixOS/rfcs](https://github.com/NixOS/rfcs)
- [Lix](https://lix.systems/)
- [nix.dev](https://nix.dev/)
- [search.nixos.org](https://search.nixos.org/)
