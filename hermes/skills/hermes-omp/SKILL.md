---
name: hermes-omp
description: "Hand every code implementation or review to omp (oh-my-pi), then check its diff and open the PR yourself."
version: 1.1.0
author: piabrota
license: MPL-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [Coding-Agent, omp, Refactoring, Code-Review]
    related_skills: [github]
---

# hermes-omp

`omp` ([oh-my-pi](https://github.com/can1357/oh-my-pi), v18.16.0) is a coding agent on this box.
It is better than your own tools at large edits in a repository: exact edits, AST search, many
files at once. It uses Claude Sonnet through the same subscription as you, so every run counts
against the owner's limits.

`omp` on your PATH is a wrapper (piabrota/nix-os `hermes.nix`). Its rules are in a read-only file
(`hermes/omp.yml`) that you and omp cannot change. omp cannot push, call `gh`, install packages,
use `sudo` or `curl`, or read `~/.hermes`, `~/.ssh` or the secrets. Your deny list does not see the
commands that omp runs; those rules do. You do the parts that omp cannot: the branch, the review,
the commit, the push and the pull request.

## When to use it

Use omp for every task that writes or reviews code, config or scripts: implement, fix, refactor,
review a pull request or a diff. The size of the change does not matter: a one-line fix goes
through omp too. Do not write code with your own file tools. You do the steps omp cannot do: the
branch, the commit, the push, the pull request, and a small slip you find in its diff (a blank line,
a typo): fix it yourself and say so.

Do not use omp for chat, notes, research, a question you can answer by reading a file, or a
change to a Markdown file that has no code. Do those yourself and say that omp did not run.
Do not start omp from a cron job or from a subagent unless the owner asked for that job. Run one
omp at a time.

The owner can also start it by name: the skill is the command `/hermes-omp` (Telegram) or `/skill`
(Discord).

## Procedure

1. **Working tree.** Clone or update the repository as the workspace AGENTS.md, "Working with
   repositories", says. Then `git switch -c hermes/<a-few-words>` from the default branch.
2. **Task file.** Write the task to `/var/lib/hermes/workspace/omp-tasks/<a-few-words>.md` with your
   file tool, not in the command line (a long prompt in the command line can trip your deny list).
   Put in it:
   - the repository and the goal, in one or two sentences;
   - what done means, and the checks to run (from the repository's AGENTS.md, only those that fit
     on 1 vCPU and 1 GB);
   - the files or the issue to start from, when you know them;
   - a section "How to prove it is done": the exact commands to run, the result that means
     success, and for a bug the test that must fail before the fix and pass after it;
   - this line: "Do not commit, push or open pull requests. When you finish, list the changed
     files and the checks you ran, with their result."

   Never put a secret or a token in the task file.
3. **Run.** From the working tree:

   ```
   terminal(command="omp -p --no-title --max-time 15m < /var/lib/hermes/workspace/omp-tasks/<a-few-words>.md", workdir="/var/lib/hermes/workspace/<repo>", timeout=960)
   ```

   For a review only, say so in the task file and add `--approval-mode write`, so omp can read and
   write files but cannot run commands.
4. **Check.** omp's answer is a claim. Read `git status`, `git diff --stat` and `git diff`. Run the
   cheapest check yourself. If the diff is wrong or too big, run omp once more with a short
   follow-up in a new task file, or fix it yourself. Do not run omp more than twice for one task.
   Compare omp's list of checks with the section "How to prove it is done". A task is not done if
   omp did not run the checks, or if it gives no output.
5. **Deliver.** Commit, push `hermes/<a-few-words>` and open the pull request as the workspace
   AGENTS.md, "Opening a pull request", says, in English. Tell the owner what omp did and what you
   checked.
6. **Clean up.** Delete the task file.

## Tell the owner

The owner must see what omp does. Say each of these in chat, in plain words:

- **Before the run**, one short message: the repository and the branch; the mode (write, or
  review only); the path of the task file; the models and the thinking level that
  `hermes/omp.yml` sets. Read those values from `hermes/omp.yml` on nix-os `main`. Do not quote
  them from memory.
- **While it runs**, facts only: `pgrep -af bin/omp`, `ps -o etime=,rss= -p <pid>`, and the time left
  under `--max-time`. Its output stays empty until it ends.
- **After the run**: the files omp changed, the checks omp says it ran and their results, the checks
  you ran yourself, what you could not verify, any "unsure" label omp wrote, how long it took,
  and the link to the pull request. Say "omp made the edits". Never say that you wrote them.
- **When the owner asks how to tune omp**, point to `docs/HERMES-OMP.md` in nix-os, name the layer
  that fits the wish (task file, repository rules, prompt file, `omp.yml`, wrapper), and offer the PR.

## Review runs

For "review PR N" or "review this diff", omp does the review and you check it.

1. Refetch the head of the PR right before the run: `git fetch --depth 1 origin pull/N/head`, then
   `git switch --detach FETCH_HEAD`. The owner may have pushed meanwhile.
2. Copy the diff to `/var/lib/hermes/workspace/omp-tasks/`. omp cannot read `~/.hermes`.
3. In the task file, list the areas to review in priority order. Ask for `file:line`, a severity
   (BLOCKER, SHOULD-FIX, NIT) with certain, likely or unsure, the files it read, and what it could
   not check. Say: edit nothing.
4. Run with `--approval-mode write`. In that mode omp reads and writes files but cannot run commands.
   A large PR takes 10 to 12 minutes: run it in the background and end the turn.
5. Check each top finding yourself with a grep or a file read. Say which findings you confirmed and
   which you only relay. Then `git switch` back to the default branch, delete the task and diff
   files, and check that `git status` is clean.
6. Post one `COMMENT` review and never approve. End the review with the signature line from
   SOUL.md.

## When it fails

- Exit 137, or the run stops with no output: the box ran out of memory and the kernel stopped omp
  first. Tell the owner. Do not run it again until he says so.
- Any other exit code: report the last lines of its output.
- An authentication error: the token in the env file does not work for omp. Tell the owner; do
  not look for another token.
- A command that omp needed was refused by its rules: do that step yourself only if your own rules
  allow it, or ask the owner.
