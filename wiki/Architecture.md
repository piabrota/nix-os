# Architecture

[Português](Arquitetura)

## The pieces

| File | What it does |
|---|---|
| `flake.nix` | The system `nixosConfigurations.piabrota` (nixos-26.05), the deploy-rs node and CI's `checks`. |
| `configuration.nix` | The Hostinger base: GRUB on `/dev/sda`, cloud-init, the QEMU agent, SSH. It imports the modules below. |
| `piabrota.nix` | The `h0ffmann` user (SSH key only) and the base packages. |
| `tools.nix` | Light command-line tools, and the disk and memory limits. |
| `deploy.nix` | The `deploy` user CI logs in as, garbage collection and the boot generation limit. |
| `loco.nix` | [Loco](https://loco.rs) apps as sandboxed systemd services, with SQLite, nginx and HTTPS. |
| `site.nix` | The static site from `site/` (Gleam and Lustre, prerendered at build time; the VPS gets only the HTML and CSS) on www.piabrota.art, over HTTP and HTTPS; `piabrota.art` redirects to `www`. |

## From a pull request to the VPS

```
PR ──► ci.yml: nix flake check (builds the system), nixpkgs-fmt, statix, deadnix, shellcheck
merge to main ──► deploy.yml: the runner builds, deploy-rs copies over SSH and activates
                    └─► if SSH does not answer within 60 s, the VPS rolls back by itself (magic rollback)
              └─► freeze.yml: the VPS's package list in the run summary
              └─► cves.yml: a vulnix report on the built system (and every Monday)
              └─► wiki.yml: copies wiki/ to this wiki (when wiki/ changed)
```

The VPS compiles nothing: it fetches from `cache.nixos.org` what the cache has. Every deploy is a
new generation, and GRUB keeps the last five.

## The figures

![How nix-os works: a pull request runs ci.yml on every push; a merge to main runs deploy.yml, which builds the system on the GitHub runner; deploy-rs copies the closure to the VPS over SSH and switches it, the VPS fetching store paths from cache.nixos.org; if SSH falls silent for 60 s, magic rollback restores the old system; after the switch, freeze.yml lists the VPS's packages, and cves.yml reports vulnix on the same push.](img/how-nix-os-works.png)

<details open>
<summary>How to read this figure</summary>

**Takeaway.** Nobody deploys by hand: merging a pull request is the deploy, and a switch that cuts SSH undoes itself.

**How to read.** Top to bottom, one lane per place where the work runs. Arrows say what flows or what comes next; the red border marks where you come in.

**Not shown.** The secrets and the `prod` environment, `wiki.yml`, the Markdown-only pushes that skip the build, and the deploy by hand (`just deploy`).

**Evidence.** [`docs/archify/how-nix-os-works.json`](https://github.com/piabrota/nix-os/blob/main/docs/archify/how-nix-os-works.json), the source of the figure; `.github/workflows/`, `flake.nix` (`deploy.nodes.piabrota`, `magicRollback`), [`docs/DEPLOY.md`](https://github.com/piabrota/nix-os/blob/main/docs/DEPLOY.md).

</details>

![piabrota.art: a browser resolves the two A records on Porkbun, which point at the VPS; nginx answers piabrota.art with a 301 to https://www and serves www.piabrota.art over HTTP and HTTPS, with /nixos a 302 to the repository and a Let's Encrypt certificate per name; the page was built before the deploy, site/ in Gleam prerendered by Nix into /nix/store as index.html and style.css, which is nginx's root.](img/piabrota-art.png)

<details open>
<summary>How to read this figure</summary>

**Takeaway.** The VPS serves two small files from the store; Gleam, node and the build never reach it.

**How to read.** Top to bottom: the visitor, DNS, nginx on the VPS, and what was built before the deploy. Arrows say what a request is sent to, or what goes into what.

**Not shown.** The ACME HTTP-01 challenge, the `httpsOnly` switch, and the Loco apps that would share nginx.

**Evidence.** [`docs/archify/piabrota-art.json`](https://github.com/piabrota/nix-os/blob/main/docs/archify/piabrota-art.json), the source of the figure; `site.nix`, `site/default.nix`, [`docs/SITE.md`](https://github.com/piabrota/nix-os/blob/main/docs/SITE.md).

</details>

## What must not break

The QEMU agent, cloud-init, SSH with `h0ffmann`'s key, GRUB on `/dev/sda`, the `deploy` user and
magic rollback. Without them, Hostinger cannot provision the machine or CI cannot deploy. The full
list is in [`AGENTS.md`](https://github.com/piabrota/nix-os/blob/main/AGENTS.md), "Do not break the machine".
