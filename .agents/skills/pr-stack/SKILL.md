---
name: pr-stack
description: "Put several open pull requests of piabrota/nix-os into one stack PR, so that one merge makes one deploy instead of one deploy per PR. Use when asked to stack, bundle, batch or combine PRs, to land many PRs at once, or to cut the downtime that many merges cause."
---

> Written for this repository (the owner, 2026-11-11). It is not vendored; AGENTS.md wins wherever
> it disagrees with this file.

# pr-stack

Each merge to `main` is a deploy (`deploy.yml`): deploy-rs builds the system and switches the VPS,
and the services that changed restart. Five PRs merged one by one are five deploys and five
restarts. A stack is one PR that carries all of them, so the owner merges once and the VPS
switches once.

A stack is made so that it **cannot conflict at merge time** and so that **no branch needs a
rebase after the merge**. Three rules give that:

1. **Merge, never rebase or cherry-pick.** The stack branch starts at `origin/main` and takes each
   PR with `git merge --no-ff`. Each PR's own head commit is then inside the stack, unchanged.
2. **Conflicts are resolved in the stack, never in the PR.** A conflict is fixed in that PR's merge
   commit on the stack branch. The original branch is not touched, so its author (a person,
   piabrota-hermes or piabrota-ops) never has to rebase it.
3. **The stack lands with a merge commit**, not squash and not rebase. Then every PR head is an
   ancestor of `main`, and GitHub marks each original PR as merged by itself. Anything built on top
   of one of those branches still has its base in `main`, so it needs no rebase either.

## Steps

1. **List the open PRs** (GitHub, `state: open`, oldest first). Leave out a draft unless the owner
   names it: a draft is not ready to deploy. Note each PR's author: a bot branch can move while
   the stack is open (step 6).
2. **Plan the order.** Oldest first, unless a PR depends on another; a PR that is already stacked
   on another comes after it. Then run:

   ```console
   just pr-stack-plan 143 162 163 221 222 223
   ```

   It merges the heads in that order onto `origin/main` in git's object store only, and names
   each PR that conflicts and the files. It changes no branch. Order the PRs so the fewest conflict;
   two PRs that both add a row to the same table conflict wherever they go, and that is fine.
3. **Build the branch.** Name it `claude/nix-os-pr-stack` (or `-<goal>` when two stacks are open).

   ```console
   git switch -c claude/nix-os-pr-stack origin/main
   git fetch origin pull/143/head:refs/pr-stack/143
   git merge --no-ff refs/pr-stack/143 -m "Merge #143: <its title>"
   ```

   One merge per PR, in the planned order. On a conflict, resolve it in that merge: keep both
   sides' meaning (two new table rows are two rows), read the PR's description for its intent, and
   never drop a change of `main`. Write in the merge commit's body what you resolved and how.
4. **Run the checks once, on the stack.** `just check`'s fast part (nixpkgs-fmt, statix, deadnix,
   shellcheck, the DeepWiki check), the justfile parse with just 1.21, and the tests of each module
   the stack touches (`just site-test`, `just ww3-site`, ...). Build both hosts if you can
   (`just build`, `just build piabrota2`): the deploy builds them anyway, and a failure there is a
   failed deploy. Say in the PR what you did not run.
5. **Open the PR** against `main`, in English, with the `bipr` sections (AGENTS.md, "Commits and
   PRs"). It lists every PR it carries with its head commit, says how each conflict was resolved,
   and has the closure difference if a build was run. The last line tells the owner to merge with
   **Create a merge commit**.
6. **Keep it ready until it merges.** Before the merge, run:

   ```console
   just pr-stack-check claude/nix-os-pr-stack 143 162 163 221 222 223
   ```

   It fails when `main` moved past the stack or when a PR's branch moved after it was stacked.
   For the first, `git merge origin/main` into the stack and push. For the second, merge that PR's
   new head again. Never rebase the stack and never force-push it: either would take the PR heads
   out of it, and rule 3 stops working.
7. **After the merge,** check that GitHub shows each original PR as merged. One whose branch moved
   after it was stacked stays open: close it with a comment that names the stack, or leave it for
   its bot when the bot opens it again from `main` (`room-pin`, `ww3-pin`).

## While a stack is open

- Merge nothing else to `main`; that is the point of the stack. A PR opened after the stack joins
  it with one more merge (step 3), or waits for the next stack.
- A bot that moves its branch every hour (`agents/room-pin`, `agents/ww3-pin`) goes last in the
  stack, so a new head is one merge at the end.
- Do not edit the original PRs to fix a conflict. Fix it in the stack.

## What this skill does not do

It does not merge. The owner merges, and the merge deploys (AGENTS.md: an agent never deploys).
