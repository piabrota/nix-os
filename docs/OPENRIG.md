# OpenRig on piabrota2

English only. The files are `openrig.nix`, `openrig/package.nix` and `openrig/specs/`.

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
|Network|The daemon listens on `127.0.0.1:7433` (`OPENRIG_BIND_HOST`). No nginx, no firewall port, no ACME. The web page of OpenRig is not shown.|
|Path|`tmux`, `bash`, `git`, `ps` and `lsof` (the daemon reads the process table), `node` (the daemon types `node ...` in each seat's pane), `rig` and the seat `omp` shim. NixOS adds `coreutils`, `findutils`, `grep`, `sed`.|
|Hermes|A `rig` command in the packages of `hermes-agent`. It sets `OPENRIG_URL=http://127.0.0.1:7433` and runs the real `rig`.|
|Sandbox|`NoNewPrivileges`, `CapabilityBoundingSet=""`, `ProtectSystem=strict`, `ProtectHome`, `PrivateTmp`, `ProtectKernel*`, `ProtectProc=invisible`, `RestrictNamespaces`, `LockPersonality`, `SystemCallFilter=@system-service ~@privileged` with `EPERM`, and `RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK`.|
|Restart|`Restart=on-failure`, `RestartSec=10s`, at most 5 starts in 600 s. After that the unit stays down.|

Four facts shaped this design. Each one came from the source of OpenRig 0.7.7 or from a test.

1. **The CLI needs no state file.** With `OPENRIG_URL` set, `rig` talks to the daemon over HTTP and
   reads no file of the daemon's state. The `hermes` user has no access to `/var/lib/openrig` (mode
   0700), and it needs none. The owner-user check of the CLI runs only on macOS. So any local user
   who can reach port 7433 can use the daemon. This is why the port stays on loopback and why the
   deny list blocks `OPENRIG_URL=`, `OPENRIG_HOME=` and `/var/lib/openrig` in Hermes's commands.
2. **The built-in "kernel" rig cannot start here.** It needs a logged-in Claude Code or Codex.
   `claude` is unfree and Codex is not installed. The unit sets `OPENRIG_NO_KERNEL=1`. Without it
   the daemon reports `Kernel: auth_blocked` at each start.
3. **A seat does not inherit the environment.** The runner of OpenRig gives each seat only `PATH`,
   `HOME`, `USER`, `TERM`, `LANG`, `SHELL`, `TMPDIR` and a few `OPENRIG_*` names, plus the key
   variable of the model's provider. `CLAUDE_CODE_OAUTH_TOKEN` and `ANTHROPIC_OAUTH_TOKEN` never
   cross, and `HOME` is the seat's own folder. So the unit puts its own `omp` first on its path.
4. **The `omp` wrapper of Hermes does not fit a seat.** `omp/wrapper.nix` stops every run after
   35 minutes. A seat lives for days. The shim in `openrig.nix` keeps the read-only overlay
   `hermes/omp.yml` (its bash deny rules) and `choom`, and drops the 35-minute limit and the
   appended prompt (`hermes/omp-append-system.md`, written for one-shot runs of Hermes).

### The token of the seats

The seats use the Claude subscription of the owner, as Hermes does. The flow:

1. At each start of the unit, a root step (`ExecStartPre=-+...`) copies one line,
   `CLAUDE_CODE_OAUTH_TOKEN=...`, from `/var/lib/hermes-secrets/hermes.env` to
   `/var/lib/openrig-secrets/.env`. Only the `openrig` user reads that file (mode 0600, folder 0700).
   The step prints nothing: `grep` writes to the file and its errors go to `/dev/null`.
2. The `omp` shim reads the line from that file, removes quotes, sets `ANTHROPIC_OAUTH_TOKEN`, and
   starts `omp`. The daemon never holds the token in its environment.
3. If the line or the source file is missing, the file is empty. The unit still starts. The seats
   then fail to log in.

A seat can read the file, as it can read the environment of its own `omp`. The rules of `omp.yml`
deny `env`, `printenv`, `*/.env*` and `/proc/*/environ`. The file name `.env` falls under the
second rule. This is a barrier of rules, not a wall. The seat norms say: never read a secret.

## Packaging

`openrig/package.nix` builds OpenRig from source (the tag `v0.7.7`, commit `f3d8bac4...`) with
`buildNpmPackage`. The source hash and the hash of the npm dependencies are fixed. No prebuilt
binary is used. The native addon `better-sqlite3` is compiled from its bundled source. The web UI is
not built. The package has the layout of the npm package `@openrig/cli`, so `rig` finds its daemon.
No script of an npm package runs at build time. `nodejs_24` is the one Node on the box, and only
OpenRig uses it. The owner accepts Node.js for OpenRig (the rule 4 of `AGENTS.md` says so).

## Limits

|Setting|Value|
|---|---|
|`MemoryMax`|2G for the whole unit|
|`MemoryHigh`|1536M|
|`CPUWeight`|50|
|`TasksMax`|2048|
|`OOMPolicy`|`continue`: an OOM kill takes one process, not the unit|

Tmux and every seat run in the cgroup of the unit. `MemoryMax` is one budget for the daemon, tmux
and all seats. An `omp` seat uses about 340 MiB when it works. The idle daemon peaked at 186.7 MiB in
the sandbox test of 2026-11-04, and tmux adds a few MiB. The kernel slows the unit above
`MemoryHigh` (1536 MiB), so that is the working limit: the daemon and tmux (about 200 MiB) plus two
working seats (about 680 MiB) use about 880 MiB. The plan is **two seats at the same time**, the
builder and the reviewer. The rest (about 650 MiB) is room for a seat that grows during a large edit
and for the page cache of a git clone, which counts against the unit. A third seat adds 340 MiB. It
fits under `MemoryHigh` on paper, but it leaves about 300 MiB of room. Add it only after
`kvm4-health` shows that the peak of `openrig` stays well under 1536 MiB. The shim runs `omp` under
`choom -n 500`, so the kernel picks a seat before the daemon.

The `MemoryMax` values on piabrota2 sum to **12.25 GiB**: `hermes-agent` 8G, `hermes-backend` 2G,
`openrig` 2G, `pgx` 256M (`nix eval` of `systemd.services.*.serviceConfig.MemoryMax`, 2026-11-04).
The machine has 15.6 GiB. A cap is a ceiling, not a use. The real use is about 1.7 GiB. The sum was
10.25 GiB before OpenRig, and it was 13.25 GiB when the cap of `openrig` was 3G. Run `kvm4-health`
before you start a large rig: it lists the unit `openrig`.

## What a deploy does to the seats

A deploy that changes the unit restarts `openrig`. `KillMode=control-group` stops the daemon, tmux
and every seat. A seat ends in the middle of its turn. After the restart nothing starts a rig.
Bring a rig back from its snapshot with:

```console
rig up piabrota-dev --existing
```

An `omp` seat that has not yet finished one turn has no session file to resume. OpenRig then asks
for a decision. Start that seat fresh with `rig seat launch <seat> --fresh --reason "<why>"`.

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
  `reviewer`. The policy is `none` (the floor): see "Not done" below.
- Each `agent.yaml` imports `shared`, selects `shared:norms` as guidance, and sends `role.md` and
  `startup/context.md` to the seat as text. The norms land in the `AGENTS.md` of the working folder.
- `shared` holds only the norms. An `omp` seat projects no plugin and no runtime resource, and the
  shared pool of OpenRig's own specs is for Claude Code and Codex seats.
- The model comes from `hermes/omp.yml` (Sonnet for work, Haiku for side roles), not from the spec.
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

- **No web page.** The UI of OpenRig is not built and not exposed.
- **No `rig setup`.** It installs tools and edits `~/.tmux.conf`. The deny list blocks it.
- **No herdr, no remote hosts.** `rig host`, `rig up --host` and pairing are blocked.
- **No Claude Code or Codex seat.** `claude` is unfree and not installed. Seats use `omp`.
- **No `PrivateDevices`.** In a test with a user unit, tmux could not start a pane with a private
  `/dev`. A pane needs a pseudo terminal. The test used a user manager, not the system manager, so
  the cause may be the test. The unit leaves `PrivateDevices` off.
- **No policy that turns off prompts.** The rig spec says `permission_policy: none`. The deny list
  blocks `rig seat set-permissions`, `rig policy apply`, `--policy`, `--permission-mode`,
  `--non-interruptive`, `--dangerously-interact` and `OPENRIG_YOLO` for Hermes.
- **No `gateway` or `slack` rule.** They contact people. The skill `hermes-rig` and the norms say
  to ask the owner first. The deny list has no rule for them.

## Not tested

I could not test these. Check them after the first deploy.

- A start of the real unit: `ProtectSystem=strict` with the real `StateDirectory`, the user
  `openrig` and `RuntimeDirectory`. The test used a user unit with the same properties, and a
  scratch folder.
- The root step that copies the token, and the read of `/var/lib/openrig-secrets/.env` by the shim.
  The test read no secret. A fake token reached `omp` and its RPC mode answered `get_state` with
  the model `anthropic/claude-sonnet-5-5`.
- A real seat: its start, its first turn, the messages between builder and reviewer, the delivery
  of the startup files and the merge of the norms into `AGENTS.md`.
- Whether the approval mode `always-ask`, which the runner passes to a seat, overrides
  `tools.approvalMode: yolo` of `hermes/omp.yml`. OpenRig says a headless seat cancels the requests
  that need an answer. If a seat cannot run a tool, this is the first cause to check.
- `rig daemon status` and `rig daemon logs` from the `hermes` user. They may read files in the
  state folder. Use `journalctl -u openrig` (with the `observer` account) for the daemon log.
- A full system build and the deploy. A build of the unit file and an evaluation ran.

## Update

Edit `openrig/package.nix`: change `version` and `commit` (the commit of the new tag), set both
hashes to `lib.fakeHash`, build, and copy each real hash from the error. The names are `hash` in
`src` and `npmDepsHash`. Check that `scripts/build-package.sh` of the new tag still matches the build
steps in the package, and run `rig spec validate` on the specs. Update the version in this file
and in `AGENTS.md`.

## Turn it off

Set `piabrota.openrig.enable = false;` in `hosts/piabrota2/default.nix`. The deploy stops the unit.
The state stays in `/var/lib/openrig`, and the token copy stays in `/var/lib/openrig-secrets`.
Delete both by hand on the box if you want them gone. Hermes then has no `rig` command.
