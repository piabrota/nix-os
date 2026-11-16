# Should piabrota fork Hermes?

The trade-offs of a piabrota fork of [Hermes Agent](https://github.com/NousResearch/hermes-agent)
against the upstream that this box runs today, for piabrota's needs. Written on 2026-11-03, from
the pinned commit `d9f15af` and this repository. This file is in English only, by the owner's
order. It replaces the earlier survey of third-party forks (git history has it).

## Answer

Do not fork yet. Keep upstream, pinned by `flake.lock`, and tailor it with configuration, skills,
plugins, MCP servers and `SOUL.md`/`AGENTS.md`. When a change to Hermes's own code is necessary,
carry it as a patch file in this repository and send it upstream. Start a fork when one of the
signals in "When to fork" is true.

Confidence: medium. The facts about upstream come from its code and docs at the pin. The cost of
a fork is an estimate: nobody here has maintained one.

## What piabrota needs from Hermes

From `hermes/AGENTS.md` and `hermes/SOUL.md`:

| Need | Met today by | Needs the core? |
|---|---|---|
| Official alerts (CEMADEN, Defesa Civil, INMET) and bathing water (FEPAM, IMA, IAT) | `watchers` and `rss-feeds` skills, Hermes's cron | No |
| Ocean research digests, papers, citations | `research-paper-writing`, `arxiv`, `evidence-ledger-research` | No |
| GitHub work as piabrota-hermes[bot], humans merge | `gh`, the App tokens (`hermes-github.nix`), the deny-list plugin | No |
| The owner's skills as commands | `skills.external_dirs` (h0ffmann/skills, pinned) | No |
| Long tasks that continue on their own (the Ralph loop) | `/goal`, at the pin | No |
| Identity, voice, the "piou a melhoria" rule | `SOUL.md`, `AGENTS.md` | No |
| Fit in 1 vCPU and 1 GB | the `minimal` package, run limits, graceful reload | No |
| Two models: Sonnet decides, Haiku does mechanical work | `delegation` and `auxiliary` settings | No |

No need on this list requires a change to Hermes's code today.

## Three ways to tailor Hermes

| | Upstream, tailored from outside (today) | Upstream plus patch files in nix-os | A fork: `piabrota/hermes-agent` |
|---|---|---|---|
| What you can change | Configuration, skills, plugins and hooks, MCP servers, `SOUL.md`/`AGENTS.md` | Also small changes to the core, a few files each | Everything: the core, the defaults, the Nix module, the dependencies |
| Updates | The weekly `flake-update.yml` PR, with CI and the `dix` closure diff | The same weekly PR. A patch that no longer applies fails the build and names the file | You merge upstream by hand. Upstream changes many times a day, and conflicts land in the files you changed |
| Security fixes | When the weekly PR merges | When the weekly PR merges | When you merge upstream |
| Nix module | Upstream keeps it ("best effort"); the pin protects you | The same | Yours to fix when it breaks |
| Size on the box | `minimal` plus four extras | The same | You can remove code paths, but `minimal` already leaves out voice, browser and Bedrock: the gain is small |
| Community add-ons and docs | Work as documented | Work as documented | Can drift from your code; each one needs a check |
| Extra work | None | One patch file and one upstream PR per change | A second repository: CI, Nix checks, merges, the MIT notice that keeps the Nous copyright line |
| Going back | Nothing to undo | Delete the patch | Hard after months of divergence |
| Giving back | Publish skills and plugins | Each patch becomes an upstream PR | Upstream PRs come from the fork |

## The cost of a fork, for this owner

- **Merge work every week.** Upstream at the pin has tens of thousands of commits and thousands of
  open PRs. A fork that changes the core must merge that flow by hand, or fall behind.
- **Late security fixes.** Hermes runs a shell, holds a GitHub App token and reads web pages. A fix
  that waits for a manual merge stays open on a live box.
- **The Nix module becomes yours.** Upstream keeps Nix "best effort". Today the pin and the weekly
  PR catch its breaks before a merge. In a fork, a break is yours to fix.
- **One person.** The owner reviews every PR here. A fork adds a second stream of reviews that do
  not move piabrota's goals.

## What a fork would give

- **Changes upstream refuses.** For example, memory scoped per user, which upstream's hooks cannot
  do (upstream issue 34352, the reason hermes-agent-mt patches the core).
- **A smaller program.** Removing modules the box never loads. The gain is small after `minimal`,
  and it was not measured.
- **Defaults for this box in code**, not in `hermes.nix`. That only moves them: the settings already
  work.
- **A home for upstream PRs.** This is cheap, and it needs no change on the box: the VPS keeps
  running upstream.

## When to fork

Start a fork when one of these is true:

1. Two or more patch files live in this repository for more than three months, and upstream
   refuses them or does not answer.
2. Upstream drops Nix, or drops a feature that piabrota depends on (cron, skills, the gateway
   platforms, `delegation`).
3. piabrota needs a change to the core that upstream will not take, such as multi-tenant memory for
   a second person who cannot use a [profile](https://hermes-agent.nousresearch.com/docs/user-guide/profiles).

Until then, a fork used only to send PRs upstream is fine, as long as `flake.nix` points at
upstream.

## How to carry a patch

1. Put the change in `hermes/patches/<name>.patch`, made against the pinned commit.
2. Apply it in `hermes.nix`, on top of the `hermes-agent` package. Check first that the `minimal`
   package takes `patches` through `overrideAttrs`: this was not tested.
3. Open the same change as an upstream PR, and link it in the patch's first line.
4. Delete the patch when upstream merges it and the weekly flake update brings it in.

## Not checked

- The cost of a fork is an estimate. I did not measure how often upstream changes the files a
  piabrota patch would touch.
- The size gain of a trimmed program was not measured.
- The patch path through `overrideAttrs` was not tested.
