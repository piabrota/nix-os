# omp under OpenRig: what a seat needs on this box

Facts read in OpenRig's source at tag `v0.7.7` (commit `f3d8bac`,
[mvschwarz/openrig](https://github.com/mvschwarz/openrig), Apache-2.0). This page says them in
piabrota's words; it copies no OpenRig text. Paths are under `packages/daemon/src/`.

## How OpenRig starts omp

- A seat with `runtime: omp` is a tmux session. The daemon types
  `node <daemon dist>/pi-runner.js --runtime omp --approval-mode <mode> ...` into the pane, and the
  runner starts `omp --mode rpc` from `PATH` (`adapters/pi-runner-protocol.ts`,
  `buildPiRunnerCommand`). So the pane needs `node`, `omp` and `tmux` on its `PATH`. The unit's
  `path` does not reach the pane: see the last row of the table below.
- The runner gives omp a **deny-by-default environment** (`buildPiChildEnv`): `PATH`, `HOME`,
  `USER`, `LOGNAME`, `SSH_AUTH_SOCK`, `TERM`, `LANG`, `LC_ALL`, `SHELL`, `TMPDIR`, the
  `OPENRIG_*` identity variables, and one provider key. For Anthropic that key is
  `ANTHROPIC_API_KEY`, and only when the seat's model is `anthropic/<id>`. `CLAUDE_CODE_OAUTH_TOKEN`,
  `ANTHROPIC_OAUTH_TOKEN` and `PI_CONFIG_FILES` do not reach omp.
- `HOME` of omp is the seat's own directory under `$OPENRIG_HOME/state/omp/`, so omp never reads
  Hermes's `~/.omp`.
- `--approval-mode` is `yolo` only when `OPENRIG_YOLO=1` is in the daemon's environment, or the
  seat has a `full_bypass` policy; otherwise `always-ask`. In RPC mode nobody can answer a prompt:
  the runner cancels it and the seat stops with "Operator action required"
  (`adapters/pi-runner.ts`). With `always-ask`, an omp seat stops at its first tool call.

## What the openrig unit needs, and why

| Need | Setting | Why |
|---|---|---|
| omp with piabrota's rules and no time ceiling | `pkgs.callPackage ./omp/wrapper.nix { ceiling = null; appendSystemPrompt = ./hermes/omp-seat-append-system.md; }` in `seatTools` | the wrapper loads `hermes/omp.yml` itself, so the overlay survives the runner's environment filter; the default 35 min ceiling would kill a seat |
| the subscription token for the seats | the token as `ANTHROPIC_API_KEY` in the unit's root-only `EnvironmentFile` | the only Anthropic variable the runner passes; the wrapper moves an `sk-ant-oat` value to `ANTHROPIC_OAUTH_TOKEN`, so omp signs in as a subscription, not as an API key |
| seats that can use their tools | `OPENRIG_YOLO=1` | see `--approval-mode` above; omp's own deny rules in `hermes/omp.yml` still refuse push, `gh`, installs, secrets and `rig` control |
| a daemon with no kernel rig | `OPENRIG_NO_KERNEL=1` (or `rig daemon start --no-kernel`) | the kernel rig boots only on Claude Code or Codex (`domain/kernel-boot.ts`); this box has neither, so without it the daemon reports `auth_blocked` |
| a model the runner forwards a key for | `model: anthropic/claude-sonnet-5-5` in each omp AgentSpec | no `provider/` prefix, no key in the seat |
| a tmux socket it can create | `RuntimeDirectory=openrig` and `TMUX_TMPDIR=/run/openrig`, or `PrivateTmp=true` | under `ProtectSystem=strict` tmux needs a writable socket directory (`adapters/tmux.ts`, `session_unconfirmed`) |
| `lsof` | `pkgs.lsof` in the one `seatTools` list (unit `path` and per-user profile) | the database-conflict check calls it (`daemon-db-path.ts`); without it the daemon warns and goes on |
| `git` | `pkgs.git` in `seatTools` | omp's work in a seat is git work |
| `node`, `omp`, `rig` and `tmux` in the pane | `users.users.openrig.packages = seatTools`, and `USER`, `LOGNAME`, `HOME` in the `env:` of the rig spec | OpenRig starts the pane with a clean environment (`env -i`, `adapters/tmux.ts`), so the unit's `path` does not reach it. The pane's login bash runs `/etc/set-environment`, which builds `PATH` from the per-user profile of `$USER` |

The daemon runs in the foreground under systemd (`node .../daemon/dist/index.js`, as Hermes
tested on 2026-11-04). `rig daemon start` forks a detached daemon: under systemd that is the same
mistake as Hermes's own detached gateway (`hermes.nix`, `--external-supervisor`). Do not use it in
a unit. Hermes's deny list refuses `rig daemon start|stop|restart` and `rig start`.

`rig doctor` shows `[FAIL] ui_dist` when the package is built without the web UI. That is
expected here: the UI is not built and not served. Report it as known, not as a failure.

At start the daemon tries to fetch `openrig-core` and falls back to its built-in copy on a 404.
That is not an error.

## Memory

Each omp seat takes about 340 MiB (Hermes, 2026-11-04), on top of the daemon (about 220 MiB idle).
Seats live in the openrig unit's cgroup, not in `hermes-agent`. Count them against that unit's
`MemoryMax` before `rig up`, and say the count to the owner.

## A deploy

A deploy that changes the openrig unit restarts it and ends every seat. Bring a rig back with
`rig up <name> --existing`. Before a merge to nix-os, tell the owner which rigs are up.

## Not checked on the box

- An omp seat signed in through `ANTHROPIC_API_KEY` with a subscription token.
- `OPENRIG_YOLO=1` together with the deny rules of `hermes/omp.yml` in RPC mode.
- `TMUX_TMPDIR` under the unit's sandbox.
