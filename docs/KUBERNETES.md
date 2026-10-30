# Kubernetes on piabrota

[Português](KUBERNETES.ptBR.md)

A survey, from 2026-10-29, of the small Kubernetes distributions that could run on this VPS
next to what it already hosts: nginx with ACME in front of Loco apps (Rust and SQLite), each a
sandboxed systemd service with `MemoryMax=256M` by default (`loco.nix`). It is research only:
nothing in the configuration changed because of it.

The machine is Hostinger's **KVM 1** plan: 1 vCPU, 4 GB RAM (plus 50% zram), a 50 GB disk,
NixOS 26.05, a system closure of 1.19 GiB.

## Recommendation

**Don't run Kubernetes on this machine for the current workload.**

The one distribution that NixOS supports well is k3s, and it would fit in memory, but only just:
its own docs measure a single-node server at 1.2 to 1.45 GB with nothing deployed. That is a
third of the RAM, and a share of the only core, spent on orchestrating a few systemd services
that NixOS already orchestrates, with rollback, through deploy-rs.

If you want containers, use `virtualisation.oci-containers` with podman: no daemon at idle, about
200 MiB of closure. If you want Kubernetes itself (to learn it, or because a chart needs it), use
`services.k3s` trimmed as below, or move to a KVM 2 plan, where it does not compete with the apps
for the machine.

## The options

"Closure added" is what the package adds to the deployed system beyond what is already in it,
measured on cache.nixos.org for nixpkgs `08d3a97` (the rev in `flake.lock`). Where a project is
not in nixpkgs, there is no closure to measure.

| Option | Idle RAM | Idle CPU | Closure added | On NixOS 26.05 | Maintenance | Fits here |
|---|---|---|---|---|---|---|
| **k3s** (SUSE / Rancher, CNCF) | 1.2–1.45 GB | 5–25% of a core | +472 MiB | `services.k3s` in nixpkgs, package 1.35.8+k3s1, NixOS tests, declarative manifests and Helm charts | patch releases every month | tight |
| **k3s, trimmed** | ~1.2 GB | same | +472 MiB | the same module, with `--disable` flags | same | tight |
| **KubeSolo** (Portainer) | <200 MB (vendor) | not published | not in nixpkgs | no package and no module; you would package the Go binary | v1.2.3 on 2026-10-27, releases every few weeks; a young project from one company | fits, unpackaged |
| **k0s** (Mirantis, CNCF sandbox) | ≥1 GB (docs minimum) | 1 vCPU minimum | not in nixpkgs | only the community flake `johbo/k0s-nix`, marked experimental | active: v1.36.3, 1.37 in alpha | tight, unpackaged |
| **MicroK8s** (Canonical) | 540 MB min., 4 GB recommended | not published | n/a | snap only, and nixpkgs has no `snapd` | active, made for Ubuntu | no |
| *Nomad* (HashiCorp), comparison | not measured | not measured | not cached | `services.nomad` exists, but the package is BUSL-1.1, so unfree; this repo keeps `allowUnfree` off | active; licence changed in 2023 | excluded |
| *systemd + podman*, comparison | ≈0 (no daemon) | ≈0 | +200 MiB | `virtualisation.podman`, `virtualisation.oci-containers` | Red Hat, steady releases (5.8.9 here) | yes |
| *systemd alone* (today) | 0 | 0 | 0 | `loco.nix` already does it | you | yes |

- **k3s.** The only Kubernetes with first-class NixOS support: a maintained module, a package
  that tracks upstream, and manifests declared in Nix. On this machine its 1.2 GB idle floor plus
  the apps leaves little headroom, and the one core is shared by the pods, nginx and the deploy
  activation. Its bundled Traefik and ServiceLB want ports 80 and 443, which nginx holds, so both
  have to go.
- **KubeSolo.** Now packaged to try, behind a flag that is off: [`KUBESOLO.md`](KUBESOLO.md). The lightest on paper: one process, SQLite through Kine, no etcd and no
  scheduler. The 200 MB figure is Portainer's own, and the project says it does not pass CNCF
  conformance. It is not in nixpkgs: you would write the derivation and the systemd unit and keep
  them current. Worth watching, not yet worth carrying.
- **k0s.** Well maintained upstream and a single binary, but on NixOS it exists only in an
  experimental community flake, and its documented minimum for controller plus worker is 1 vCPU
  and 1 GB, the same order as k3s without the module support.
- **MicroK8s.** Ships only as a snap. NixOS has no snapd, so there is no supported way to
  install it, and Canonical recommends 4 GB for real workloads, which is the whole machine.

## If you run k3s anyway

A trimmed single-node server: SQLite instead of etcd (the default for one server), nginx stays
at the edge, and the add-ons you don't need are off. Not built or tested; measure it with `dix`,
as `AGENTS.md` asks.

```nix
services.k3s = {
  enable = true;
  role = "server";
  extraFlags = [
    "--disable=traefik"          # nginx already owns 80 and 443
    "--disable=servicelb"
    "--disable=metrics-server"
    "--disable=local-storage"    # keep it if a pod needs a PVC
    "--disable-cloud-controller"
    "--disable-helm-controller"  # drop this if you use services.k3s.autoDeployCharts
    "--kubelet-arg=system-reserved=memory=512Mi"
  ];
};
# nginx then proxies to a NodePort, as it does for the Loco apps today.
# Plan for the closure to go from 1.19 GiB to about 1.65 GiB, plus the images in /var/lib/rancher.
```

## Sources and what was not checked

- k3s RAM and CPU: [k3s resource profiling](https://docs.k3s.io/reference/resource-profiling)
  (server with no workload: 1428 MB with SQLite and 1450 MB with etcd on an Intel 8375C,
  1215 MB on a Pi 4B; 5% and 25% of a core).
- k0s: [k0s system requirements](https://docs.k0sproject.io/main/system-requirements/); on
  NixOS: [johbo/k0s-nix](https://github.com/johbo/k0s-nix); versions from the
  [v1.36.3 notes](https://newreleases.io/project/github/k0sproject/k0s/release/v1.36.3%2Bk0s.0).
- KubeSolo: [portainer/kubesolo](https://github.com/portainer/kubesolo) and
  [its docs](https://kubesolo.pages.dev/documentation); versions from
  [pkg.go.dev](https://pkg.go.dev/github.com/portainer/kubesolo?tab=versions).
- MicroK8s: 540 MB and 4 GB from
  [LinuxConfig](https://linuxconfig.org/linux-system-requirements-for-kubernetes) and the
  [Kubernetes forum](https://discuss.kubernetes.io/t/get-started/18344); not confirmed on
  Canonical's own page.
- Versions, licences, modules and closures: evaluated from the nixos-26.05 channel at `08d3a97`
  and with `nix path-info` against cache.nixos.org. "Closure added" is the closure minus that of
  systemd, coreutils, bash, openssh, nginx, iptables, util-linux, glibc, sqlite, openssl, curl
  and git, so it is close to the `dix` number, not equal to it.
- Not checked: the machine's current memory use, the idle CPU of Nomad and KubeSolo, and any of
  these options running on this VPS.
