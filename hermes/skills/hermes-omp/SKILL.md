---
name: hermes-omp
description: "Hand every code implementation or review to omp (oh-my-pi), then check its diff and open the PR yourself."
version: 1.4.0
author: piabrota
license: MPL-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [Coding-Agent, omp, Refactoring, Code-Review]
    related_skills: [github, hermes-rig]
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
Do not start omp from a cron job or from a subagent unless the owner asked for that job.

## Where omp runs, and what it can read

omp runs in the cgroup of the unit that starts it, and one run takes about 340 MiB:

| You talk from | Unit | `MemoryMax` | omp runs at once |
|---|---|---|---|
| Telegram, Discord, cron | `hermes-agent` | 8G | at most 2, on two different working trees |
| the dashboard's Chat tab | `hermes-backend` | 2G | 1 |
| an OpenRig seat | the openrig unit | its own | one per seat (`references/openrig-seats.md`) |

Before a second run, run `kvm4-health` and start it only if the `units` line of your unit is not
`WARN` or `CRIT`. Each run also spends the owner's Claude quota: run two at once only when the
owner waits on both. A `nix build` that omp starts runs in `nix-daemon`, not in your unit.

omp can read the working tree, `/var/lib/hermes/workspace` and the store (`/nix/store`). Your
skills from nix-os are in the store: give omp the store path from `skills.external_dirs`, not a path
under `~/.hermes`. omp cannot read `~/.hermes` (its rules refuse it), so a skill or a reference that
you wrote yourself, a log or a session file reaches omp only as a copy:
`mkdir -p /var/lib/hermes/workspace/omp-tasks/<a-few-words>/` and copy the files there. Never copy
`.env`, `auth.json` or a file that holds a token.

Tools come from Nix. omp's rules and your deny list refuse `npm install`, `pip`, `npx`, `curl` and
a fetched script, and they are right to: do not test a Node or Python project by an install. Build
it with Nix (`nix build .#<package>`, with `fetchNpmDeps` or `buildNpmPackage` and the project's own
lock file) and test the built binary. Do not ask the owner to loosen a rule for a test.

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
     in the memory of your unit: see the table above; name the unit in the task file);
   - the input files you copied into `omp-tasks/<a-few-words>/`, by path;
   - the files or the issue to start from, when you know them;
   - a section "How to prove it is done": the exact commands to run, the result that means
     success, and for a bug the test that must fail before the fix and pass after it;
   - this line: "Do not commit, push or open pull requests. When you finish, list the changed
     files and the checks you ran, with their result."

   Never put a secret or a token in the task file.
3. **Run.** From the working tree, in the background, with `omp-run`:

   ```
   terminal(command="omp-run <a-few-words> --max-time 15m", workdir="/var/lib/hermes/workspace/<repo>", background=true, notify=true, heartbeat=120)
   ```

   `omp-run <name> [flags]` runs `omp -p --mode json --no-title [flags]` on the task file
   `omp-tasks/<name>.md`, pipes the output through `omp-stream`, and at the end prints how the run
   ended and the progress file `omp-tasks/<name>.progress`. Put only omp flags after the name. Do
   not write the `omp ... | omp-stream` pipeline yourself: when a signal kills it, the background
   shell prints `tcsetattr: Inappropriate ioctl for device` and the task fails with exit 143.

   `--mode json` makes omp print one event per line as it works. `omp-stream` turns each event
   into one plain line: `omp: start`, `> <tool>: <what>`, `< <tool> ok (<ms> ms)` with the first
   lines of the result, `omp says: <text>`, and at the end `omp: done, <N> turns, cost $<sum>`. A
   line that is not JSON prints as `omp stderr: <line>`. Keys and tokens print as `[redacted]`.

   Each heartbeat (every 120 seconds) delivers the new lines to the conversation. Show them to the
   owner as they arrive: short, in a code block. Do not rewrite them. Each heartbeat costs one turn
   of yours, so keep your own words to a line or none. A run with no `omp: done` line ended in an
   abnormal way, and an `omp-run:` line or an `omp stderr` line says why.

   **To stop or restart a run** (the owner changed the task, or it went the wrong way), run
   `omp-run --stop <a-few-words>` in the foreground. It stops only that run, waits until it has
   ended, and the background task then ends with `omp-run: stopped on request` and exit 0, not as
   a failure. Then write the new task file and start again. Never stop omp with `pkill -f`,
   `pgrep ... | kill` or `kill <pid>`: a pattern can match another run, and the task ends as a
   failure with exit 143. For a task that needs more than 10 minutes, follow "Long
   tasks". The wrapper stops every run at 35 minutes.

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
6. **Clean up.** Delete the task file, the progress file and the directory
   `omp-tasks/<a-few-words>/`.

## Tell the owner

The owner must see what omp does. Say each of these in chat, in plain words:

- **Before the run**, one short message: the repository and the branch; the mode (write, or
  review only); the path of the task file; the models and the thinking level that
  `hermes/omp.yml` sets. Read those values from `hermes/omp.yml` on nix-os `main`. Do not quote
  them from memory.
- **While it runs**, the stream of step 3 is the main source: show the new lines at each
  heartbeat. As a fallback, when no line arrives, give facts only: `pgrep -af bin/omp`,
  `ps -o etime=,rss= -p <pid>`, and the time left under `--max-time`.
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

### A review that fixes the code

When the owner asks the review to change the code (for example on your own branch before the pull
request), omp edits the files directly.

1. Commit the work under review first, so the review's changes are a diff of their own.
2. In the task file, list the areas in priority order. Ask omp to fix each BLOCKER and SHOULD-FIX
   in place, to fix a NIT only when the fix is one line, and to write `OPEN: <file:line> <why>` for
   a finding it cannot fix without weakening a guardrail (a deny rule, a sandbox setting, a
   firewall port, a licence rule). Ask for the checks after the fixes.
3. Run in the normal mode, not with `--approval-mode write`: omp must run the checks.
4. Read the diff as in "Check". Commit it separately (`fix: apply review findings`), so the owner
   sees what the review changed. Show the owner every `OPEN` line.

## Long tasks

A deploy or a restart of the gateway stops omp, and the wrapper stops every run at 35 minutes.
This section and step 3 win over a skill that you wrote yourself about omp runs (for example
`omp-long-tasks`): start and stop every run with `omp-run`.

- Split a task that needs more than 10 minutes into steps in the task file. Give each step one
  check. Name a progress file in the task file: `omp-tasks/<name>.progress`. Run one omp for each
  group of steps of at most 15 minutes.
- Before a run longer than 10 minutes, run `systemctl show hermes-agent -p NRestarts -p ActiveState`
  and `gh run list -R piabrota/nix-os --workflow deploy.yml --limit 1`. If a deploy is in progress,
  or `NRestarts` is above 5, do not start. Tell the owner.
- During the run, tell the owner not to merge a pull request of nix-os. A merge deploys, and a
  deploy can restart the gateway.
- Start the run as in step 3 (`terminal(background=true, notify=true, heartbeat=120)`) and end the
  turn. Do not poll: the heartbeat delivers the output.
- If the output says `omp-run: stopped by SIGTERM`, read the progress file and `git status`. Then start a
  new run with a task file that says: continue after the last finished step. Tell the owner that
  the run stopped, and why.
- If `NRestarts` of `hermes-agent` rises while you work, stop. Run `hermes doctor` and
  `hermes gateway status`. Tell the owner. Do not hide a restart loop.

## OpenRig

For work on OpenRig (the package, the module, the RigSpec under `openrig/specs/`) or for a rig
whose seats run omp, read `references/openrig-seats.md` first. It says how OpenRig starts omp,
which variables reach a seat, and what the openrig unit needs. The `hermes-rig` skill, when it is
installed, has the `rig` commands.

## When it fails

- Exit 137, or the run stops with no `omp: done` line and no output: the box ran out of memory and
  the kernel stopped omp first. Tell the owner. Do not run it again until he says so.
- Exit 143 with `omp-run: stopped by SIGTERM`: a restart of your unit, a deploy or a kill stopped
  the run. It is not a bug of omp: follow "Long tasks". Exit 0 with `omp-run: stopped on request`
  is your own `omp-run --stop`: it is not a failure, so do not report it as one.
- No `omp: done` line and no memory kill: report the last lines of the stream, with the
  `omp-run` and `omp stderr` lines.
- An authentication error: the token in the env file does not work for omp. Tell the owner; do
  not look for another token.
- A command that omp needed was refused by its rules: do that step yourself only if your own rules
  allow it, or ask the owner.
