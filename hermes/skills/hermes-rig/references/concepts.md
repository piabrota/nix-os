# Concepts

The words of OpenRig, as they apply on this box.

## The parts

|Word|Meaning|Here|
|---|---|---|
|Daemon|One process that keeps the state in SQLite and serves an HTTP API. The `rig` CLI is its client.|The unit `openrig`, on `127.0.0.1:7433`. systemd starts and stops it.|
|Rig|A team with a purpose. It has a name, pods and edges.|`piabrota-dev`.|
|Pod|A group of seats with one domain. The pod id must not hold a dot or `@`.|`dev`.|
|Seat (member)|A role in a pod. It is durable: the seat stays when the program in it changes. Its logical id is `pod.member`.|`dev.builder`, `dev.reviewer`.|
|Occupant|The program that fills a seat now. A new occupant keeps the seat's address and queue.|One `omp` run.|
|Node|The stored row for a seat. Output and the API say "node" where this file says "seat".|One per seat.|
|Session name|`pod-member@rig`. It is the address for `rig send`, `rig capture` and the rest.|`dev-builder@piabrota-dev`.|
|Edge|A typed link between two seats: `delegates_to`, `spawned_by`, `can_observe`, `collaborates_with` or `escalates_to`. The first two set the start order.|`delegates_to` from builder to reviewer.|
|Spec|A YAML file that describes a rig (RigSpec) or an agent (AgentSpec).|`/etc/openrig/specs`. See `rig-spec.md`.|
|Snapshot|A saved record of a rig's topology and resume data. `rig down --snapshot` and `rig snapshot` make one.|Used by `rig up <rig> --existing`.|
|Runtime|What a seat runs: `omp`, `pi`, `claude-code`, `codex`, `terminal`, `stub`, or a community harness. See `runtimes.md`.|`omp`.|
|tmux session|Every seat is one tmux session, named as the seat. The daemon types into it and reads it.|The tmux server runs inside the unit.|
|Queue item|A durable work item with an owner seat. `rig queue create` makes one.|Optional.|

A rig name is also a spec name. `rig up <spec path>` on a name that exists replaces the stopped
rig with a new generation: the old one is archived. `rig up <rig> --existing` instead restores the
stopped rig and resumes the conversations. Use the second form after a deploy.

## Instance layout

The daemon keeps its state under `OPENRIG_HOME`. On this box that is `.openrig` in the home of the
`openrig` user, owned by that user (mode 0700). You cannot read it, and the deny list blocks its
path. The top-level entries are:

|Entry|Holds|
|---|---|
|`config.json`|Typed settings. It starts as an empty object.|
|`state/`|Durable runtime state. An `omp` seat has `state/omp/<seat>/agent` and `sessions/`.|
|`context/`, `skills/`|The context library and the managed skill catalog.|
|`workspace/`|The project work tree (`SPEC.md`, `project.yaml`, missions).|
|`specs/`, `topology/`, `plugins/`|The spec library; the continuity tree; installed plugins.|
|`run/`, `logs/`, `transcripts/`|Process files; daemon logs; per-seat terminal transcripts.|
|`backups/`, `secrets/`|Recovery files; connector and host secrets.|

The SQLite file is `openrig.sqlite` in the same folder. The seats' working folder is a separate
folder of the unit (`work`), where the specs point `cwd`.

## States you will read

`rig ps --nodes` shows one row per seat. `rig ps --nodes --full` adds more columns, and it also
shows resume tokens, so do not paste it.

**Lifecycle** (column LIFECYCLE, short form in brackets):

|State|Meaning|
|---|---|
|`running` (`run`)|The process exists.|
|`detached` (`det`)|The seat has no live session now. After `rig seat stop` this is what you see.|
|`recoverable` (`rec`)|The seat can come back from a snapshot.|
|`attention_required` (`att`)|Something blocks the seat. Read the REASON column and the pane.|
|`stopped` (`stp`)|A rig-level state: every seat is stopped on purpose.|

**Activity** (column ACTIVITY): `working`, `idle-at-prompt`, `unknown`, and "needs-input", which
shows when at least one prompt is open. `unknown` means "the daemon cannot tell". For `omp` and
`pi` seats the runner posts each turn boundary. A quiet pane is never read as idle on its own. A
working boundary that is not renewed becomes `unknown` after about 15 seconds. In a test, a
stopped terminal seat still showed `working`: treat ACTIVITY as a hint, and read the pane.

**Startup** (STARTUP): `pending`, `ready`, `attention_required`, `failed`. `ready` means startup
ended. It does not mean the seat is oriented or has read its role. After a failure, a monitor
marks a seat `ready` again when its pane looks ready, so also read the pane.

**Oriented** (ORIENTED): `verified`, `missing`, `rejected`, `n-a`. Only a startup proof sets it. A
missing proof does not block startup.

**Restore outcome** (RESTORE): `resumed`, `fresh-primed`, `awaiting-decision`,
`attention_required`, `failed`, plus `rebuilt` and `operator_recovered`. `awaiting-decision` is the
case of an `omp` seat that never finished a turn: it has no session file to resume. Start it with
`rig seat launch <seat> --fresh --reason "<why>"`.

**Attention codes** (REASON; they come from Claude Code and Codex): `trust_gate`,
`hook_trust_gate`, `update_gate`, `login_required`, `mcp_gate`, `bypass_consent_gate`,
`codex_auth_refusal`, `codex_client_incompatible`. For an `omp` seat, attention comes from a
cancelled approval request or an extension dialog, or from a model error.

**Derived diagnoses.** `rig parked` says whether stopped seats owe work. HELD is a deliberate stop
with a live wake: it is healthy. PARKED is a stop by accident.

## How a message reaches a seat

`rig send` pastes the text into the tmux pane, waits, then presses Enter. It adds a From and To
envelope for agent seats, and none for a terminal seat. From outside a seat the From line reads
"unknown sender". The send is refused only when the pane shows a prompt. A busy seat gets the text
with an advisory. `--verify` checks that the text appeared in the pane. It is not an answer from the
agent.

Source: `docs/reference/topology-naming.md`, `agent-state-taxonomy.md`, `instance-layout.md`,
`seat-delivery.md`, `rig-spec.md` of OpenRig `v0.7.7`; `rig ps`, `rig send` and `rig seat` help of
the built binary; a test with a terminal seat in a scratch daemon, 2026-11-04.
