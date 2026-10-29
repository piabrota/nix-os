# Operations

[Português](Operacao)

Commands run from the repository root, on any machine with Nix (it does not need NixOS). To see
every recipe: `just`.

| To | Run |
|---|---|
| Build the system without deploying it | `just build` |
| Run what CI runs | `just check` |
| See what a change adds to the system | `nix run nixpkgs#dix -- <old-system> <new-system>` |
| See the VPS's CPU, RAM, disk and generation | `just remote-specs` |
| List the VPS's packages with their sizes | `just remote-freeze` |
| CVE report of the system | `just cves` |

## Make a change

Open a branch, make the change and open a PR. CI builds the system; the merge deploys it. Say in
the PR what changed in the system (the `dix` summary). Nobody deploys from their own machine,
except for the first deploy ([`docs/DEPLOY.md`](https://github.com/piabrota/nix-os/blob/main/docs/DEPLOY.md)).

## Roll back

- On the VPS: `sudo nixos-rebuild switch --rollback`, or pick an older generation in the GRUB menu
  on the serial console.
- Then revert the commit on `main`. If you don't, the next deploy brings the change back.

## Turn on the site on piabrota.art

Point DNS at the VPS, then turn on `piabrota.site.enable` in a PR. The steps are in
[`docs/SITE.md`](https://github.com/piabrota/nix-os/blob/main/docs/SITE.md).

## Add an app

Package the app in its own flake, create its DNS record, put its secrets on the VPS and declare it
here: [`docs/LOCO.md`](https://github.com/piabrota/nix-os/blob/main/docs/LOCO.md).
