# Architecture

[Português](Arquitetura)

## The pieces

| File | What it does |
|---|---|
| `flake.nix` | One system per host, `nixosConfigurations.piabrota` and `.piabrota2` (nixos-26.05, from `hosts/<name>/`), a deploy-rs node for each, and CI's `checks`. |
| `configuration.nix` | What both hosts share: the Hostinger base (GRUB on `/dev/sda`, cloud-init, the QEMU agent, SSH). It imports the modules below. |
| `piabrota.nix` | The `h0ffmann` user (SSH key only) and the base packages. |
| `tools.nix` | Light command-line tools, and the disk and memory limits. |
| `deploy.nix` | The `deploy` user CI logs in as, garbage collection and the boot generation limit. |
| `loco.nix` | [Loco](https://loco.rs) apps as sandboxed systemd services, with SQLite, nginx and HTTPS. |
| `site.nix` | The static site from `site/` (Gleam and Lustre, prerendered at build time; the VPS gets only the HTML and CSS) on www.piabrota.art, over HTTP and HTTPS; `piabrota.art` redirects to `www`. |
| `pgx.nix` | [PGX](https://pgx.dev), a Postgres-compatible database in one process, instead of a PostgreSQL server or Docker, for the next workload that needs Postgres (nothing uses it today). Only for data that can be rebuilt; the apps' data stays in SQLite. See [`docs/PGX.md`](https://github.com/piabrota/nix-os/blob/main/docs/PGX.md). |
| `paperclip.nix` | [Paperclip](https://github.com/paperclipai/paperclip), a control plane for a team of AI agents, at paperclip.piabrota.art on KVM 4, with PostgreSQL 17 on a socket only. Off for now (`enable = false`). When on, Hermes is its agent: Paperclip sends each task to the Hermes API server on loopback. See [`docs/PAPERCLIP.md`](https://github.com/piabrota/nix-os/blob/main/docs/PAPERCLIP.md). |
| `hermes.nix` | [Hermes Agent](https://github.com/NousResearch/hermes-agent), Nous Research's agent, from its flake's NixOS module: a sandboxed service that answers on chat platforms, on Claude through the owner's subscription; its secrets stay on the box. See [Hermes](Hermes-EN). |
| `openrig.nix` | [OpenRig](https://github.com/mvschwarz/openrig), a control plane for a team of coding agents, on KVM 4, with its UI at rig.piabrota.art behind basic auth. It is the engine of the [software factory](Factory): a builder seat and a reviewer seat, both on `omp`, which Hermes operates. See [`docs/OPENRIG.md`](https://github.com/piabrota/nix-os/blob/main/docs/OPENRIG.md). |
| `kubesolo-purge.nix` | A oneshot that clears an old install from the box, once. A human deletes it later. |

## From a pull request to the VPS

```
PR ──► ci.yml: nixpkgs-fmt, statix, deadnix, shellcheck, justfiles (nix flake check by hand)
merge to main ──► deploy.yml: the runner builds, deploy-rs copies over SSH and activates
                    └─► if SSH does not answer within 60 s, the VPS rolls back by itself (magic rollback)
              └─► freeze.yml: the VPS's package list in the run summary
              └─► cves.yml: a vulnix report on the built system (and every Monday)
              └─► wiki.yml: copies wiki/ to this wiki (when wiki/ changed)
```

The VPS compiles nothing: it fetches from `cache.nixos.org` what the cache has. Every deploy is a
new generation, and GRUB keeps the last five.

## The figures

![Two hosts: Porkbun DNS sends www.piabrota.art to VPS 1 (KVM 1), which serves the site, /hermes, /hosts and the /notes Loco app, and hermes.piabrota.art and rig.piabrota.art to VPS 2 (KVM 4); there the dashboard behind basic auth shares its state with the hermes-agent gateway, and the OpenRig UI behind basic auth fronts the openrig unit with its two omp seats, which the gateway drives with the rig CLI; the owner's Telegram and Discord chats reach the gateway by polling, and it opens pull requests on hermes/* branches as piabrota-hermes[bot]; deploy.yml builds both systems and deploys each on a merge.](img/two-hosts.png)

<details open>
<summary>How to read this figure</summary>

**Takeaway.** KVM 1 serves the public web and nothing else; everything Hermes and OpenRig is on KVM 4.

**How to read.** Top to bottom, one lane per place: people, DNS, each VPS, GitHub. Arrows say where a request or a deploy goes; the red border marks what is outside the two boxes.

**Not shown.** PGX on KVM 4 (Paperclip is off for now), the ACME certificates, the secrets on each box, the clones the seats work in, and the deploy by hand.

**Evidence.** [`docs/archify/two-hosts.json`](https://github.com/piabrota/nix-os/blob/main/docs/archify/two-hosts.json), the source of the figure; `hosts/piabrota/default.nix`, `hosts/piabrota2/default.nix`, `hermes-web.nix`, `openrig.nix`, [`docs/OPENRIG.md`](https://github.com/piabrota/nix-os/blob/main/docs/OPENRIG.md), [`docs/MIGRATION-KVM4.md`](https://github.com/piabrota/nix-os/blob/main/docs/MIGRATION-KVM4.md).

</details>

![The software factory: the owner sends a task to Hermes on VPS 2; Hermes sends it to the builder seat of the OpenRig rig piabrota-dev, which delegates its diff to the reviewer seat, and the verdict goes back to Hermes; Hermes commits, pushes a hermes/* branch and opens a pull request on GitHub; a human merges it, always; deploy.yml then deploys the two VPSs with deploy-rs and magic rollback.](img/software-factory.png)

<details open>
<summary>How to read this figure</summary>

**Takeaway.** The rig will do the build and the review, Hermes routes and checks, and only a human merges.

**How to read.** Top to bottom, one lane per stage: people, Hermes, the rig, GitHub, deploy. Arrows say what goes next; the red border marks where a person comes in.

**Not shown.** The skills `/triage` and `/mip` that come before the task, the watchers after the deploy (`kvm4-health`), the deny list, and the token of the seats.

**Evidence.** [`docs/archify/software-factory.json`](https://github.com/piabrota/nix-os/blob/main/docs/archify/software-factory.json), the source of the figure; `openrig/specs/rigs/piabrota-dev/rig.yaml`, [`docs/OPENRIG.md`](https://github.com/piabrota/nix-os/blob/main/docs/OPENRIG.md), `.github/workflows/deploy.yml`, the skills `hermes-rig` and `hermes-omp`. ⚠ No task has gone through the rig yet: the seats, the verdict arrow and the pull request from a seat's diff are the plan, not a run.

</details>

![How nix-os works: a pull request runs ci.yml on every push; a merge to main runs deploy.yml, which builds the system on the GitHub runner; deploy-rs copies the closure to the VPS over SSH and switches it, the VPS fetching store paths from cache.nixos.org; if SSH falls silent for 60 s, magic rollback restores the old system; after the switch, freeze.yml lists the VPS's packages, and cves.yml reports vulnix on the same push.](img/how-nix-os-works.png)

<details open>
<summary>How to read this figure</summary>

**Takeaway.** Nobody deploys by hand: merging a pull request is the deploy, and a switch that cuts SSH undoes itself.

**How to read.** Top to bottom, one lane per place where the work runs. Arrows say what flows or what comes next; the red border marks where you come in.

**Not shown.** The secrets and the `prod` environment, `wiki.yml`, the Markdown-only pushes that skip the build, and the deploy by hand (`just deploy`).

**Evidence.** [`docs/archify/how-nix-os-works.json`](https://github.com/piabrota/nix-os/blob/main/docs/archify/how-nix-os-works.json), the source of the figure; `.github/workflows/`, `flake.nix` (`deploy.nodes.piabrota`, `magicRollback`), [`docs/DEPLOY.md`](https://github.com/piabrota/nix-os/blob/main/docs/DEPLOY.md).

</details>

![piabrota.art: a browser resolves the two A records on Porkbun, which point at the VPS; nginx answers piabrota.art with a 301 to https://www and serves www.piabrota.art over HTTP and HTTPS, with /nixos a 302 to the repository and a Let's Encrypt certificate per name; the page was built before the deploy, site/ in Gleam prerendered by Nix into /nix/store as three pages and style.css, which is nginx's root.](img/piabrota-art.png)

<details open>
<summary>How to read this figure</summary>

**Takeaway.** The VPS serves a few small files from the store; Gleam, node and the build never reach it.

**How to read.** Top to bottom: the visitor, DNS, nginx on the VPS, and what was built before the deploy. Arrows say what a request is sent to, or what goes into what.

**Not shown.** The ACME HTTP-01 challenge, the `httpsOnly` switch, and the Loco apps that would share nginx.

**Evidence.** [`docs/archify/piabrota-art.json`](https://github.com/piabrota/nix-os/blob/main/docs/archify/piabrota-art.json), the source of the figure; `site.nix`, `site/default.nix`, [`docs/SITE.md`](https://github.com/piabrota/nix-os/blob/main/docs/SITE.md).

</details>

## What must not break

The QEMU agent, cloud-init, SSH with `h0ffmann`'s key, GRUB on `/dev/sda`, the `deploy` user and
magic rollback. Without them, Hostinger cannot provision the machine or CI cannot deploy. The full
list is in [`AGENTS.md`](https://github.com/piabrota/nix-os/blob/main/AGENTS.md), "Do not break the machine".
