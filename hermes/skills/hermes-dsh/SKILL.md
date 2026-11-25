---
name: hermes-dsh
description: "Hand every code implementation or review to DeepSeek Harness (dsh) on deepseek-v4.1-flash, then check its diff and open the PR yourself."
version: 1.0.0
author: piabrota
license: MPL-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [Coding-Agent, dsh, DeepSeek, Refactoring, Code-Review]
    related_skills: [github, hermes-rig, hermes-omp]
---

# hermes-dsh

`dsh` ([DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness), the package
`deepseek-harness`) is the coding agent for the model `deepseek-v4.1-flash`. It is DeepSeek's own
harness and uses the model's native tool and cache protocol, which is why it replaces omp on this
model. It is better than your own tools at large edits in a repository: exact edits, many files at
once.

Use this skill while your model is `deepseek-v4.1-flash` (the default). Use `hermes-omp` only when
the owner runs Hermes on another model.

`dsh` on your PATH is a wrapper (piabrota/nix-os `hermes.nix`, `dsh/wrapper.nix`). Its profile
patch is in a read-only store file (`dsh/wrapper.nix` builds it from `hermes/dsh-append-system.md`),
so you and dsh cannot loosen it. It points dsh at the OpenCode Go route
`https://opencode.ai/inference/go/openai/v1`, model `deepseek-v4.1-flash`, reasoning `high`, and it
moves Hermes's `OPENCODE_GO_API_KEY` to `OPENCODE_API_KEY`. You do the parts dsh cannot: the branch,
the review, the commit, the push and the pull request.

## When to use it

Use dsh for every task that writes or reviews code, config or scripts: implement, fix, refactor,
review a pull request or a diff. The size of the change does not matter: a one-line fix goes
through dsh too. Do not write code with your own file tools. You do the steps dsh cannot do: the
branch, the commit, the push, the pull request, and a small slip you find in its diff (a blank line,
a typo): fix it yourself and say so.

Do not use dsh for chat, notes, research, a question you can answer by reading a file, or a change
to a Markdown file that has no code. Do those yourself and say that dsh did not run.
Do not start dsh from a cron job or from a subagent unless the owner asked for that job.

## Where dsh runs, and what it can read

dsh runs in the cgroup of the unit that starts it, and one run takes about 300 MiB:

| You talk from | Unit | `MemoryMax` | dsh runs at once |
|---|---|---|---|
| Telegram, Discord, cron | `hermes-agent` | 8G | at most 2, on two different working trees |
| the dashboard's Chat tab | `hermes-backend` | 2G | 1 |
| an OpenRig seat | the openrig unit | its own | one per seat |

Before a second run, run `kvm4-health` and start it only if the `units` line of your unit is not
`WARN` or `CRIT`. Each run also spends the owner's OpenCode Go quota: run two at once only when the
owner waits on both. A `nix build` that dsh starts runs in `nix-daemon`, not in your unit.

dsh runs with DSH's `workspace-write` sandbox: writes are confined to the working tree, and
`--approval-policy never` refuses a call that would need a person. The task file and
`hermes/dsh-append-system.md` carry the same prohibitions as omp: no commit, push, `gh`, install,
`sudo`, `curl`, or secret reading. dsh has no omp-style bash deny list; Hermes's deny list sees
only the outer `dsh` command, so the sandbox and the task rules are the guardrail. Never copy
`.env`, `auth.json` or a file that holds a token into `dsh-tasks/`.

Tools come from Nix. dsh's rules and the task file refuse `npm install`, `pip` or a fetched script:
build a Node or Python project with Nix (`nix build .#<package>`, `nix develop -c ...`) and test
the built binary. Do not ask the owner to loosen a rule for a test.

The owner can also start it by name: the skill is the command `/hermes-dsh` (Telegram) or `/skill`
(Discord).

## Procedure

1. **Working tree.** Clone or update the repository as the workspace AGENTS.md, "Working with
   repositories", says. Then `git switch -c hermes/<a-few-words>` from the default branch.
2. **Task file.** Write the task to `/var/lib/hermes/workspace/dsh-tasks/<a-few-words>.md` with your
   file tool, not in the command line (a long prompt in the command line can trip your deny list).
   Put in it:
   - the repository and the goal, in one or two sentences;
   - what done means, and the checks to run (from the repository's AGENTS.md, only those that fit
     in the memory of your unit: see the table above; name the unit in the task file);
   - the input files you copied into `dsh-tasks/<a-few-words>/`, by path;
   - the files or the issue to start from, when you know them;
   - a section "How to prove it is done": the exact commands to run, the result that means
     success, and for a bug the test that must fail before the fix and pass after it;
   - this line: "Do not commit, push or open pull requests. When you finish, list the changed
     files and the checks you ran, with their result."

   Never put a secret or a token in the task file.
3. **Run.** From the working tree, in the background, with `dsh-run`:

   ```
   terminal(command="dsh-run <a-few-words>", workdir="/var/lib/hermes/workspace/<repo>", background=true, notify=true, heartbeat=120)
   ```

   `dsh-run <name> [dsh flags]` runs `dsh --profile headless --json --permission-mode
   workspace-write --approval-policy never [flags] - < dsh-tasks/<name>.md` through `dsh-stream`,
   and at the end prints how the run ended and the progress file
   `dsh-tasks/<name>.progress`. It adds the shared Git directory with `--add-dir` when the working
   tree is a Git checkout. Put only dsh flags after the name.

   `dsh-stream` turns each event into one plain line: `dsh: start in <cwd>`, `> <tool>: <input>`,
   `< <status>: <result>`, `dsh says: <text>`, and at the end `dsh: done (<reason>)`. A line that is
   not JSON prints as `dsh stderr: <line>`. Keys and tokens print as `[redacted]`.

   Each heartbeat (every 120 seconds) delivers the new lines to the conversation. Show them to the
   owner as they arrive: short, in a code block. Do not rewrite them. Each heartbeat costs one turn
   of yours, so keep your own words to a line or none. A run with no `dsh: done` line ended in an
   abnormal way, and a `dsh-run:` or `dsh stderr:` line says why.

   **To stop or restart a run** (the owner changed the task, or it went the wrong way), run
   `dsh-run --stop <a-few-words>` in the foreground. It stops only that run, waits until it has
   ended, and the background task then ends with `dsh-run: stopped on request` and exit 0, not as
   a failure. Then write the new task file and start again. Never stop dsh with `pkill -f`,
   `pgrep ... | kill` or `kill <pid>`: a pattern can match another run, and the task ends as a
   failure. The wrapper stops every run at 35 minutes.
4. **Check.** dsh's answer is a claim. Read `git status`, `git diff --stat` and `git diff`. Run the
   cheapest check yourself. If the diff is wrong or too big, run dsh once more with a short
   follow-up in a new task file, or fix it yourself. Do not run dsh more than twice for one task.

## What you tell the owner

Before the run: the repository, the branch, the task file and the model (`deepseek-v4.1-flash`,
reasoning `high`). After the run: the files dsh changed, the checks dsh ran, the checks you ran, what
nobody verified, the run time and the pull request link. If dsh could not start or the profile patch
is wrong, say what the wrapper printed and stop; do not fall back to another coding agent without
the owner's word.
