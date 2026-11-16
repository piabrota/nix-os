---
name: site-pins
description: "Move every website that piabrota/nix-os serves (wave, closed, hffmnn, marola, skills, proof, pirsig, room) to the head of its source's main in one pull request. Use when asked to update the websites, bump or refresh the site pins, or when a site shows an old version of its repository."
version: 1.0.0
author: piabrota
license: MPL-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [DevOps, Nix, Websites, Pins]
    related_skills: [hermes-omp, kvm4-health]
---

> Written for this repository (the owner, 2026-11-12). It is not vendored. Hermes loads it from
> `hermes/skills/`; coding agents read the same file through `.agents/skills/site-pins`, a link.
> AGENTS.md wins wherever it disagrees with this file.

# site-pins

Each website on piabrota.art is built from its source repository at one pinned commit. A new
commit on that repository reaches the site only after a pull request here moves the pin and the
owner merges it (the merge deploys). `piabrota pins all` (`scala/scripts/Pins.scala`) moves all the pins in one go.

| Site | Address | Source | Pinned file | What else moves |
|---|---|---|---|---|
| `ww3` | wave.piabrota.art | h0ffmann/ww3-gpu | `ww3-site/default.nix` | `commits` (through `piabrota pins one ww3`) |
| `closed` | closed.piabrota.art | h0ffmann/closed-source | `closed-site/default.nix` | `commits` |
| `hffmnn` | hffmnn.piabrota.art | h0ffmann/h0ffmann | `hffmnn-site/default.nix` | `readmeCommits`, `readmeFirst` |
| `marola-site` | marola.piabrota.art | marola-dev/marola-site | `marola-site/default.nix` | — |
| `skills` | skills.piabrota.art | piabrota/skills | `skills-site/default.nix` | — |
| `proof` | proof.piabrota.art | h0ffmann/proof | `proof-site/default.nix` (`proofRev`) | — |
| `pirsig` | pirsig.piabrota.art | piabrota/pirsig | `proof-site/pirsig.nix` (`pirsigRev`) | — |
| `room` | room.piabrota.art | piabrota/room | `room-site/default.nix` | `npmDepsHash`, `version` (through `piabrota pins one room`) |

Each row always moves `rev` and the source `hash` together. Not here: the archify pin (a vendored
tool, `vendor/archify`), the thesis source (`thesis/`, a toolkit, not a site), the Hermes add-ons
(`hermes.nix`) and nixpkgs (`flake.lock`, its own PR).

## When to Use

- The owner says the websites are old, asks to update them, or asks for a "full update".
- A site shows a commit or a count that is older than its repository's `main`.
- Not for one site that has its own hourly job: `ww3-pin.yml` and `room-pin.yml` open those PRs by
  themselves. Run this skill for them only as part of a full update.

## Steps

1. Get a clean checkout of `main` of piabrota/nix-os. Hermes: the clone in
   `/var/lib/hermes/workspace` (hermes/AGENTS.md, "Working with repositories"), then
   `git fetch --depth 1 origin main` and `git switch -C hermes/site-pins FETCH_HEAD`. A coding agent:
   a branch named as AGENTS.md says (`claude/<project>-site-pins`).
2. See what is behind, without a change:

   ```bash
   piabrota pins all --list      # or: just site-pins --list
   ```

   `piabrota` is the scripts' binary that both boxes install (`/run/current-system/sw/bin/piabrota`).
   Elsewhere, from the checkout: `nix run .#piabrota -- pins all --list`.

   One line per site: `same <sha>` or `behind <pinned> <head>`. Stop here if all are `same`.
3. Look at the open PRs of piabrota/nix-os. If one already moves a pin (`agents/ww3-pin`,
   `agents/room-pin`, a person's PR), leave that site out, or say in your PR that the two move
   the same lines.
4. Move the pins:

   ```bash
   piabrota pins all                 # every site
   piabrota pins all closed proof    # some sites
   ```

   It builds each site that moved, with this flake's nixpkgs. A site that fails is put back as
   it was, and the others go on: the line says `FAILED <step>` and the exit status is 1.
   Hermes on kvm4: run `kvm4-health` first. `closed` (XeLaTeX) and `marola-site` (GHC) are the
   heavy builds; if memory is short, run `PIN_BUILD=0 piabrota pins all` and say in the PR
   that the sites were not built here and that CI's flake check builds them.
5. Read `git diff`. Only the pinned files above may change. Delete the `result-*` links; do not
   commit them.
6. Commit with a subject like `chore(sites): move the website pins to their sources' main`, and in
   the body one line per site: `<site>: <old 7> -> <new 7>`. Then a `Tested:` line with the command
   and its result (which sites were built, which failed). No agent trailer, no "Generated" line.
7. Push the branch by name and open the PR against `main`. Body in English, with the sections
   **Summary**, **Tested**, **What changed** (AGENTS.md, "Commits and PRs"); Hermes's PRs also in
   ASD-STE100. For each site, link the compare page:
   `https://github.com/<source>/compare/<old>...<new>`. Send the owner the link. Never merge.

The script is the edit: it writes only the pins. That is not a hand edit of code, so Hermes does
not need `omp` for it. A fix to a site that does not build is code: that goes through `hermes-omp`,
in its own PR, or to the owner.

## When a site fails

| Line | Usual cause | What to do |
|---|---|---|
| `FAILED the head of <repo>'s main` | no network, or the repository moved | check `git ls-remote https://github.com/<repo>.git` |
| `FAILED prefetch` | GitHub or the network | run that site again |
| `FAILED build` | the source changed its build (a new file, a new dependency, a gate in its tests) | leave that site out of the PR; tell the owner the site and the last lines of the log |
| `FAILED scripts/<site>-pin.sh` | the same, for ww3 or room; the log tail is on stderr | as above |

`closed` also reads `closed-site/zenodo.json` (the version DOIs): after a release of
closed-source, the build can pass with old DOIs. Say so in the PR if closed-source has a release
newer than that file's date.
