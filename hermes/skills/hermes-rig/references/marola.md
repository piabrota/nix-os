# marola-front and marola-back on piabrota-dev

MIP-0092 (Draft, marola-dev/marola): `marola-dev/marola-front` (Vite, TypeScript, MapLibre) and
`marola-dev/marola-back` (Rust, Loco). The rig is `piabrota-dev`: two seats, no new seat. For setup B
(Claude Code) use `piabrota-dev-claude`, see "Compare omp and Claude Code" below. Open this
file only when the owner asks for work on one of these two repositories. The guide for the owner is
[`docs/OPENRIG.md`](../../../../docs/OPENRIG.md), "marola-front and marola-back".

**Not run yet.** Everything here needs `piabrota.openrig.marola.enable` (on at piabrota2) and the key
file of `marola-pr-bot`. No seat has run this flow.

## The rules

- For these two repositories you act as `marola-pr-bot[bot]`. Use `marola-gh`, never `gh`, and a plain
  `git push origin hermes/<issue>-<slug>`. Every other repository stays on piabrota-hermes.
- `marola-gh` allows `pr create|view|list|diff|checks|status|comment|edit` and
  `issue view|list|comment`. Humans merge and review. Never try `pr merge`.
- Never use, mint, read or name the token of any other bot of marola. The seats never push.
- PR text: English, ASD-STE100, as every PR. Only `hermes/*` branches.

## Check

```console
rig status                                    # "Daemon running"
kvm4-health                                   # room in the unit openrig
ls -l /run/hermes-github/marola-pr-bot        # exists: marola-bot-token ran
systemctl status marola-bot-token --no-pager  # key file missing: the unit is skipped
```

No token file: tell the owner (the key file or the App's installation is missing). Do not push with
another token: the credential helper refuses on purpose.

## Run

```console
rig up /etc/openrig/specs/rigs/piabrota-dev/rig.yaml
rig send dev-builder@piabrota-dev "<marola-dev/marola-front or marola-back, issue, done means, checks, no push>" --verify
```

The rig keeps the spec that made it. After a deploy that changes the guidance, ask the owner, then
`rig archive piabrota-dev`, `rig import /etc/openrig/specs/rigs/piabrota-dev/rig.yaml --materialize-only`
and `rig up`.

## Take the result

The builder leaves `/var/lib/rig-outbox/marola/<repo>-<issue>-<slug>.bundle` and a `.md` report.

```console
cat /var/lib/rig-outbox/marola/<repo>-<issue>-<slug>.md
git clone https://github.com/marola-dev/<repo>.git        # once, in /var/lib/hermes/workspace
git -C <clone> fetch /var/lib/rig-outbox/marola/<repo>-<issue>-<slug>.bundle HEAD:hermes/<issue>-<slug>
git -C <clone> switch hermes/<issue>-<slug>
git -C <clone> rebase --exec 'git commit --amend --no-edit --reset-author' origin/main
git -C <clone> push origin hermes/<issue>-<slug>
marola-gh pr create --repo marola-dev/<repo> --base main --head hermes/<issue>-<slug> --title "..." --body-file <file>
```

Read the diff yourself before the push. Check that the commits show `marola-pr-bot[bot]`
(`git log --format='%an <%ae>'`). Send the owner the link.

## Compare omp and Claude Code

Setup A is `piabrota-dev` (omp). Setup B is `piabrota-dev-claude` (Claude Code, same agents, tokens and
outbox). Never run both at once. The bundle name ends with `-omp` or `-claude`; the branch is
`hermes/<issue>-<slug>-omp` or `-claude`. Guide: `docs/OPENRIG.md`, "Comparing omp and Claude Code".

```console
# 1. One agent-ready issue, ONE task text (same for both; only the suffix changes)
# 2. Run A
date -Is; systemctl show openrig -p MemoryCurrent -p MemoryPeak                 # before
rig up /etc/openrig/specs/rigs/piabrota-dev/rig.yaml
rig send dev-builder@piabrota-dev "<task, branch ...-omp>" --verify             # note the time
stat -c '%y %n' /var/lib/rig-outbox/marola/*-omp.*                              # end of A
rig transcript dev-builder@piabrota-dev --tail 100                              # the `omp: done` line
systemctl show openrig -p MemoryCurrent -p MemoryPeak                           # after
rig snapshot piabrota-dev && rig down piabrota-dev
kvm4-health
# 3. Run B, the same text
rig up /etc/openrig/specs/rigs/piabrota-dev-claude/rig.yaml
rig send dev-builder@piabrota-dev-claude "<task, branch ...-claude>" --verify
stat -c '%y %n' /var/lib/rig-outbox/marola/*-claude.*
rig transcript dev-reviewer@piabrota-dev-claude --tail 100                      # rejections
systemctl show openrig -p MemoryCurrent -p MemoryPeak
```

Record, from commands only: wall time (first `rig send` to the outbox file time), reviewer rejections,
the checks each seat says it ran and the ones you ran again, `git diff --stat` of each bundle, cost or
turns where printed (Claude Code: "not printed" if it prints none), and the unit's memory before and
after (`MemoryPeak` is for the whole unit since its start). Judge by the diff and the checks, not by
the seat's words. The operator posts the table as a comment on the issue, never in a file. Never invent
a number. Open ONE pull request, from the better branch. The other bundle stays in the outbox (14 days).
