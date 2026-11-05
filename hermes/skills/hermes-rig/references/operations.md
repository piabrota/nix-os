# Operations runbook

Seats of `piabrota-dev`: `dev-builder@piabrota-dev` and `dev-reviewer@piabrota-dev`. Run each
command from any folder: the `rig` on your PATH already points at the daemon.

Marks: **tested** means it ran in a scratch daemon on 2026-11-04 (a terminal seat, no model).
**From the docs** means it was not run.

## 1. Check health

```console
kvm4-health                                   # memory, peak and limit of the unit openrig
systemctl show openrig -p ActiveState -p SubState -p NRestarts -p MemoryCurrent -p MemoryPeak
rig status                                    # tested
rig ps                                        # tested: one row per rig
rig ps --nodes --rig piabrota-dev             # tested: one row per seat
```

Read the result:

- `rig status` prints "Daemon running on port 7433" and `Kernel: skipped`. The unit sets that on
  purpose (the [reference](../../hermes-omp/references/openrig-seats.md)).
- `rig status` prints "Daemon not running." and exits 0. `rig ps` and the other commands print
  "Daemon not running." and exit 1. **Stop here.** Do not run `rig up`: it would start a daemon
  of its own (see `safety.md`). Read `journalctl -u openrig -n 50 --no-pager`, then follow
  `troubleshooting.md`.
- A rig that is stopped does not show in `rig ps`. The footer says "not shown: 1 stopped". Use
  `rig ps --filter status=stopped` or `rig ps --include-archived`.
- `NRestarts` above 0 since the last deploy, or `ActiveState` not `active`: tell the owner.
- `rig doctor` shows FAIL rows for Claude Code and Codex. They are known here (the
  [reference](../../hermes-omp/references/openrig-seats.md)). A FAIL on `ui_dist` is not: tell the owner.

## 2. Start a rig and check every seat

```console
rig up /etc/openrig/specs/rigs/piabrota-dev/rig.yaml --plan   # tested (the plan only)
rig up /etc/openrig/specs/rigs/piabrota-dev/rig.yaml          # tested with a terminal rig
rig ps --nodes --rig piabrota-dev
rig seat status dev-builder@piabrota-dev                      # "Startup: ready"
rig capture dev-builder@piabrota-dev --lines 30
```

A seat is ready when all of these hold:

1. LIFECYCLE is `run` and ATTN is `no` in `rig ps --nodes`.
2. `rig seat status <seat>` says "Startup: ready". `ready` only means that startup ended.
3. `rig capture` shows the `omp` screen, and not a shell, an error or a login request.
4. The seat has acted on its role: ask a short question with `rig send` and read the answer.

The first wait is 30 seconds by default. An `omp` seat that is slow can show `failed` and then
`ready` when a monitor re-reads the pane (every 30 seconds). Read the pane before you decide. A
seat still on `attention_required`: see section 5. Then run `kvm4-health` and check the memory of
`openrig` with two seats up.

## 3. Read what a seat does

```console
rig capture dev-builder@piabrota-dev --lines 60       # the screen now (tested)
rig transcript dev-builder@piabrota-dev --tail 100    # recorded output (tested)
rig transcript dev-builder@piabrota-dev --grep "error|fail"
rig ask piabrota-dev "what did the builder change?"   # search past transcripts, read-only
rig ps --nodes --rig piabrota-dev --active            # only seats that work (tested)
```

`rig capture` reads the pane: the screen and a little history. `--lines N` shows the last N
lines. When it cuts lines, the activity may read "unknown": that is not idle. Over a seat that is
mid-turn, read a second time a few seconds later.

You cannot read the files in a seat's clone. The `work` folder of the unit belongs to the
`openrig` user (mode 0700) and the deny list blocks its path. To get a diff, ask the seat to print
it: "print `git diff --stat`, then `git diff`". Read it with `rig capture --lines 200` or
`rig transcript`. A long diff can be cut. Ask for it in parts. Tell the owner that this limit
exists when a task needs you to commit what a seat made.

## 4. Send a task and confirm delivery

Follow the task rules of `hermes-omp`: the goal, what done means, the checks to run and their
expected result, and this line: "Do not commit, push or open pull requests. When you finish, list
the changed files and the checks you ran, with their result."

```console
rig send dev-builder@piabrota-dev "<short task text>" --verify --wait-for-idle 60   # --verify tested
```

- A short task goes in `rig send`. Put the text in double quotes, and put no secret in it.
- A long task: write the text to a file in your own workspace, then use
  `rig queue create --source hermes@external --destination dev-builder@piabrota-dev --summary "<one line>" --body-file <file>`
  (the call was accepted in a test; its effect on an `omp` seat is from the docs, not run). The
  CLI reads the file, so the seat does not need access to your folder. A queue item names its
  sender; a plain `rig send` from outside a seat arrives from an "unknown sender".
- `--wait-for-idle 60` sends only after the seat shows idle. If it is still busy, nothing is sent
  and the exit code is 1. Then wait, or queue the task.
- `--verify` prints "Verified: yes" and "Delivery: delivered" when the text appeared in the pane.
  That is not an answer from the agent. After a timeout or a pane without the text, do not resend
  at once: a busy agent can hold the text off-screen. Read the pane, then decide.
- A send to a seat at a prompt is **refused**. Do not force it. See section 5.
- `--force` does nothing useful. `--dangerously-interact` is denied.

To make the reviewer check the builder, ask the builder (in its task) to send its diff to
`dev-reviewer@piabrota-dev` with `rig send`, as its role file says. That uses `rig` inside the
seat and is from the docs, not run. You can instead send the reviewer the diff text yourself.

Then read the result in the pane. Check the builder's claims: read the reviewer's verdict, and run
the cheapest check yourself on your own clone of the patch. Say "the seat made the edits". Tell the
owner before and after, as `hermes-omp` says.

## 5. A seat stuck at a prompt

Signs: ATTN `yes` and a REASON in `rig ps --nodes`; `rig send` is refused with a prompt message;
the pane shows a question or a menu.

1. `rig capture <seat> --lines 40`. Read the question. Quote it to the owner.
2. For an `omp` seat, a usual cause is a cancelled extension dialog (a cancelled approval request
   only if the unit runs without `OPENRIG_YOLO`; see the
   [reference](../../hermes-omp/references/openrig-seats.md)). The seat then waits until the next
   agent run. Send an instruction that needs no answer: "Do not use that tool. Do this instead:
   ...". From the docs, not run.
3. If sends stay refused after the prompt is gone, record it:
   `rig seat clear-attention <seat> --reason "<what you saw in the pane>"`. Use it only when the
   pane proves the prompt is gone. It cannot bypass restore or identity checks.
4. A trust, permission or consent prompt: **do not answer it and do not turn it off.**
   `--dangerously-interact`, `rig seat set-permissions`, `rig policy apply` and
   `--non-interruptive` are denied. Tell the owner, with the captured text. The owner may attach
   (from the docs, not run): `sudo -u openrig env TMUX_TMPDIR=/run/openrig tmux attach -t dev-builder@piabrota-dev`.
   The tmux socket is in `/run/openrig`, a private folder of the unit.
5. A seat that works for far too long with no progress: capture twice a minute apart. If the
   screen did not change, tell the owner. Stop it (section 6) only when the owner agrees or when
   you started the task and it is yours to cancel.

## 6. Stop a seat or a rig

`rig down` ends every seat's session and the work in progress. Check first.

```console
rig ps --nodes --rig piabrota-dev --active          # no seat should be at work
rig parked --rig piabrota-dev                       # are stopped seats owing work?
rig capture dev-builder@piabrota-dev --lines 60     # keep the evidence
rig snapshot piabrota-dev                           # tested: prints "Snapshot created: <id>"
rig down piabrota-dev --snapshot                    # tested: "stopped. 1 session(s) killed."
```

- Stop only a rig you started, or one the owner asked you to stop.
- `rig down --delete` removes the rig record, so it cannot come back from a snapshot. `--force`
  kills at once. Both need the owner.
- One seat: `rig seat stop <seat> --reason "<why>"`. It ends that seat's tmux session and nothing
  else. A dead seat is refused: use `rig seat clean <seat>`.
- OpenRig has a checked stop on its HTTP API: it reads `GET /api/seat/stop-precondition/<seat>`
  and passes the answer back, so a stop is refused with HTTP 409 `selection_changed` if the seat
  changed in between. The 0.7.7 CLI has no code for it (a search of its source found none). Do the
  check by hand: capture the seat just before you stop it. A result `stop_uncertain` means: look at
  the seat before you try again.
- Restore from a named snapshot: `rig restore <snapshotId> --rig piabrota-dev`, and read the
  attempt with `rig restore status <attemptId> --rig piabrota-dev`.

## 7. After a deploy

A deploy that changes the unit restarts `openrig` and ends every seat (the
[reference](../../hermes-omp/references/openrig-seats.md)). A merge to nix-os deploys, so before the owner merges, take
`rig snapshot piabrota-dev`, and check `gh run list -R piabrota/nix-os --workflow deploy.yml
--limit 1`.

After the deploy:

```console
systemctl show openrig -p ActiveState -p NRestarts     # wait for active
rig status                                             # must say "Daemon running"
rig up piabrota-dev --existing                         # tested with a terminal rig
rig ps --nodes --rig piabrota-dev
```

`--existing` restores the stopped rig from its latest usable snapshot and resumes the conversations
where the harness can. It refuses while any seat of that rig is live. Never run it while
`rig status` says the daemon is down: it would start a stray daemon. An `omp` seat that never
finished a turn shows `awaiting-decision` in the RESTORE column. Start it blank with
`rig seat launch <seat> --fresh --reason "<why>"` (`--plan` first). Check each seat as in
section 2. Tell the owner which seats resumed and which started blank.

## 8. Logs

|Where|What|
|---|---|
|`journalctl -u openrig --since -1h --no-pager`|The daemon's output, its start-up lines and its errors. The `hermes` user can read the journal; check with `journalctl -u openrig -n 5`.|
|`journalctl -k --since -24h`|Kernel lines, for an OOM kill.|
|`rig transcript <seat>`, `rig capture <seat>`|A seat's output.|
|`rig health --rig <rig-id> --json`, `rig seat status <seat>`|What the daemon thinks.|
|`rig ps --resources`|Host load and the cost of transcript capture (tested).|

`rig daemon logs` reads the daemon's log files, and you cannot read them. It printed "No daemon
logs found". The daemon's own log folder is in the state folder of the `openrig` user.

Source: `rig up`, `rig down`, `rig ps`, `rig send`, `rig capture`, `rig transcript`, `rig seat`,
`rig snapshot`, `rig restore` and `rig queue create` help of the built OpenRig `v0.7.7`;
`docs/reference/checked-seat-stop.md`, `agent-startup-guide.md` and `rig-spec.md`; commands run
against a scratch daemon on 2026-11-04.
