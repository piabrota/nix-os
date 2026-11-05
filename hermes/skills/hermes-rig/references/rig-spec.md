# RigSpec and AgentSpec: what an operator writes

Version 0.2 of the RigSpec. The real specs of this box are in `openrig/specs/` of piabrota/nix-os.
The module installs them, read-only, at `/etc/openrig/specs`. This file explains their layout and
how to change them. It has no second example: read the real files.

A spec change is a pull request to piabrota/nix-os. You cannot edit `/etc/openrig/specs`, and a
deploy replaces it. Ask the owner for a change that is not yours to make.

## The layout on this box

```text
/etc/openrig/specs/
  rigs/piabrota-dev/rig.yaml        the rig: one pod "dev", two members, one edge
  agents/shared/agent.yaml          declares one guidance resource, "norms"
  agents/shared/guidance/norms.md   the rules of every seat
  agents/builder/agent.yaml         the builder: imports shared, profile "default", startup files
  agents/builder/guidance/role.md   the builder's role (sent to the seat as text)
  agents/builder/startup/context.md limits of the box (sent as text)
  agents/reviewer/...               the same three files for the reviewer
  rigs/wave-forecaster-dev/rig.yaml            pod "port": porter and auditor
  rigs/wave-forecaster-dev-integrate/rig.yaml  pod "wire": integrator and auditor
  agents/wf-shared/...              the norms for h0ffmann/chaceon, imported after shared
  agents/wf-porter/, wf-auditor/, wf-integrator/   the three files of each seat
```

|File|Its job|
|---|---|
|`rig.yaml`|Names the rig and lists the members. It sets no permission policy: the unit decides. Each member says which agent folder it uses (`agent_ref`), which profile, which runtime (`omp`) and which working folder (`cwd`, the `work` folder of the unit). The `delegates_to` edge makes the builder start before the reviewer.|
|`agents/<name>/agent.yaml`|Describes one agent: its default runtime, what it imports, its profile, and its startup files.|
|`agents/shared/agent.yaml`|A pool that other agents import. It holds only the norms. An agent selects it with `guidance: [shared:norms]`.|
|`guidance/norms.md`|Merged into the `AGENTS.md` of the seat's working folder, so every `omp` seat reads it.|
|`guidance/role.md`|The role. It is delivered as a startup file with `delivery_hint: send_text` and `orientation: role`, so one seat's role never replaces another's in the shared `AGENTS.md`.|
|`startup/context.md`|Text sent after the seat is ready: the limits of the box.|

The model of a seat is `defaults.model` in its `agent.yaml` (`anthropic/claude-sonnet-5-5`, the form
for which the runner passes the key; see the
[reference](../../hermes-omp/references/openrig-seats.md)). The tool rules of a seat do not come
from the spec. They come from `hermes/omp.yml`, through the seat's `omp` wrapper.

## RigSpec fields

Required: `version` (use `"0.2"`), `name`, `pods` (at least one).

|Field|Notes|
|---|---|
|`summary`|Text for people.|
|`permission_policy`|`builtin:locked`, `builtin:standard`, `builtin:open`, `builtin:yolo`, `builtin:auto`, a relative path to a policy file, or `none` (the floor, recorded as a choice). A bare name such as `yolo` is refused. `piabrota-dev` sets `builtin:yolo` by the owner's decision (PR 124): do not change it. A rig with no policy gets the floor, and `OPENRIG_YOLO=1` does not widen it.|
|`env`|`NAME: value` pairs for every seat. The value is not secret. Names that start `OPENRIG_` are reserved.|
|`startup`, `culture_file`, `docs`, `workspace`, `services`, `managed_blocks`, `non_interruptive`|Optional. `non_interruptive` accepts harness warnings: do not set it.|
|`edges`|Cross-pod edges. Use `pod.member` on both ends.|

Pod: required `id` (no dot, no `@`), `label`, `members`. Optional `summary`, `startup`, `edges`
(pod-local; use the plain member id), `continuity_policy`.

Member: required `id`, `agent_ref`, `profile`, `runtime`, `cwd`. `agent_ref` starts with `local:`
(relative to the rig spec's folder, not to your shell) or `path:` (absolute); the folder must hold
an `agent.yaml`. Optional: `label`, `model`, `effort`, `role`, `env`, `permission_policy`,
`restore_policy` (`resume_if_possible`, `relaunch_fresh`, `checkpoint_only`; a member may only
narrow the agent's), `startup`, `session_source`, `starter_ref`. A relative `cwd` resolves against
the rig spec's folder. The fields for `claude-code`, `codex` and Pi (`agent_file`, `plugin_dirs`,
`codex_permissions` and the like) do not apply to `omp`.

Edge kinds: `delegates_to` and `spawned_by` set the start order. `can_observe`,
`collaborates_with` and `escalates_to` do not. The session name of a member is
`{pod}-{member}@{rig}`.

## AgentSpec fields

Required: `name`, `version` (quote it: `"1.0"`).

|Field|Notes|
|---|---|
|`description`|Text for people.|
|`defaults`|`runtime`, `model`, `effort`, `lifecycle`. The runtime of a seat comes from, in order: the member, the profile's `preferences.runtime`, `defaults.runtime`, then `claude-code`.|
|`imports`|List of `ref: local:<path>` or `path:<abs>`, with an optional exact `version`. An imported spec cannot import another. Use `namespace:id` (the imported spec's `name`) to pick its resource.|
|`resources`|The pool: `skills`, `guidance`, `subagents`, `plugins`, `runtime_resources`. Each has an `id` and a relative `path`. Nothing in the pool reaches a seat until a profile selects it.|
|`profiles`|A map. A profile has `summary`, `preferences`, `uses` (which resource ids it selects), `startup`, `lifecycle`.|
|`startup`|Files and actions for every profile.|

For an `omp` seat only `guidance` and `skills` matter. `omp` does no skill discovery on disk, so
every skill must be a declared resource. Subagents, plugins and runtime resources are not
projected. Guidance merges into `AGENTS.md` of the working folder. Resource paths are safe relative
paths: no `..`, no absolute path.

Startup files: `path`, `delivery_hint` (`auto`, `guidance_merge`, `skill_install`, `send_text`),
`required` (default true), `orientation: role`, `applies_on` (`fresh_start`, `restore`; default
both). Startup actions: `type` (`slash_command`, `send_text`, `startup_proof`), `value`,
`idempotent` (required), `phase`, `applies_on`. There is no shell action. Layers add up and never
replace: agent, profile, culture, rig, pod, member, then OpenRig's own operator layer. The
culture layer starts with OpenRig's default culture text for every seat. On a fresh start the
operator layer also sends onboarding text. Both come on top of your own files (from the docs, not run).

## The five jobs

**(a) Start the rig.**

```console
rig up /etc/openrig/specs/rigs/piabrota-dev/rig.yaml --plan     # read the plan
rig up /etc/openrig/specs/rigs/piabrota-dev/rig.yaml            # only if rig status shows a daemon
rig ps --nodes --rig piabrota-dev                               # LIFECYCLE run, STARTUP ready
```

**(b) Add an agent.** Add a folder `agents/<name>/` with an `agent.yaml` that imports
`local:../shared` and selects `shared:norms`, plus `guidance/role.md` and `startup/context.md`.
Add a member to the pod in `rig.yaml` with `agent_ref` set to `local:../../agents/<name>`, profile
`default` and runtime `omp`. Check the memory rule in `runtimes.md`: a third seat is a decision of
the owner. Open a pull request to piabrota/nix-os. After the deploy, a running rig does not change.
For a seat in a stopped rig, run the spec again (job a). To add the seat to a running rig, the
owner may use `rig add`.

**(c) Change a role.** Edit `agents/<name>/guidance/role.md`. After the merge and deploy, a running
seat still has its old text. Run `rig snapshot piabrota-dev`, then `rig down piabrota-dev`, then
`rig up <spec path>`. That starts a new generation with fresh conversations. The older
conversations stay in the snapshot.

**(d) Change a seat's runtime or `cwd`.** A change to `runtime` or `cwd` in `rig.yaml` does not
reach an existing seat. For a new generation, do job (c). For one seat's folder, `rig seat set-cwd
<seat> --cwd <absolute path> --reason "<why>"` saves it for the next launch. The seat that runs now
keeps its old folder. To switch, run `rig seat launch <seat> --fresh --stop --reason "<why>"`,
which starts a blank conversation. The path must be absolute. OpenRig makes it if it is missing, and the
`openrig` user must be able to write it. The unit can write only its `work` folder. `rig seat
set-runtime` moves a seat between Claude Code and Codex only, so it does not apply to `omp`. Both
`set-cwd` and a runtime change need the owner.

**(e) Validate before it runs.** Three levels, from the cheapest. These ran on 2026-11-04 against
a scratch daemon (port 47433, scratch `OPENRIG_HOME`) and the specs of this repository:

```console
$ rig spec validate rigs/piabrota-dev/rig.yaml
Rig spec valid: piabrota-dev
$ rig agent validate agents/builder/agent.yaml
Agent spec valid: builder v1.0
$ rig up rigs/piabrota-dev/rig.yaml --plan
  resolve_spec: ok
  preflight: ok
Status: planned
  warning: dev.builder: permission_policy absent; launch_posture=floor
  warning: dev.reviewer: permission_policy absent; launch_posture=floor
```

The two warnings came while the spec had no policy. `piabrota-dev` now sets `builtin:yolo`, so they
should go (not run). What each level catches, tested:

|Mistake|`spec validate`|`up --plan`|
|---|---|---|
|`agent_ref` names a folder that does not exist|passes|fails: "No agent.yaml found at ..." (exit 1)|
|`runtime: omx` (unknown)|passes|fails: "unsupported runtime" (exit 1)|
|A startup file named in `agent.yaml` is missing|passes|passes (not caught)|

So run `rig up <spec> --plan` for every change, and also check by hand that each path in each
`agent.yaml` exists. `--plan` starts no daemon: with no daemon running it refuses. A `--plan` that
passes is not proof that the seats start.

Source: `docs/reference/rig-spec.md`, `agent-spec.md` and `agent-startup-guide.md` of OpenRig
`v0.7.7`; `openrig/specs/` of piabrota/nix-os; `rig spec`, `rig agent`, `rig up` and `rig seat`
help of the built binary. The tests in (e) were run for real. Job (c) after a merge, and (d) with
`set-cwd`, are from the docs and the help, not run.
