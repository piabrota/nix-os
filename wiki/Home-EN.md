# nix-os

[Português](Home)

The NixOS configuration of two Hostinger VPSs. Each change is a pull request. A merge to `main`
builds the two systems and deploys them.

- `piabrota` (KVM 1: 1 vCPU, 4 GB RAM) serves the public site.
- `piabrota2` (KVM 4: 4 vCPU, 16 GB RAM) runs Hermes Agent, its dashboard, OpenRig, PGX and the
  other web services.

OpenRig is the engine of the open software factory of piabrota. [Factory](Factory) tells what it
does today and what it will do.

This wiki is a map. The rules and the procedures are in the repository. Each page here links to
them.

## Pages

- [Architecture](Architecture): the pieces, and how a change reaches the VPS.
- [Operations](Operations): day to day (build, check, roll back, turn the site on, add an app).
- [Hermes](Hermes-EN): how Hermes Agent runs here (the unit, the models, the limits, the restart on a deploy) and where its configuration is.
- [Factory](Factory): the open software factory, with OpenRig as its engine (the stages, who does each, the status today and the guardrails).
- [Runtimes](Runtimes-EN): the OpenRig runtimes (Claude Code, Codex, Pi, omp, terminal, stub and the community harnesses): pros, cons, and which ones the box runs.
- [Thesis](Thesis-EN): the rig that writes a UFRJ final-year project in Portuguese, one section at a time, with four gates and a PDF (no seat has run it yet).
- [Reels](Reels-EN): the Reels Fabric, the OpenRig rig that makes 15 s and 30 s Instagram videos, with the screenplay as the source and Claude only (no media API).
- [Mockups](Mockups): three directions for the piabrota.art homepage, generated in Nix.

## Addresses

The [README](https://github.com/piabrota/nix-os#every-piabrotaart-address) has the full list.

- On `piabrota` (KVM 1): [www.piabrota.art](https://www.piabrota.art/), the site, and
  [skills.piabrota.art](https://skills.piabrota.art/), the skills website. `piabrota.art` sends you
  to `www`.
- On `piabrota2` (KVM 4), with a login: [hermes.piabrota.art](https://hermes.piabrota.art/), the
  Hermes dashboard, and [rig.piabrota.art](https://rig.piabrota.art/), the OpenRig UI.
- On `piabrota2`, open: [metrics.piabrota.art](https://metrics.piabrota.art/), the metrics of the
  two hosts, and the project websites (room, grid, proof, pirsig, wave, closed, marola).

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
