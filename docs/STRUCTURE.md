# Structure

The pins, the file tree, the flake outputs and every `just` recipe of nix-os. The README keeps the short version.

## Recipes

```console
just build          # build the system here, without deploying it
just check          # what CI runs: nix flake check, nixpkgs-fmt, statix, deadnix, the DeepWiki check
just deploy         # deploy by hand, as CI does (DEPLOY_HOST=<ip>; a human only)
just specs          # CPU, RAM, disk, kernel and NixOS generation of this machine
just remote-specs   # the same, of the VPS, over SSH
just remote-hermes-check  # Hermes's add-ons are live on KVM 4 (DEPLOY_HOST=<its address>)
just remote-health  # memory, disk, CPU and units of a VPS: `just remote-health h0ffmann <address>` for KVM 4
just remote-restart  # restart the services the box has, after a prompt: `just remote-restart hermes`, `list`, `"all --dry-run"` (a human only; docs/DEPLOY.md)
just metrics-test   # the metrics page's rules and its fetch (docs/METRICS.md)
just scala-test     # compile scala/ and run the tests of every script (scala/README.md)
just scala-build    # the scripts' binary, piabrota, built by Nix with its tests
just cves           # CVE report of the system closure (vulnix; a report, not a gate)
just security       # the security review of security.yml: gitleaks on the history (fails on a finding), zizmor on the workflows
just freeze         # every package of the running system with its size, like pip freeze
just remote-freeze  # the same, of the VPS, over SSH
just drawing        # write docs/drawings/ again from drawings/
```

Every justfile here runs on the `just` that Ubuntu 24.04 ships through apt (1.21.0); CI parses it
with that version.

## What it pins

| Input | Pinned at | What for |
|---|---|---|
| [nixpkgs](https://github.com/NixOS/nixpkgs/tree/nixos-26.05) `nixos-26.05` | [`9bb5222`](https://github.com/NixOS/nixpkgs/commit/9bb52223f4f6a0cc606fd0852d8784f896c137d5) (2026-11-01) | the system; `system.stateVersion` is 26.05 |
| [deploy-rs](https://github.com/serokell/deploy-rs) | [`1cec052`](https://github.com/serokell/deploy-rs/commit/1cec0527bd09074bbee6d4461900ce5d58267217) (2026-10-19) | the activation and its rollback; the `deploy` binary comes from nixpkgs, so CI does not compile it |
| [hermes-agent](https://github.com/NousResearch/hermes-agent) [`v0.23.1`](https://github.com/NousResearch/hermes-agent/releases/tag/v0.23.1) | [`3b42157`](https://github.com/NousResearch/hermes-agent/commit/3b421578588243f920886e6fe79a6faa87ea026e) (2026-11-09) | Hermes Agent's package and NixOS module (`hermes.nix`); pinned to a release tag in `flake.nix`; it keeps its own nixpkgs (unstable), for which its build is made |

`flake.lock` is the truth; this table is what it held on 2026-11-07. The Hermes badge at the top is
edited by hand: change it with the pin. Update nixpkgs with `nix flake update` in a pull request; the
Hermes tag is changed by hand (`docs/HERMES.md`, "Updating and turning it off").

## Structure

```
.
├── flake.nix, flake.lock    a system and a deploy-rs node per host, the checks
├── configuration.nix        what every host shares: the Hostinger KVM base and the common modules
├── hosts/piabrota/          KVM 1: the public web only
├── hosts/piabrota2/         KVM 4: the full Hermes, its GitHub App and dashboard, OpenRig, PGX (docs/DEPLOY.md)
├── piabrota.nix             the user h0ffmann and the base packages
├── tools.nix                light CLI tools, and the size and memory limits
├── deploy.nix               the deploy user that CI logs in as, GC, boot generation limit
├── loco.nix                 Loco apps: a sandboxed service each, SQLite, backups, nginx + ACME
├── apps.nix, apps/notes/    the Loco apps: a notes CRUD demo at www.piabrota.art/notes (docs/LOCO.md)
├── site.nix, site/          the static site on www.piabrota.art (Gleam + Lustre, prerendered by Nix)
├── skills-site/             the skills website at skills.piabrota.art, a vhost of site.nix (docs/SITE.md)
├── pgx.nix, pgx/            PGX, a Postgres-compatible engine, its package and its VM test
├── hermes.nix               Hermes Agent, from its flake's NixOS module (docs/HERMES.md)
├── hermes-github.nix        Hermes's GitHub App: hermes/* branches and pull requests
├── hermes-web.nix           Hermes's dashboard on hermes.piabrota.art, behind nginx and basic auth
├── hermes-web/docs/         the page the dashboard's Documentation tab shows
├── metrics.nix, metrics/    the metrics page at metrics.piabrota.art and its VM test; the collector is in scala/metrics/ (docs/METRICS.md)
├── proof.nix, proof-site/   the HTML pages of h0ffmann/proof at proof.piabrota.art and of piabrota/pirsig at pirsig.piabrota.art, each with an index
├── favicon.nix, favicon/    the eye as the icon of every vhost under piabrota.art (docs/SITE.md)
├── openrig.nix, openrig/    OpenRig, the engine of the software factory: its package, its rig specs and its UI (docs/OPENRIG.md)
├── thesis/                  the thesis rig's profile and TeX set; its `thesis` command is in scala/thesis/ (docs/THESIS.md)
├── kubesolo-purge.nix       a oneshot that clears an old install from the box; delete once it ran
├── keys/deploy.pub          the public key of the CI deploy key
├── scala/                   every script, in Scala 3, as one Scala Native binary: `piabrota <command>` (scala/README.md)
├── scripts/domains.txt      every name under piabrota.art and its host, for `piabrota cert-check`
├── drawings/                the pen and the drawing, in Nix, that draw docs/drawings/mu.svg
├── mockups/                 three mockups of the piabrota.art homepage, SVG in pure Nix (docs/MOCKUPS.md)
├── docs/archify/, docs/img/ the figures' archify sources and PNGs; vendor/archify is the pinned archify
├── docs/DEPLOY.md           how a merge reaches the VPSs, and the one-time setup
├── docs/MIGRATION-KVM4.md   the checklist that moves Hermes from KVM 1 to KVM 4
├── docs/FIGURES.md          the figures, how to read them, the software factory status
├── docs/STRUCTURE.md        this page: recipes, pins, the file tree, the flake outputs
├── docs/LOCO.md             how to add a Loco app
├── docs/SITE.md             how to turn the static site on
├── docs/MOCKUPS.ptBR.md     the homepage mockups, in Portuguese
├── docs/MOCKUPS.md          the same, in English
├── docs/FORK.ptBR.md        how to run your own VPS from a fork, in Portuguese
├── docs/FORK.md             the same, in English
├── docs/CLAUDE_PROJECT.ptBR.md  a Claude Project for a fork, in Portuguese
├── docs/CLAUDE_PROJECT.md   the same, in English
├── docs/HERMES.ptBR.md      Hermes Agent here: setup, secrets, checks, in Portuguese
├── docs/HERMES.md         the same, in English
├── docs/PGX.ptBR.md         PGX here: cost, limits, use, in Portuguese
├── docs/PGX.md            the same, in English
├── docs/OPENRIG.md        OpenRig and the software factory here: setup, UI, status, guardrails
├── docs/THESIS.ptBR.md    the thesis rig: parts, gates, UFRJ rules, deployment notes, in Portuguese
├── docs/THESIS.md         the same, in English
├── docs/drawings/           the README drawing and its Desmos state
├── .github/workflows/       ci.yml (every PR beyond Markdown: lints and the justfile parse; the full flake check by hand), cves.yml (push to main beyond Markdown, and weekly), deploy.yml (push to main beyond Markdown), freeze.yml (after each deploy), wiki.yml (copies wiki/ to the GitHub wiki), code-smell-report.yml (every PR and push to main: a code smell score, not a gate), flake-update.yml (weekly: a nix flake update PR with its closure diff), security.yml (by hand: gitleaks on the history, zizmor on the workflows; .gitleaksignore holds the findings read and cleared)
├── .github/dependabot.yml   one PR a week that bumps the actions the workflows use
├── wiki/                    the GitHub wiki's pages, in Portuguese and English
├── .agents/skills/          vendored skills for agents (.claude/skills links here), four Nix, three frontend, figure and archify (their README); .mcp.json: mcp-nixos, OpenPencil, DeepWiki
├── .devin/wiki.json         how DeepWiki writes this repository's wiki (deepwiki.com/piabrota/nix-os); piabrota deepwiki-check checks it in CI
├── justfile
├── llms.txt                 the index of all the public work of h0ffmann, for agents and visitors (no DOI); the README links it
└── AGENTS.md                the rules for AI agents working here
```

## Flake outputs

```console
$ nix flake show
├───checks
│   └───x86_64-linux
│       ├───deploy-activate: derivation 'deploy-rs-check-activate'
│       ├───deploy-schema: derivation 'jsonschema-deploy-system'
│       ├───drawing: derivation 'mu-art-check'
│       ├───loco-example: derivation 'nixos-system-nixos-26.05.20261028.08d3a97'
│       ├───mockups: derivation 'mockups-check'
│       ├───toplevel: derivation 'nixos-system-srv2108887-26.05.20261101.9bb5222'
│       └───toplevel-kvm4: derivation 'nixos-system-kvm4-26.05.20261101.9bb5222'
├───deploy: unknown
├───devShells
│   └───x86_64-linux
│       ├───default: development environment 'nix-shell'
│       └───site: development environment 'nix-shell'
├───formatter
│   └───x86_64-linux: package 'nixpkgs-fmt-1.3.0'
├───nixosConfigurations
│   ├───kvm4: NixOS configuration
│   └───piabrota: NixOS configuration
└───packages
    └───x86_64-linux
        ├───deploy-rs: package 'deploy-rs-1.0.0'
        ├───mockups: package 'mockups'
        ├───mu-art: package 'mu-art'
        └───site: package 'piabrota-site-1.0.0'
```

This block was taken before the rename of `kvm4` to `piabrota2`: the host, its system and its check now carry the new name.
