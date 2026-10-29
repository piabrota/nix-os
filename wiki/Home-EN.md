# nix-os

[Português](Home)

The NixOS configuration of one small, live VPS: a Hostinger KVM guest (the KVM 1 plan: 1 vCPU,
4 GB RAM, a 50 GB disk). Everything goes through GitHub: a pull request builds the whole system
in CI, and a merge to `main` deploys it.

This wiki is a map. The rules and the step-by-step guides live in the repository, and each page
here points to them.

## Pages

- [Architecture](Architecture): the pieces, and how a change reaches the VPS.
- [Operations](Operations): day to day (build, check, roll back, turn the site on, add an app).

## In the repository

| For | Read |
|---|---|
| The rules for anyone changing the repository (people and agents) | [`AGENTS.md`](https://github.com/piabrota/nix-os/blob/main/AGENTS.md) |
| How the deploy works, and the one-time setup | [`docs/DEPLOY.md`](https://github.com/piabrota/nix-os/blob/main/docs/DEPLOY.md) |
| The static site on piabrota.art | [`docs/SITE.md`](https://github.com/piabrota/nix-os/blob/main/docs/SITE.md) |
| Adding a Loco app | [`docs/LOCO.md`](https://github.com/piabrota/nix-os/blob/main/docs/LOCO.md) |
| Running your own VPS from a fork | [`docs/FORK.md`](https://github.com/piabrota/nix-os/blob/main/docs/FORK.md) |
| Kubernetes on this machine | [`docs/KUBERNETES.md`](https://github.com/piabrota/nix-os/blob/main/docs/KUBERNETES.md), [`docs/MICROK8S.md`](https://github.com/piabrota/nix-os/blob/main/docs/MICROK8S.md) |

The pages come from the repository's [`wiki/`](https://github.com/piabrota/nix-os/tree/main/wiki)
folder and are copied here on every merge. Don't edit the wiki directly: the next copy erases the
edit.
