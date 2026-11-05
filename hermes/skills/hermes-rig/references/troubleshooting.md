# Troubleshooting

Each entry: the symptom, the read-only check, the fix, and who owns the fix. A fix that is a change
to the unit, the memory limit, the packages or the specs is a pull request to piabrota/nix-os:
tell the owner, with the evidence. Never run `systemctl start|stop|restart`: it is denied.

Marks: **tested** = reproduced in a scratch daemon on 2026-11-04. **From the docs/source** = not
run. `[INFERENCE]` = a likely cause that is not confirmed.

## Daemon not reachable

Symptom (tested): `rig ps` prints "Daemon not running." and exits 1. `rig send` prints "Cannot
connect to the OpenRig daemon at http://127.0.0.1:7433: fetch failed (ECONNREFUSED)". `rig status`
prints "Daemon not running." and exits 0.

1. Check: `systemctl show openrig -p ActiveState -p SubState -p Result -p NRestarts`, then
   `journalctl -u openrig -n 80 --no-pager`.
2. `activating` or `auto-restart`: the unit waits `RestartSec=10s`. Wait a minute, check again.
3. `failed`, or `inactive` after 5 starts in 600 s: see "Unit in a restart loop".
4. **Do not run `rig up`.** The error text says "Run 'rig up' (it auto-starts the daemon)". Here
   that starts a stray daemon (see `safety.md`). Do not follow it.
5. Fix: the owner. The unit is a nix-os matter.

## Port in use

Symptom (tested): a second daemon on the same port ends with "Error: listen EADDRINUSE: address
already in use 127.0.0.1:7433". In the journal, the unit then restarts, and fails again.

1. Check: `ss -ltnp | grep 7433` (it names only your own processes), `systemctl show openrig -p
   ActiveState`, and the journal.
2. If a daemon answers while the unit is not `active`, it is a stray daemon, most likely from a
   `rig up` run while the unit was down. Do not stop it yourself: tell the owner with the output.
3. Fix: the owner stops the stray daemon. A different port is a change of `piabrota.openrig.port`
   in nix-os.

## The tmux server is missing

Symptom (tested): `rig capture <seat>` prints "The tmux server could not be reached (no server
running on ...) ... Nothing was captured." and exits 1. `rig send` prints the same, "No text was
sent.", and exits 2. `rig ps --nodes` can still show `run` for a short time. In the unit the socket
is in `/run/openrig`.

1. Check: `rig ps --nodes --rig piabrota-dev` again after a minute; `rig doctor | grep tmux`
   (it checks a throwaway server, so it does not prove the unit's server is up); the journal for a
   kill or an OOM line.
2. The seats are gone. Take stock with `rig ps --nodes`, then restore as in `operations.md`
   section 7: `rig up piabrota-dev --existing`, after `rig status` says "Daemon running".
3. If it repeats, tell the owner: [INFERENCE] a memory kill or a sandbox rule.

## A seat is not ready

Symptom: STARTUP `pending`, `failed` or `attention_required`; the pane shows a shell or an error.

1. Check: `rig seat status <seat>`, `rig capture <seat> --lines 40`, `rig ps --nodes --rig
   piabrota-dev`.
2. A shell in the pane: the `omp` process did not start. Read the journal for the `omp` wrapper. A
   login or authentication error: the token file of the unit is empty or wrong. Tell the owner.
   Do not look for a token.
3. `node: command not found` in the pane: the pane has a clean environment. It finds its tools only
   in the per-user profile of `openrig` (`users.users.openrig.packages`), and `USER` comes from
   the RigSpec `env:`. A relaunch does not fix it. This is a nix-os fix. Tell the owner.
   `/bin/rm: No such file or directory` in the pane is harmless on NixOS.
4. "No default model selected" in the pane means the key did not reach the seat. Check that the
   unit sets `OPENRIG_RECOVERY_PROVIDER_AUTH_ENV_ALLOWLIST=ANTHROPIC_API_KEY`. Check that the model
   of the seat is `anthropic/...`: `not-declared` in `rig ps --nodes --rig piabrota-dev` is wrong.
   A relaunch does not fix it. This is a nix-os fix. Tell the owner.
5. `failed` with a good pane: wait 30 seconds, the monitor re-reads it. Then check again.
6. A seat with no session file after a restore: `rig seat launch <seat> --fresh --plan`, then
   without `--plan` and with `--reason "<why>"`.
7. Fix: relaunch is yours. A broken wrapper, token or spec is the owner's pull request.

## A seat is at a prompt

See `operations.md`, section 5. Read the pane, send an instruction that needs no dialog, or tell
the owner. Never answer a trust or consent prompt and never change the permissions of a seat.

## `better-sqlite3` does not load

[INFERENCE] The daemon uses the native addon `better-sqlite3`, built for one Node version. A
mismatch shows as a Node error such as "was compiled against a different Node.js version", or
"Could not locate the bindings file", on each start. It was not reproduced: the built package
works. The 0.7.7 source has no special handling for it.

1. Check: `journalctl -u openrig -n 80 --no-pager | grep -i -E "sqlite|bindings|NODE_MODULE"`.
2. It happens after an update of Node or of the package without a full rebuild.
3. Fix: the owner, in nix-os (`openrig/package.nix`: the addon is built from its bundled source).

## Unit in a restart loop

Symptom: `NRestarts` rises, or `ActiveState` is `failed` with `Result=start-limit-hit`. The unit
tries up to 5 starts in 600 s, then stays down.

1. Check: `systemctl show openrig -p NRestarts -p ActiveState -p SubState -p Result`, and
   `journalctl -u openrig --since -1h --no-pager`. Group repeated lines:
   `journalctl -u openrig --since -1h -o cat | sort | uniq -c | sort -rn | head`.
2. Common causes: a port in use; a bad sandbox rule after a change; a full disk; a failed addon.
3. Do not hide a loop. Tell the owner with the last error lines. The fix is a pull request.

## Out of memory

Symptom: a seat vanishes (`det` in LIFECYCLE) with no stop from you; `kvm4-health` shows OOM lines
or `WARN` or `CRIT` for `openrig`; a seat's process died mid-task.

1. Check: `kvm4-health`; `systemctl show openrig -p MemoryCurrent -p MemoryPeak`; `journalctl -k
   --since -24h | grep -i -A3 'killed process'`.
2. All seats share the unit's 2 GiB cgroup (`MemoryHigh` 1536 MiB). `OOMPolicy=continue` keeps
   the unit up, and the `choom` setting makes the kernel pick a seat before the daemon.
3. Fix, yours: `rig seat clean <seat> --reason "<why>"`, then
   `rig seat launch <seat> --fresh --plan`, or restore with `rig up piabrota-dev --existing` if the
   rig is stopped. Run one seat until the cause is known.
4. Fix, the owner's: a higher `memoryMax` (it changes the sum of limits in `docs/OPENRIG.md`), or lighter
   tasks. Do not start a third seat.

## A deploy ended the seats

Symptom: all seats gone, the unit has a new start time, `NRestarts` is unchanged or 1.

1. Check: `gh run list -R piabrota/nix-os --workflow deploy.yml --limit 3`;
   `systemctl show openrig -p ActiveEnterTimestamp`.
2. Fix, yours: wait for the unit to be `active`, run `rig status`, then `rig up piabrota-dev
   --existing`. A seat that never finished a turn needs `rig seat launch <seat> --fresh --reason
   "<why>"`. Details are in `operations.md`, section 7.
3. Prevention: take `rig snapshot piabrota-dev` before the owner merges a nix-os pull request.

## Disk is full

Symptom: `kvm4-health` shows `WARN` or `CRIT` for disk; the journal shows "No space left on
device" for `openrig`; `rig` commands time out or fail on write.

1. Check: `df -h` and the disk line of `kvm4-health`. You cannot read `/var/lib/openrig` (denied and
   mode 0700), so you cannot see what grew. `rig ps --resources` shows what transcript capture
   costs.
2. The growth is usually seat transcripts, the SQLite file, and the clones in the `work` folder.
3. Fix: the owner. The options are to delete old clones, to archive or delete old rigs (`rig
   archive <rig>` is yours; it keeps the data), and to tune `transcripts.*` with `rig config set`
   (owner). A bigger disk or garbage collection is a nix-os matter.

## Other messages

|Message or sign|Meaning and next step|
|---|---|
|`rig send` refused, prompt named|The seat is at a prompt. Section 5 of `operations.md`.|
|"unknown sender" in the seat|You sent from outside a seat. Use `rig queue create --source hermes@external ...` to name yourself.|
|`/bin/rm: No such file or directory` printed in a terminal seat (tested)|A harmless line from the daemon's paste step on NixOS. It shows in a shell seat only.|
|`rig up <spec>` refuses|A rig of that name has live seats. Read `rig ps --nodes --rig <name>`. Do not force it.|
|"lsof isn't installed" warning at start|Ownership of the database file is unknown. The unit has `lsof` in its path, so you should not see it.|
|`fetch openrig-core returned 404` in the journal at start, or `rig doctor` FAIL on `claude_install`, `codex_install`, `ui_dist`|Known here, not an error: the [reference](../../hermes-omp/references/openrig-seats.md).|

Source: `rig` help of the built OpenRig `v0.7.7`; `docs/reference/agent-startup-guide.md` and
`checked-seat-stop.md`; `openrig.nix` of piabrota/nix-os for the limits and the restart rules;
`skills/kvm4-health`. Daemon-down, port-in-use and missing-tmux messages come from tests in a
scratch daemon on 2026-11-04. The `better-sqlite3`, out-of-memory and disk entries are not run.
