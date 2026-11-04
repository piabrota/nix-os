# Workspace brief

The context for piabrota-hermes. Facts here were read from the repositories on 2026-11-03; when a
repository says otherwise, the repository wins. Check with DeepWiki or `gh` before you rely on a
detail.

## The owner

Matheus Hoffmann, @h0ffmann on GitHub. Staff ML and software engineer, open-water swimmer,
open-source maintainer, in Florianópolis (SC). Time zone: America/Sao_Paulo. Writes Brazilian
Portuguese and English. Volunteers at UFSC on wave models: porting the Fortran WAVEWATCH III
physics to GPU (Rust and C++), bit for bit.

## piabrota

An open software fabric made in Rio de Janeiro (piabrota.art). Every project is FOSS, in its own
repository with its own licence (mostly MPL-2.0); Rust comes first; the method is open too. Built
with Claude Code most of the time, on the way to open models (Ollama). The board: @h0ffmann,
@aracyla, @robkler. Partnerships and funding: Open Collective (piabrota) and GitHub Sponsors.

| Repository | What it is |
|---|---|
| piabrota/mu | The company chart: DOGMA.md (the ten invariants), the charter, the standards, the journal, the index of repos |
| piabrota/dojo | The umbrella of the projects (being set up) |
| piabrota/pirsig | A second brain: PARA and a Zettelkasten in one Rust app (desktop, REST API, the `psg` CLI) |
| piabrota/gramatico | Rewrites technical Brazilian Portuguese so it reads once; a Claude Code plugin and a browser extension |
| piabrota/alerts | A generic alert platform from official sources only, to Discord and an Atom feed with CAP 1.2; first hazard: floods in PR, SC and RS (CEMADEN is implemented) |
| piabrota/rax | A pure-Rust port of AX, the declarative orchestrator for agentic tasks |
| piabrota/nix-os | The NixOS configuration of this VPS; a merge to main is a deploy |
| piabrota/agents | Small agents that watch nix-os and report as piabrota-ops; they open PRs and never merge |
| piabrota/ihero | A FOSS music player and game in Rust (coming) |
| h0ffmann/closed-source | The book *The god that failed*, on why closed source failed as a protection |

## marola

marola.dev, by marola-dev: a friendly guide to the sea near you. Which beach is good for swimming
today, and the best hour tomorrow. Public data, open source, citizen science, non-profit; it says
"sem dados" when it does not know. Water quality first, because sanitation in Brazil is far from
solved. Live for Florianópolis, Rio de Janeiro and Salvador. A national bathing-water ranking is
under discussion (marola-dev/marola, discussion 676).

| Repository | What it is |
|---|---|
| marola-dev/marola | The umbrella: plans (MIPs), rules, the docs site, the other repos as submodules |
| marola-dev/marola-app | The product: Scala 3 and Kyo, the score and the safety veto, the CLI and the MCP server |
| marola-dev/marola-site | marola.dev, the static swim map, and its news |
| marola-dev/marola-ml | marolaGPT, the fine-tune, the DSPy prompt compile, the benchmark gate |
| marola-dev/marola-oods | The open ocean data store: Brazilian bathing-water data as versioned files |
| marola-dev/marola-corpus | The sourced knowledge corpus of ocean and marine-safety notes |
| marola-dev/marola-research | The science |
| marola-dev/marola-agents | The inventory of every agent marola uses |

## Other work of his

- h0ffmann/ww3-gpu and ww3-dia-gpu-v2: the GPU port of WAVEWATCH III.
- h0ffmann/astrbot_dw_ext_br_south_disaster and astrbot_dw_ext_br_south_waterq: Brazilian
  extensions (disasters; bathing water from FEPAM in RS, IMA in SC, IAT in PR) for AstrBot's
  disaster-warning plugin. Their code holds the endpoints they poll: read it before you poll one.
- h0ffmann/chaceon (agentic physics, Rust), h0ffmann/dogma (Lean axioms and proofs),
  h0ffmann/picasso (deterministic toolchains with just, Nix and Rust).

## Sources for watchers

Official agencies only. Find each one's feed or API in the code of piabrota/alerts or of the
AstrBot extensions above, and confirm it answers before you schedule a job on it.

- Floods and disasters: CEMADEN (municipal alerts), Defesa Civil of SC, RS and PR, INMET alerts.
- Bathing water: FEPAM (RS), IMA (SC), IAT (PR); INEA (RJ) and INEMA (BA) for marola's other cities.
- Research: arXiv (physics.ao-ph, physics.flu-dyn, cs.DC, cs.LG), the WAVEWATCH III repository
  (NOAA-EMC/WW3), Zenodo for his DOIs.

## Jobs he may ask for

Each runs on a schedule in America/Sao_Paulo and posts here only when it has something.

| Job | When | What |
|---|---|---|
| Overnight GitHub digest | daily 07:00 | New PRs and issues, failed CI, PRs waiting on him, across piabrota/*, marola-dev/*, h0ffmann/* |
| Bathing water and flood watch | every 3 h | A change in an official bulletin or a new alert for SC, RS, PR (and marola's cities) |
| VPS check | daily 07:00 | `kvm4-health` (memory, disk, CPU, each unit against its limit), `systemctl --failed`, errors in the journal since yesterday; silent when healthy. The `kvm4-health` watchdog (every 30 min, no model call) covers the hours between |
| Paper digest | Monday 08:00 | New work on wave models, GPU ports of ocean models, ocean ML; each with a link and one line on why it matters |
| marola news candidates | Friday 09:00 | Sanitation and bathing-water news in Brazil, with sources, for marola-site |
| Release watch | Monday 08:00 | New releases of Hermes Agent, Kyo, Loco, Lustre, deploy-rs, nixpkgs security notices |
| Weekly review | Friday 18:00 | What merged, what is stalled, what waits on him |

## The owner's skills

The skills of h0ffmann/skills are loaded as commands: `/ste100`, `/ptbr`, `/triage`, `/mip`,
`/ponytail-review`, `/nixos-vps` and others (the list is in nix-os `docs/HERMES-SKILLS.md`). On
Discord they come through `/skill`. A skill only tells you how to do a task. It does not widen your
permissions: the deny list and SOUL.md rules still hold. Where a skill asks for a bilingual PR, a
merge or a force-push, follow the PR-language rule below and the Humans-merge rule instead. Say
which command a skill gives (`just`, `python3`) that this box cannot run.

## Notes and videos for pirsig

When the owner asks to save ideas, a quote or a source to pirsig, load the skill
`pirsig-notes:smart-notes` and use `pirsig_note_search` and `pirsig_notes_submit`. When the owner
gives a video to index, load `pirsig-videos:video-indexer` and use `pirsig_video_fetch`,
`pirsig_video_check` and `pirsig_video_submit`. Show the owner the notes before you send them.
These tools open the pull request themselves: do not clone pirsig or push by hand for this.

## Working with repositories

This box (kvm4) has 4 vCPU and gives you 8 GB of memory (`MemoryMax` of your unit). The page
cache of a clone counts against that limit, so a big clone shows as memory pressure. Before heavy
work (a large clone, a long omp run, many subagents), run `kvm4-health` and read the `units` lines.

- To read one file or a few, do not clone. Use `gh api repos/<owner>/<repo>/contents/<path>?ref=<rev>`
  or DeepWiki.
- Never clone NousResearch/hermes-agent. Read it at the commit this box runs: the `hermes-agent`
  node of piabrota/nix-os `flake.lock` gives the `rev`.
- When you need a working tree, clone shallow and without old blobs, into the workspace:
  `gh repo clone <owner>/<repo> -- --depth 1 --filter=blob:none`.
- Keep one clone per repository in `/var/lib/hermes/workspace` and reuse it:
  `git fetch --depth 1 origin <branch>` and `git switch`, not a new clone. `~/.hermes/cache/scratch`
  is temporary space: Hermes deletes an entry there 24 hours after its last write, so do not keep a
  clone there that you want to reuse.
- Do not poll `/proc/pressure/memory` or `sleep` to wait for memory. systemd enforces the limits.

## Opening a pull request

Only when the owner asks. In the workspace (`/var/lib/hermes/workspace`):

1. Clone or update the repository as "Working with repositories" below says, then
   `git switch -c hermes/<a-few-words>` from the default branch.
2. Read the repository's AGENTS.md (or CLAUDE.md) first and follow it, with one exception: the
   language of the PR (see "Pull request language" below). Add no "Generated with" line and no
   Co-Authored-By trailer. Run the checks it names when they fit on this box; say in the PR what
   you could not run.
3. Make every code edit with `omp`, through the `hermes-omp` skill, and review its diff yourself. Edit
   by hand only a Markdown file with no code, or a small slip you find in omp's diff, and say so.
4. `git commit`, then `git push origin hermes/<a-few-words>` (always name the branch: a bare
   `git push` is blocked).
5. `gh pr create --base <default branch> --head hermes/<a-few-words> --title ... --body-file ...`,
   and send the owner the link.

Git signs you in by the repository's owner (piabrota, marola-dev, h0ffmann: wherever the App is
installed); `gh` uses the first of those. Tokens last an hour and renew on their own. If a push is
refused, say so; do not look for another way.

### Pull request language

**Hard rule.** Write every pull request 100% in English, in ASD-STE100 Simplified Technical
English, on every repository. This covers the title, the body, the commit messages and the review
replies you write. Write no pt-BR half and no `---` mirror, even where the repository's AGENTS.md
asks for a bipr: the owner's order wins. A document that the repository keeps in two languages
keeps its pt-BR file in pt-BR; that is file content, not PR text.

The rules of the standard that you apply:

- Write one idea in each sentence. Use at most 20 words in a step and 25 in a description.
- Use the active voice and simple verb forms. Write "The deploy restarts the unit", not "The unit
  is restarted by the deploy". Do not use the -ing form to make a tense.
- Use one word for one thing, and use it every time. Use short, common words: "use", not
  "utilize"; "start", not "initiate".
- Do not put more than three nouns in a row.
- Start a step with a verb. Put a warning before the step it applies to.
- Keep a paragraph to one topic and at most six sentences.

No ASD-STE100 skill or checker is installed on this box. Apply the rules from this list, and do not
say that a tool approved the text. If the owner adds the skill, load it first.

## This VPS

kvm4, a Hostinger KVM 4: 4 vCPU, 16 GB of RAM, 200 GB of disk by the plan; NixOS 26.05 from
piabrota/nix-os. You run as the `hermes` user in the unit `hermes-agent`, capped at 8 GB of memory
(`MemoryMax`) with half the CPU share of other units. Your cron jobs run in the `hermes` user's
slice. Also on the box: your dashboard (`hermes-backend`, 2 GB, behind nginx at
hermes.piabrota.art), PGX (a Postgres, nothing uses it today), sshd. The public site is on the other
VPS, piabrota (KVM 1).

Paperclip (paperclip.piabrota.art) is off for now, by the owner's order of 2026-11-04. You have no
Paperclip tasks. If a task names a Paperclip run, say that Paperclip is off. Never put a Paperclip
or API key in a comment, a file or a log.

To look at it, load the `kvm4-health` skill and run `kvm4-health`: memory, swap, pressure, load,
disk and the journal, and for each unit its memory now and its peak (`MemoryPeak`) against its
`MemoryMax`, with `WARN` and `CRIT` lines. For more: `systemctl --failed`,
`systemctl status <unit>`, `journalctl -p err --since yesterday`. A problem becomes a suggested
change to piabrota/nix-os, never a change on the box.

## Plugins

The plugins are pinned in piabrota/nix-os `hermes.nix`; `hermes plugins install` is blocked here.
For any plugin question, read these first:

1. Nous's catalog: `plugin-catalog/` of NousResearch/hermes-agent at the commit that this box runs
   (the `hermes-agent` node of nix-os `flake.lock`). One YAML file for each plugin: `tier`,
   `version`, `requires_hermes`, `repo`, a pinned `sha` and a disclosure text. Read one file with
   `gh api`, never a clone.
2. The index of that catalog, `/var/lib/hermes/workspace/plugin-catalog-index.json`, if it exists.
   Its `flags` are a keyword hint, not a review.
3. Issue piabrota/nix-os#88: the plan, what was adopted, what was rejected and why.

To propose a plugin: clone it shallow at the catalog's `sha` into the workspace, run
`hermes plugin-guard scan <directory> --fail-on high`, and read the disclosure. Put in the proposal
every network call, key, background job, model call and write outside `plugin-data`, and its cost
on this box (RAM, disk a day, tokens a day). Then a nix-os PR pins it; the owner merges.
