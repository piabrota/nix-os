# AGENTS.md

Instructions for any AI coding agent working in this repository. Read this file before you change
or run anything. Humans should read it too.

## What this repo is

The NixOS configuration of one small, live VPS: a Hostinger KVM guest on Proxmox that hosts
piabrota.art/nixos. The machine has little RAM and a small disk, so every change is judged by what
it adds to the system closure and to memory use. Nothing here is a desktop: no GUI, no fonts, no
display server.

Agents do not run on the VPS. You work in a clone elsewhere and open a PR. A merge to `main` is
the deploy: GitHub Actions builds the system and switches the VPS to it ([docs/DEPLOY.md](docs/DEPLOY.md)).

## Files

| File | Is |
|---|---|
| `flake.nix`, `flake.lock` | The flake: `nixosConfigurations.piabrota` on `nixos-26.05`, the deploy-rs node `deploy.nodes.piabrota`, `checks` (the system and the deploy-rs checks), `packages.deploy-rs`. |
| `configuration.nix` | The host: GRUB on `/dev/sda` (BIOS, MBR), root on the `nixos` label with auto-resize, serial console, QEMU guest agent, cloud-init (NoCloud, ConfigDrive), OpenSSH. It imports the four modules below. |
| `piabrota.nix` | Users and Nix settings: the `h0ffmann` user (SSH key only, passwordless sudo), flakes on, the base packages. Nothing unfree: `allowUnfree` is off. |
| `tools.nix` | Light CLI tools and defaults taken from [gvolpe/nix-config](https://github.com/gvolpe/nix-config), plus the size and memory limits. See "Resource budget". |
| `deploy.nix` | The `deploy` user that CI logs in as (key from `keys/deploy.pub`), garbage collection, store optimisation, the boot generation limit, `max-jobs`/`cores`. |
| `loco.nix` | `piabrota.loco.apps.<name>`: a [Loco](https://loco.rs) app as the sandboxed service `loco-<name>` with SQLite in `/var/lib/loco-<name>`, a daily `sqlite3 .backup`, nginx with ACME, ports 80 and 443. With no app it adds nothing. `checks.loco-example` builds it with a stand-in app. See [docs/LOCO.md](docs/LOCO.md). |
| `keys/deploy.pub` | The public half of the CI deploy key. Never a private key. |
| `scripts/specs.sh` | POSIX sh: prints OS, kernel, CPU, RAM, swap, disk, uptime and the NixOS generation. |
| `scripts/freeze.sh` | POSIX sh, like `pip freeze`: every package of the running system as `name==version` with its size, and the total. `--by-size` sorts by size. |
| `.github/workflows/freeze.yml` | After each deploy and by hand: `scripts/freeze.sh` on the VPS, into the run summary and the `freeze` artifact. |
| `justfile` | `build`, `check`, `cves`, `deploy`, `specs`, `remote-specs`, `freeze`, `remote-freeze`, `drawing`. |
| `drawings/`, `docs/drawings/` | The README drawing, 无 (*mu*): a Rust crate (pirsig's pen) that writes `mu.svg` and its Desmos state. `checks.drawing` fails if the committed files are not its output; run `just drawing` after changing `drawings/src/mu.rs`. |
| `.github/workflows/cves.yml` | On every PR and push that changes more than Markdown, and each Monday: `vulnix --closure` on the built system, into the run summary. A report, not a gate: name matching gives false matches. `just cves` runs it here. |
| `.claude/skills/`, `.mcp.json` | Four Nix skills vendored at pinned commits (their README lists them and their licences) and the mcp-nixos server. Refresh a skill by recopying upstream, never by editing its body. |
| `.github/workflows/ci.yml` | On every PR and push that changes more than Markdown: `nix flake check`, `nixpkgs-fmt`, `shellcheck`, the justfile parse with Ubuntu's `just`. |
| `.github/workflows/deploy.yml` | On a push to `main` that changes more than Markdown: deploy-rs to the VPS, then `scripts/specs.sh` into the run summary. |
| `docs/LOCO.md` | How to add a Loco app: package it in its own flake, DNS, secrets on the box, declare it here. |
| `docs/DEPLOY.md` | How the deploy works and its one-time setup (key, secrets, firewall, first deploy). |
| `docs/FORK.ptBR.md`, `docs/FORK.md` | How to run your own VPS from a fork, in pt-BR first and its English mirror: what to change, and the manual steps on Hostinger and GitHub. Change both when a file they name changes. |
| `docs/KUBERNETES.ptBR.md`, `docs/KUBERNETES.md` | A survey of small Kubernetes distributions for this VPS (2026-10-29), in pt-BR first and its English mirror. Research only: the configuration runs none of them. Change both together. |
| `docs/CLAUDE_PROJECT.ptBR.md`, `docs/CLAUDE_PROJECT.md` | How to set up a Claude Project on a fork, in pt-BR first and its English mirror. For people only: an agent working here does not act on them. Change both together. |
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
- The `deploy` user, its key and `nix.settings.trusted-users` in `deploy.nix`, and
  `magicRollback` in `flake.nix`: without them CI cannot deploy, or cannot undo a switch that
  breaks SSH.

Never change `system.stateVersion`.

Loco apps: never put a secret in `piabrota.loco.apps.<name>.environment` (it lands in the world-readable
store); secrets go in the `environmentFile` on the box. Add an app only after its DNS record points at
the VPS, or the ACME order fails on the deploy. Do not add Postgres or Redis for an app: SQLite and
in-process workers (docs/LOCO.md).

## Resource budget

The VPS is on Hostinger's **KVM 1** plan (hPanel, 2026-10-29, from the owner):

| CPU | RAM | Disk | Bandwidth |
|---|---|---|---|
| 1 vCPU core | 4 GB | 50 GB | 4 TB a month |

These are the plan's figures. What the system can use is less (the kernel, zram, the root
partition). Read the machine's own numbers (`just remote-specs`, or the summary of the last
`deploy` run) before you rely on a number, and change this table when the plan changes.

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

`deploy.nix` sets garbage collection (weekly, paths older than 14 days), `auto-optimise-store`,
five boot generations and `max-jobs = 1`, `cores = 1`. Change them there, not in a second module.

## Build

The configuration is a flake. From the repository root, on any machine with Nix (it does not
need NixOS):

```console
just build        # nix build .#nixosConfigurations.piabrota.config.system.build.toplevel
just check        # what CI runs: nix flake check, nixpkgs-fmt, shellcheck
```

Add `--dry-run` to the `nix build` to see what would be built and fetched. Compare two builds:

```console
nix run nixpkgs#dix -- <old-system-path> <new-system-path>
```

Lint the Nix files you changed:

```console
nix run nixpkgs#nixpkgs-fmt -- --check <file>.nix
nix run nixpkgs#statix -- check <file>.nix
nix run nixpkgs#deadnix -- --fail <file>.nix
```

Update nixpkgs with `nix flake update` in its own PR; CI runs with `--no-update-lock-file`.

## Deploy

An agent never deploys and never runs `just deploy`. It prepares the change and its PR; the merge
to `main` deploys it ([docs/DEPLOY.md](docs/DEPLOY.md)).

`deploy.yml` builds the system on the GitHub runner, and deploy-rs copies it to the VPS over SSH
as the `deploy` user and activates it. The VPS compiles nothing; it fetches from
`cache.nixos.org` what the cache has. If SSH does not answer within 60 seconds after the switch,
deploy-rs rolls the VPS back (magic rollback). The secrets are `DEPLOY_SSH_KEY`, `DEPLOY_HOST`
and `DEPLOY_KNOWN_HOSTS` in the `prod` environment.

A human can deploy by hand with the same tool, for example the first time, before the `deploy`
user exists: `DEPLOY_HOST=<ip> just deploy h0ffmann`. To undo a bad switch on the VPS:
`sudo nixos-rebuild switch --rollback`, or pick an older generation in the GRUB menu on the
serial console; then revert the commit on `main`, or the next deploy brings it back.

## Justfiles

A justfile in this repository must run on the `just` that `apt install just` gives on Ubuntu
24.04 LTS (just 1.21.0). Do not use syntax that version does not know, such as the
`[group(...)]` or `[positional-arguments]` attributes; use `set positional-arguments` instead.
CI's `justfiles parse with Ubuntu's just` job (`ci.yml`, on `ubuntu-24.04`) parses every
justfile with that version (`just --justfile <file> --summary`). Do not move it to a newer
Ubuntu while 24.04 is supported.

## Commits and PRs

- **Hard rule: every PR is a bipr.** Write and open each PR with the `bipr` skill of
  [h0ffmann/ptbr-writer](https://github.com/h0ffmann/ptbr-writer/blob/main/skills/bipr/SKILL.md):
  the title in pt-BR, the body in pt-BR first and its English mirror after `---`. Leave out the
  skill's `footer.md`: the body ends with the English half. Commit messages stay in English.
- **Hard rule: no agent trail.** No commit, PR, issue, comment or file carries a mark of Claude or of
  any other agent or tool: no `Co-Authored-By:` agent trailer, no "Generated with" or "Generated by"
  line (the bipr footer included), no agent name as the commit author, no link to an agent session
  or project thread. A tool that appends such a line on its own: remove the line after it does.
- Work on a branch and open a PR. Do not push to `main`.
- Name an agent's branch `claude/<project>-<goal-slug>`: the project, then the goal of the work in a
  few lowercase words joined by `-`, for example `claude/nix-os-gitops-deploys`. Never use a branch
  name made from a thread or session id, such as `claude/project-thread-wchbf1`.
- Never commit a secret, a private key or an `.age` file (`.gitignore` blocks the usual names).
- The PR says what changed in the closure (the `dix` summary) and whether the build was run.
