# Commands of `rig`

The map of every command of `rig` 0.7.7, from its real `--help` tree (90 top-level commands, 411
commands in all). A flag is named only where an operator needs it. For any other flag, run
`rig <command> --help`: that text is the truth, and this file is only a map.

Column "Hermes":

- **allowed**: you may run it.
- **owner**: ask the owner first. It changes a setting, contacts people, runs foreign code, adds
  seats beyond the plan, or has no use on this box.
- **denied**: `hermes/dangerous-patterns.yaml` blocks it. Do not look for a way round.

The `rig` on your PATH is a wrapper that aims the real CLI at the daemon on 127.0.0.1:7433. Never
set `OPENRIG_URL`, `OPENRIG_HOME` or `OPENRIG_DB` yourself (denied).

Seat names have the form `pod-member@rig`. In `piabrota-dev`: `dev-builder@piabrota-dev` and
`dev-reviewer@piabrota-dev`. The logical form is `pod.member`, for example `dev.builder`.

## Daemon and host

|Command|Use|Hermes|
|---|---|---|
|`rig status` (`--json`)|Is the daemon up, its port, the rigs. Prints "Daemon not running." and exits 0 when it is down.|allowed|
|`rig daemon status`|One line: running or not, and the port.|allowed|
|`rig daemon logs` (`--follow`)|Reads the daemon's own log files. Over the wrapper it printed "No daemon logs found". Use `journalctl -u openrig`.|allowed (useless here)|
|`rig daemon start`, `rig daemon stop`|Start or stop a daemon. systemd owns the daemon.|denied|
|`rig start`|Start the daemon and restore the rigs that ran last.|denied|
|`rig setup`|Install tools and edit `~/.tmux.conf`.|denied|
|`rig destroy` (`--state`, `--all`)|Erase local OpenRig state and tmux sessions.|owner (never needed)|
|`rig config` (`get`, `set`, `reset`, `init-workspace`)|`rig config` and `rig config get <key>` read. `set`, `reset` and `init-workspace` change settings.|read allowed, write owner|
|`rig preflight`, `rig doctor` (`--spec <path>`)|Read-only checks. On this box `doctor` shows known FAIL rows (the [reference](../../hermes-omp/references/openrig-seats.md)). Its fix line "Run `rig setup`" is denied for you.|allowed|
|`rig crash-cart`|Read-only JSON verdict for a daemon that is down.|allowed|
|`rig host` (`add`, `select`, `rename`, `pair`, `list`, `doctor`), any `--host <id>`|Other machines over SSH or pairing.|denied|
|`rig file copy`|Copy files across hosts.|owner|
|`rig ui open`, `rig tui`, `rig terminal` (`open`, `views`, `status`)|Browser, dashboard and desktop tiles. The web UI is served on `127.0.0.1:7433` for the owner (SSH tunnel). There is no desktop here.|owner (no use)|

## Rigs and seats

|Command|Use|Hermes|
|---|---|---|
|`rig up <spec>` (`--plan`)|Start a rig from a spec path. Without `--plan` it starts a daemon if it cannot reach one: see `safety.md`.|allowed for `/etc/openrig/specs`, only with a live daemon|
|`rig up <rig> --existing`|Bring a stopped rig back from its snapshot.|allowed|
|`rig up` with `--fresh <seats...>`, `--name <rig>`, `--cwd <path>`, `--env K=V`, `--yes`|Fresh-start named seats; run the spec under another name; override the folder; add an environment value (never a secret); auto-approve trusted actions.|owner|
|`rig up` with a GitHub link or a `.rigbundle`, `--target`, `--preset`, `--seat`|Runs code from outside.|owner|
|`rig up` with `--non-interruptive`|Accepts a harness's first-launch warnings at full bypass.|denied|
|`rig ps` (`--json`, `--nodes`, `--rig <name>`, `-A`, `--filter k=v`, `--active`, `--fields`, `--summary`, `--limit`, `--include-archived`, `--resources`, `--session`)|The rigs, or with `--nodes` the seats. `--full` also shows resume tokens: never paste it.|allowed|
|`rig down <rig>` (`--snapshot`, `--json`)|Stop every seat of a rig. Follow `operations.md`.|allowed, after the checks|
|`rig down` with `--delete`, `--force`|Erase the rig record, or kill the sessions at once.|owner|
|`rig snapshot <rig>`, `rig snapshot list <rig>`|Save a rig's topology and resume data; list snapshots.|allowed|
|`rig restore <snapshotId> --rig <rig>`, `rig restore status <attemptId> --rig <rig>`|Restore from a named snapshot; read one attempt.|allowed|
|`rig restore-check` (`--rig`, `--json`)|Read-only: can each rig be restored.|allowed|
|`rig launch <rig> [nodeRef]` (`--seats`, `--plan`, `--snapshot-id`)|Start a node of a running rig that is not running.|allowed (use `--plan` first)|
|`rig archive <rig>`, `rig unarchive <rig>`|Hide or show a rig. Reversible. `--force` archives a running rig.|allowed; `--force` owner|
|`rig export <rig>` (`-o <path>`), `rig spec show <rig-id>`|Write the spec that rebuilds a live rig.|allowed|
|`rig import <path>`|Import a spec (`--instantiate` starts it).|owner|
|`rig expand`, `rig add`, `rig grow`, `rig create`, `rig remove`, `rig shrink`, `rig edge add`, `rig edge remove`|Change a live rig: add a pod, a member or seats; remove them; edit edges. `grow` and `create` default to the runtime `claude-code`, so they need `--runtime omp`. The specs are the source of truth.|owner|
|`rig discover`, `rig discover --draft`|List tmux sessions that OpenRig does not manage; draft a spec.|allowed|
|`rig bind`, `rig adopt`, `rig attach --self`, `rig release`, `rig unclaim`, `rig reconcile-session`|Take over, or let go of, a live tmux session.|owner|
|`rig mode`, `rig whoami`|Read the operating posture; read the identity of the shell. From outside a seat, `whoami` has no identity.|allowed|

## Seats (`rig seat`)

|Command|Use|Hermes|
|---|---|---|
|`rig seat status <seat>` (`--json`)|Read-only state: session, startup, occupant, last handover.|allowed|
|`rig seat held-messages <seat>`, `rig seat history`, `rig seat effort <seat>`|Read held messages, resume candidates, effort settings.|allowed|
|`rig seat stop <seat>` (`--reason`)|Stop one live seat. Capture it first.|allowed|
|`rig seat clean <seat>` (`--reason`)|Make a dead seat launchable again.|allowed|
|`rig seat launch <seat> --fresh` (`--plan`, `--stop`, `--reason <text>`)|Start a blank occupant in a seat. `--plan` previews; `--stop` replaces a live one.|allowed (`--stop` after a capture)|
|`rig seat clear-attention <session>` (`--reason`)|Record that an attention cause is gone. Read the pane first.|allowed|
|`rig seat set-permissions`|Choose a seat's native permissions.|denied|
|`rig seat set-cwd`, `set-model`, `set-effort`, `set-typing-guard`, `set-terminal-policy`, `set-resume-token`, `retire-held-message`, `switch-client`, `continue`|Change a seat's saved settings or continue startup. `set-resume-token` reads a token from stdin.|owner|
|`rig seat set-runtime`, `rig seat restart`|Move a seat between Claude Code and Codex; restart a Codex seat. Neither exists here.|owner (no use)|
|`rig seat handover <seat>`, `rig handover <seat>`|Hand a seat to a successor.|owner|

## Messaging and reading

|Command|Use|Hermes|
|---|---|---|
|`rig send <seat> "<text>"` (`--verify`, `--wait-for-idle <s>`, `--raw`, `--urgent`, `--json`)|Type a message into a seat's pane. A seat at a prompt refuses it. `--verify` proves only that the text reached the pane.|allowed|
|`rig send --to a,b`, `--pod <name>`, `--rig <name>`|Send to several seats.|allowed|
|`rig send` with `--dangerously-interact`, `--type-without-checking`|Type keystrokes into a prompt.|denied|
|`rig capture <seat>` (`--lines <n>`, `--readable`, `--size WxH`, `--rig`, `--pod`, `--json`)|Read the pane: the screen and some history.|allowed|
|`rig transcript <seat>` (`--tail <n>`, `--grep <regex>`, `--json`)|Read the seat's recorded terminal output.|allowed|
|`rig broadcast "<text>"` (`--rig`, `--pod`, `--context <ref>`)|Send to many seats. With neither `--rig` nor `--pod` it goes to all running seats.|allowed with `--rig`; bare owner|
|`rig ask <rig> "<question>"` (`--seat`, `--session`)|Search past transcripts. Read-only.|allowed|
|`rig ask` with `--wake <target>`|Wakes an agent to answer. It runs `claude` or Codex.|owner (no use)|
|`rig queue create` (`--source`, `--destination`, `--summary`, `--body-file <path>`, `--priority`)|Put a work item on a seat's queue. `--source hermes@external` names the sender. Good for long task text.|allowed|
|`rig queue list`, `rig queue show <id>`, `rig queue inbox-pending`, `rig queue overdue`, `rig queue undelivered`|Read the queue.|allowed|
|`rig queue` others: `claim unclaim update block resolve handoff handoff-and-complete whoami fallback transitions inbox-drop inbox-absorb inbox-deny outbox-record outbox-list`|Seat-side workflow of a work item.|owner|
|`rig walk <seat>`, `rig chatroom` (`send history watch topic wait clear`)|Paced context; a rig chat room.|owner|

## Snapshots and recovery

`rig snapshot`, `rig restore`, `rig restore-check`, `rig up <rig> --existing`, `rig crash-cart` and
`rig seat launch --fresh` are in the tables above. Two more read-only views:

|Command|Use|Hermes|
|---|---|---|
|`rig parked` (`--rig <rig>`, `--json`)|Are stopped seats owing work? Derived at read time.|allowed|
|`rig health` (`--rig <id>`, `--instance`, `--severity`, `--json`; `explain`, `policy`, `checkpoint`, `diagnose`, `diagnosis`)|Read-only health findings. "This is not a healthy assertion" when empty. `diagnose --apply` writes context.|read allowed|

## Discovery and diagnostics

|Command|Use|Hermes|
|---|---|---|
|`rig usage` (`top`, `cost`, `series`), `rig telemetry` (`events`, `transitions`, `tenures`)|Token burn per seat; retained metadata.|allowed|
|`rig roster` (`list`, `show`, `find`)|Find specialist seats across rigs.|allowed|
|`rig workspace` (`validate`, `doctor`)|Check a workspace root.|allowed|
|`rig env` (`status`, `logs`, `down`)|Environment services of service-backed rigs. `piabrota-dev` has none.|owner|
|`rig heartbeat`, `rig scope`, `rig proof` (`show`, `judge`, `add`), `rig startup-proof submit`|Workflow proof and scope records. Seat-side tools.|owner|

## Specs and bundles

|Command|Use|Hermes|
|---|---|---|
|`rig spec validate <path>`|Syntax check of a RigSpec. No daemon needed. Does not resolve agent paths.|allowed|
|`rig spec preflight <path>`, `rig spec audit <path>`|Preflight diagnostics; advisory audit.|allowed|
|`rig agent validate <path>`|Syntax check of an `agent.yaml`. Needs the daemon. Does not resolve imports or find files.|allowed|
|`rig requirements <spec>`|Check what a spec needs.|allowed|
|`rig specs ls` (`--kind`), `rig specs show <name>`, `rig specs preview <name>`|Browse the spec library.|allowed|
|`rig specs add`, `sync`, `remove`, `rename`|Change the user library.|owner|
|`rig bundle inspect <path>`|Inspect a local `.rigbundle`. With a GitHub link it builds from the network.|local file allowed; link owner|
|`rig bundle create`, `install`, `check`, `history`, `configurations`, `rig bootstrap <spec>`, `rig package` (`validate plan install rollback list`)|Make, install or bootstrap from bundles and legacy packages.|owner|

## Context, skills and harnesses

|Command|Use|Hermes|
|---|---|---|
|`rig context` (`list`, `show`, `preview`, `get`, `compose`, `profile`, `trace`)|Read context packs.|allowed|
|`rig context` (`work-install`, `recap-write`, `sync`, `add`, `source`, `rm`)|Change the context library.|owner|
|`rig skill` (`loadout`, `audit`), `rig plugin` (`list`, `show`, `used-by`, `validate`)|Read skill and plugin state.|allowed|
|`rig community-harness list`|List installed harness presets.|allowed|
|`rig agent-image` (`list show preview create delete pin unpin prune sync`), `rig fork <session>`|Saved images and forks of seats.|owner|
|`rig policy` (`permissions`, `list`, `show`, `current`)|Read permission policy.|allowed|
|`rig policy apply`|Apply a permission policy.|denied|
|`rig compact`, `rig compact-plan`|Claude-only compaction. No Claude seat here.|owner (no use)|
|`rig restore-packet` (`write`, `read`, `validate`)|Cross-runtime restore packets.|owner|

## Contact and network surfaces

|Command|Use|Hermes|
|---|---|---|
|`rig gateway` (`human`, `channel`, `org`, `group`, `participants`, `default`), `rig slack` (`setup status manifest verify channel-map enable post-open-asks disable outbound inbound`)|Registry and connectors that reach people.|owner|
|`rig mcp serve` (`--http`), `rig mcp token`|An MCP server and its grants. `--http` opens a second port.|owner|
|`rig acp` (`run`, `cancel`, `stop`)|Hand a queue row to an ACP agent.|owner|
|`rig auth` (`status list save switch validate seats`), `rig provider` (`status accounts bindings signals precheck switch moves`)|Login profiles and provider accounts of Codex and Claude. Tokens are never printed.|owner (no use)|
|`rig stream`, `rig project`, `rig view`, `rig watchdog`, `rig workflow`|The coordination layers. `rig view list` and `rig view show` read. The others, such as `rig watchdog register`, `rig workflow run` and `rig stream emit`, schedule or wake seats and spend tokens.|view read allowed; rest owner|

Subcommands of the last row: `stream` (`emit list watch show archive subscribe unsubscribe
subscriptions read act`); `project` (`experimental decisions candidates wake shadow-status
shadow-drain shadow-stop lease-acquire lease-heartbeat lease-show reclaim-classifier classify list
show`); `view` (`list show register`); `watchdog` (`register list show status stop update`);
`workflow` (`validate compile revise operation instantiate-lifecycle instantiate project list specs
guidance show trace continue run watch route resume abort status`).

Source: `rig --help` and `rig <command> --help` of the built OpenRig `v0.7.7` (every command walked
on 2026-11-04); `docs/reference/rig-spec.md` and `agent-spec.md`; `hermes/dangerous-patterns.yaml`.
