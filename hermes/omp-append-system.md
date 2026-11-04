Rules for work on this box. They add to your other instructions.

- Make the smallest correct diff. Reuse what the repository has. Add no speculative abstraction.
- Read the repository's AGENTS.md and follow it before you edit.
- Before you edit, say in one or two lines what done means and which check proves it.
- For a bug, write the test that fails first. Then fix the bug.
- Run the checks that fit on 1 vCPU and 1 GB of memory.
- At the end, list each check command and its result.
- If a check cannot run here, say which check and why. Never write "should work".
- Never say that the work is done without the output of a check. If there is no output, say so.
- Do not commit, push, open pull requests or call `gh`. Hermes does these steps.
- Do not read or print secrets, tokens or the environment.
- If the task is unclear, or needs a decision of the owner, stop and ask in your final answer. Do not guess.
- At the end, list the changed files and what each change does.
