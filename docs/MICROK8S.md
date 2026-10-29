# MicroK8s on piabrota

[Português](MICROK8S.ptBR.md) (the first version; this page is its English mirror)

A survey, from 2026-10-29, for the next PR: testing MicroK8s on this VPS with Kubernetes
management kept apart from operating-system management. It is research only: nothing in the
configuration changed because of it. It adds to [`KUBERNETES.md`](KUBERNETES.md), which compared
the distributions and rated MicroK8s "no".

## Short answer

- MicroK8s ships only as a snap, and nixpkgs has no snapd. The only route on NixOS is the
  community flake [nix-community/nix-snapd](https://github.com/nix-community/nix-snapd)
  (`services.snap.enable`).
- I found no report of MicroK8s running on NixOS that way, and nix-snapd's README does not say
  whether `classic` confinement snaps (which MicroK8s needs) work. Treat it as an experiment: test
  it in a local VM before the VPS.
- To keep it modular, split it in two layers: the **node** (snapd, MicroK8s, kernel, firewall)
  lives in this repository behind a flag that is off by default; the **workloads** (manifests,
  charts) live in `k8s/` with their own workflow. A system deploy never touches the pods, and a
  pod change never switches the system.
- If nix-snapd cannot run MicroK8s, the same split works with `services.k3s`, which is native to
  NixOS.

## How MicroK8s would get onto NixOS

| Point | What happens | What it means here |
|---|---|---|
| Install | `snap install microk8s --classic`, through nix-snapd's snapd | A new flake input (`nix-snapd`, with `nixpkgs.follows`) |
| Confinement | A `strict` variant exists, but it blocks workloads that need a mount shared with the host | Use `--classic`, which is exactly what nobody has tested on nix-snapd |
| Updates | snapd updates the snap by itself, outside Nix | A NixOS rollback does not roll MicroK8s back. Pin the channel (`--channel=1.3x/stable`) and hold refreshes (`snap refresh --hold microk8s`) |
| State | `/var/snap/microk8s`, `/var/lib/snapd`, `/snap` | Outside the store: Nix garbage collection does not touch it, and turning the flag off does not delete it |
| Memory | 540 MB minimum, 4 GB recommended (sources below) | Fits on KVM 1 only with few add-ons, sharing the one core with nginx and the apps |

## The two layers

### Layer 1: the node (this repository, `deploy.yml`)

A `k8s.nix` module with `piabrota.k8s.enable`, off by default, like `site.nix`. When on, it:

- imports `nix-snapd.nixosModules.default` and turns on `services.snap.enable`;
- runs a oneshot unit, `microk8s-install`, that installs the snap on the pinned channel if it is
  not installed yet, and holds its refreshes;
- loads the `br_netfilter` and `overlay` kernel modules and turns on `net.ipv4.ip_forward`;
- trusts the CNI interfaces in the firewall (`cali+`, `vxlan.calico`) and keeps the API (16443)
  closed: access goes through an SSH tunnel;
- reserves memory for the system in the kubelet (`--system-reserved=memory=512Mi`), so a pod
  cannot take `sshd` down.

A `checks.k8s-example` builds the system with the flag on, like `checks.loco-example`, so CI
catches a broken module before anyone turns the flag on.

Why not a second `nixosConfiguration` or a separate deploy-rs profile: the VPS has one system
profile. Two systems for the same machine overwrite each other on every deploy, and whichever
deployed last would win. The flag is how Kubernetes is turned on and off without splitting the
system.

### Layer 2: the workloads (`k8s/`, their own workflow)

- The manifests (or a `kustomization.yaml`) live in `k8s/`, or in a separate repository.
- A `k8s.yml` runs on a push to `main` that changes `k8s/**`: it opens an SSH tunnel to port
  16443 and runs `kubectl apply --server-side -k k8s/`. The kubeconfig is a secret of a `k8s`
  environment, separate from `prod`.
- `deploy.yml` adds `k8s/**` to its `paths-ignore`. A system deploy then never reapplies the pods,
  and a pod change never switches the system.
- Alternative: Flux, installed once, pulls `k8s/` by itself and needs no inbound access. It costs
  four controllers, a few hundred MiB more. On a 4 GB machine, the `kubectl` workflow is cheaper.

### Ingress

nginx keeps ports 80 and 443 (the site and the Loco apps). MicroK8s's `ingress` add-on stays off;
nginx proxies to a NodePort, as it already does for the Loco apps.

## Test plan for the next PR

1. **Local.** Build the VM with the flag on (`nix run .#nixosConfigurations.piabrota.config.system.build.vm`,
   on an x86_64 machine with KVM) and check that `snap install microk8s --classic` works and that
   `microk8s status --wait-ready` finishes. A `nixosTest` in CI does not help here: the test VM has
   no network and cannot download the snap.
2. **Before the VPS.** Take a Hostinger snapshot. deploy-rs's magic rollback only guards SSH, not
   memory.
3. **On the VPS.** Merge the PR with the flag on and measure: `free -m` at idle, the time to
   `status --wait-ready`, and a test pod reached through nginx on a NodePort.
4. **Exit.** `sudo snap remove --purge microk8s`, then a PR that turns the flag off, then delete
   `/var/lib/snapd` by hand.
5. **If nix-snapd fails.** The same two-layer split on `services.k3s`
   ([`KUBERNETES.md`](KUBERNETES.md) has the trimmed configuration).

## Sources and what was not checked

- nix-snapd: [README](https://github.com/nix-community/nix-snapd) and the
  [NixOS wiki's Snap page](https://wiki.nixos.org/wiki/Snap), which says snap is not in nixpkgs
  yet.
- MicroK8s as a snap only: the [Snap Store](https://snapcraft.io/microk8s) and
  [this Hacker News comment](https://news.ycombinator.com/item?id=27916515).
- Strict confinement: [MicroK8s docs](https://microk8s.io/docs/strict-confinement).
- Memory: the same sources as [`KUBERNETES.md`](KUBERNETES.md) (540 MB and 4 GB, not confirmed on
  Canonical's own page).
- Not checked: MicroK8s actually running through nix-snapd, its memory use on this VPS, and
  whether the `snap.microk8s.*` units accept memory limits set from NixOS.
