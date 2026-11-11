# Figures

The figures of the README, with how to read each one and what it leaves out. The README shows them; this page keeps the text. Each figure has an interactive page at `https://www.piabrota.art/figures/<name>/`.

![Two hosts: a visitor's browser asks Porkbun DNS, whose A records send www.piabrota.art to VPS 1 (KVM 1), which serves the site, /hermes, /figures and the /notes Loco app, and hermes.piabrota.art and rig.piabrota.art to VPS 2 (KVM 4); there the dashboard behind basic auth shares its state with the hermes-agent gateway, which drives the openrig unit with its two omp seats; the OpenRig UI behind basic auth proxies to openrig; the gateway polls the owner's Telegram and Discord chats.](img/two-hosts.png)

Interactive page: <https://www.piabrota.art/figures/two-hosts/>

<details open>
<summary>How to read this figure</summary>

**Takeaway.** KVM 1 serves the public web and nothing else; everything Hermes and OpenRig is on KVM 4.

**How to read.** Top to bottom, one lane per place: visitor, DNS, each VPS, owner. DNS turns each name into a host. On KVM 4, read the row from left to right: the dashboard shares state with the gateway, the gateway drives openrig, and the OpenRig UI proxies to it. The gateway reaches out to the chats; they do not call it. The red border marks what is outside the two boxes.

**Not shown.** The deploy and the pull requests (the figures "How nix-os works" and "The software factory" show them), PGX on KVM 4 (Paperclip is off for now), the ACME certificates, the secrets on each box, and the clones the seats work in.

**Evidence.** [`docs/archify/two-hosts.json`](archify/two-hosts.json), the source of the figure; `hosts/piabrota/default.nix`, `hosts/piabrota2/default.nix`, `hermes-web.nix`, `openrig.nix`, [`docs/OPENRIG.md`](OPENRIG.md), [`docs/MIGRATION-KVM4.md`](MIGRATION-KVM4.md).

</details>

[OpenRig](https://github.com/mvschwarz/openrig) is the engine of the open software factory behind
piabrota. The rig `piabrota-dev` has two seats on `omp`: a builder and a reviewer. The builder will
write the change and the reviewer will check it. Hermes routes the task and checks the result, then
opens the pull request on a `hermes/*` branch. A human merges, always, and the merge deploys.

**Status today.** OpenRig 0.7.7 runs on KVM 4. The rig is specified and the UI is on. The seats are
idle: no task has gone through the builder and reviewer loop. Today Hermes makes a pull request by
running `omp` itself (skill `hermes-omp`). The guardrails stay: humans merge, the deny list and
`hermes/omp.yml` apply, no secret goes in a spec or a task, at most two seats run at once, and the UI
is behind basic auth and TLS.

![The software factory: the owner sends a task to Hermes on VPS 2; Hermes sends it to the builder seat of the OpenRig rig piabrota-dev, which delegates its diff to the reviewer seat, and the verdict goes back to Hermes; Hermes commits, pushes a hermes/* branch and opens a pull request on GitHub; a human merges it, always; deploy.yml then deploys the two VPSs with deploy-rs and magic rollback.](img/software-factory.png)

Interactive page: <https://www.piabrota.art/figures/software-factory/>

<details open>
<summary>How to read this figure</summary>

**Takeaway.** The rig will do the build and the review, Hermes routes and checks, and only a human merges.

**How to read.** Top to bottom, one lane per stage: people, Hermes, the rig, GitHub, deploy. Arrows say what goes next; the red border marks where a person comes in.

**Not shown.** The skills `/triage` and `/mip` that come before the task, the watchers after the deploy (`kvm4-health`), the deny list, and the token of the seats.

**Evidence.** [`docs/archify/software-factory.json`](archify/software-factory.json), the source of the figure; `openrig/specs/rigs/piabrota-dev/rig.yaml`, [`docs/OPENRIG.md`](OPENRIG.md), `.github/workflows/deploy.yml`, the skills `hermes-rig` and `hermes-omp`. ⚠ No task has gone through the rig yet: the seats, the verdict arrow and the pull request from a seat's diff are the plan, not a run.

</details>

The rig `wave-forecaster-thesis` is a second rig on the same engine. Six Claude Code seats write a
final-year project of the Escola Politécnica of UFRJ in Portuguese, one independent section at a
time, and the command `thesis` (no model, no network) claims the sections, runs four gates and builds
the PDF. It is off at piabrota2, and no seat has run it ([`docs/THESIS.md`](THESIS.md)).

![The thesis rig: the owner gives the brief to the editor, which writes thesis.json; the librarian keeps the sources and refs.bib; three writers each take one section with thesis fetch and hand it in with thesis submit; the thesis toolkit, with pandoc, the Lua filter, the template and pdfLaTeX, runs the gates; the reviewer records the verdict with a hash; assemble builds the PDF and runs pdf-qa and ufrj-check; publish puts the PDF in the outbox, where Hermes and the owner read it; the six seats run on Claude Code in the openrig unit of 2G.](img/thesis-rig.png)

Interactive page: <https://www.piabrota.art/figures/thesis-rig/>

<details open>
<summary>How to read this figure</summary>

**Takeaway.** Six Claude Code seats write independent sections, a toolkit with no model checks and builds them, and one PDF leaves in an outbox that the owner reads.

**How to read.** Top to bottom and left to right, one lane for each role. The top strip marks the five phases. The red border marks where a person comes in. Each arrow carries the command or the file that passes from one part to the next.

**Not shown.** The three writers are one box. Also the four gates, the project files and the consent prompt of Claude Code.

**Evidence.** [`docs/archify/thesis-rig.json`](archify/thesis-rig.json), the source of the figure; `openrig/specs/rigs/wave-forecaster-thesis/rig.yaml`, [`docs/THESIS.md`](THESIS.md). ⚠ No seat has run this rig: the arrows are the design, not a run.

</details>

![How nix-os works: a pull request runs ci.yml on every push; a merge to main runs deploy.yml, which builds the system on the GitHub runner; deploy-rs copies the closure to the VPS over SSH and switches it, the VPS fetching store paths from cache.nixos.org; if SSH falls silent for 60 s, magic rollback restores the old system; after the switch, freeze.yml lists the VPS's packages, and cves.yml reports vulnix on the same push.](img/how-nix-os-works.png)

Interactive page: <https://www.piabrota.art/figures/how-nix-os-works/>

<details open>
<summary>How to read this figure</summary>

**Takeaway.** Nobody deploys by hand: merging a pull request is the deploy, and a switch that cuts SSH undoes itself.

**How to read.** Top to bottom, one lane per place where the work runs. Arrows say what flows or what comes next; the red border marks where you come in.

**Not shown.** The secrets and the `prod` environment, `wiki.yml`, the Markdown-only pushes that skip the build, and the deploy by hand (`just deploy`).

**Evidence.** [`docs/archify/how-nix-os-works.json`](archify/how-nix-os-works.json), the source of the figure; `.github/workflows/`, `flake.nix` (`deploy.nodes.piabrota`, `magicRollback`), [`docs/DEPLOY.md`](DEPLOY.md).

</details>

![piabrota.art: a browser resolves the two A records on Porkbun, which point at the VPS; nginx answers piabrota.art with a 301 to https://www and serves www.piabrota.art over HTTP and HTTPS, with /nixos a 302 to the repository and a Let's Encrypt certificate per name; the page was built before the deploy, site/ in Gleam prerendered by Nix into /nix/store as three pages and style.css, which is nginx's root.](img/piabrota-art.png)

Interactive page: <https://www.piabrota.art/figures/piabrota-art/>

<details open>
<summary>How to read this figure</summary>

**Takeaway.** The VPS serves a few small files from the store; Gleam, node and the build never reach it.

**How to read.** Top to bottom: the visitor, DNS, nginx on the VPS, and what was built before the deploy. Arrows say what a request is sent to, or what goes into what.

**Not shown.** The ACME HTTP-01 challenge, the `httpsOnly` switch, and the Loco apps that would share nginx.

**Evidence.** [`docs/archify/piabrota-art.json`](archify/piabrota-art.json), the source of the figure; `site.nix`, `site/default.nix`, [`docs/SITE.md`](SITE.md).

</details>

`just figure` draws them again with the pinned [archify](https://github.com/tt-a1i/archify)
(`vendor/archify`), the same way as piabrota/pirsig and piabrota/gramatico; `just figure-check` says
whether a PNG is stale. The `figure` skill (`.agents/skills/figure/`) has the rules.
