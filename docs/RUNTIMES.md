# OpenRig runtimes: what a seat can run

[Português](RUNTIMES.ptBR.md)

A runtime is the program that a seat runs. The member's `runtime:` field in a rig spec names it.
OpenRig 0.7.7 has six built in: `claude-code`, `codex`, `pi`, `omp`, `terminal` and `stub`. It also
loads community harnesses, which a spec names as `runtime: <name>`. This page compares them and says
which ones this box runs. The rest of the OpenRig setup is in [`OPENRIG.md`](OPENRIG.md).

**How to read it.** Every claim about a runtime comes from the OpenRig documents of tag
[v0.7.7](https://github.com/mvschwarz/openrig/tree/v0.7.7), named in the text, or from this
repository. "Docs only" means that I read it and did not run it here. `⚠` marks a fact that I could
not check. Nothing here says that a seat has done a task: no seat has.

Credits. [OpenRig](https://github.com/mvschwarz/openrig) is by mvschwarz (Apache-2.0).
[Pi](https://pi.dev) ([badlogic/pi-mono](https://github.com/badlogic/pi-mono)) is by Mario Zechner.
[oh-my-pi](https://github.com/can1357/oh-my-pi) (`omp`, by can1357) is a fork of Pi. Claude Code is
Anthropic's, and Codex is OpenAI's.

## At a glance

|Runtime|What it is|Model route|Guidance file|On this box|
|---|---|---|---|---|
|`claude-code`|Anthropic's Claude Code in a tmux pane|Claude login, `CLAUDE_CODE_OAUTH_TOKEN` or `ANTHROPIC_API_KEY`|`CLAUDE.md`|The port rig, after this PR and with `waveForecaster.enable` on. Needs `unfree.nix`|
|`codex`|OpenAI's Codex CLI in a tmux pane|An OpenAI login (`codex login`) or key|`AGENTS.md`|Not installed|
|`pi`|The Pi harness, through OpenRig's RPC runner|One key of OpenRouter, Z.ai, Kimi or MiniMax, by model prefix|`AGENTS.md`|Not installed. No spec uses it|
|`omp`|oh-my-pi, through the same kind of runner|A provider key, by model `provider/id`|`AGENTS.md`|Works. `piabrota-dev` and the integrate rig|
|`terminal`|A plain shell, no agent|None|None|Works|
|`stub`|A scripted test harness|None|Not stated in the docs I read|Available. No spec uses it|
|Community harness|An outside tool, one preset file|Whatever the tool does|None. Not placed|None installed|

How the rig's permission policy reaches each one (`permission_policy:` of the rig or the member).
Sources: [`rig-spec.md`](https://github.com/mvschwarz/openrig/blob/v0.7.7/docs/reference/rig-spec.md),
[`adapters-and-runtimes.md`](https://github.com/mvschwarz/openrig/blob/v0.7.7/docs/as-built/architecture/adapters-and-runtimes.md).
Docs only.

|Runtime|Floor (no policy, or `builtin:locked`, `standard`, `open`)|`builtin:auto`|`builtin:yolo`|
|---|---|---|---|
|`claude-code`|`--permission-mode acceptEdits`, and for a seat with no policy a short allow and ask list in `--settings`|`--permission-mode auto`|`--dangerously-skip-permissions`|
|`codex`|`-s workspace-write`, or `-p <profile>`|The floor|`-s danger-full-access -a never`|
|`pi`|No permission policy. Resource trust: `--no-approve`|The floor|`--approve`|
|`omp`|`--approval-mode always-ask`|⚠ The floor (not stated for omp)|`--approval-mode yolo`|
|`terminal`|None|None|None|
|`stub`|Carried to its runner as `--posture`, nothing enforced|Same|Same|
|Community|None: approvals stay in the harness's own pane|Same|Same|

A rig with no policy gets the floor, and a policy wins over `OPENRIG_YOLO=1` in the unit. So this
box's rigs set `permission_policy: builtin:yolo` (the owner's decision, PR 124).

## `claude-code`

**What.** Claude Code, started in the seat's pane as
`claude <posture> --session-id <id> --name <name> [--model <m>] [--effort <e>]`. A resume uses
`--resume <token>`. A fork needs Claude Code 2.0.73 or later.

**Features.**
- Guidance goes into a managed block of `CLAUDE.md` in the seat's folder (or `CLAUDE.local.md`, with
  the rig's `managed_blocks`). Skills, sub-agents, plugins and MCP entries go to `.claude/` and
  `.mcp.json`.
- Activity comes from Claude's own hooks and its session file, not from the screen alone.
- The member can set `effort`, `advisor` (a second model) and `claude_token` (a token file for the
  seat).
- Before the first turn OpenRig marks the folder as trusted and onboarding as done in Claude's state
  file. It writes no permission rules.
- A seat can be resumed, forked and handed over, with a check that the conversation really resumed.

**Pros.** The best supported runtime of OpenRig. It uses the Claude subscription. Its permission
modes are native, and managed settings can add rules that nothing in a repository overrides.

**Cons.**
- Claude Code is unfree. This box allows it by name (`unfree.nix`).
- It is big: the closure grows by about 280 MiB, and the vendor binary is not in `cache.nixos.org`.
- Its first run in bypass mode shows a warning dialog that a person must accept once.
- Claude Code ranks `ANTHROPIC_API_KEY` above `CLAUDE_CODE_OAUTH_TOKEN` (see "Credentials").
- Its memory use is not measured here.

**Spec.**

```yaml
- id: porter
  agent_ref: "local:../../agents/wf-porter"
  profile: default
  runtime: claude-code
  model: claude-sonnet-5-5   # a full Claude model id, as in rig-spec.md
  cwd: /var/lib/openrig/work/wave-forecaster-dev/porter
```

**Credentials.** Claude keeps its login in its config dir (`~/.claude`, or the seat's
`CLAUDE_CONFIG_DIR`). A subscription token goes in `CLAUDE_CODE_OAUTH_TOKEN`. OpenRig lists the
names that Claude Code ranks above that token: a cloud provider switch, `ANTHROPIC_AUTH_TOKEN` and
`ANTHROPIC_API_KEY`
([`claude-credential-precedence.ts`](https://github.com/mvschwarz/openrig/blob/v0.7.7/packages/daemon/src/domain/claude-credential-precedence.ts)).
A name reaches a seat only if the daemon holds it and the operator names it in
`recovery.provider_auth_env_allowlist` ([`startup.ts`](https://github.com/mvschwarz/openrig/blob/v0.7.7/packages/daemon/src/startup.ts)).

**State.** `~/.claude` and `~/.claude.json` (here `HOME` is `/var/lib/openrig`), and
`<cwd>/.claude/settings.local.json`, where OpenRig puts its hooks and its status-line collector.

**On this box.** The port rig `wave-forecaster-dev` (porter and auditor) runs it after this PR, and
only when `piabrota.openrig.waveForecaster.enable` is on, which it is not. Details are in "Claude
Code on this box" below. **Not run:** no live Claude seat.

## `codex`

**What.** OpenAI's Codex CLI in the seat's pane: `codex <posture> -C <cwd>`, with `-m <model>` and
`-c model_reasoning_effort=...` when the spec sets them. Docs only.

**Features.**
- Guidance goes into `AGENTS.md`, skills into `.agents/skills/`, plugins into `.codex/plugins/`.
- Resume and fork are native. A launch never lets Codex update itself.
- On the floor, OpenRig asks a one-shot `codex app-server` whether network access in the sandbox is
  allowed, and turns it on when it is.
- Activity comes from Codex hooks. That rung is on trial in 0.7.7: it needs 50 agreeing readings
  before it is trusted ([`agent-state-taxonomy.md`](https://github.com/mvschwarz/openrig/blob/v0.7.7/docs/reference/agent-state-taxonomy.md)).

**Pros.** A native sandbox (`workspace-write`) on the floor. A second model family beside Claude.

**Cons.** It needs an OpenAI login or key and a `codex` binary: neither is on this box. Its
permission posture has no middle step: `builtin:auto` gives the floor.

**Spec.**

```yaml
- id: reviewer
  agent_ref: "local:agents/reviewer"
  profile: default
  runtime: codex
  model: gpt-5.5   # the id that rig-spec.md uses in an example
```

**Credentials.** `codex login`, or `OPENAI_API_KEY` (a name that the allowlist accepts). The login
lives in `CODEX_HOME` (default `~/.codex`).

**State.** `~/.codex`, or the seat's own `CODEX_HOME`.

**On this box.** Not installed. No Codex route for the Claude subscription exists: the seat would
need its own OpenAI login, which the owner has not given.

## `pi`

**What.** The Pi coding agent, "a minimal, extensible agent harness" (pi.dev), started as
`pi --mode rpc` inside OpenRig's runner. The runner reads Pi's event stream and reports each turn
boundary to the daemon. Docs only.

**Features.**
- Activity comes from the runner's reports: working, idle, needs input. A quiet pane never reads as
  idle by itself.
- The seat's effort goes to Pi as `--thinking <level>`.
- Custom models: `models.json` in the seat's agent folder.
- Resume and fork work. The resume token is Pi's session file.

**Pros.** Small. Many providers. Precise activity from the runner.

**Cons.**
- No sub-agents and no plan mode by default (pi.dev).
- No permission policy: only resource trust (`--approve` or `--no-approve`).
- An extension dialog (`select`, `confirm`, `input`, `editor`) is cancelled, because the pane cannot
  answer, and the seat then needs attention.
- It takes at most one provider key: `OPENROUTER_API_KEY`, `ZAI_API_KEY`, `KIMI_API_KEY` or
  `MINIMAX_API_KEY`, chosen by the model prefix. There is no route for a Claude subscription token.

**Spec.**

```yaml
- id: helper
  agent_ref: "local:agents/helper"
  profile: default
  runtime: pi
  model: openrouter/<model-id>   # or zai/<id>, kimi-coding/<id>, minimax/<id>
```

**State.** `$OPENRIG_HOME/state/pi/<session>/agent`, with `sessions/` beside it. OpenRig copies
nothing from `~/.pi/agent`.

**On this box.** Not installed, and the unit has none of the four keys. No spec uses it.

## `omp`

**What.** [oh-my-pi](https://github.com/can1357/oh-my-pi), a fork of Pi. OpenRig runs it through a
runner of the same kind, as a separate runtime (it does not use Pi's `--name` or `--approve`). Its
README says "60+ providers, 31 built-in tools, 14 LSP operations, 28 DAP operations"; I did not
measure that.

**Features.**
- The same runner reports as for Pi.
- A seat has its own `HOME`: `$OPENRIG_HOME/state/omp/<seat>/agent`, with `sessions/`.
- OpenRig does not copy omp credentials. Provision the seat, or name the provider's key variable in
  `recovery.provider_auth_env_allowlist`.
- A model error with status 408, 429, 500, 502, 503, 504 or 529 returns to idle at the end of the
  turn, so an ordinary retry works.

**Pros.** It works with the subscription token here, through the wrapper `omp/wrapper.nix`. It has
rules of its own (`hermes/omp.yml`) that a cloned repository cannot loosen. A run takes about
340 MiB (a figure in `hermes/omp.yml`).

**Cons.**
- A seat gets a key only if its model is written `provider/id`. A short name such as `opus` passes
  none.
- A new seat with no finished turn has no session file, so a restore leaves it waiting: start it with
  `rig seat launch <seat> --fresh --reason "<why>"`.
- After a full restore, `rig seat clear-attention` cannot clear an omp seat
  ([openrig#41](https://github.com/mvschwarz/openrig/issues/41)).
- An omp seat of this box projects no plugin and no runtime resource (`openrig/specs/agents/shared/agent.yaml`).

**Spec.**

```yaml
- id: builder
  agent_ref: "local:../../agents/builder"
  profile: default
  runtime: omp
  model: anthropic/claude-sonnet-5-5   # `anthropic/<id>`: the form for which the runner passes the key
  cwd: /var/lib/openrig/work
```

**Credentials here.** The unit gives every seat `ANTHROPIC_API_KEY`, which holds the subscription
token. The wrapper moves it to `ANTHROPIC_OAUTH_TOKEN`
([`OPENRIG.md`](OPENRIG.md), "The token of the seats").

**On this box.** Works. `piabrota-dev` and `wave-forecaster-dev-integrate` use it. The port rig used
it until this PR.

## `terminal`

**What.** A shell for a server, a log tail or a build watcher. It is not an agent: every adapter
step is a no-op, and the seat is ready at once.

**Features.** `rig send` types the exact text, with no From and To lines. A restore relaunches the
seat fresh and runs its startup actions again.

**Pros.** No model, no token, no memory beyond the process.

**Cons.** No guidance, no skills, no identity. A queue wake does not reach it (`failed:terminal-seat`).

**Spec.** The three fields go together, or the spec is invalid.

```yaml
- id: logs
  agent_ref: "builtin:terminal"
  profile: none
  runtime: terminal
```

**On this box.** Works. It was tried in a scratch daemon.

## `stub`

**What.** A deterministic test harness. A Node runner in the pane follows `<cwd>/.openrig/stub/script.json`
and calls no model. It goes through the normal launch, skill, startup and readiness path.

**Pros.** It tests the rig plumbing with no tokens.

**Cons.** It has no input channel, so no test can prove that a message was consumed. It cannot
fork. It ignores native permission behaviour
([`test-layers.md`](https://github.com/mvschwarz/openrig/blob/v0.7.7/docs/as-built/test-layers.md),
"What a stub can and cannot prove").

**Spec.**

```yaml
- id: probe
  agent_ref: "local:agents/probe"
  profile: default
  runtime: stub
```

**State.** `<cwd>/.openrig/stub/`.

**On this box.** Available in 0.7.7. No spec uses it, and I did not run it.

## Community harnesses

**What.** A tool that an outside maintainer owns, installed as `$OPENRIG_HOME/community-harnesses/<name>.yaml`.
The preset's name is the runtime. OpenRig types the preset's `command` into the pane and does not
test the tool. Examples in 0.7.7: Hermes, OpenClaw, Cursor and Pi's own TUI
([`community-harness-presets.md`](https://github.com/mvschwarz/openrig/blob/v0.7.7/docs/reference/community-harness-presets.md)).

**Features.** Launch, delivery (`rig send` pastes the text and presses Enter), transport and, when
the preset declares it, identity and resume. Activity comes from the screen only, or from a runner
preset's reports.

**Cons.** No guidance, skills or startup files are placed. The model comes from the tool's own
config, unless the preset sets `passes_model`. No approvals, no cancel. A screen that looks idle
reads `unknown`.

**Spec.** A member names the preset as its runtime. The other member fields are as for any agent
seat; I found no full member example in the preset document, so I give only the line that changes.

```yaml
  runtime: example-harness   # the preset's name; built-in names are reserved
```

**On this box.** None installed. `hermes-rig` says not to add one (a Hermes seat is a second Python
runtime in the unit's 2 GiB).

## Which one to pick

|You want|Use|
|---|---|
|The Claude subscription, and the most that OpenRig can see and control|`claude-code`. It is unfree and big, so here it is opt-in|
|The Claude subscription with no unfree package, rules of your own, and a runner|`omp` (what this box does for `piabrota-dev` and the integrate rig)|
|OpenAI models and Codex's native sandbox|`codex`, after an OpenAI login and a binary exist|
|A small harness and a key of OpenRouter, Z.ai, Kimi or MiniMax|`pi`|
|A server, a log tail or a build watcher|`terminal`|
|A check of the rig plumbing with no tokens|`stub`|
|A tool that OpenRig does not ship|A community harness, knowing that it is read from the screen and gets no guidance|

On this box the choice is also a memory choice: the daemon and every seat share the unit's
`MemoryMax=2G`, two seats at a time.

## Claude Code on this box

This PR gives the port rig `runtime: claude-code` (porter and auditor, `model: claude-sonnet-5-5`).
`piabrota-dev` and `wave-forecaster-dev-integrate` stay on omp. All of it is behind
`piabrota.openrig.waveForecaster.enable`, which stays off.

**What the option adds for Claude.**
- `unfree.nix` allows `claude-code` by name and nothing else. `allowUnfree` stays off. A name is
  added there only with the owner's yes.
- A `claude` command in the seat profile and in the unit's path (`openrig.nix`, `seatClaude`): a
  wrapper of `pkgs.claude-code` with `choom`, like omp's.
- `/etc/claude-code/managed-settings.json`, with `allowManagedPermissionRulesOnly` and deny rules.

**The credential problem, and the fix.** The unit gives every seat `ANTHROPIC_API_KEY` (the
subscription token) for the omp seats. Claude Code ranks that name above `CLAUDE_CODE_OAUTH_TOKEN`
and would send the token as an API key. OpenRig's own answer, `claude_token` in the spec, reads the
token with `/bin/cat` (`claude-seat-token.ts`), and NixOS has no `/bin/cat`. So `seatClaude` moves a
token that starts with `sk-ant-oat` to `CLAUDE_CODE_OAUTH_TOKEN`, and unsets `ANTHROPIC_API_KEY`,
`ANTHROPIC_AUTH_TOKEN` and the cloud switches, for Claude's process only. Any other value in
`ANTHROPIC_API_KEY` is dropped, so Claude never bills an API key by accident. omp seats are
unchanged. I ran the wrapper's logic on stand-in values and `claude --version` through it.

**The guard.** The deny rules are the `bash.patterns` of `hermes/omp.yml`, one for one, as
`Bash(...)` rules, and its `restrictedFolders` as `Read(...)` rules. They add `git -C * push`,
`claude *`, `rig seat set-permissions*`, `rig policy apply*` and the seat's own token. Claude Code
checks deny rules before the permission mode, so they hold under `--dangerously-skip-permissions`.
They are not a sandbox: a program that the seat starts can read what a rule names. The hard layer is
the unit's sandbox. The key `allowManagedPermissionRulesOnly` is in this version's settings schema
(read in the binary), so a repository's own rules cannot loosen the managed ones.

**Version.** The flake pins nixos-26.05, whose `claude-code` is 2.1.223. The binary has the strings
`claude-sonnet-5` and `claude-opus-5`, and not `claude-sonnet-5-5`. ⚠ I did not test that a seat
accepts that model. The other flags that OpenRig uses (`--session-id`, `--name`, `--effort`,
`--permission-mode`, `--dangerously-skip-permissions`) are in its `--help`. If the model fails, set
`model: sonnet` or bump nixpkgs.

**Cost.** The closure grows by about 280 MiB against the running system (the binary is 290 MB; the
rest is small). The binary comes from `downloads.claude.ai` as a fixed-output fetch, so the CI runner
builds it (nothing is in `cache.nixos.org`), and the deploy copies it to the box.

**What a person must do.**
1. Set `piabrota.openrig.waveForecaster.enable = true` in `hosts/piabrota2/default.nix`, merge, and
   let the deploy run.
2. A rig keeps the spec that made it. The two wave rigs were made from the old spec, so run
   `rig archive wave-forecaster-dev`, then
   `rig import /etc/openrig/specs/rigs/wave-forecaster-dev/rig.yaml --materialize-only`. That makes
   the rig and its seats and starts nothing. Then `rig up`.
3. Claude Code asks once to accept its bypass-permissions warning. OpenRig reports the seat as
   `attention_required` until `rig seat continue`, or the web UI, answers it. A spec line
   `non_interruptive: true` would accept it by flag. This PR does not add that line: Hermes's deny
   list blocks the `--non-interruptive` flag, and the choice is the owner's.

## What is not proved

- A live Claude seat: its start, its first turn, the login with the wrapper's token, the bypass
  dialog, the model id with Claude Code 2.1.223, and its memory use.
- That OpenRig finds the process of a seat that starts through the wrapper (`choom` then the Nix
  wrapper of `claude`). OpenRig knows the Nix layout of `claude-code`
  ([`native-process-lineage.ts`](https://github.com/mvschwarz/openrig/blob/v0.7.7/packages/daemon/src/domain/native-process-lineage.ts)),
  and this chain was not run under a rig.
- Read rules with an absolute path: the documented form is `//path`, and the file also carries the
  `/path` form.
- The Codex, Pi, `stub` and community rows: docs only.

## Sources

- OpenRig v0.7.7: `docs/reference/rig-spec.md`, `docs/reference/community-harness-presets.md`,
  `docs/reference/harness-runner-contract.md`, `docs/reference/non-interruptive-mode.md`,
  `docs/reference/agent-state-taxonomy.md`, `docs/as-built/architecture/adapters-and-runtimes.md`,
  `docs/as-built/test-layers.md`, `packages/daemon/src/domain/claude-seat-token.ts`,
  `claude-credential-precedence.ts`, `claude-managed-launch.ts` and `startup.ts`.
- This repository: `openrig.nix`, `unfree.nix`, `omp/wrapper.nix`, `hermes/omp.yml`,
  `openrig/specs/`, [`OPENRIG.md`](OPENRIG.md),
  [`hermes/skills/hermes-rig/references/runtimes.md`](../hermes/skills/hermes-rig/references/runtimes.md).
