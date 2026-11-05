# Runtimes

A runtime is what a seat runs. The member's `runtime` field in a rig spec names it. The full
comparison (features, pros, cons, auth, permission mapping, state) is in
[`docs/RUNTIMES.md`](../../../../docs/RUNTIMES.md). This file is what you need to operate the rigs.

|Runtime|What it is|On this box|
|---|---|---|
|`omp`|Oh My Pi, the coding agent that Hermes already uses (`hermes-omp`), run by OpenRig's RPC runner.|**Works.** The runtime of `piabrota-dev` and `wave-forecaster-dev-integrate`.|
|`claude-code`|Claude Code (`claude`, unfree: `unfree.nix`).|**Only the port rig `wave-forecaster-dev`**, and only when `piabrota.openrig.waveForecaster.enable` is on (off today). Not run: no live Claude seat.|
|`terminal`|A shell for a server, a log tail or a build watcher. No agent, no profile (`agent_ref: "builtin:terminal"`, `profile: none`).|**Works.** Tested in a scratch daemon. `rig send` types the exact text, with no From and To lines.|
|`stub`|A scripted test harness. It calls no model.|Present; from the docs, not run.|
|`codex`|OpenAI Codex.|**Not here.** Not installed. It would need an OpenAI login.|
|`pi`|The Pi coding agent.|No `pi` program is set up for the unit, and the unit has none of the keys that Pi takes (OpenRouter, Z.ai, Kimi, MiniMax). No spec uses it.|
|Community harness|An outside tool, installed as a preset file `$OPENRIG_HOME/community-harnesses/<name>.yaml`. The preset's name is the runtime. OpenRig does not test it.|None installed. Do not add one.|

`rig grow` and `rig create` default to `claude-code`. On this box, give `--runtime omp`, and ask
the owner first (see `commands.md`).

**A changed spec does not reach a rig.** A rig keeps the spec that made it. After a change to a
spec in `/etc/openrig/specs`, run `rig archive <rig>`, then import the spec again. `rig import <spec>
--materialize-only` makes the rig and its seats and starts nothing. Then `rig up <rig>` starts it.
Ask the owner before `rig archive`.

## How a `claude-code` seat works

- **Guidance.** The spec's guidance lands in the `CLAUDE.md` of the seat's working folder, not in
  `AGENTS.md`. The seat's `claude` is `seatClaude` in `openrig.nix`.
- **Rules.** `/etc/claude-code/managed-settings.json` has the deny rules. They hold in bypass mode,
  and they are no sandbox. If a seat cannot run a command, tell the owner and name the command.
- **Bypass warning.** Claude Code asks once to accept its bypass-permissions warning. OpenRig then
  reports the seat as `attention_required`. This is a consent prompt: show the pane to the owner
  and let the owner answer it (`rig seat continue` or the web UI). Never answer it yourself. Do
  not add `--non-interruptive`: the deny list blocks it.
- **Login errors.** If `rig capture` shows a login or authentication error, tell the owner. Do not
  look for another token. This skill never reads the token file.

## How an `omp` seat works

- **Home and state.** The seat runs `omp` with its own `HOME`, a folder under the instance state
  (`state/omp/<seat>/agent`, with `sessions/`). OpenRig copies no `omp` login into it.
- **What the unit gives the seat.** The `omp` wrapper, the token, the approval mode and the
  environment of the runner are in
  [`../../hermes-omp/references/openrig-seats.md`](../../hermes-omp/references/openrig-seats.md).
  Read it, do not copy it. This skill never reads the token file: the deny list blocks its path.
  If a seat shows a login or authentication error in `rig capture`, tell the owner. Do not look
  for another token. If a seat cannot run a tool, tell the owner and name the tool.
- **Dialogs.** An extension request (`select`, `confirm`, `input`, `editor`) is shown in the pane
  and then cancelled. Send the seat an instruction that needs no dialog.
- **Model errors.** A failed turn with status 408, 429, 500, 502, 503, 504 or 529 returns to idle at
  the end of the turn. Then send the task again. A 429 may mean the subscription limit: tell the
  owner.
- **Restore.** `omp` writes its session file after its first completed turn. A seat that never
  finished a turn cannot resume. Start it with `rig seat launch <seat> --fresh --reason "<why>"`.
  After a full restore, an `omp` seat left in `attention_required` or `failed` is not cleared by
  `rig seat clear-attention`. Relaunch it fresh.
- **Guidance.** The spec's guidance lands in the `AGENTS.md` of the seat's working folder. A skill
  needs a declared resource.

## The Hermes community harness: not used here

OpenRig ships an example preset for Hermes Agent (`hermes.yaml` and the launcher
`openrig-hermes-launch`, in its `community-harness-examples/hermes/`). A Hermes seat would give
each seat its own Hermes home under the instance state and, through that home, its own Hermes
gateway. This box does not use it:

1. The unit's budget is small (below). One Hermes process per seat is a second Python runtime in
   it. The owner gave the one Hermes of this box its own 8 GiB unit. A Hermes seat was not
   measured here.
2. The example says a seat's gateway may keep running after its pane closes, and whether it exits
   when idle is unchecked. A stray process would stay in the unit's budget.
3. The preset takes no guidance, no skills and no startup files, so the specs of `piabrota-dev`
   would not reach it. It has no resume, and it reads prompts from the screen only.
4. It needs its own provider key and config. The box gives seats one token: the Claude
   subscription, through the `omp` wrapper.
5. Hermes already runs here. Its coding work goes through `omp`, and a seat is an `omp` run that
   stays alive.

Do not install a preset, and do not name a community harness in a spec.

## The memory rule

Every seat lives in the cgroup of the `openrig` unit. The limits come from `openrig.nix`:

|Item|Value|
|---|---|
|`MemoryMax`|2G (2048 MiB), for the daemon, tmux and every seat|
|`MemoryHigh`|1536M. Above it the kernel slows the unit down. Treat it as the working limit.|

The memory of the daemon and of one seat is in
[the reference](../../hermes-omp/references/openrig-seats.md). The plan is **two seats at the same
time**, the builder and the reviewer. That leaves room for growth and for the page cache of a git
clone, which counts against the unit. Start a third only when the owner says so.

Before you start a rig or add a seat:

1. Run `kvm4-health` and read the `openrig` line: the memory now, the peak, and the limit. Do not
   start if it shows `WARN` or `CRIT`, or if a peak is already near 1536 MiB.
2. Count the seats that run: `rig ps --nodes -A`. Two at most.
3. Never run a heavy one-shot `omp` run of `hermes-omp` at the same time as a large build in a
   seat. Those runs use the `hermes-agent` budget, but the machine is shared. The sum of all
   `MemoryMax` values is in `docs/OPENRIG.md`, "Limits".

If the kernel kills a process for lack of memory, `OOMPolicy=continue` keeps the unit alive and the
`choom` setting aims at a seat. See `troubleshooting.md`.

Source: `docs/reference/rig-spec.md` (Pi, Oh My Pi and terminal sections),
`community-harness-presets.md`, `community-harness-examples/hermes/` of OpenRig `v0.7.7`;
`openrig.nix` and `docs/OPENRIG.md` of piabrota/nix-os for the unit and its numbers. The terminal
runtime was run in a scratch daemon. Everything about a real `omp` seat is from the docs, not run.
