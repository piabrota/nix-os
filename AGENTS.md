# AGENTS.md

Instructions for any AI coding agent working in this repository. Read this file before you change
or run anything. Humans should read it too.

## What this repo is

The NixOS configuration of one small, live VPS: a Hostinger KVM guest on Proxmox that hosts
piabrota.art/nixos. The machine has little RAM and a small disk, so every change is judged by what
it adds to the system closure and to memory use. Nothing here is a desktop: no GUI, no fonts, no
display server.

Agents do not run on the VPS. You work in a clone elsewhere, and a human deploys.

## Files

| File | Is |
|---|---|
| `configuration.nix` | The host: GRUB on `/dev/sda` (BIOS, MBR), root on the `nixos` label with auto-resize, serial console, QEMU guest agent, cloud-init (NoCloud, ConfigDrive), OpenSSH. It imports the two modules below. |
| `piabrota.nix` | Users and Nix settings: the `h0ffmann` user (SSH key only, passwordless sudo), flakes on, `allowUnfree` (for `claude-code`), the base packages. |
| `tools.nix` | Light CLI tools and defaults taken from [gvolpe/nix-config](https://github.com/gvolpe/nix-config), plus the size and memory limits. See "Resource budget". |
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

Never change `system.stateVersion`.

## Resource budget

The exact RAM and disk of the plan are not recorded here. Read them on the machine
(`free -h`, `df -h /`) before you rely on a number.

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
   `nix-output-monitor` from gvolpe's list were left out for this reason.
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

Garbage collection and the number of boot generations are not set yet. Add them in one module
only, so that two modules do not define the same option.

## Build

There is no flake yet. The configuration builds with the classic NixOS entry point. The
`stateVersion` is 26.05, so these commands use the `nixos-26.05` channel; check which channel the
VPS follows (`sudo nix-channel --list`) and use that one.

Build and evaluate, from the repository root, on any machine with Nix (it does not need NixOS):

```console
NIXPKGS=https://channels.nixos.org/nixos-26.05/nixexprs.tar.xz
nix build --impure --print-out-paths --expr \
  "(import \"\${builtins.fetchTarball \"$NIXPKGS\"}/nixos\" { configuration = $PWD/configuration.nix; }).system"
```

Add `--dry-run` to see what would be built and fetched. Compare two builds:

```console
nix run nixpkgs#dix -- <old-system-path> <new-system-path>
```

Lint the Nix files you changed:

```console
nix run nixpkgs#nixpkgs-fmt -- --check <file>.nix
nix run nixpkgs#statix -- check <file>.nix
nix run nixpkgs#deadnix -- --fail <file>.nix
```

## Deploy (a human does this)

An agent never deploys. It prepares the change and its PR; the human runs one of the commands
below.

Build on another machine and copy the result to the VPS. This keeps the compiler and the build
dependencies off the small disk:

```console
nix run nixpkgs#nixos-rebuild -- test --target-host h0ffmann@<vps> --sudo \
  -I nixos-config=./configuration.nix -I nixpkgs=channel:nixos-26.05
# if SSH and the guest agent still work:
nix run nixpkgs#nixos-rebuild -- switch --target-host h0ffmann@<vps> --sudo \
  -I nixos-config=./configuration.nix -I nixpkgs=channel:nixos-26.05
```

Or on the VPS, from a clone of this repository:

```console
sudo nixos-rebuild test   -I nixos-config=$PWD/configuration.nix
sudo nixos-rebuild switch -I nixos-config=$PWD/configuration.nix
```

`test` activates without adding a boot entry, so a reboot goes back to the last good system.
After a `switch`, the activation script prints the `dix` diff of the change. To undo a bad switch:
`sudo nixos-rebuild switch --rollback`, or pick an older generation in the GRUB menu on the
serial console.

## Justfiles

There is no justfile here yet. A justfile in this repository must run on the `just` that
`apt install just` gives on Ubuntu 24.04 LTS (just 1.21.0). Do not use syntax that version does
not know, such as the `[group(...)]` or `[positional-arguments]` attributes; use
`set positional-arguments` instead. CI must parse every justfile with that version
(`just --justfile <file> --summary`).

## Commits and PRs

- Commit messages, PR titles and PR bodies are in English.
- Work on a branch and open a PR. Do not push to `main`.
- Never commit a secret, a private key or an `.age` file (`.gitignore` blocks the usual names).
- The PR says what changed in the closure (the `dix` summary) and whether the build was run.
