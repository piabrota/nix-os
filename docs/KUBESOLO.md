# KubeSolo on piabrota

[Português](KUBESOLO.ptBR.md) (the first version; this page is its English mirror)

How to try [KubeSolo](https://github.com/portainer/kubesolo) on this VPS, and how to go back. The
module is `kubesolo.nix`, behind `piabrota.kubesolo.enable`, off by default (off, the built
system is identical to the one before: the same store path) and **on** in `configuration.nix`
since 2026-10-30. The design follows
[`MICROK8S.md`](MICROK8S.md): the node lives in this repository, the workloads live in `k8s/` and
go in through an SSH tunnel, never through a system deploy.

Written on 2026-10-30, the state brought up to date on 2026-10-31. ⚠ marks what was not checked
on a machine running KubeSolo.

## Where it stands (2026-10-31)

| Piece | State | Since |
|---|---|---|
| KubeSolo v1.2.3 | **On**, node `srv2108887` Ready. The first deploy (#27) failed on the CPU reservation and rolled back; #28 fixed it | 2026-10-30, #28 |
| `kubectl logs`, `exec`, `port-forward` | Work, once the host name is in `/etc/hosts` | 2026-10-31, #33 |
| PGX (Postgres for pods) | On, port 5432, database `ax`. A pod connects with the Secret: `ax\|PostgreSQL 18.6 (pgrust 0.3)` | 2026-10-30, #30 |
| Secret `ax-system/ax-store` | Written on the box by every deploy (`pgx-kube-secrets`), never in the repository | 2026-10-31, #31 |
| rax-server (AX's API, in Rust) | Image published by piabrota/rax#9 to `ghcr.io/piabrota/rax-server` and pinned by digest in `k8s/rax/`. ⚠ Not applied yet: `kubectl apply -k k8s/rax` ("Run, reach, remove") | image 2026-10-31 |
| Agent Substrate, tasks | Not here: they need gVisor and feature gates KubeSolo does not set. rax runs as an API and a store only | |

Measured on the box, 2026-10-31, with only CoreDNS running:

| | Value |
|---|---|
| RAM, whole system | 965 MiB used of 3.8 GiB (2.9 GiB available) |
| `kubesolo` unit | 278 MiB of process memory (`anon`), plus 325 MiB of page cache the kernel can take back; `MemoryMax=1G` |
| Pods (`kubepods.slice`) | 22 MiB (CoreDNS) |
| `pgx` unit | 50 MiB |
| Disk | `/var/lib/kubesolo` 726 MiB, `/var/lib/pgx` 63 MiB; `/` 5.1 GiB used of 50 GiB |
| CPU | Load 0.00 idle |

## kubectl

The admin kubeconfig is `/var/lib/kubesolo/pki/admin/admin.kubeconfig`, readable by root only.
It is full access to the cluster: keep any copy of it at mode 600.

**On the VPS**, simplest. `kubectl` is not installed; `nix shell` fetches it for the session:

```console
nix shell nixpkgs#kubectl
install -d -m 700 ~/.kube
sudo install -m 600 -o "$USER" /var/lib/kubesolo/pki/admin/admin.kubeconfig ~/.kube/config
kubectl get nodes
```

Copy it again if KubeSolo ever re-signs its certificates. Without the copy, use
`sudo -E kubectl` with `KUBECONFIG` set to the file above.

**From your computer**, through an SSH tunnel: the next section. The API listens on every address
(`*:6443`), and the firewall keeps 6443 closed, so the tunnel is the only way in from outside.

Useful commands:

```console
kubectl get pods -A                                  # everything running
kubectl -n ax-system get secret ax-store             # the store Secret (never print .data)
kubectl -n kube-system logs deploy/coredns --tail=5  # logs
sudo systemctl restart pgx-kube-secrets              # write the Secret again
journalctl -u kubesolo -f                            # the node's own log
```

## What it is

| Point | Value | Source |
|---|---|---|
| Project | `portainer/kubesolo`, by Portainer, MIT licence | [repository](https://github.com/portainer/kubesolo) |
| Packaged version | v1.2.3, from 2026-10-27 | [release](https://github.com/portainer/kubesolo/releases/tag/v1.2.3) |
| Shape | One binary. The amd64 musl variant is static (`file`: *statically linked*), 197,423,240 bytes, in an 86 MB `.tar.gz` | downloaded and inspected here |
| What is inside | apiserver, controller-manager and kubelet in one process; containerd and crun; CoreDNS; Kine on SQLite instead of etcd; no scheduler (a webhook, `NodeSetter`, fills in `spec.nodeName`) | the project's README |
| Network | A `cni0` bridge, pods in `10.42.0.0/16`, services in `10.43.0.0/16`, CoreDNS on `10.43.0.10`; kube-proxy on iptables (or nftables, if `ip_tables` does not load) | `types/const.go`, `install.sh` |
| Ports | 6443 (API), 10250 (kubelet), 10443 (webhook); 6060 (pprof) and 9105 (metrics) only when turned on; Kine uses a unix socket | `uninstall.sh`, `types/const.go`, the example config |
| State | `/var/lib/kubesolo`: PKI, SQLite database, containerd, kubelet. It also writes `/etc/cni/net.d/10-bridge.conflist` | the example config, `uninstall.sh` |
| Images pulled at start (online variant) | `coredns/coredns:1.14.4`, `portainer/pause:latest`; `rancher/local-path-provisioner:v0.0.36` if local storage is on | the binary's strings, `types/const.go` |
| Memory | "under 200 MB", the vendor's figure ⚠ not measured here | the project's README |
| Conformance | Does not pass CNCF conformance, the project says | [`KUBERNETES.md`](KUBERNETES.md) |

**nixpkgs has no KubeSolo** (neither `nixos-26.05` nor `master`, on 2026-10-30).
`kubesolo/package.nix` packages the release binary: `fetchurl` with a pinned version and hash (the
hash is the `sha256` GitHub publishes for the asset, checked here with `shasum`) and an `install`.
Building from source does not work: the project's `make build` downloads containerd, crun and the
CNI plugins during the build. Being static, it needs no `patchelf` and no glibc. To update, change
`version` and `hash` together.

## The cost

| | Value |
|---|---|
| Closure, flag off | **0**: `system.build.toplevel` is the same path as before (`w0mb8vfj…`), evaluated here |
| Closure, flag on | **≈ +191 MiB**: the binary (188.3 MiB) plus `nftables` and the libraries of it the system does not have yet (jansson, gmp, libedit: at most 2.4 MiB, from `nix path-info` against cache.nixos.org). `iptables`, `kmod`, `util-linux` and `iproute2` are in the system already ⚠ `dix` did not run: the system is x86_64 and the machine here does not build x86_64 |
| Download | The binary is not on cache.nixos.org: the runner downloads the `.tar.gz` (86 MB) from GitHub, and deploy-rs copies the 188 MiB from the runner to the VPS once per version. Nothing is compiled anywhere |
| Disk, in use | `/var/lib/kubesolo` with containerd, the images and the database: 726 MiB with CoreDNS only (2026-10-31) |
| RAM | KubeSolo, containerd and the shims stay in the `kubesolo` unit, capped at `MemoryMax=1G`. Pods live in `kubepods.slice`, which the kubelet caps at the node's memory minus `systemReserved` (1536 Mi here): all pods together stay under about 2.2 GiB. Measured: 278 MiB for the unit's processes, 22 MiB of pods ("Where it stands") |
| CPU | `CPUQuota=60%` and `CPUWeight=50` on the unit. sshd and nginx share the one vCPU at normal weight. No `systemReserved.cpu`: KubeSolo rounds it up to whole CPUs and, with one vCPU, exits at start (`--system-reserved cpu=300m reserves 1 of this host's 1 CPUs, leaving none for workloads`; this stopped the first deploy, 2026-10-30, and deploy-rs rolled it back) |

## What the module does when on

- Runs the `kubesolo` unit with `--config` pointing at a YAML file in the store, generated from
  `piabrota.kubesolo.settings`. The module sets defaults (all `mkDefault`): IPv6 off (forwarding
  IPv6 on the host would make the VPS ignore router advertisements), the load balancer off (it
  would give the public IP to every `LoadBalancer` Service, past the firewall), local storage,
  d2k, metrics, pprof and the configuration API off, `127.0.0.1` and `localhost` in the API
  certificate, and the `systemReserved` above.
- Loads `br_netfilter` and `overlay`, and turns on `net.ipv4.ip_forward` and
  `net.bridge.bridge-nf-call-iptables`.
- Trusts `cni0` in the NixOS firewall, so pods can talk to the API and CoreDNS. **It opens no
  port**: 6443, 10250 and 10443 stay closed to the outside.
- Puts `iptables`, `nftables`, `kmod`, `util-linux` and `iproute2` on the unit's `PATH`.
- Refuses to evaluate with docker, podman or containerd on (KubeSolo brings its own containerd).

No systemd sandbox (`ProtectSystem`, `PrivateTmp`, `NoNewPrivileges`, `SystemCallFilter`):
containerd and the kubelet run inside the unit, every pod inherits its namespaces and seccomp
filters, and the kubelet needs mounts that propagate to the host. The hardening that is possible
is the closed firewall, the resource limits, and the settings that turn off what listens.
`KillMode=process` and `Delegate=yes` come from upstream's unit: without them a restart duplicates
every pod (the project's issue #197); the consequence is that stopping the unit does **not** stop
the pods (see the rollback).

`piabrota.kubesolo.hostName` puts the box's host name in `/etc/hosts` (as `127.0.0.1`). The API
server reaches the kubelet by that name for `kubectl logs`, `exec` and `port-forward`, and
KubeSolo's static musl resolver does not get it from systemd-resolved: without the entry those
fail with `lookup srv2108887: Try again` (seen 2026-10-31). Here the name is cloud-init's, not
`networking.hostName`; on a fork, set it to what `hostname` prints.

`checks.kubesolo-example` builds the system with the flag on, so CI catches a broken module before
anyone turns it on.

## Turning it on

Done on 2026-10-30 (#27, then #28). The steps, for a fork or after turning it off:

1. **Take a Hostinger snapshot first** (rollback step (d)).
2. Open a one-line PR in `configuration.nix`, next to `piabrota.site.enable`:

   ```nix
   piabrota.kubesolo.enable = true;
   ```

3. The merge deploys it. On the VPS, watch it start (it pulls CoreDNS and pause the first time):

   ```console
   ssh h0ffmann@piabrota.art
   systemctl status kubesolo
   journalctl -u kubesolo -f
   free -m
   ```

## Reaching the API

The API stays closed to the internet. From your computer, with `kubectl` installed there (not on
the VPS):

```console
# the admin kubeconfig, readable by root only
ssh h0ffmann@piabrota.art sudo cat /var/lib/kubesolo/pki/admin/admin.kubeconfig > ~/.kube/piabrota.yaml
chmod 600 ~/.kube/piabrota.yaml

# the tunnel, in another terminal
ssh -N -L 6443:127.0.0.1:6443 h0ffmann@piabrota.art

# point the kubeconfig at the tunnel
kubectl --kubeconfig ~/.kube/piabrota.yaml config set-cluster \
  "$(kubectl --kubeconfig ~/.kube/piabrota.yaml config view -o jsonpath='{.clusters[0].name}')" \
  --server=https://127.0.0.1:6443
export KUBECONFIG=~/.kube/piabrota.yaml
kubectl get nodes
```

The API listens on every address (`*:6443`, seen on the box), and its certificate covers
`127.0.0.1` through this module's config, so the tunnel above works as is.

## A first workload

```console
kubectl create deployment hello --image=nginxdemos/hello:plain-text
kubectl set resources deployment hello --requests=cpu=10m,memory=16Mi --limits=cpu=200m,memory=64Mi
kubectl expose deployment hello --port=80          # ClusterIP, never NodePort
kubectl port-forward svc/hello 8080:80             # through the API tunnel
curl localhost:8080
kubectl delete deployment,svc hello
```

**No `NodePort` and no `LoadBalancer`.** kube-proxy's DNAT happens before the NixOS firewall's
`INPUT` chain ⚠ (that is how iptables works; not tested here), so a NodePort is open to the
internet. To publish something, the path is the one the Loco apps take: the VPS's nginx as a
proxy, in a PR to this repository, to a Service exposed on loopback only (⚠ that needs a
`hostPort` on 127.0.0.1 or a `kubectl port-forward` as a unit; not designed yet).

## rax on KubeSolo

[piabrota/rax](https://github.com/piabrota/rax) (MPL-2.0) is the Rust port of
[AX](https://github.com/google/ax), the declarative orchestrator for agentic tasks on
[Agent Substrate](https://github.com/agent-substrate/substrate). It keeps AX's `ax.io/v1alpha1`
API (a gRPC service and `/healthz` on the same port, 8080).

### What full rax needs from the cluster

From rax's own `docs/minikube-footprint.md` and `docs/local-kubernetes.md` (2026-10-29, ⚠
estimates rax has not yet run end to end):

- **Agent Substrate**: about 15 deployments in `ate-system` (API, IdP, controller, router with
  Envoy, atelet as a DaemonSet, RustFS for snapshots, PostgreSQL), gVisor workers that run as root
  with `SYS_ADMIN` and `NET_ADMIN`, and a pod certificate controller.
- **Feature gates** `ClusterTrustBundle`, `ClusterTrustBundleProjection` and
  `PodCertificateRequest`, plus the `certificates.k8s.io/v1beta1` API. The `ax-server` manifest
  mounts `podCertificate` and `clusterTrustBundle` volumes. **KubeSolo has no setting for feature
  gates** (no key in `config.yaml` and no flag for it) ⚠.
- **PostgreSQL** for AX (or `--store memory://`, which loses everything on restart). Here it is
  [PGX](PGX.md), on the host, not a PostgreSQL server in a pod.
- **Size**: 26 pods, ≈1.5 CPU and ≈2 GiB requested, 2 to 3 GiB at idle, ≈6 GB of images on the
  node; an estimated minimum of 3 CPUs and 6 GB.

**That does not fit on KVM 1** (1 vCPU, 4 GB, next to KubeSolo, nginx and sshd), and KubeSolo
cannot turn the feature gates on. What fits is **`rax-server` alone**: AX's API with its store in
PGX on the host, without Substrate. It starts without Substrate ("running without substrate
reconciliation", in `main.rs`) ⚠ not tested on a cluster; it accepts, lists and deletes Tasks,
Workspaces and Models, but runs no task. It is for testing the API, the `rax` CLI and the path to
the cluster.

### The manifests: `k8s/rax/`

`k8s/rax/` is AX's `ax-server.yaml` from `test/e2e/manifests`, cut down for a small node
(`kubectl kustomize k8s/rax` renders it; checked here):

- `namespace.yaml`: the `ax-system` namespace and a `ResourceQuota` (at most 512 Mi and 1 CPU of
  limits, 4 pods, no NodePort and no LoadBalancer).
- `rax-server.yaml`: a ServiceAccount, a `Role` that reads secrets **only in `ax-system`** (AX
  uses a `ClusterRole`), the Deployment (`--addr=:8080`, the store's URL from the Secret `ax-store`, `Recreate`, user
  65534, read-only filesystem, no capabilities, seccomp `RuntimeDefault`, requests 50m/64Mi,
  limits 500m/256Mi) and a `ClusterIP` Service on 8080.
- `kustomization.yaml`: the image is `ghcr.io/piabrota/rax-server`, pinned by digest (`sha-78632e9`,
  2026-10-31), published by rax's CI.

`deploy.yml` ignores `k8s/**`: a merge that only touches `k8s/` does not switch the system. This
PR adds no workflow that applies the manifests. When there is one, it follows `MICROK8S.md`: a
`k8s.yml` in a `k8s` environment apart from `prod`, which opens the SSH tunnel and runs
`kubectl apply -k k8s/rax`.

### The image

The VPS compiles nothing, so the image arrives built. The path taken is the second one below:
piabrota/rax#9 publishes `ghcr.io/piabrota/rax-server` from rax's CI, and `k8s/rax/` pins its digest. Two paths:

1. **Build elsewhere and import** (no registry). On an x86_64 machine with Docker, in a rax
   checkout:

   ```console
   docker build -f Dockerfile.server -t rax-server:dev .
   docker save rax-server:dev | ssh h0ffmann@piabrota.art \
     'sudo nix shell nixpkgs#containerd -c ctr --address "$(sudo find /var/lib/kubesolo -name containerd.sock | head -1)" -n k8s.io images import -'
   ```

   ⚠ The path of KubeSolo's containerd socket was not seen on a running machine (`types/const.go`
   suggests `/var/lib/kubesolo/containerd/containerd.sock`). `nix shell` fetches `ctr` from the
   cache, compiles nothing, and does not stay in the system.
2. **Publish to a registry**: a workflow in the rax repository that builds the image (from the
   Dockerfile, or in Nix with `dockerTools.buildLayeredImage` over a `rustPlatform.buildRustPackage`,
   which rax does not have yet) and pushes it to `ghcr.io/piabrota/rax-server`. Then
   `k8s/rax/kustomization.yaml` gets `newName` and `digest`. Done: piabrota/rax#9 (from the Dockerfile,
   linux/amd64), first published as `sha-78632e9`. The package must be public, or the node cannot
   pull it: it has no registry credentials.

The `Dockerfile.server` image is 34 MB to download and 135 MB on the node (measured by rax); on
musl or distroless it would be about 80 MB smaller.

### Run, reach, remove

The store comes with the deploy: `piabrota.pgx.kubeSecrets.ax-store` (`configuration.nix`) has
the unit `pgx-kube-secrets` create the database `ax` in PGX, if it is missing, and write its URL,
with the password and the host as pods see it (`cni0`, 10.42.0.1), as the Secret
`ax-system/ax-store`. The password stays on the box, never in the repository. Check it on the VPS
with `systemctl status pgx-kube-secrets`.

Then, through the tunnel:

```console
kubectl apply -k k8s/rax
kubectl -n ax-system rollout status deploy/ax-server
kubectl -n ax-system port-forward svc/ax-server 8080:8080   # through the API tunnel
curl localhost:8080/healthz                                  # ok
rax --server localhost:8080 get tasks
```

Without `--server`, `rax` runs its own `port-forward` to `svc/ax-server` in the current context, as
`ax` does. Not through nginx on a path (`/rax`): the API is gRPC without authentication and must
not sit on the internet.

**Remove rax before turning KubeSolo off:**

```console
kubectl delete -k k8s/rax --wait
kubectl get ns ax-system      # NotFound
```

That also deletes the Secret. To bring rax back without a deploy, write it again on the VPS with
`sudo systemctl restart pgx-kube-secrets`. The PR that turns KubeSolo off removes
`piabrota.pgx.kubeSecrets.ax-store` too, or the build stops at an assertion.

## Rollback

### (a) The normal path: a PR that turns it off

Revert the PR that turned it on (or set the line to `false`) and merge. The deploy stops and
removes the `kubesolo` unit and the binary leaves the system (the path stays in the store until
garbage collection: 14 days and 5 generations, `deploy.nix`).

What deploy-rs covers: if SSH does not answer within 60 s after the switch, it rolls back to the
previous generation by itself (magic rollback), and a failed activation rolls back too
(`autoRollback`). What it does **not** cover: the unit is `Type=simple`, so the switch succeeds
even if KubeSolo then crash-loops; memory pressure that shows up minutes later, when pods start;
downloaded images; and all the state outside the store (step (c)). And since KubeSolo uses
`KillMode=process`, turning the unit off **leaves the containers running** until step (c) or a
reboot.

### (b) Emergency on the box

If the VPS gets too slow to wait for a PR:

```console
ssh h0ffmann@piabrota.art
sudo systemctl stop kubesolo kubepods.slice   # stops KubeSolo and every pod ⚠
sudo nixos-rebuild switch --rollback          # back to the previous generation
```

Without SSH: the serial console in hPanel (VPS → Console), reboot and pick the previous generation
in the GRUB menu (`configuration.nix` shows it for 1 s; GRUB keeps 5 generations). Once in, run
`sudo nixos-rebuild switch --rollback` so it becomes the default. Then **revert on `main` too**
(step (a)), or the next deploy brings KubeSolo back.

### (c) Cleaning what is left

None of this is in the store, and no NixOS rollback deletes it. Once the flag is off:

```console
# 1. stop leftover pods (KillMode=process keeps them alive)
sudo systemctl stop kubepods.slice            # ⚠ or reboot the VPS
# 2. unmount what containerd mounted and delete the state
findmnt -rn -o TARGET | grep '^/var/lib/kubesolo' | sort -r | xargs -r -n1 sudo umount -l
sudo rm -rf /var/lib/kubesolo /etc/cni/net.d/10-bridge.conflist
# 3. network: the bridge and the kube-proxy and CNI rules
sudo ip link delete cni0 2>/dev/null
sudo ip link show | grep -o 'veth[^@:]*' | xargs -r -n1 sudo ip link delete
sudo iptables-save | grep -v -E 'KUBE-|CNI-' | sudo iptables-restore
sudo nft list tables | grep -i kube           # if kube-proxy used nftables: sudo nft delete table ip kube-proxy
sudo systemctl restart firewall               # rebuilds the NixOS rules
```

The simplest and safest path is to **reboot the VPS** after the deploy that turns it off: the
iptables rules, `cni0`, the `veth`s, the mounts, `ip_forward` and the modules do not survive a
boot, and KubeSolo does not start again. Only `/var/lib/kubesolo` and
`/etc/cni/net.d/10-bridge.conflist` are left to delete. The kubeconfig on your computer
(`~/.kube/piabrota.yaml`) can go too.

### (d) A Hostinger snapshot before turning it on

In hPanel: **VPS → Snapshots & backups → Create snapshot**, before the merge that turns it on. It
is the full way back if everything else fails: restoring returns the whole disk to that moment
(and loses what changed since). ⚠ From what Hostinger documents, each VPS keeps one snapshot, and a
new one replaces the old; check in the panel before relying on it.

## Sources and what was not checked

- KubeSolo: [README](https://github.com/portainer/kubesolo),
  [`examples/kubesolo-config.yaml`](https://github.com/portainer/kubesolo/blob/develop/examples/kubesolo-config.yaml),
  [`docs/configuration/config-file.md`](https://github.com/portainer/kubesolo/blob/develop/docs/configuration/config-file.md),
  `install.sh` (the systemd unit, `KillMode=process`, `Delegate=yes`, the iptables
  prerequisites), `uninstall.sh` (ports, mounts, cleanup), `types/const.go` (CIDRs, images),
  `pkg/kubernetes/kubelet/config.go` (the `systemd` cgroup driver, `systemReserved`); the
  [v1.2.3 release](https://github.com/portainer/kubesolo/releases/tag/v1.2.3) and the binary,
  inspected with `file` and `strings`.
- nixpkgs: `pkgs/by-name/ku/` on `nixos-26.05` and `master`, with no `kubesolo`.
- rax: [README](https://github.com/piabrota/rax), `docs/minikube-footprint.md`,
  `docs/local-kubernetes.md`, `Dockerfile.server`, `crates/rax-server/src/main.rs`; AX:
  [`test/e2e/manifests/ax-server.yaml`](https://github.com/google/ax/blob/main/test/e2e/manifests/ax-server.yaml).
- Checked here: the binary's hash, that it is static, that the flag off leaves the system
  unchanged, `nix flake check --no-build --all-systems`, nixpkgs-fmt, statix, deadnix, and that
  `k8s/rax` renders with `kubectl kustomize`. CI builds `checks.kubesolo-example` on x86_64.
- **Not checked** (⚠): KubeSolo running on NixOS or on this VPS; its real memory use; the size of
  `/var/lib/kubesolo`; whether the API listens on 127.0.0.1; whether pods reach the API with only
  `cni0` trusted; whether `systemctl stop kubepods.slice` stops every pod; the containerd socket for
  `ctr import`; `rax-server` starting without Substrate on a cluster; Hostinger's snapshot policy.
