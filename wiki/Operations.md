# Operations

[Português](Operacao)

Commands run from the repository root, on any machine with Nix (it does not need NixOS). To see
every recipe: `just`.

| To | Run |
|---|---|
| Build the system without deploying it | `just build` |
| Run what CI runs | `just check` |
| See what a change adds to the system | `nix run nixpkgs#dix -- diff <old-system> <new-system>` |
| See a VPS's CPU, RAM, disk and generation | `just remote-specs` |
| List a VPS's packages with their sizes | `just remote-freeze` |
| CVE report of the system | `just cves` |

## The two hosts

`piabrota` (KVM 1) serves the public web. `piabrota2` (KVM 4) runs Hermes, its dashboard, OpenRig and PGX. The
`just remote-*` recipes read `DEPLOY_HOST` and default to `piabrota.art`, the `piabrota` host. For
`piabrota2`, set `DEPLOY_HOST` to its address:

```console
DEPLOY_HOST=<piabrota2 address> just remote-specs         # CPU, RAM, disk and generation
DEPLOY_HOST=<piabrota2 address> just remote-health        # memory, MemoryPeak against MemoryMax, disk and CPU, with the Hermes units
DEPLOY_HOST=<piabrota2 address> just remote-hermes-check  # Hermes's add-ons of the last deploy are live
```

`remote-health` runs the script of the `kvm4-health` skill, the same report that Hermes reads with
the `kvm4-health` command on the box.

## Make a change

Open a branch, make the change and open a PR. CI builds the system; the merge deploys it. Say in
the PR what changed in the system (the `dix` summary). Nobody deploys from their own machine,
except for the first deploy ([`docs/DEPLOY.md`](https://github.com/piabrota/nix-os/blob/main/docs/DEPLOY.md)).

## Roll back

- On a VPS: `sudo nixos-rebuild switch --rollback`, or pick an older generation in the GRUB menu
  on the serial console.
- Then revert the commit on `main`. If you don't, the next deploy brings the change back.

## The site on www.piabrota.art

The site is on. Both names, `piabrota.art` and `www`, must point at the `piabrota` VPS (KVM 1);
`hermes.piabrota.art` and `rig.piabrota.art` point at `piabrota2`. The DNS steps are in
[`docs/SITE.md`](https://github.com/piabrota/nix-os/blob/main/docs/SITE.md).

## Add an app

Package the app in its own flake, create its DNS record, put its secrets on the VPS and declare it
here: [`docs/LOCO.md`](https://github.com/piabrota/nix-os/blob/main/docs/LOCO.md).

## OpenRig and the rig UI

The OpenRig web UI is at [rig.piabrota.art](https://rig.piabrota.art/). The login is the same as for
the Hermes dashboard (basic auth). Take care: its terminal types into the seats, and the seats run
without approval prompts. Whoever reaches the UI runs commands as the user `openrig`. Never open the
UI without auth.

If the address does not open, use the SSH tunnel. On your computer, run:

```console
ssh -L 7433:127.0.0.1:7433 h0ffmann@<piabrota2 address>
```

Then open `http://localhost:7433` in a browser.

To look at the rig, Hermes runs these commands (the skill `hermes-rig`):

```console
rig status                         # must say "Daemon running"
rig ps --nodes --rig piabrota-dev  # one row per seat: dev-builder and dev-reviewer
```

On the box, `kvm4-health` lists the unit `openrig` with its memory against `MemoryMax`.

**The rule.** Hermes starts and stops the seats, only when the owner asks. No cron job does it. A
deploy that changes the unit `openrig` restarts it and ends the seats, and after it nothing starts
the rig. Today the seats are idle: no task has gone through them. The full guide is
[`docs/OPENRIG.md`](https://github.com/piabrota/nix-os/blob/main/docs/OPENRIG.md); the
[Factory](Factory) page says what the rig will do.
