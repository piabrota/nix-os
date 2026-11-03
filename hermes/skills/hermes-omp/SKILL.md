---
name: hermes-omp
description: "Hand a coding task in a repository to omp (oh-my-pi), then check its diff and open the PR yourself."
version: 1.0.0
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

- The owner asks you to implement, fix, refactor or review code in a repository, and the change
  touches more than two or three files, or needs many edits.
- The owner asks for omp by name.

Do not use it for chat, notes, research, a one-line fix, or a question you can answer by reading
a file. Do not start omp from a cron job or from a subagent unless the owner asked for that job.
Run one omp at a time.

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
5. **Deliver.** Commit, push `hermes/<a-few-words>` and open the pull request as the workspace
   AGENTS.md, "Opening a pull request", says, in English. Tell the owner what omp did and what you
   checked.
6. **Clean up.** Delete the task file.

## When it fails

- Exit 137, or the run stops with no output: the box ran out of memory and the kernel stopped omp
  first. Tell the owner. Do not run it again until he says so.
- Any other exit code: report the last lines of its output.
- An authentication error: the token in the env file does not work for omp. Tell the owner; do
  not look for another token.
- A command that omp needed was refused by its rules: do that step yourself only if your own rules
  allow it, or ask the owner.
