# Runtimes

A runtime is what a seat runs. The member's `runtime` field in a rig spec names it.

|Runtime|What it is|On this box|
|---|---|---|
|`omp`|Oh My Pi, the coding agent that Hermes already uses (`hermes-omp`), run by OpenRig's RPC runner.|**Works.** The only agent runtime.|
|`terminal`|A shell for a server, a log tail or a build watcher. No agent, no profile (`agent_ref: "builtin:terminal"`, `profile: none`).|**Works.** Tested in a scratch daemon. `rig send` types the exact text, with no From and To lines.|
|`stub`|A scripted test harness. It calls no model.|Present; from the docs, not run.|
|`claude-code`|Claude Code.|**Not here.** The `claude` program is unfree and not installed.|
|`codex`|OpenAI Codex.|**Not here.** Not installed.|
|`pi`|The Pi coding agent.|No `pi` program is set up for the unit. No spec uses it.|
|Community harness|An outside tool, installed as a preset file `$OPENRIG_HOME/community-harnesses/<name>.yaml`. The preset's name is the runtime. OpenRig does not test it.|None installed. Do not add one.|

`rig grow` and `rig create` default to `claude-code`. On this box, give `--runtime omp`, and ask
the owner first (see `commands.md`).

## How an `omp` seat works

- **Home and state.** The seat runs `omp` with its own `HOME`, a folder under the instance state
  (`state/omp/<seat>/agent`, with `sessions/`). OpenRig copies no `omp` login into it.
- **The program.** The unit puts a shim called `omp` first on the daemon's path. The shim loads the
  rules of `hermes/omp.yml` (read-only; bash deny rules; no `git push`, `gh`, `sudo`) and runs
  `omp` under `choom`, so the kernel picks a seat before the daemon. It has no 35-minute limit.
- **The token.** The seat uses the owner's Claude subscription, like you. The `openrig` unit gets
  the token in a root-only step at each start and keeps it in a file that only the `openrig` user
  reads. The shim reads that file and sets the variable `omp` reads. The daemon's environment
  never holds the token, and a seat does not inherit the daemon's environment. This skill never
  reads the file: the deny list blocks its path. If a seat shows a login or authentication error in
  `rig capture`, tell the owner. Do not look for another token.
- **Credentials of other providers.** A seat gets a provider key only if its model name has the
  form `provider/id` and the daemon is set to pass that key. Nothing is set. Do not try.
- **Approvals.** OpenRig starts `omp` with `--approval-mode always-ask` unless the policy bypasses
  prompts. A headless runner cancels `omp`'s approval requests, and the seat then needs attention
  until the next agent run starts. If a seat cannot run a tool, this is the first cause to check.
  Whether it overrides `tools.approvalMode` in `hermes/omp.yml` is not tested.
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
   subscription, through the `omp` shim.
5. Hermes already runs here. Its coding work goes through `omp`, and a seat is an `omp` run that
   stays alive.

Do not install a preset, and do not name a community harness in a spec.

## The memory rule

Every seat lives in the cgroup of the `openrig` unit. These numbers come from `openrig.nix`:

|Item|Value|
|---|---|
|`MemoryMax`|2G (2048 MiB), for the daemon, tmux and every seat|
|`MemoryHigh`|1536M. Above it the kernel slows the unit down. Treat it as the working limit.|
|Daemon and tmux|About 200 MiB (the idle daemon peaked at 186.7 MiB in a test).|
|One `omp` seat at work|About 340 MiB.|

On paper, (1536 − 200) / 340 gives three seats. The plan is **two at the same time**, the builder
and the reviewer: about 880 MiB, which leaves about 650 MiB for growth and for the page cache of a
git clone, which counts against the unit. A third seat leaves about 300 MiB. Start a third only
when the owner says so.

Before you start a rig or add a seat:

1. Run `kvm4-health` and read the `openrig` line: the memory now, the peak, and the limit. Do not
   start if it shows `WARN` or `CRIT`, or if a peak is already near 1536 MiB.
2. Count the seats that run: `rig ps --nodes -A`. Two at most.
3. Never run a heavy one-shot `omp` run of `hermes-omp` at the same time as a large build in a
   seat. Those runs use the `hermes-agent` budget, but the box has 15.6 GiB in all, and the sum of
   all `MemoryMax` values is 12.25 GiB.

If the kernel kills a process for lack of memory, `OOMPolicy=continue` keeps the unit alive and the
`choom` setting aims at a seat. See `troubleshooting.md`.

Source: `docs/reference/rig-spec.md` (Pi, Oh My Pi and terminal sections),
`community-harness-presets.md`, `community-harness-examples/hermes/` of OpenRig `v0.7.7`;
`openrig.nix` and `docs/OPENRIG.md` of piabrota/nix-os for the unit and its numbers. The terminal
runtime was run in a scratch daemon. Everything about a real `omp` seat is from the docs, not run.
