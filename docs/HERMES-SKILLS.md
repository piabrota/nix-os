# The owner's skills in Hermes

Hermes can use the skills in [h0ffmann/skills](https://github.com/h0ffmann/skills) (MPL-2.0).
Each skill is a command in chat. This file is in English only, by the owner's order.

Read on 2026-11-03, at commit `78c5cac` of `h0ffmann/skills`. That repository has 51 skills.
This box loads 29 of them.

## How to use a skill

- **Telegram and other chats:** send `/name` and your request. Example: `/ste100 rewrite this PR body`.
- **Discord:** send `/skill`, choose the name from the list, and write the request in `args`.
  Discord shows 25 names at a time. Type some letters to filter them.
  Plain text that starts with `/name` goes to the same handler in the gateway code. I did not test it on Discord.
- **Stack skills:** put up to 5 names at the start of one message. Example:
  `/ste100 /ponytail-review check this diff`.
- **No command:** Hermes can also load a skill by itself when the task matches its description.
- **Who can use it:** only the allowed user, as for every other command.

A skill is text that tells me how to do a task. It does not give me new permissions.
The deny list in `hermes/dangerous-patterns.yaml` and the rules in `hermes/SOUL.md` still apply.

## The 29 commands

**Writing**

| Command | What it does |
|---|---|
| `/ste100` | Writes or rewrites English in ASD-STE100 Simplified Technical English |
| `/ptbr` | Rewrites technical pt-BR text by level of rigour |
| `/cientifico` | Writes and reviews scientific pt-BR text with sources |
| `/ptbr-humanizer` | Makes the pt-BR text of a site sound Brazilian |
| `/easy-translate` | Makes an easy pt-BR, Easy Japanese or controlled Chinese version of a source |
| `/essay` | Checks that an essay keeps the form of Montaigne |
| `/writing-styles` | Picks the writing style of a document from its reader |

**Research**

| Command | What it does |
|---|---|
| `/paper` | Writes a citable text where each claim has a mark and a source check |
| `/cite-release` | Keeps the Zenodo and `CITATION.cff` data of a release correct |
| `/open-text` | Gets the full text of a free work and keeps it with its licence |
| `/eli5` | Explains a part of a project to a new reader, picture first |

**Work on code**

| Command | What it does |
|---|---|
| `/lean-code` | Writes or reviews code with the smallest correct diff |
| `/ponytail-review` | Reviews a change for logic, safety, load, tests and speed |
| `/loco` | Helps with a Loco (Rust) app |
| `/nixos-vps` | Changes the NixOS configuration of a small live VPS |
| `/nix-debug` | Finds why a Nix build, deploy or service fails |
| `/nix-lab` | Writes a self-contained Nix flake lab |
| `/systemd-hardening` | Hardens a systemd service written in Nix |
| `/sharingan` | Reads another repository and decides, with its licence, what to copy |
| `/retro` | Reviews a coding session and proposes changes to the environment |

**Project flow**

| Command | What it does |
|---|---|
| `/triage` | Turns a raw idea or bug report into one issue body. A person files it. |
| `/mip` | Writes or revises an Improvement Proposal |
| `/easy-issues` | Finds small open issues that are ready for an agent |
| `/skill-validator` | Writes, reviews or fixes an agent skill |

**Sites and figures**

| Command | What it does |
|---|---|
| `/news-post` | Writes or reviews a news post in pt-BR and English |
| `/web-ui` | Changes or reviews what a visitor sees on a site |
| `/citizen-science` | Keeps an open-data site checkable and easy to join |
| `/svg-diagram` | Draws a repository map as one SVG |
| `/ddraw` | Draws a one-line drawing as Desmos equations and SVG |

## What is not loaded, and why

22 skills stay out. The list of loaded skills is `ownerSkillPaths` in `hermes.nix`.

| Skill | Reason |
|---|---|
| `bipr`, `pr-images` | They make a bilingual PR. The owner's rule for my PRs is 100% English. |
| `mip-tasks` | It tells the agent to merge in order and to force-push. I may do neither. |
| `mip-overnight` | It assumes the settings file of Claude Code. |
| `handoff` | It saves notes in an Obsidian vault. This box has none. |
| `agentskills-checker`, `zk-method`, `voice-note` | Each one runs a script with `python3`. This box has no `python3` command. `voice-note` also needs whisper. |
| `citation-score` | It runs a script that needs `pandoc`. This box has no `pandoc`. |
| `ptbr-routing` | It runs a shell script, and it only picks between `ptbr` skills. |
| `ptbr-writer` | It is a copy of `ptbr` under a longer name. Two copies cost tokens twice. |
| `retorica` | It is a stub. The skill itself says it has no rules yet. |
| `maps` | The name is already a bundled Hermes skill. The bundled one wins. |
| `figure` | It needs `just`, Node and Chrome. |
| `pirsig`, `pirsig-slips` | They need the `psg` and `zk` programs. This box has neither. |
| `ww3-port`, `ww3-port-rust`, `ww4-status`, `noaa-notices`, `wfip`, `release` | They are for the WAVEWATCH III work and call `just`, `python3` or Docker. This box is not a build machine. |

To add a skill, add its path to `ownerSkillPaths` in `hermes.nix`. A merge deploys and restarts the unit.

## Limits you should know

- **Commands in a skill may not run here.** Some loaded skills say `just check` or `nix flake check`.
  This box has no `just`, and I do not run Nix builds here. I say what I could not run.
- **Manual-only flag.** Three loaded skills carry `disable-model-invocation: true` in the source repository
  (`triage`, `easy-issues` and `retro`). I found no code in Hermes at the pinned commit
  that reads this key. Hermes can load them without a command.
- **Read-only.** The skills are in the Nix store. I cannot edit them with `skill_manage`.
  A fix goes to `h0ffmann/skills`, and then a new pin goes to this repository.
- **Conflicts with a local skill.** A skill in `/var/lib/hermes/.hermes/skills/` with the same name
  wins over these. No loaded name clashes with a local one today (checked on 2026-11-03).
- **Prompt cost.** The 29 descriptions are about 6,000 characters in total. Hermes shows a shorter
  text of each one in my skill index, and a skill body loads only when used. I did not measure the
  cost per session.
- **The source repository's own rules do not apply here.** Its `AGENTS.md` asks for a `Co-Authored-By`
  trailer in commits. That rule is for work in that repository. In this repository, and for my PRs,
  the rules of `hermes/AGENTS.md` win.
- **Tested:** the real `hermes skills list` loaded all 29 from a copy of the pinned source, next to
  the 6 optional skills, with no error. I did not run a skill on a task.

## Should h0ffmann/skills be a git submodule here?

No. Use a pin by commit in `hermes.nix`, as for the other add-ons.

1. **A flake does not see submodules.** A flake reads its git tree without submodules unless its URL
   says `?submodules=1`. The build runs on the CI runner and on `nix flake check`.
   A submodule path would be empty there, and the skills would be missing with no error.
2. **The existing submodule is different.** `vendor/archify` is used only by `just figure`, outside
   the Nix build. Skills are an input of the system.
3. **`fetchFromGitHub` fits the rules of this repository.** It pins a commit and a hash. The hash
   proves the content. Two other add-ons already use this pattern.
4. **A submodule adds work.** CI would need `submodules: true` in the checkout. That means a change
   to a workflow, which I cannot make.
5. **The closure stays small.** `runCommand` copies only the 29 skill folders (under 300 KB) and has
   `allowedReferences = [ ]`, so the full source stays out of the system.

A flake input with `flake = false` is the other good option. The weekly `flake-update` job would
then move the pin. This repository chose a manual pin, so a person reviews each new commit.

## Update the pin

```console
rev=$(gh api repos/h0ffmann/skills/commits/main --jq .sha)
nix-prefetch-url --unpack "https://github.com/h0ffmann/skills/archive/$rev.tar.gz"
nix hash convert --hash-algo sha256 --to sri <the hash that the first command prints>
```

Put `rev` and the new hash in `ownerSkillsSrc` in `hermes.nix`. Read the diff of the skills first.
Then check that every path in `ownerSkillPaths` still exists. A missing path fails the build.
