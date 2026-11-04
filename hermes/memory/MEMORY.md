# What Hermes learned since the install

A reading of about 10 minutes. It is the long form of Hermes's memory. The short form
(`MEMORY.md` in Hermes's state) has a limit of 2,200 characters and loads in every turn.
This file does not load by itself. Hermes reads it when a task needs the history.

**Scope.** The record covers the first Hermes log (2026-11-02 22:01 UTC) to 2026-11-04 06:30 UTC.
The source is the work of session `20261103_170335_564c7f49`, the pull requests of piabrota/nix-os and
the logs on the box. Earlier chat is not in this record. A line with no date has no single date.

## 1. Timeline

- [2026-11-02] The first Hermes log is from 22:01 UTC. Hermes ran on piabrota (KVM 1: 1 vCPU, 4 GB RAM,
  50 GB disk) as the unit `hermes-agent`, built from the NixOS module of its upstream flake.
- [2026-11-03] #69 documented the interfaces and the restart on a deploy.
- [2026-11-03] #70 set Sonnet as the main model and Haiku for subagents. It also made every pull request of Hermes
  English-only and ASD-STE100, and it added a survey of Hermes forks. Result of the survey: keep upstream.
- [2026-11-03] #71 added 29 of the 51 skills of h0ffmann/skills as commands. The pin is a commit,
  not a git submodule. It also added a cost study of Paperclip. Paperclip is not installed.
- [2026-11-03] The owner turned off `nix flake check` for pull requests. It runs by hand.
- [2026-11-04] #83 and #86 gave omp a release binary and tuned it for Sonnet.
- [2026-11-04] #87 moved Hermes to KVM 4. Merged at 03:44 UTC.
- [2026-11-04] #93 took `h0ffmann` out of the `hermes` group so the dashboard Chat tab can attach.
- [2026-11-04] #103 moved the input `hermes-agent` to the release v0.22.7 (commit `b200f5b`).
- [2026-11-04] #104 stamped the package with its real version. Merged at 06:22 UTC.

## 2. The machines

- `piabrota` is KVM 1. It serves the public web: www.piabrota.art, `/hermes`, `/hosts`, `/notes`. Its
  `hostName` is Hostinger's `srv2108887`. It stays that name, because cloud-init needs it.
- The second host is KVM 4: 4 vCPU, 15.6 GiB of RAM, 197 GB of disk. The flake calls it `kvm4`.
  The owner wants the name `piabrota2` in every place, so the name in the Hostinger panel maps to the
  name in the flake. This change is in a pull request that is not merged yet.
- [2026-11-04] KVM 4 at rest: `hermes-agent` 0.43 GiB, `hermes-backend` (the dashboard) 0.55 GiB, `pgx` 0.1 GiB.
  Caps: 8G, 2G and 256M. Load: 0.24. No swap in use. No OOM kill in 24 hours.
- [2026-11-04] DNS at Porkbun: `hermes.piabrota.art` has an A record to 187.41.117.18 (KVM 4), TTL 600.
  `piabrota.art` and `www` stay on KVM 1 (187.41.103.185). There is no AAAA record and no CAA record.
  The AAAA record waits until the IPv6 firewall of the VPS opens ports 80 and 443.
- The `hostname` on KVM 4 still prints `nixos`, even though `main` sets another name. cloud-init
  keeps `/etc/hostname`. This is the reason KVM 1 pins its name. Check `hostname` after the next deploy.

## 3. How a change reaches the machines

- A merge to `main` is a deploy. The GitHub runner builds the systems. deploy-rs copies them over SSH and
  rolls back if SSH does not answer in 60 seconds. A change of Markdown only does not deploy.
- One deploy key serves both hosts. The secret `DEPLOY_KNOWN_HOSTS` holds one line for each host. GitHub
  does not show a secret after it is saved. So the owner writes the whole value again when a host is added.
- The secret `DEPLOY_HOST_KVM4` holds the address of KVM 4. A host with no address secret is skipped, not failed.
- `deploy.yml` and `freeze.yml` still name the node `kvm4`. A human must change them. Until then `flake.nix`
  keeps `kvm4` as an alias of the new node name.
- Hermes cannot edit `.github/workflows`. It writes a patch file, checks it with `git apply --check`, and the
  owner applies it. Two patches wait: the `FLAKE_CHECK` variable for CI, and the `context-size` check.

## 4. Things that went wrong, and the lesson

**Package version 0.0.0 (fixed in #104).**
The flake builds the Hermes package with the version `0.0.0`. Hermes then skipped eleven plugins that need a
higher version, among them the deny list, tripwire, four ledgers, `gh-ref`, `wiki-ref`, `progress-squash`,
`hermes-guide` and `memory-rewind`. The first skip in the log is 2026-11-03 13:25 UTC. A command that the
deny list should block ran without a block.
Lesson: `enabled` in `hermes plugins list` means "set in the config", not "loaded". Search the log for
`skipped: requires hermes`. After the fix, `hermes --version` prints v0.22.7 and the skips stopped.

**The Chat tab said "retrying" for ever.**
The TUI of the dashboard attaches to the gateway through a control socket. Upstream refuses that socket when the
home directory is group-writable and its group has a member besides the owner. The group `hermes` had
`h0ffmann`. The check is in `gateway_runtime_discovery.py`.
Lesson: reproduce a symptom with the upstream script first. Running `gateway_bootstrap.py` printed the real
cause in one line.

**`config.yaml` kept old limits after the move.**
The module merges the Nix settings into the file on disk and never deletes a key. A copied `config.yaml` brings
back the limits of the old host. The cutover copies the state without that file.

**The cutover list had four errors.** A review found them before the move:
- `chmod 600 dir/*` inside an `ssh` string. The glob expanded in the wrong shell. Use `find ... -exec chmod`.
- A pipe with no `pipefail`. A failed `tar` on the source left a partial copy with exit code 0.
- KVM 4 had run Hermes before, so its old `state.db` could mix with the copied one. Move it aside first.
- Cron jobs run in a user scope and survive `systemctl stop hermes-agent`. Stop the user manager too.

**A fix pull request whose base is another branch.** Hermes can push only `hermes/*` branches. A fix for a
`claude/*` pull request goes in a `hermes/*` pull request with that branch as base. If the base merges first,
the fix does not reach `main`. #89 and #91 had the base of #87. Check that their changes are in `main`.

**`AGENTS.md` above 32,000 characters.** Hermes cuts a context file at 32,000 characters and drops the middle.
For the nix-os file that middle held "Do not break the machine" and "Resource budget". The file had 34,482
characters. A size check and a smaller file are in a pull request.

**One very long session.** This session reached 435,000 tokens of input in a single call. Each answer reads that
context again and spends the owner's quota. Start a new session (`/new`) after a large piece of work.

## 5. Working rules that came out of the work

- Humans merge. Hermes never merges, approves or closes a pull request.
- Hermes pushes only `hermes/*` branches, and never force-pushes.
- A pull request that deploys says so in its first lines.
- A pull request says what was tested and what was not. A parse is not a build. A build is not a run.
- The deny list is active since #104. It blocks a compound command that contains a `git push`. Run
  `git add`, `git commit` and `git push` as separate calls.
- Hermes cannot use `sudo`. The service sets `no new privileges`. The owner runs privileged steps.
- Hermes does not read `/var/lib/hermes-secrets` or the env file. It reads logs and unit state only.
- An alert comes only from an official agency. This rule has not been used yet on this box.

## 6. Tools and their traps

**Terminal.**
- There is no `python3`. Use `execute_code` for Python. In `execute_code`, call Nix tools by full path
  (`/run/current-system/sw/bin/nix-instantiate`).
- `pgrep -f` matches its own shell. Use `ps -eo pid,etime,args | grep` instead.
- A terminal call with a timeout over 600 seconds runs in the background and notifies at the end.
- `nix eval` works on the box (16 GB). It proves that the flake evaluates. It does not prove that the deploy works.
  The evaluation of a package derivation shows its version in the install stamp.

**omp (the coding agent).**
- The rule: every task that writes or reviews code, config or scripts goes through omp.
- Write the task to `workspace/omp-tasks/<name>.md`. Run `omp -p --no-title --max-time 15m < task.md`
  from the repository. Run one at a time. It prints its answer only at the end.
- A review-only run uses `--approval-mode write`. omp then cannot run commands, so it cannot run `nix` or `git`.
  Put the diff in `omp-tasks/` and check out the pull request head first.
- omp reports what it did not check. Read that list. An exit code of 0 is not proof of success. Read the diff.
- Typical run: 1 to 10 minutes. The process used about 500 MiB of memory.
- The first run with the added system prompt (#86) worked: it kept to "do not edit" and cited file and line.

**Haiku subagents.**
- `delegate_task` runs on Haiku. Use it for fan-out of read-only work.
- [2026-11-04] A pilot rewrote two documents into ASD-STE100. A script checked them: code blocks, inline code,
  links, headings, tables and numbers were all identical. Sentences over 25 words fell from 9 to 1 and from 9 to 0.
  But the text did not get shorter (1% and 5% longer), and one report line was wrong: it said bold was removed,
  and the count did not change.
  Lesson: trust the script, not the report. Use a script to check structure, then read the diff for meaning.

**GitHub.**
- `gh` runs as the App `piabrota-hermes[bot]`. It can read, comment, push `hermes/*` and open pull requests.
- A comment signs with the line `— piabrota-hermes (Claude Sonnet, Claude Code on the piabrota VPS)`.
- A review with `suggestion` blocks lets the owner apply a fix in one click.

## 7. Plugins and skills

- [2026-11-03] The plugin catalog is the folder `plugin-catalog/` of NousResearch/hermes-agent. The docs page draws it
  in the browser, so a plain fetch sees nothing. A local index of 976 entries exists (not in git). The tracking
  issue is #88.
- Wave 1 is installed: `hermes-guide`, `hermes-plugin-guard`, `memory-rewind`. `hermes guide` ran 10 checks on
  2026-11-04 with exit code 1 (warnings, no error). Warnings: the 22 playbook skills are not installed, the
  `github-copilot` provider sits in `plugins.enabled`, memory entries have no date, and four sessions are heavy.
- Wave 2 waits for a measurement: `hermes-telemetry` (its default mode blocks tool calls on a budget breach,
  so use `observe` only), `custodian` (it creates three recurring agent jobs that spend quota) and one memory provider.
- `hermes-dreaming` was read and not installed. It runs a nightly job, a weekly job and a 15-minute job without a
  model. It needs the pinned plugin, then a user-run installer that creates cron jobs. The owner must approve the cost.
- Skills that appeared in the skill list: `kvm4-health` (memory, disk, CPU and each unit against its cap) and `hermes-plugin-inspection`.

## 8. Upgrading Hermes

- [2026-11-04] The module did not change between the old pin and v0.22.7. Only the Python dependencies moved.
  The upgrade is one pin in `flake.lock` and one version string in `hermes.nix` (`hermesVersion`).
- Change `hermesVersion`, the README badge and the pin in the same pull request.
- The check `hermes-docs-url` fails if upstream renames the docs address that the dashboard replaces.
  It runs only in `nix flake check`, which the owner runs by hand.
- After a deploy: run `hermes --version`, `kvm4-health`, `just remote-hermes-check`, open the dashboard and the Chat tab,
  and search `errors.log` for new plugin errors.

## 9. Open items

- Rename the host to `piabrota2` in the flake, the directory and the docs, then edit `deploy.yml` and `freeze.yml`
  and remove the `kvm4` alias.
- Check that #89 and #91 reached `main`.
- `cves.yml` and `flake-update.yml` build only `piabrota`. They miss the host with the most software.
- `hermes/AGENTS.md` and `hermes/SOUL.md` still say that Hermes runs on KVM 1 with 1 GB. These are Hermes's own
  limits, so the owner decides the new values.
- The `kvm4-health` watchdog (a silent job every 30 minutes) is not created. It needs the owner's approval.
- Install `hermes-dreaming`, if the owner approves.
- The ASD-STE100 conversion of the other English documents: 36 files, about 275,000 characters.
- Remove `github-copilot` from `plugins.enabled`.
