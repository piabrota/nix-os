# OpenRig on piabrota2

English only. The files are `openrig.nix`, `openrig/package.nix` and `openrig/specs/`.

What a seat needs from the unit (how OpenRig starts `omp`, the environment of its runner, the
approval mode, the tmux socket, `lsof`, `git`, the kernel rig, the memory of one seat) is in
[`hermes/skills/hermes-omp/references/openrig-seats.md`](../hermes/skills/hermes-omp/references/openrig-seats.md).
This page does not repeat it. It says what is only true of this module and this repository.

## What it is

[OpenRig](https://github.com/mvschwarz/openrig) (`mvschwarz/openrig`, version 0.7.7, Apache-2.0) is a
control plane for a team of AI coding agents. A daemon keeps the state in SQLite. Each agent is a
"seat": a program in a tmux pane. The `rig` command starts rigs (teams), sends messages to seats
and reads their output.

## Why Hermes runs it

Hermes hands code work to one `omp` run at a time. OpenRig keeps a builder seat and a reviewer
seat alive between tasks. The reviewer checks the diff of the builder by evidence. Hermes is the
operator: it gives the task, reads the result and does the steps that a seat may not do (commit,
push, pull request). The owner's order (2026-11-04): "Add OpenRig to piabrota2, operated by Hermes
with a skill `hermes-rig`."

## The software factory

The owner's order (2026-11-05): OpenRig is the engine that will automate the SDLC (software
development life cycle). This is the open software factory behind piabrota. The direction: the rig
does the build and the review, Hermes routes the work and checks the result, and a human merges.
The rig has not yet done a task: see "Status today".

### Status today

- OpenRig 0.7.7 runs on piabrota2 as the unit `openrig`: loopback only, `MemoryMax=4G`. Its web UI
  is at https://rig.piabrota.art behind basic auth (see "The web UI").
- Six rigs are specified. `piabrota-dev` (`openrig/specs/rigs/piabrota-dev/rig.yaml`) has three seats on
  `omp`, `dev-builder`, `dev-front-builder` and `dev-reviewer`. All run without approval prompts
  (`permission_policy: builtin:yolo`, the owner's decision in PR 124). They use the owner's Claude
  subscription (see "The token of the seats").
  `piabrota-dev-claude` has the same three seats on Claude Code. The other four are the two rigs of
  wave-forecaster-dev, `wave-forecaster-thesis` and `reels-fabric` (below). A keeper keeps the port
  rig up. Nobody starts the integrate rig. The options of the thesis and reels rigs are off.
- Hermes operates the rig with the `rig` CLI and the skill `hermes-rig`. Hermes does not start seats
  from cron.
- **The seats are idle.** No task has gone through the builder to reviewer loop yet.
- Today Hermes makes a pull request by running `omp` itself (the skill `hermes-omp`). Then Hermes
  checks the diff, commits, pushes a `hermes/*` branch and opens the pull request. A human merges.
  A merge to `main` deploys (`deploy.yml`).

### The stages

|Stage|Who does it|State|
|---|---|---|
|Idea and triage|The owner, with the skills `/triage` and `/mip`|Today|
|Build|The builder seat|Next: the seat has not run a task|
|Review|The reviewer seat|Next: the seat has not run a task|
|Pull request|Hermes: `hermes/*` branch, English, ASD-STE100|Today, after a run of `omp` by Hermes|
|Merge|A human, always|Today|
|Deploy|`deploy.yml`: deploy-rs, magic rollback|Today|
|Watch|`kvm4-health`, the watchers, the daily VPS check|Today|

### How a task will go through

1. The owner gives Hermes a task. Hermes writes it as the skill `hermes-omp` says.
2. Hermes checks `kvm4-health` and `rig status`, then starts the rig (`rig up`) and sends the task
   to the builder seat (`rig send`).
3. The builder writes and tests the change in its own clone. It asks the reviewer seat to check the
   diff (the edge `delegates_to`).
4. The reviewer checks the diff by evidence and answers.
5. Hermes reads the answer, checks the diff itself, commits, pushes a `hermes/*` branch and opens
   the pull request. The seats cannot push.
6. A human reviews and merges. The merge deploys.

Steps 2 to 5 **will** run this way. They have not run yet.

### The guardrails that stay

- Humans merge. No seat and no agent merges.
- The deny list of Hermes and `hermes/omp.yml` stay in force. A seat cannot push: `omp.yml` denies
  `git push`, `gh` and `sudo`.
- No secret in a spec, a task or a message.
- At most three seats at the same time, in one rig (`MemoryHigh=3G` at piabrota2).
- The UI is behind basic auth and TLS. It has a terminal for each seat: see "The web UI".

### What is next, and what is not proved

- **Next.** Send the first real task through the builder and the reviewer, and compare the result
  with a run of `omp` by Hermes. Decide then if Hermes sends all code tasks to the rig.
- **Not proved.** A task through the loop. The messages between the two seats. A pull request that
  starts from a seat's diff. See "Not tested".

## Design

|Part|What it is|
|---|---|
|Option|`piabrota.openrig.enable`. Off by default. `hosts/piabrota2/default.nix` turns it on. `piabrota` does not import the module. `piabrota.openrig.waveForecaster.enable` and `piabrota.openrig.thesis.enable` turn on the rigs of the two blocks below. The first is on at piabrota2, the second is off. `piabrota.openrig.waveForecaster.alwaysOn.enable` adds the keeper of the port rig: it is on.|
|User|The system user and group `openrig`, no login shell. State in `/var/lib/openrig` (`HOME`, and `OPENRIG_HOME` is `.openrig` in it). Seats work in `/var/lib/openrig/work`.|
|Unit|`openrig` runs `node .../daemon/dist/index.js` in the foreground, as `openrig`.|
|Network|The daemon listens on `127.0.0.1:7433` (`OPENRIG_BIND_HOST`) and serves the web UI there. No firewall port, no ACME. The option `piabrota.openrig.web` adds an nginx vhost at `rig.piabrota.art` with basic auth: it is on.|
|Path|`tmux`, `bash`, `git`, `ps`, `lsof`, `node`, `rig` and the seat `omp`. NixOS adds `coreutils`, `findutils`, `grep`, `sed`.|
|Seat `omp`|`omp/wrapper.nix` with `ceiling = null` and `hermes/omp-seat-append-system.md`: the one wrapper of the repository, as PR 124 decided. Its rules (`hermes/omp.yml`) are the guard of a seat.|
|Permissions|The rig sets `permission_policy: builtin:yolo`: the seats run without approval prompts. This is the owner's decision in PR 124. `OPENRIG_YOLO=1` in the unit does not do it: a rig with no policy gets the floor, and a policy wins over the variable. The deny rules of `hermes/omp.yml` stay in force. Hermes cannot change it: its deny list blocks `OPENRIG_YOLO` and the permission commands of `rig`.|
|Seat key|The unit sets `OPENRIG_RECOVERY_PROVIDER_AUTH_ENV_ALLOWLIST=ANTHROPIC_API_KEY`: the name only. The value stays in the root-only `EnvironmentFile`. A seat whose model is `anthropic/<id>` gets the key. A Claude Code seat gets it too, as every seat does, and its `claude` (`seatClaude`) turns it into `CLAUDE_CODE_OAUTH_TOKEN`, because Claude Code ranks `ANTHROPIC_API_KEY` above that token. No other variable reaches a seat.|
|Marola bots|With `piabrota.openrig.marola.enable` (on at piabrota2), the rig `piabrota-dev` also serves marola-front and marola-back, and Hermes acts as `marola-pr-bot[bot]` on those two repositories only. `marola-bot.nix` mints the tokens. The merge bot of MIP-0086 is not used. See "marola-front and marola-back".|
|Hermes|A `rig` command in the packages of `hermes-agent`. It sets `OPENRIG_URL=http://127.0.0.1:7433` and runs the real `rig`.|
|Sandbox|`NoNewPrivileges`, `CapabilityBoundingSet=""`, `ProtectSystem=strict`, `ProtectHome`, `PrivateTmp`, `ProtectKernel*`, `ProtectProc=invisible`, `RestrictNamespaces`, `LockPersonality`, `SystemCallFilter=@system-service ~@privileged` with `EPERM`, and `RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK`.|
|Restart|`Restart=on-failure`, `RestartSec=10s`, at most 5 starts in 600 s. After that the unit stays down.|

**The pane has its own tools.** OpenRig starts each seat pane with a clean environment, so the
unit's `path` does not reach it. The pane's login bash builds its `PATH` from the per-user profile
of `$USER`. The user `openrig` has `tmux`, `bash`, `git`, `ps`, `lsof`, `node`, `rig` and the seat
`omp` in `users.users.openrig.packages`, and the rig spec sets `USER`, `LOGNAME` and `HOME` in its
`env:`. `openrig.nix` keeps one list (`seatTools`) for the unit and the profile.

**The CLI needs no state file.** With `OPENRIG_URL` set, `rig` talks to the daemon over HTTP and
reads no file of the daemon's state. The `hermes` user has no access to `/var/lib/openrig` (mode
0700), and it needs none. The owner-user check of the CLI runs only on macOS. So any local user
who can reach port 7433 can use the daemon. This is why the port stays on loopback and why the
deny list blocks `OPENRIG_URL=`, `OPENRIG_HOME=` and `/var/lib/openrig` in Hermes's commands.

### The token of the seats

The seats use the Claude subscription of the owner, as Hermes does. The flow:

1. At each start of the unit, a root step (`ExecStartPre=-+...`) copies one line,
   `CLAUDE_CODE_OAUTH_TOKEN=...`, from `/var/lib/hermes-secrets/hermes.env` to
   `/var/lib/openrig-secrets/.env`, and renames the variable to `ANTHROPIC_API_KEY` with `sed` on
   that line. Only the `openrig` user reads that file (mode 0600, folder 0700). The step prints
   nothing and does not run with `set -x`.
2. The unit reads the file with `EnvironmentFile=-`. The runner passes `ANTHROPIC_API_KEY` to the
   seat, and the wrapper moves the value to `ANTHROPIC_OAUTH_TOKEN`
   ([the reference](../hermes/skills/hermes-omp/references/openrig-seats.md)).
3. If the line or the source file is missing, the file is empty. The unit still starts. The seats
   then fail to log in.

The daemon holds the key in its environment, and a seat can read the file. The rules of
`omp.yml` deny `env`, `printenv`, `*/.env*` and `/proc/*/environ`. This is a barrier of rules, not
a wall. The seat norms say: never read a secret.

## Packaging

`openrig/package.nix` builds OpenRig from source (the tag `v0.7.7`, commit `f3d8bac4...`) with
`buildNpmPackage`. The source hash and the hash of the npm dependencies are fixed. No prebuilt
binary is used. The native addon `better-sqlite3` is compiled from its bundled source. The web UI is
built with `tsc` and `vite`, and only its `dist` folder is installed (see "The web UI"). The package has the layout of the npm package `@openrig/cli`, so `rig` finds its daemon.
No script of an npm package runs at build time. `nodejs_24` is the one Node on the box, and only
OpenRig uses it. The owner accepts Node.js for OpenRig (the rule 4 of `AGENTS.md` says so).

## The web UI

OpenRig has a web UI: React and vite, the package `packages/ui` of the source. `openrig/package.nix`
builds it into `@openrig/cli/ui/dist`. The unit sets `OPENRIG_UI_ENABLED=true`, so the daemon serves
it at `http://127.0.0.1:7433`. The setting is read once, at start. Upstream keeps the UI in
maintenance mode: expect no new features.

**It is on at https://rig.piabrota.art** (`hosts/piabrota2/default.nix`). The login is the same as
for `hermes.piabrota.art`: the file `/var/lib/hermes-web-secrets/htpasswd` (see `hermes-web.nix`). The
deploy makes the certificate: nginx asks Let's Encrypt for it (ACME) on the first start of the vhost.
The DNS record of the name already points at the box.

**To give the UI its own login**, set `piabrota.openrig.web.htpasswdFile` to another file. The
file has one `name:bcrypt-hash` line per user (`htpasswd -B`), mode 0640, owner root, group nginx.
Its directory must exist: `hermes-web.nix` makes only its own. Without the file every request gets
a 500, and the UI stays closed.

**The SSH tunnel stays as a fallback.** The port stays on loopback. On your computer, run:

```console
ssh -L 7433:127.0.0.1:7433 h0ffmann@<host>
```

Then open `http://localhost:7433` in a browser. The daemon accepts `localhost` as a name, and the
page's own origin as an origin.

**To open it on another domain**, add a DNS A record for the name, pointing at piabrota2. Without
it the ACME order fails on the deploy. Then change `piabrota.openrig.web.domain` and open a pull
request.

The vhost gives TLS from Let's Encrypt and HTTP basic auth, with the headers and the rate limit of
`hermes-web.nix`. It proxies to `127.0.0.1:7433` with the WebSocket headers and a one-hour read
timeout for the terminal. It opens no new port: nginx uses 80 and 443. When the vhost is on, the
unit gets `OPENRIG_ALLOWED_HOSTS=<name>` and `OPENRIG_ALLOWED_ORIGINS=https://<name>`. The daemon's
browser boundary for `/api/*` needs both: it refuses a Host or an Origin that it does not know.
nginx hides the basic-auth header from the daemon.

**The risk.** The UI has a terminal for each seat, and it can type into the seats. The seats run
without approval prompts (`OPENRIG_YOLO=1`). So whoever reaches the UI can run commands as the
user `openrig`, with the Claude token of the seats in reach. Never expose it without auth.

**The terminal has no token here.** The daemon asks for a terminal bearer token only on a bind that
is not loopback or tailnet, or when `OPENRIG_TERMINAL_BEARER_TOKEN` is set (read from the source of
0.7.7, not tested). The unit sets neither. So the gate of the terminal is the SSH tunnel, or the
basic auth of nginx plus the browser boundary. A local user on the box who can reach port 7433 can
also use the API (see "The CLI needs no state file"). A token does not fit the vhost: the UI sends it
as an `Authorization` header, and the header of the basic auth uses the same name. The unit
rewrites `/var/lib/openrig-secrets/.env` at each start, so a token cannot live there. Do not write
a token value in this repository.

**Not proved.** A browser session, the certificate, the login and the real unit. The smoke test ran
the built daemon on a scratch port.

## Limits

|Setting|Value|
|---|---|
|`MemoryMax`|4G for the whole unit at piabrota2 (`piabrota.openrig.memoryMax`, default 2G)|
|`MemoryHigh`|3G at piabrota2 (`piabrota.openrig.memoryHigh`, default 1536M)|
|`CPUWeight`|50|
|`TasksMax`|2048|
|`OOMPolicy`|`continue`: an OOM kill takes one process, not the unit|

Tmux and every seat run in the cgroup of the unit. `MemoryMax` is one budget for the daemon, tmux
and all seats. The kernel slows the unit above `MemoryHigh`, so that is the working limit. The
figures for the daemon and for one seat are in
[the reference](../hermes/skills/hermes-omp/references/openrig-seats.md). With the
defaults, the plan is **two seats at the same time**, the builder and the reviewer. That leaves room
under `MemoryHigh` for a seat that grows during a large edit and for the page cache of a git clone,
which counts against the unit. At piabrota2 the owner raised the unit to 4G and 3G (7 November
2026) so that `piabrota-dev` and `piabrota-dev-claude` run **three seats**: `builder` on marola-back
and `front-builder` on marola-front build at the same time and share `reviewer`. Check with
`kvm4-health` that the peak of `openrig` stays under `MemoryHigh`; if it does not, lower the load
before you raise the limit. The wrapper runs `omp` under `choom -n 500`, so the kernel picks a
seat before the daemon.

The `MemoryMax` values on piabrota2 sum to **14.25 GiB**: `hermes-agent` 8G, `hermes-backend` 2G,
`openrig` 4G, `pgx` 256M (`nix eval` of `systemd.services.*.serviceConfig.MemoryMax`). The machine
has 15.6 GiB. A cap is a ceiling, not a use. Run `kvm4-health` before you start a large rig: it
lists the unit `openrig`.

## What a deploy does to the seats

A deploy that changes the unit restarts `openrig` and ends every seat
(`KillMode=control-group`; see the reference). After the restart nothing starts a rig. The steps to
bring a rig back are in the skill `hermes-rig`, `references/operations.md`, section 7.

## Specs

The folder `openrig/specs/` holds the first RigSpec and the AgentSpecs that it uses. The module
installs it, read-only, at `/etc/openrig/specs`. Nothing starts the rig. Hermes or a human runs:

```console
rig up /etc/openrig/specs/rigs/piabrota-dev/rig.yaml
```

The layout follows the reference of OpenRig (`docs/reference/rig-spec.md` and `agent-spec.md`):

```text
openrig/specs/
  agents/
    shared/agent.yaml                  # one guidance resource: norms
    shared/guidance/norms.md           # the rules of every seat
    builder/agent.yaml
    builder/guidance/role.md
    builder/startup/context.md
    reviewer/agent.yaml
    reviewer/guidance/role.md
    reviewer/startup/context.md
  rigs/piabrota-dev/rig.yaml           # pod "dev": builder and reviewer, runtime omp
  rigs/piabrota-dev-claude/rig.yaml    # pod "dev": the same two agents, runtime claude-code
```

The block wave-forecaster-dev adds two rigs and four agents to the same folders (see
"wave-forecaster-dev" below):

```text
openrig/specs/
  agents/
    wf-shared/agent.yaml               # one guidance resource: the norms for h0ffmann/chaceon
    wf-shared/guidance/norms.md
    wf-porter/...                      # agent.yaml, guidance/role.md, startup/context.md
    wf-auditor/...
    wf-integrator/...
  rigs/wave-forecaster-dev/rig.yaml            # pod "port": porter and auditor
  rigs/wave-forecaster-dev-integrate/rig.yaml  # pod "wire": integrator and auditor
```

The block wave-forecaster-thesis adds one rig and five agents (see "wave-forecaster-thesis" above):

```text
openrig/specs/
  agents/
    thesis-shared/...                  # the norms for the thesis seats
    thesis-editor/...                  # agent.yaml, guidance/role.md, startup/context.md
    thesis-librarian/...
    thesis-writer/...                  # one spec for writer-a, writer-b and writer-c
    thesis-reviewer/...
  rigs/wave-forecaster-thesis/rig.yaml # pods "plan", "writing", "review": six Claude Code seats
```

The block reels-fabric adds one rig and six agents (see "reels-fabric" below):

```text
openrig/specs/
  agents/
    reels-shared/agent.yaml            # one guidance resource: the norms of every reels seat
    reels-shared/guidance/norms.md
    reels-creative-director/...        # agent.yaml, guidance/role.md, startup/context.md
    reels-producer-editor/...
    reels-artist-3d/...
    reels-music-director/...
    reels-qa/...
  rigs/reels-fabric/rig.yaml           # pod "crew": creative-director, producer-editor, artist-3d, music-director, qa
```
- `rig.yaml` has one pod, `dev`, with the members `builder`, `front-builder` and `reviewer`. All use
  the runtime `omp`, the model `anthropic/claude-sonnet-5-5` and the folder `/var/lib/openrig/work`.
  `front-builder` uses the agent `builder`. An edge `delegates_to` goes from each builder to
  `reviewer`. The rig sets `permission_policy: builtin:yolo`
  (see "Design").
- Each `agent.yaml` imports `shared`, selects `shared:norms` as guidance, and sends `role.md` and
  `startup/context.md` to the seat as text. The norms land in the `AGENTS.md` of the working folder.
- `shared` holds only the norms. An `omp` seat projects no plugin and no runtime resource, and the
  shared pool of OpenRig's own specs is for Claude Code and Codex seats.
- Each `agent.yaml` sets `model: anthropic/claude-sonnet-5-5` in `defaults`, and each member of
  `rig.yaml` sets the same `model`: with only the default, `rig ps` showed `not-declared`. The
  roles of `hermes/omp.yml` (Haiku for side tasks) still apply inside the seat.
- The seats cannot push: `omp.yml` denies `git push`, `gh` and `sudo`. The norms say so.

**To add an agent.** Make a folder `openrig/specs/agents/<name>/` with an `agent.yaml` that imports
`local:../shared`, and with `guidance/role.md` and `startup/context.md`. Add a member in
`rigs/piabrota-dev/rig.yaml` with `agent_ref: "local:../../agents/<name>"`. Open a pull request.

**To change a role.** Edit `guidance/role.md` of the agent. Merge the pull request. The deploy
updates `/etc/openrig/specs`. A running seat keeps its old text. Run `rig down piabrota-dev`, then
`rig up /etc/openrig/specs/rigs/piabrota-dev/rig.yaml`, to start a new generation.

**To check the specs.** These commands ran against a scratch daemon on 2026-11-04:

```console
rig spec validate openrig/specs/rigs/piabrota-dev/rig.yaml     # Rig spec valid: piabrota-dev
rig agent validate openrig/specs/agents/builder/agent.yaml     # Agent spec valid: builder v1.0
rig up openrig/specs/rigs/piabrota-dev/rig.yaml --plan         # Status: planned
```

`--plan` did not catch a missing startup file or a missing norms file in a test. It checks the
spec and its agent references, not the files. Check by hand that each path in an `agent.yaml`
exists.

## Runtimes

A runtime is what a seat runs. OpenRig 0.7.7 has six (`claude-code`, `codex`, `pi`, `omp`,
`terminal`, `stub`) and community harnesses. [`RUNTIMES.md`](RUNTIMES.md) compares them: features,
pros, cons, a spec line, credentials, permission mapping, state and the status on this box.

|Rig|Runtime|
|---|---|
|`piabrota-dev`|`omp`|
|`piabrota-dev-claude`|`claude-code`, when `piabrota.openrig.marola.claude.enable` is on (on at piabrota2)|
|`wave-forecaster-dev` (port)|`claude-code`, when `piabrota.openrig.waveForecaster.enable` is on (on at piabrota2)|
|`wave-forecaster-dev-integrate`|`omp`|
|`wave-forecaster-thesis`|`claude-code`, when `piabrota.openrig.thesis.enable` is on (off)|
|`reels-fabric`|`omp`, five seats|

## wave-forecaster-dev

The block wave-forecaster-dev runs the port of WAVEWATCH III (WW3) from Fortran to Rust in
[h0ffmann/chaceon](https://github.com/h0ffmann/chaceon) on this box. chaceon defined the
same loop for Claude Code seats on the owner's machine (its `rigs/` folder, PR 20 of
h0ffmann/chaceon). The port rig `wave-forecaster-dev` now runs its two seats on Claude Code
(`runtime: claude-code`, `claude-sonnet-5-5`, a pure Claude Code harness). The integrate rig stays on
`omp`, on `anthropic/claude-sonnet-5-5`. Both follow the protocol of piabrota-dev otherwise:
`builtin:yolo`, the box norms first, two seats per rig, and Hermes as the operator who commits,
pushes and opens the pull request. `wf-auditor` serves both rigs: the port rig's member entry sets its runtime, and
the shared agent keeps omp as its default.

|Rig|Seats|Does|
|---|---|---|
|`wave-forecaster-dev`|`port-porter`, `port-auditor`|Translates one WW3 routine to a Rust kernel, with its ledger row and report, to the status `translated`. The auditor reads it against the Fortran.|
|`wave-forecaster-dev-integrate`|`wire-integrator`, `wire-auditor`|Wires one ported package into `W3SRCE` and `mod_def.ww3`. The auditor reads the wiring.|

**One rig at a time.** Each rig has two seats, so it fits the plan of "Limits", and never at the
same time as piabrota-dev or the other rig. A cold `cargo check --workspace` of chaceon peaks at
about 850 MiB with one job (measured on an arm64 Mac, `/usr/bin/time -l`, not on the box). With the
daemon and two seats that is about 1.75 GiB: above `MemoryHigh`, so the kernel slows the unit, and
below `MemoryMax`. The norms make every build `CARGO_BUILD_JOBS=1 nice -n 10`, one at a time.

**What the seats cannot check.** chaceon's evidence needs Docker (the Fortran reference, gdb
captures, the comparison replays), Vulkan (the SPIR-V replays) and CUDA (PTX). This box has none
of them, and adds none: Docker would give the seats root. So a seat runs `just check` and
`just lint-sh` only, and its work leaves the box at the status `translated`. The owner runs the
other gates on the owner's machine and moves the status. The norms say this, and they win over
chaceon's rule that a missing tool must be installed.

**Always on.** `piabrota.openrig.waveForecaster.enable` and `piabrota.openrig.waveForecaster.alwaysOn.enable`
are on at piabrota2 (the owner's order of 2026-11-07: the port rig runs 24/7). A restart of the unit
`openrig` ends the seats: a deploy, a crash or a reboot. So a keeper brings the port rig back. The
option `alwaysOn` needs `waveForecaster.enable`. The integrate rig stays manual. A rig keeps the spec
that made it: if the spec of the port rig changes, run `rig archive wave-forecaster-dev` and
`rig import /etc/openrig/specs/rigs/wave-forecaster-dev/rig.yaml --materialize-only`.

**The keeper.** The unit `openrig-wf-keeper` (`openrig.nix`, `wfKeeper`) runs 2 minutes after boot and
then every 2 minutes. It asks the daemon only (`rig` with `OPENRIG_URL`):

|Case|The keeper|
|---|---|
|The daemon does not answer|Prints a line and exits 0. It never starts a daemon, and it does not start `openrig.service`.|
|Another rig runs|Skips: one rig at a time ("Limits").|
|The port rig runs|Exits 0. With `attentionCount > 0` it logs a warning.|
|The port rig is `partial`|Logs a warning with the seats that do not run. It changes nothing.|
|The port rig is stopped, and every seat has `intentionallyStopped`|Someone ran `rig down`. It does nothing.|
|The port rig is stopped|Runs `rig up wave-forecaster-dev --existing`. If that fails, it runs `rig up /etc/openrig/specs/rigs/wave-forecaster-dev/rig.yaml`. With no rig of that name, it runs the spec at once.|
|3 starts in the last hour|Does not try. The unit exits 1, so it shows in `systemctl --failed`. The attempts are in `/var/lib/openrig-wf-keeper/attempts` (an epoch second a line).|

The unit is a oneshot with its own sandbox: `DynamicUser`, `MemoryMax=256M`, `CPUQuota=25%`,
`IPAddressAllow=localhost`, no secret. It reads `/etc/openrig/specs`, which is world-readable. The
script does not print the output of `rig up`.

**To stop the port rig on purpose:** `rig down wave-forecaster-dev`. `rig down` marks every seat as
stopped on purpose, and the keeper leaves such a rig down, even after another rig ends. **To run
another rig:** run `rig down wave-forecaster-dev` first. When the other rig ends, bring the port rig
back with `rig up wave-forecaster-dev --existing`. The keeper does not do this step. A rig that
stops without `rig down` (a deploy, a crash, a reboot) it restores 2 minutes later.

**What the keeper does not do.** It sends no task: an idle rig does no work. It does not answer
Claude Code's one-time bypass-permissions warning. The owner answers it once with `rig seat continue`
or attaches (docs/RUNTIMES.md, "Claude Code on this box"). It does not fix a `partial` rig. It does
not look at memory: the budget is the unit `openrig` (`MemoryMax=2G`).

**What `piabrota.openrig.waveForecaster.enable` adds** (when on):

|Part|Setting|
|---|---|
|Tools|`rustup`, `gcc` (the linker of build scripts), `just`, `shellcheck` and `chaceon-clone` in the profile of the user `openrig` and in the unit's `path`. A Claude seat that OpenRig starts with a clean environment finds its tools only through the path. `claude` (`seatClaude`: `pkgs.claude-code` behind a small wrapper) is in the same two places, and `piabrota.openrig.thesis.enable` adds it too. Each seat installs Rust 1.99.1 with rustup into its own home under `/var/lib/openrig`.|
|Claude Code|`unfree.nix` allows `claude-code` by name (`allowUnfree` stays off). `seatClaude` moves the subscription token from `ANTHROPIC_API_KEY` to `CLAUDE_CODE_OAUTH_TOKEN` and drops what Claude Code ranks above it, for Claude's process only. `/etc/claude-code/managed-settings.json` holds the deny rules of a Claude seat (below). Closure: about +280 MiB, built on the CI runner.|
|Folders|`/var/lib/openrig/work/wave-forecaster-dev/{porter,auditor,integrator}` (`StateDirectory`). Each seat has its own folder: the norms go in its `CLAUDE.md` (port rig) or `AGENTS.md` (omp seats), and the chaceon clone in a subfolder, so the files never mix.|
|Read token|`piabrota.openrig.githubRead = [ "h0ffmann/chaceon" ]`. `hermes-github.nix` mints, every 45 minutes, a token of Hermes's App with `contents: read` on that repository only, into `/run/openrig-github/h0ffmann--chaceon` (root, group `openrig`, 0640). `chaceon-clone` clones with a credential helper that reads it. The App must be installed on h0ffmann/chaceon.|
|Outbox|`/var/lib/rig-outbox/wave-forecaster-dev` (owner `openrig`, group `hermes`, 0750, a default ACL that gives the group read access, files older than 14 days removed). A seat writes a `git bundle` there; Hermes fetches it, reads it, and pushes a `hermes/*` branch. The unit has it in `ReadWritePaths`. It is not under `/var/lib/openrig`, which Hermes's deny list blocks.|

**The risk.** A seat runs without approval prompts and can read the read token. The token can
only read one repository, and it ends after one hour. The deny rules still refuse `git push`, `gh`,
installs and secrets: `hermes/omp.yml` for an omp seat, `managed-settings.json` for a Claude seat.
The Claude rules are `Bash(...)` and `Read(...)` rules, translated from `omp.yml`. Claude Code checks
deny rules before its permission mode, so they hold in bypass mode, but they are no sandbox: a
program that a seat starts can read what a rule names. The unit's sandbox is the hard layer. Rules
of `omp.yml` that a Claude seat cannot have: regex rules of `hermes/dangerous-patterns.yaml` (a push
to a branch other than `hermes/*`, `rig` with `--host` or `--policy`), the path of the daemon's state
(a seat's folder is under it), and any limit on `WebFetch` (omp's own fetch is not limited either).

**chaceon's own rules that this box changes.** chaceon names an agent's branch
`goal/<id>-<slug>`. Hermes can push only `hermes/*`, so the seats use `hermes/wf-<slug>`. chaceon
asks for an agent `Co-Authored-By` trailer; Hermes's commits carry none. The owner decides whether
chaceon's `AGENTS.md` accepts both.

To start the port rig by hand (the keeper does it when the rig is stopped), after `rig status` says "Daemon running" and `kvm4-health` shows room:

```console
rig up /etc/openrig/specs/rigs/wave-forecaster-dev/rig.yaml --plan
rig up /etc/openrig/specs/rigs/wave-forecaster-dev/rig.yaml
rig send port-porter@wave-forecaster-dev "<routine, switch file, template commit; done means; checks; no push>" --verify
```

When the porter reports a bundle, Hermes fetches it into its own clone of chaceon:

```console
git -C <clone> fetch /var/lib/rig-outbox/wave-forecaster-dev/<slug>.bundle HEAD:hermes/wf-<slug>
```

## marola-front and marola-back

MIP-0092 (status Draft, [marola-dev/marola](https://github.com/marola-dev/marola), PR 929) asks for a
code factory on OpenRig that builds two new repositories: `marola-dev/marola-front` (Vite,
TypeScript, MapLibre) and `marola-dev/marola-back` (Rust, Loco). The MIP proposes a new rig of four
seats, `code-factory`. The owner decided otherwise: `piabrota-dev` serves it. The rig `code-factory` is
not built. Front and back changes are made in parallel (the owner, 7 November 2026), so the rig has
two builders and one reviewer: `builder` works on marola-back (and on every other task),
`front-builder` on marola-front only. Both use the agent `builder` and delegate to `reviewer`, which
reviews one diff at a time.

The owner also decided that the rig uses the marola bots of MIP-0086. `marola-pr-bot` proposes: it
pushes branches, opens pull requests and comments, and never lands on `main`. `marola-merge-bot`
merges. This change uses only `marola-pr-bot`: nothing here mints, reads or names a token of the
merge bot. Humans merge.

**What `piabrota.openrig.marola.enable` adds** (on at piabrota2). Everything is off without it, and
the generated Hermes git config, token unit and `openrig` unit are then as before.

|Part|Setting|
|---|---|
|Tools|`rustup`, `gcc`, `just`, `shellcheck`, `openrig-git-credential` and `marola-clone` in the profile of the user `openrig` and in the unit's `path` (`marolaTools`). The Rust part is shared with the chaceon rigs (`rustTools`). A host with both options on has no duplicate. `marola-clone <marola-front\|marola-back\|owner/name> [dir]` clones with the credential helper and refuses a name that is not in `piabrota.openrig.marola.repos`.|
|Folders|The outbox `/var/lib/rig-outbox/marola` (owner `openrig`, group `hermes`, 0750, a default ACL that gives the group read access, files older than 14 days removed). The unit has it in `ReadWritePaths`. The folder `/run/openrig-github` for the read tokens exists too.|
|Read tokens|`marola-bot.nix` (unit `marola-bot-token`, every 45 minutes) mints one token per repository with `contents: read` on that repository only, into `/run/openrig-github/marola-dev--<name>` (root, group `openrig`, 0640). The repositories are not in `piabrota.openrig.githubRead`: `hermes-github.nix` would write the same files with the other App.|
|Operator token and identity|The same unit mints one token for Hermes: `contents`, `pull_requests` and `issues` (write) on the two repositories. It goes to `/run/hermes-github/marola-pr-bot` (root, group `hermes`, 0640). The unit also writes `/var/lib/hermes/.gitconfig-marola-bot` with the name and the noreply email of the bot.|
|`marola-gh`|A command in the packages of `hermes-agent`. It runs `gh` with the operator token. It allows only `pr create\|view\|list\|diff\|checks\|status\|comment\|edit` and `issue view\|list\|comment`. Everything else, and a global flag before the subcommand, exits 2.|
|Git credential helper|`hermes-github.nix` makes the helper of Hermes answer for the two repositories with the token of `marola-pr-bot`. If that file is missing, the helper prints nothing: the push fails, and never falls back to the token of piabrota-hermes. An `includeIf` block in `.gitconfig` gives the bot's identity to these two repositories only. Every other repository stays on piabrota-hermes[bot].|

**How the tokens are scoped.** The App `marola-pr-bot` has one installation, on `marola-dev`, so
`piabrota.openrig.marola.repos` takes only `marola-dev/<name>` (an assertion checks it). The
operator token has `contents`, `pull_requests` and `issues` (write) on the two repositories. A seat
token has `contents: read` on one repository. No token has `workflows` (GitHub then refuses a push
that changes `.github/workflows`) or `administration`. No token is of the merge bot.

**The flow for Hermes.** The seats never push.

1. `rig status` says "Daemon running", and `kvm4-health` shows room. Nothing else runs in the rig.
2. `rig up /etc/openrig/specs/rigs/piabrota-dev/rig.yaml` (see "A rig keeps the spec that made it").
3. Send a back task to `builder` and a front task to `front-builder`. Both can run at the same time:
   `rig send dev-builder@piabrota-dev "<marola-dev/marola-back, the issue, done means, checks, no push>" --verify`
   and `rig send dev-front-builder@piabrota-dev "<marola-dev/marola-front, ...>" --verify`.
   The guidance `shared:marola` is in the seat's `AGENTS.md`.
4. Each builder clones with `marola-clone`, works on `hermes/<issue>-<slug>`, asks the reviewer, and
   leaves `/var/lib/rig-outbox/marola/<repo>-<issue>-<slug>.bundle` and a `.md` report.
5. Hermes reads the report and the diff. It makes its own clone with
   `git clone https://github.com/marola-dev/<repo>.git` (the credential helper gives the token),
   then `git fetch <bundle> HEAD:hermes/<issue>-<slug>`.
6. Reset the authors, so that the commits show the bot:
   `git rebase --exec 'git commit --amend --no-edit --reset-author' origin/main`.
7. `git push origin hermes/<issue>-<slug>`, then `marola-gh pr create --base main --head hermes/<issue>-<slug> --title ... --body-file ...`.
   The PR is in English and in ASD-STE100, as every PR of Hermes. Humans merge.

**What the seats cannot check.** Playwright with a browser, `oasdiff`, the Cloudflare deploy and
the live API do not run on this box. The guidance tells a seat to write each one as "runs in CI"
with `⚠` and not to install it.

**The risk.** The private key of `marola-pr-bot` is on the box, in `/var/lib/hermes-secrets/`, as
the key of piabrota-hermes is. Make a SECOND private key of the App for the box, so that the owner
can revoke it alone. The App has no merge permission, so it can push branches and open pull
requests, and nothing more. Keep a ruleset on `main` of each repository, so that a push to it fails
at GitHub. A seat holds a
read token that ends after one hour. The seats run without approval prompts, as in the other rigs,
and `hermes/omp.yml` still denies `git push`, `gh` and secrets.

**A rig keeps the spec that made it.** `piabrota-dev` exists since an earlier deploy, so the new
guidance does not reach its seats by itself. After the deploy, ask the owner and run:

```console
rig archive piabrota-dev
rig import /etc/openrig/specs/rigs/piabrota-dev/rig.yaml --materialize-only
rig up /etc/openrig/specs/rigs/piabrota-dev/rig.yaml
```

**The key file.** Without `/var/lib/hermes-secrets/marola-pr-bot.env` (`GH_APP_ID=` and
`GH_APP_PRIVATE_KEY_B64=`, the `.pem` in base64 on one line), `marola-bot-token` does not run: no
token exists, `marola-clone` clones only a public repository, and a push to the two repositories
fails.

**Not tested.** None of this ran on the box: the deploy with the option on, the App's installation on
`marola-dev`, a token for the two repositories, the bot's identity in a commit, `marola-gh` against
GitHub, the credential helper on a push, the `includeIf` block (it needs git 2.36 or later), the
outbox ACL with the unit's `UMask`, and a seat that runs the guidance. Only the Nix evaluation ran.

### Comparing omp and Claude Code

The owner wants two setups for marola-front and marola-back, run on the same issue. Only the runtime
changes. The agents, the guidance, the bot tokens and the outbox are the same.

|Setup|Rig|Seats|Runtime|
|---|---|---|---|
|A|`piabrota-dev` (exists)|builder, front-builder, reviewer|`omp`, `anthropic/claude-sonnet-5-5`|
|B|`piabrota-dev-claude` (new)|builder, front-builder, reviewer|`claude-code`, `claude-sonnet-5-5`|

Setup B needs `piabrota.openrig.marola.claude.enable` (on at piabrota2). It adds `claude`,
`/etc/claude-code/managed-settings.json` and the folders `/var/lib/openrig/work/piabrota-dev-claude/builder`,
`.../front-builder` and `.../reviewer`. It costs about 280 MiB of closure (see [`RUNTIMES.md`](RUNTIMES.md)). The member
of the rig names `runtime: claude-code` and a plain Claude id, and these win over the omp default of
the agents. A Claude seat reads its guidance in the `CLAUDE.md` of its own folder, so the two folders
differ. The deny rules of `managed-settings.json` cover the same secret folders as for the other
Claude rigs, among them `/var/lib/hermes-secrets`, where the key of `marola-pr-bot` is.

Never run A and B at the same time: the unit has one memory budget for one rig. Do not run B when
A is up.

**The protocol,** in order:

1. Pick one `agent-ready` issue. Write ONE task text: the issue URL, the repository, the branch
   `hermes/<issue>-<slug>-omp` or `hermes/<issue>-<slug>-claude`, what done means, the checks, and
   "no push". Use the same text for both runs. Only the branch suffix changes.
2. Run A to the end. Read its outbox. Then `rig snapshot piabrota-dev` and `rig down piabrota-dev`.
   Then run `kvm4-health`. Then `rig up` B with the same text.
3. Record these values for each run, from commands only:
   - the wall time: from the first `rig send` to the time of the outbox file (`stat -c %y`);
   - the number of reviewer rejections (the reviewer's verdicts in `rig transcript`);
   - the checks that each seat says it ran, and the checks that Hermes ran again;
   - the files and lines changed (`git diff --stat` of the bundle);
   - the cost or the turns, where the runtime prints them (omp: the `omp: done` line of
     `rig transcript`; Claude Code: write "not printed" if it prints none);
   - the memory of the unit: `systemctl show openrig -p MemoryCurrent -p MemoryPeak`, before and
     after each run. `MemoryPeak` is for the whole unit since its start.
4. Judge by the diff and the checks, not by what a seat says about its own work. The operator posts
   the table as a comment on the issue under test, never in this document. Never invent a number.
5. Hermes opens ONE pull request, from the better branch. The other bundle stays in the outbox
   (14 days).

Seat names of B are `dev-builder@piabrota-dev-claude`, `dev-front-builder@piabrota-dev-claude` and
`dev-reviewer@piabrota-dev-claude`. The reviewer of B reads a builder's clone at
`/var/lib/openrig/work/piabrota-dev-claude/<builder or front-builder>/<repo>`.
A rig keeps the spec that made it: after a change to its `rig.yaml`, `rig archive` it and import it
again.

**Not tested.** Neither setup has run a live task on this box. Setup B has not started a seat:
the first run of Claude Code in bypass mode asks once to accept its warning (see `RUNTIMES.md`).

## wave-forecaster-thesis

The rig `wave-forecaster-thesis` has six Claude Code seats (`plan-editor`, `writing-librarian`,
`writing-writer-a`, `-b`, `-c` and `review-reviewer`). They write one final-year project of the
Escola Politécnica of UFRJ in Portuguese, one section at a time, and hand in a PDF. The command
`thesis` (`thesis/`, no model, no network) claims the sections, runs four gates and builds the PDF
with pandoc and TeX. Only the librarian may use the web. The guide is [`THESIS.md`](THESIS.md): the
parts, the contract, the gates and what each cannot prove, the UFRJ rules, and the deployment notes.

**Off at the start.** `piabrota.openrig.thesis.enable` is off at piabrota2. The specs are in
`/etc/openrig/specs` as a definition only. When the owner turns the option on, it adds:

|Part|Setting|
|---|---|
|Tools|`thesis` (the package `thesis/default.nix`, closure 727.3 MiB: pandoc, poppler-utils and a small TeX set) and `claude` (`seatClaude`) in the profile of the user `openrig` and in the unit's `path`.|
|Claude Code|The same pieces as for the port rig: `unfree.nix`, `seatClaude`, and `/etc/claude-code/managed-settings.json`. They turn on when `waveForecaster.enable` or `thesis.enable` is on.|
|Folders|`/var/lib/openrig/work/wave-forecaster-thesis/{editor,writer-a,writer-b,writer-c,librarian,reviewer,projects,out}` (`StateDirectory`).|
|Outbox|`/var/lib/rig-outbox/wave-forecaster-thesis` (owner `openrig`, group `hermes`, 0750, a default ACL, files older than 14 days removed). The seats write the PDF there. The unit has it in `ReadWritePaths`.|

**Run it by phases, two seats at a time**, and never together with another rig. The memory of a
Claude Code seat is not measured: [`THESIS.md`](THESIS.md), "Deployment notes", step 9, says how to
measure it. **Not run:** no seat has run this rig. The proof so far is `thesis` on a sample thesis
(60 checks, 0 failed).

## reels-fabric

The rig `reels-fabric` makes one 15 s or 30 s vertical video (1080x1920) for Instagram Reels. Claude
is the only model: no image, video, voice or music service, no network. The screenplay
(`screenplay.json`) is the one source, and a hash gate stops every stage after it until the
screenplay is approved. The guide is [`REELS.md`](REELS.md), and the wiki's `Reels` pages summarise it.

|Part|Setting|
|---|---|
|Rig|`openrig/specs/rigs/reels-fabric/rig.yaml`: one pod, `crew`, a film crew of five seats (`creative-director`, `producer-editor`, `artist-3d`, `music-director`, `qa`), all on `omp`, `anthropic/claude-sonnet-5-5`, `builtin:yolo`. The edges form a chain with no cycle: creative director to producer-editor and to artist-3d, producer-editor to music director and to QA. The executive producer is the owner, a human, not a seat.|
|Option|`piabrota.openrig.reels.enable`. Off at piabrota2. The specs are in `/etc/openrig/specs` as a definition only. `piabrota.openrig.reels.blender.enable` (off) adds `pkgs.blender`, headless, for the 3D shots: the owner's exception to "no GUI" (2026-11-08). It needs the first option. Cycles on the CPU only: EEVEE crashes on this box.|
|Tools|The toolkit `reel` (`reels/`, built by `reels/default.nix`) with `ffmpeg-headless` and `jq`, in the profile of the user `openrig` and in the unit's `path`. Two font files (Inter and Fjalla One) are the owner's exception to "no fonts".|
|Folders|`/var/lib/openrig/work/reels-fabric/{creative-director,producer-editor,artist-3d,music-director,qa}` (the seats' own folders), `projects` (shared, one folder for each slug) and `out` (the renders), all `StateDirectory`.|
|Outbox|`/var/lib/rig-outbox/reels-fabric` (owner `openrig`, group `hermes`, 2750 with setgid, a default ACL for the group, files older than 14 days removed). `reel publish` writes `reel.mp4`, `qa.json`, `screenplay.json` and `review/` to `<slug>/` and gives the group read access to them. The unit has it in `ReadWritePaths`. The parent is shared with the wave and thesis rigs.|
|Env|The rig sets `REELS_HOME=/var/lib/openrig/work/reels-fabric` and `REELS_OUTBOX=/var/lib/rig-outbox/reels-fabric`.|

**Five phases, two seats at a time.** The rig has five seats, and a render adds an `ffmpeg` of up to
540 MiB (a Blender render adds 536 MiB). So the operator starts the seats in phases, and never more
than two at once: story and look (creative director and producer-editor, until `reel approve`),
picture (the same two seats, until the shotlist, the storyboard and the flat clips exist), 3D shots
(`artist-3d` with the producer-editor, skipped without a `3d` shot or without Blender), sound
(`music-director` with the producer-editor, until the cut has its audio) and check and publish (`qa`
with the producer-editor still up, until `reel publish`). The exact commands are in
[`REELS.md`](REELS.md), "The phases". The executive producer, the owner, decides the brief, the start
of each phase and what to do with the published reel. A human approves or the producer-editor does:
Hermes never approves.

**Not proved.** A live run of the rig, a Blender render inside the unit `openrig`, and Instagram's
acceptance of the file. `rig spec validate` and `rig agent validate` passed on the specs without a
daemon. The toolkit ran on this box: the numbers are in [`REELS.md`](REELS.md), "Measured numbers".
## What is not done

- **No public web page without auth.** The daemon runs on loopback only. The public vhost (`rig.piabrota.art`) has TLS and basic auth (see "The web UI").
- **No `rig setup`.** It installs tools and edits `~/.tmux.conf`. The deny list blocks it.
- **No herdr, no remote hosts.** `rig host`, `rig up --host` and pairing are blocked.
- **No Codex seat.** Codex is not installed. A Claude Code seat exists only in the port rig and the
  thesis rig, and only with `piabrota.openrig.waveForecaster.enable` or `piabrota.openrig.thesis.enable`
  on (the first is on at piabrota2, the second is off): `claude` is unfree, allowed by name
  in `unfree.nix`. See [`RUNTIMES.md`](RUNTIMES.md).
- **No `PrivateDevices`.** In a test with a user unit, tmux could not start a pane with a private
  `/dev`. A pane needs a pseudo terminal. The test used a user manager, not the system manager, so
  the cause may be the test. The unit leaves `PrivateDevices` off.
- **No `gateway` or `slack` rule.** They contact people. The skill `hermes-rig` and the norms say
  to ask the owner first. The deny list has no rule for them.

## Not tested

For wave-forecaster-dev, none of this ran: a deploy, a seat, `rig spec validate` on the new specs
(OpenRig's own schema check of the three rig specs passed in a script, and nothing more), a Claude
Code seat (its start, login, the bypass dialog, the model id with Claude Code 2.1.223, memory, and
that OpenRig finds the process behind `seatClaude`), rustup's toolchain on NixOS (nixpkgs patches
it for NixOS: not checked here), the read token (the App's installation may not include
h0ffmann/chaceon), the outbox ACL with the unit's `UMask`, and Hermes's read of the outbox under the
`hermes-agent` sandbox.

The keeper `openrig-wf-keeper` did not run on the box either: a deploy with the option on is needed
first. It is `piabrota openrig-wf-keeper` (`scala/scripts/WfKeeper.scala`); its tests
(`WfKeeper.test.scala`) run it against a fake `rig`: stopped rig, `--existing` failing, `rig down`,
another rig, partial rig, daemon down, back-off. The shell version's `jq` filters ran against the
output of the live `rig ps`; the Scala version has not met a live `rig ps`. `rig up` from the keeper (a stopped rig with no usable
snapshot, a spec that the daemon refuses) never ran.

For wave-forecaster-thesis, no seat ran. Not tested: a deploy with the option on, the closure growth
of the system (`dix`), a Claude Code seat (the memory of one, the bypass dialog, the tool `deny`
rules), `rig spec validate` on the new spec, the outbox ACL with the unit's `UMask`, and Hermes's
read of the outbox. Tested: the `thesis` command, in [`THESIS.md`](THESIS.md), "What is proved and
what is not".

For marola-front and marola-back, no seat ran: see the end of that section. Not tested: also
`rig spec validate` on the changed `shared` agent and the two agents that use it.

For the rest:

I could not test these. Check them after the first deploy. The reference lists the seat settings
that were not checked on the box.

- A start of the real unit: `ProtectSystem=strict` with the real `StateDirectory`, the user
  `openrig` and `RuntimeDirectory`. The test used a user unit with the same properties, and a
  scratch folder.
- The root step that copies the token, and the read of the file by `EnvironmentFile=-` after it.
  The test read no secret.
- A real seat: its start, its first turn, the messages between builder and reviewer, the delivery
  of the startup files, the merge of the norms into `AGENTS.md` (`CLAUDE.md` for a Claude seat), and the `model` of the AgentSpec.
- `rig daemon status` and `rig daemon logs` from the `hermes` user. They may read files in the
  state folder. Use `journalctl -u openrig` (with the `observer` account) for the daemon log.
- A full system build and the deploy. A build of the unit file and an evaluation ran.

## Update

Edit `openrig/package.nix`: change `version` and `commit` (the commit of the new tag), set both
hashes to `lib.fakeHash`, build, and copy each real hash from the error. The names are `hash` in
`src` and `npmDepsHash`. Check that `scripts/build-package.sh` of the new tag still matches the build
steps in the package, and run `rig spec validate` on the specs. Update the version in this file
and in `AGENTS.md`. Read the reference again: its facts come from one tag.

## Turn it off

Set `piabrota.openrig.enable = false;` in `hosts/piabrota2/default.nix`. The deploy stops the unit.
The state stays in `/var/lib/openrig`, and the token copy stays in `/var/lib/openrig-secrets`.
Delete both by hand on the box if you want them gone. Hermes then has no `rig` command.
