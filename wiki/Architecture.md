# Architecture

[Português](Arquitetura)

## The pieces

| File | What it does |
|---|---|
| `flake.nix` | The system `nixosConfigurations.piabrota` (nixos-26.05), the deploy-rs node and CI's `checks`. |
| `configuration.nix` | The Hostinger base: GRUB on `/dev/sda`, cloud-init, the QEMU agent, SSH. It imports the modules below. |
| `piabrota.nix` | The `h0ffmann` user (SSH key only) and the base packages. |
| `tools.nix` | Light command-line tools, and the disk and memory limits. |
| `deploy.nix` | The `deploy` user CI logs in as, garbage collection and the boot generation limit. |
| `loco.nix` | [Loco](https://loco.rs) apps as sandboxed systemd services, with SQLite, nginx and HTTPS. |
| `site.nix` | The static site from `site/` on www.piabrota.art, over HTTP and HTTPS; `piabrota.art` redirects to `www`. |

## From a pull request to the VPS

```
PR ──► ci.yml: nix flake check (builds the system), nixpkgs-fmt, statix, deadnix, shellcheck
   └─► cves.yml: a vulnix report on the built system
merge to main ──► deploy.yml: the runner builds, deploy-rs copies over SSH and activates
                    └─► if SSH does not answer within 60 s, the VPS rolls back by itself (magic rollback)
              └─► freeze.yml: the VPS's package list in the run summary
              └─► wiki.yml: copies wiki/ to this wiki (when wiki/ changed)
```

The VPS compiles nothing: it fetches from `cache.nixos.org` what the cache has. Every deploy is a
new generation, and GRUB keeps the last five.

## What must not break

The QEMU agent, cloud-init, SSH with `h0ffmann`'s key, GRUB on `/dev/sda`, the `deploy` user and
magic rollback. Without them, Hostinger cannot provision the machine or CI cannot deploy. The full
list is in [`AGENTS.md`](https://github.com/piabrota/nix-os/blob/main/AGENTS.md), "Do not break the machine".
