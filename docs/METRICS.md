# Live metrics with Beszel

[Português](METRICS.ptBR.md)

[Beszel](https://github.com/henrygd/beszel) (MIT) shows the metrics of the two machines live on a
web page: CPU, memory, disk, network and the systemd services. It has a hub (the page, with its
own login) and an agent on each machine. The module is `metrics.nix`. Everything is off by
default; each host turns on what is its own.

## Why Beszel and not Grafana

The owner wants to watch the metrics as in Grafana, but lighter. Grafana, with Prometheus and
exporters, is too much for two machines. Beszel is a 37 MB hub and an 11 MB agent, with no
separate database (the hub keeps SQLite, through PocketBase). In the measures below: **34 MiB** of
RAM for the hub, **17 MiB** for the agent.

## Who runs what

| | piabrota2 (KVM 4) | piabrota (KVM 1) |
|---|---|---|
| Hub | yes, at `metrics.piabrota.art` (nginx, ACME, ports 80 and 443 that are already open) | no |
| Agent | yes, talks to the hub at `http://127.0.0.1:8090` | yes, talks to `https://metrics.piabrota.art` |
| New port | none | none |
| nginx change | the hub's vhost | none |

The agent **only dials out** (one WebSocket). It binds no port (`DISABLE_SSH=true`:
`agent/server.go`, `agent/connection_manager.go`). So piabrota needs no new firewall rule.

Options (`metrics.nix`): `piabrota.metrics.hub.{enable,domain}` and
`piabrota.metrics.agent.{enable,hubUrl,environmentFile}`. The hub and the agent use the same
package (`piabrota.metrics.package`), so the two versions are always equal.

## Before the merge: DNS

On Porkbun, add an **A** record, `metrics`, with the address of `rig.piabrota.art` (the same as
piabrota2). Do it **before the merge**. Without the record the ACME order fails on the deploy and
deploy-rs rolls the switch back. The steps are in [`SITE.md`](SITE.md), "DNS on Porkbun".

## The first setup, in order

1. (Optional, avoids a race.) On piabrota2, before the merge, create
   `/var/lib/beszel-secrets/hub.env` (root, mode 0600, in a folder you make with
   `sudo install -d -m 0750 /var/lib/beszel-secrets`) with `USER_EMAIL=` and `USER_PASSWORD=`.
   On the first start with new data the hub makes that account the admin
   (`internal/migrations/initial-settings.go`). Measured: it works.
2. Merge. The deploy starts the hub and both agents. The agents have no `KEY` and `TOKEN` yet: the
   unit is **skipped**, not failed (`ConditionPathExists`), so the deploy does not roll back.
3. Open `https://metrics.piabrota.art`. **Without step 1, create the admin account at once**: while
   no user exists, `POST /api/beszel/create-user` accepts whoever comes first
   (`internal/hub/api.go:171`). After the first user it refuses
   (`internal/users/users.go:108`) and nobody else can register: the hub does not turn on
   `USER_CREATION`.
4. On the page, **Add System**, twice: "piabrota2" and "piabrota". The page shows each one's `KEY`
   (the hub's public key) and `TOKEN`.
5. On each machine, write `/var/lib/beszel-secrets/agent.env` by hand, **root, mode 0600**:

   ```console
   sudo install -m 0600 /dev/null /var/lib/beszel-secrets/agent.env
   sudoedit /var/lib/beszel-secrets/agent.env     # two lines: KEY=... and TOKEN=...
   sudo systemctl restart beszel-agent
   ```

   systemd reads the file as root, before it drops to the `DynamicUser`. So root 0600 is enough,
   and the agent does not need to read the file. None of this goes into the repository or the
   store.
6. In seconds the system shows as "up".

Without the file the unit stays inactive (`systemctl status beszel-agent` says the condition
failed). After you create the file, the unit starts only with `restart` (or on the next boot).

## What it shows, what it does not show

It shows, per machine: CPU, memory, swap, disk, network, temperature when there is a sensor, and
the list of systemd services with their state.

**Per service (checked in the v0.21.1 source and in a real run):** the agent collects the state,
the **CPU** (`CPUUsageNSec`), the **current memory** (`MemoryCurrent`) and the **peak**
(`MemoryPeak`) of every `*.service` (`agent/systemd.go:252-286`). So you can see the memory of
`hermes-agent`. But:

- The list is read **every 10 minutes** (`agent/systemd.go:142-146`), not live. Memory per service
  is a snapshot, up to 10 minutes old.
- The hub keeps **only the latest snapshot** of each service (`INSERT ... ON CONFLICT DO UPDATE` in
  `internal/hub/systems/system.go:433`). **There is no history chart per service.**
- The hub shows the memory and the peak, but **does not compare them with the `MemoryMax`** of 8G.
  The limit only shows in the service details. You do the comparison by eye.
- Service logs are off (`SKIP_SYSTEMD_LOGS`): the agent does not read the journal.
- Measured on piabrota2 (a test agent, not a unit): 58 services, and `hermes-agent` with 641 MB
  now and a peak of 942 MB.

For the memory of `hermes-agent` against `MemoryMax=8G` over time, the cheapest way is
`kvm4-health` (every 30 minutes, no model cost), which already reads `MemoryCurrent` and
`MemoryPeak`. The heavier alternative would be Netdata (a 1.1 GiB closure in nixpkgs), which keeps
history per cgroup. It is not planned.

D-Bus: nixpkgs' module lets the `beszel-agent` user call `ListUnits`, and the unit has
`PrivateUsers=true`. I ran the agent as a normal user and it listed the services. **The VM test
`checks.metrics` ran the real unit under `PrivateUsers` and it saw `beszel-hub` through D-Bus.**

## nginx in front of the hub

No basic auth: piabrota's agent dials in through the same name, and an nginx password would stop
it. The hub has its own login (PocketBase) and the agent has its token. The paths (read in the
source):

- `/api/beszel/agent-connect`: the agent's WebSocket (`internal/hub/api.go:195`,
  `agent/client.go:221`). Headers `X-Token` and `X-Beszel`.
- `/api/realtime`: the page's live updates, as SSE events (PocketBase's `apis/realtime.go`, which
  already sends `X-Accel-Buffering: no`).
- Login: `/api/collections/<collection>/auth-with-password`, `request-otp`, `auth-with-otp`
  (`apis/record_auth.go:31,39,42`).

The vhost proxies everything to `127.0.0.1:8090` with the WebSocket upgrade headers,
`proxy_buffering off` and a `proxy_read_timeout` of 1 hour. The three login paths have a limit of
**10 attempts a minute for each address** (`limit_req_zone`, burst of 5, answer 429). Security
headers as in `hermes-web.nix`.

## The hub variables I confirmed

Read in `internal/hub` and `internal/migrations` (v0.21.1). Each also takes the `BESZEL_HUB_`
prefix.

| Variable | Effect | Used here |
|---|---|---|
| `USER_EMAIL`, `USER_PASSWORD` | Make the admin on the first start with new data (`initial-settings.go:28-30`) | optional, through `hub.env` |
| `USER_CREATION` | Only with `true` does it allow OAuth user creation (`collections.go:32`). Without it nobody registers | **no**, stays off |
| `DISABLE_PASSWORD_AUTH` | Turns off password login (`collections.go:28`). With no OAuth set up you lock yourself out | no |
| `APP_URL` | The public address, used in alert links (`hub.go:131`) | yes, `https://metrics.piabrota.art` |
| `CHECK_UPDATES` | Checks for versions on GitHub; only with `true` | no |

From the agent: `HUB_URL`, `KEY`, `TOKEN` (by file), `DISABLE_SSH`, `SKIP_GPU`,
`SKIP_SYSTEMD_LOGS`.

## Cost

Measured on this machine on 2026-11-05, with the real binaries of the pinned version, run as a
normal user in a scratch folder:

| | |
|---|---|
| Hub RAM, idle | **34 MiB** (VmRSS 34208 kB after 20 s; 35516 kB after 60 s) |
| Agent RAM, connected to the hub | **16.5 MiB** (VmRSS 16832 kB, the same after 60 s) |
| Hub data | 0.9 MiB with one system, after 80 s (grows with the history) |
| Limits | hub `MemoryMax=256M` and `CPUWeight=20`; agent `MemoryMax=64M` and `CPUWeight=20` |
| Closure | the package closure is 91.1 MiB, of which 52.3 MiB are its own; glibc, tzdata and the rest are usually in the system already (not measured on the whole system). Against the nixpkgs beszel 0.18.7 of this lock: **+3.11 MiB** (`dix`) |
| Disk per host | the same 52 MiB, once, in the store |
| CPU | almost nothing idle; each agent sends one packet a minute |

piabrota (4 GB) grows only by the agent and the package. The `dix` of the two whole systems against
`main` **did not run** here: piabrota's system is 360 derivations to build on this machine
(`max-jobs = 1`). Run `just build` and the `dix` in CI before the merge.

## The pinned package

`beszel/package.nix` pins version **0.21.1** (upstream's latest on 2026-11-05; the nixpkgs of this
lock has 0.18.7). It is a copy of nixpkgs' derivation (MIT), with `version`, `hash`, `vendorHash`
and `npmDepsHash` at the top. It is a copy and not an `overrideAttrs` because `webui` is a second
derivation that reads `finalAttrs.src`, and the skipped tests and the build tags change between
versions: an override would repeat most of the file.

⚠ This package is **not in `cache.nixos.org`** (checked with `nix path-info --store`). It compiles
on the GitHub runner of `deploy.yml`; the VPS never compiles, it only receives the result from
deploy-rs. On this machine the build took **3 min 22 s** (with the Go tests; the npm and Go
dependencies, fetched from the network, add about 4 minutes the first time) and used up to about
**1.1 GiB** of system memory (the difference in used memory, measured from outside, with noise).

⚠ The module of the nixpkgs in this lock calls `beszel-hub history-sync`, a command 0.21 does not
have ("unknown command"): the hub would never start. `metrics.nix` replaces the `ExecStartPre` with
`migrate up` and `migrate history-sync`, as newer nixpkgs does. Check it when the lock moves.

## Updating the pin

The hub and the agent move **together**: one package, one version. Never change one without the
other.

```console
# 1. the source (hash)
nix flake prefetch github:henrygd/beszel/vX.Y.Z --json | jq -r .hash
# 2. the UI's npm modules (npmDepsHash)
nix run nixpkgs#prefetch-npm-deps -- <source path>/internal/site/package-lock.json
# 3. the Go modules (vendorHash): put lib.fakeHash, build, copy the "got:" value
nix build .#beszel
```

Change `version`, `hash`, `npmDepsHash` and `vendorHash` at the top of `beszel/package.nix`.
Compare `checkFlags` with nixpkgs' `package.nix` of the same version. Check:

```console
nix build .#beszel && ./result/bin/beszel-agent --version
```

The method was proved on 0.21.0: the three computed hashes equal nixpkgs'. When the lock's nixpkgs
catches up with the version, delete `beszel/` and use `pkgs.beszel`. There is no daily update job.

## Turning it off

Remove `piabrota.metrics.*` from the files in `hosts/`. piabrota2 loses the vhost; the data stays
in `/var/lib/beszel-hub`. To erase: `sudo rm -r /var/lib/beszel-hub /var/lib/beszel-secrets`.

## Backing up the data

The hub keeps everything in `/var/lib/beszel-hub` (SQLite). For a consistent copy:
`sudo systemctl stop beszel-hub`, copy the folder, `sudo systemctl start beszel-hub`. PocketBase's
superuser account (`/_/`) is of no use to the owner: Beszel makes it with a random password. The
data is metrics: losing it costs only the history.

## What I could not prove

- A real agent on piabrota (KVM 1), the deploy, ACME and the browser.
- `checks.metrics` (`beszel/test.nix`) passed on this machine on 2026-11-05 (107 s): the agent is
  skipped without its file, the first user is made once, nobody else can register, nginx limits
  logins (429), the agent reaches the hub over the WebSocket through nginx, binds no port and
  sees the systemd units. It ran with plain HTTP and a fake name, so TLS and ACME stay unproved.
