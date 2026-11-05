# nix-os

[Português](Home)

The NixOS configuration of two live VPSs, both Hostinger KVM guests. `piabrota` (the KVM 1 plan:
1 vCPU, 4 GB RAM, a 50 GB disk) serves the public web. `piabrota2` (the KVM 4 plan) runs Hermes Agent,
its dashboard, OpenRig and PGX. Measured on `piabrota2` on 2026-11-04: 4 vCPU, 15.6 GiB RAM, a 196.8 GiB disk
(6 % used) and 7.8 GiB of swap; at rest, `hermes-agent` uses about 0.4 GiB, `hermes-backend` about
0.55 GiB and `pgx` about 0.1 GiB. Everything goes through GitHub: a pull request runs the CI
checks, and a merge to `main` builds and deploys each system.

OpenRig is the engine of the open software factory behind piabrota. [Factory](Factory) says what it
does today and what it will do: its seats have not run a task yet.

This wiki is a map. The rules and the step-by-step guides live in the repository, and each page
here points to them.

## Pages

- [Architecture](Architecture): the pieces, and how a change reaches the VPS.
- [Operations](Operations): day to day (build, check, roll back, turn the site on, add an app).
- [Hermes](Hermes-EN): how Hermes Agent runs here (the unit, the models, the limits, the restart on a deploy) and where its configuration is.
- [Factory](Factory): the open software factory, with OpenRig as its engine (the stages, who does each, the status today and the guardrails).
- [Runtimes](Runtimes-EN): the OpenRig runtimes (Claude Code, Codex, Pi, omp, terminal, stub and the community harnesses): pros, cons, and which ones the box runs.
- [Thesis](Thesis-EN): the rig that writes a UFRJ final-year project in Portuguese, one section at a time, with four gates and a PDF (no seat has run it yet).
- [Mockups](Mockups): three directions for the piabrota.art homepage, generated in Nix.

## Addresses

Every piabrota.art address that this repository serves. The full table, with the status of each, is
in the [README section "Every piabrota.art address"](https://github.com/piabrota/nix-os#every-piabrotaart-address).

- On `piabrota` (KVM 1), open: [www.piabrota.art](https://www.piabrota.art/) (the site, and also
  `/index/`, `/paths/`, `/hosts/`, `/hermes/` and `/skills/`) and `/nixos` (it leads to the
  repository). `piabrota.art` redirects to `www`.
- On `piabrota`, with one password: [www.piabrota.art/notes](https://www.piabrota.art/notes), the Loco app `notes`.
- On `piabrota2` (KVM 4), with a login (basic auth): [hermes.piabrota.art](https://hermes.piabrota.art/),
  the Hermes dashboard, and [rig.piabrota.art](https://rig.piabrota.art/), the OpenRig UI.
- `paperclip.piabrota.art`: off since 2026-11-04, no answer.

## In the repository

| For | Read |
|---|---|
| The rules for anyone changing the repository (people and agents) | [`AGENTS.md`](https://github.com/piabrota/nix-os/blob/main/AGENTS.md) |
| How the deploy works, and the one-time setup | [`docs/DEPLOY.md`](https://github.com/piabrota/nix-os/blob/main/docs/DEPLOY.md) |
| The static site on www.piabrota.art, and DNS on Porkbun | [`docs/SITE.md`](https://github.com/piabrota/nix-os/blob/main/docs/SITE.md) |
| Adding a Loco app | [`docs/LOCO.md`](https://github.com/piabrota/nix-os/blob/main/docs/LOCO.md) |
| Running your own VPS from a fork | [`docs/FORK.md`](https://github.com/piabrota/nix-os/blob/main/docs/FORK.md) |
| Hermes Agent on this machine | [`docs/HERMES.md`](https://github.com/piabrota/nix-os/blob/main/docs/HERMES.md), and its configuration as YAML at [www.piabrota.art/hermes](https://www.piabrota.art/hermes) |
| The figures as interactive pages | [www.piabrota.art/figures](https://www.piabrota.art/figures/) |

The pages come from the repository's [`wiki/`](https://github.com/piabrota/nix-os/tree/main/wiki)
folder and are copied here on every merge. Don't edit the wiki directly: the next copy erases the
edit.
