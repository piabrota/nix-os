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

## Design

|Part|What it is|
|---|---|
|Option|`piabrota.openrig.enable`. Off by default. `hosts/piabrota2/default.nix` turns it on. `piabrota` does not import the module.|
|User|The system user and group `openrig`, no login shell. State in `/var/lib/openrig` (`HOME`, and `OPENRIG_HOME` is `.openrig` in it). Seats work in `/var/lib/openrig/work`.|
|Unit|`openrig` runs `node .../daemon/dist/index.js` in the foreground, as `openrig`.|
|Network|The daemon listens on `127.0.0.1:7433` (`OPENRIG_BIND_HOST`) and serves the web UI there. No firewall port, no ACME. The option `piabrota.openrig.web` adds an nginx vhost with basic auth. It is off.|
|Path|`tmux`, `bash`, `git`, `ps`, `lsof`, `node`, `rig` and the seat `omp`. NixOS adds `coreutils`, `findutils`, `grep`, `sed`.|
|Seat `omp`|`omp/wrapper.nix` with `ceiling = null` and `hermes/omp-seat-append-system.md`: the one wrapper of the repository, as PR 124 decided. Its rules (`hermes/omp.yml`) are the guard of a seat.|
|Permissions|The unit sets `OPENRIG_YOLO=1`. This is the owner's decision in PR 124. The deny rules of `hermes/omp.yml` stay in force. Hermes cannot change it: its deny list blocks `OPENRIG_YOLO` and the permission commands of `rig`.|
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

**Open it by an SSH tunnel.** The port stays on loopback. On your computer, run:

```console
ssh -L 7433:127.0.0.1:7433 h0ffmann@<host>
```

Then open `http://localhost:7433` in a browser. The daemon accepts `localhost` as a name, and the
page's own origin as an origin.

**To open it on a domain**, do these steps in this order:

1. Add a DNS A record for the name, pointing at piabrota2. Without it the ACME order fails on the
   deploy.
2. On the box, write `/var/lib/openrig-web-secrets/htpasswd`: one `name:bcrypt-hash` line per user
   (`htpasswd -B`), mode 0640, owner root, group nginx. Without the file every request gets a 500.
3. In `hosts/piabrota2/default.nix`, set `piabrota.openrig.web = { enable = true; domain = "<name>"; };`.
   Open a pull request. The deploy builds the vhost.

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

**Not proved.** A browser session, the vhost, and the real unit. The smoke test ran the built daemon
on a scratch port.

## Limits

|Setting|Value|
|---|---|
|`MemoryMax`|2G for the whole unit|
|`MemoryHigh`|1536M|
|`CPUWeight`|50|
|`TasksMax`|2048|
|`OOMPolicy`|`continue`: an OOM kill takes one process, not the unit|

Tmux and every seat run in the cgroup of the unit. `MemoryMax` is one budget for the daemon, tmux
and all seats. The kernel slows the unit above `MemoryHigh`, so that is the working limit. The
figures for the daemon and for one seat are in
[the reference](../hermes/skills/hermes-omp/references/openrig-seats.md). The plan is **two seats at the
same time**, the builder and the reviewer. That leaves room under `MemoryHigh` for a seat that
grows during a large edit and for the page cache of a git clone, which counts against the unit. A
third seat leaves little room. Add it only after `kvm4-health` shows that the peak of `openrig`
stays well under `MemoryHigh`. The wrapper runs `omp` under `choom -n 500`, so the kernel picks a
seat before the daemon.

The `MemoryMax` values on piabrota2 sum to **12.25 GiB**: `hermes-agent` 8G, `hermes-backend` 2G,
`openrig` 2G, `pgx` 256M (`nix eval` of `systemd.services.*.serviceConfig.MemoryMax`). The machine
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
```

- `rig.yaml` has one pod, `dev`, with the members `builder` and `reviewer`. Both use the runtime
  `omp` and the folder `/var/lib/openrig/work`. An edge `delegates_to` goes from `builder` to
  `reviewer`. The spec sets no `permission_policy`: the unit decides (see "Design").
- Each `agent.yaml` imports `shared`, selects `shared:norms` as guidance, and sends `role.md` and
  `startup/context.md` to the seat as text. The norms land in the `AGENTS.md` of the working folder.
- `shared` holds only the norms. An `omp` seat projects no plugin and no runtime resource, and the
  shared pool of OpenRig's own specs is for Claude Code and Codex seats.
- Each `agent.yaml` sets `model: anthropic/claude-sonnet-5-5` in `defaults`. The roles of
  `hermes/omp.yml` (Haiku for side tasks) still apply inside the seat.
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

## What is not done

- **No public web page by default.** The UI runs on loopback only. The vhost is off (see "The web UI").
- **No `rig setup`.** It installs tools and edits `~/.tmux.conf`. The deny list blocks it.
- **No herdr, no remote hosts.** `rig host`, `rig up --host` and pairing are blocked.
- **No Claude Code or Codex seat.** `claude` is unfree and not installed. Seats use `omp`.
- **No `PrivateDevices`.** In a test with a user unit, tmux could not start a pane with a private
  `/dev`. A pane needs a pseudo terminal. The test used a user manager, not the system manager, so
  the cause may be the test. The unit leaves `PrivateDevices` off.
- **No `gateway` or `slack` rule.** They contact people. The skill `hermes-rig` and the norms say
  to ask the owner first. The deny list has no rule for them.

## Not tested

I could not test these. Check them after the first deploy. The reference lists the seat settings
that were not checked on the box.

- A start of the real unit: `ProtectSystem=strict` with the real `StateDirectory`, the user
  `openrig` and `RuntimeDirectory`. The test used a user unit with the same properties, and a
  scratch folder.
- The root step that copies the token, and the read of the file by `EnvironmentFile=-` after it.
  The test read no secret.
- A real seat: its start, its first turn, the messages between builder and reviewer, the delivery
  of the startup files, the merge of the norms into `AGENTS.md`, and the `model` of the AgentSpec.
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
