# nix-os

NixOS configuration of the piabrota Hostinger VPS, as a flake (`nixosConfigurations.piabrota`).

Changes reach the VPS only through GitHub: a merge to `main` builds the system in GitHub
Actions and deploys it with deploy-rs. [docs/DEPLOY.md](docs/DEPLOY.md) has how it works and
the one-time setup (deploy key, secrets, firewall).

| File | What it is |
|---|---|
| `flake.nix`, `flake.lock` | the system, the deploy-rs node, the checks |
| `configuration.nix` | the Hostinger KVM base: boot, disk, cloud-init, guest agent, SSH |
| `piabrota.nix` | the user `h0ffmann` and the packages |
| `tools.nix` | light CLI tools and the size and memory limits |
| `deploy.nix` | the `deploy` user that CI logs in as, garbage collection, generation limit |
| `keys/deploy.pub` | the public key of the CI deploy key |
| `scripts/specs.sh` | prints the machine's specs (POSIX sh) |
| `justfile` | `just build`, `just check`, `just deploy`, `just specs`, `just remote-specs` |
| `AGENTS.md` | rules for AI agents working here |
