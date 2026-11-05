# Runtimes

[Português](Runtimes)

A runtime is the program that a seat of [OpenRig](https://github.com/mvschwarz/openrig) runs. This
page is a map of the six that OpenRig has built in (as read at v0.7.7), of its community harnesses, and of which
ones `piabrota2` runs. The full guide, with a spec line, the credentials, the permission mapping and
the state of each, is
[`docs/RUNTIMES.md`](https://github.com/piabrota/nix-os/blob/main/docs/RUNTIMES.md). It was read from
OpenRig's documents of tag v0.7.7 and not all of it ran here: no seat has done a task yet. Credits:
OpenRig by mvschwarz (Apache-2.0), [Pi](https://pi.dev) by Mario Zechner
([badlogic/pi-mono](https://github.com/badlogic/pi-mono)), and
[oh-my-pi](https://github.com/can1357/oh-my-pi) by can1357.

## The runtimes

|Runtime|What it is|Pro|Con|On `piabrota2`|
|---|---|---|---|---|
|`claude-code`|Anthropic's Claude Code in a tmux pane|The best supported by OpenRig. Uses the Claude subscription. Managed settings add rules that a repository cannot override|Unfree. About +280 MiB. Asks once to accept its bypass warning. Ranks `ANTHROPIC_API_KEY` above the OAuth token|The port rig `wave-forecaster-dev`, after this change and with `waveForecaster.enable` on (off). Needs `unfree.nix`|
|`codex`|OpenAI's Codex CLI|A native sandbox. Another model family|Needs an OpenAI login and a binary|Not installed|
|`pi`|The Pi harness, through OpenRig's runner|Small. Many providers. Precise activity|No sub-agents or plan mode by default. No Claude subscription route. No permission policy|Not installed. No spec|
|`omp`|oh-my-pi, a fork of Pi, through a runner|Works with the subscription token here. Rules of its own that a repository cannot loosen|A key only for a model written `provider/id`. A restore of a new seat needs `--fresh`|Works: `piabrota-dev` and the integrate rig|
|`terminal`|A plain shell|No model, no token|No guidance, no skills, no queue wake|Works|
|`stub`|A scripted test harness|Tests the plumbing with no tokens|Cannot prove that a message was consumed|Available. No spec|
|Community harness|An outside tool as one preset file|Brings a tool that OpenRig does not ship|Read from the screen only. No guidance. No approvals|None installed|

## Which one to pick

- The Claude subscription and the most that OpenRig can see and control: `claude-code`.
- The Claude subscription, with no unfree package: `omp`. This is what the box runs.
- OpenAI models: `codex`, after an OpenAI login and a binary exist.
- A small harness and an OpenRouter, Z.ai, Kimi or MiniMax key: `pi`.
- A server, a log tail or a build watcher: `terminal`.
- A test of the plumbing with no tokens: `stub`.

Whatever the choice, the daemon and every seat share the unit's `MemoryMax=2G`, two seats at a time.

## What is not proved

A live Claude Code seat has not run: not its login, its first turn, the bypass dialog, the
`claude-sonnet-5-5` model with the pinned Claude Code 2.1.223, or its memory. The rows for Codex, Pi,
`stub` and the community harnesses come from the documents only. The guide lists each gap.

## See also

- [Factory](Factory): the stages of the software factory and its status.
- [`docs/OPENRIG.md`](https://github.com/piabrota/nix-os/blob/main/docs/OPENRIG.md): the unit, the
  specs and the rigs, including `wave-forecaster-dev`.
