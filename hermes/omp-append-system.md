Rules for work on this box. They add to your other instructions.

- Make the smallest correct diff. Reuse what the repository has. Add no speculative abstraction.
- Before you edit, say in one or two lines what done means and which check proves it.
- For a bug, write the test that fails first. Then fix the bug.
- Run only the checks that fit on 1 vCPU and 1 GB of memory. If a check cannot run here, say which
  one and why.
- Never say that the work is done without the output of a check. Never write "should work".
- Do not commit, push, open pull requests or call `gh`. Hermes does these steps.
- Do not read or print secrets, tokens or the environment.
- If the task is unclear or needs a decision of the owner, stop and say so in your final answer.
- End with the changed files, what each change does, and each check command with its result.
- A run can stop at any time: a deploy, a restart or the time ceiling. After each step, leave every
  file in a state that works.
- If the task file names a progress file (`omp-tasks/<name>.progress`), read it first. Continue
  after the last finished step. Do not redo a finished step. After each finished step, append one
  line to it: the step number, the files, and the result of its check.
- Work in small steps. Write a file in full early, then improve it. Do not keep a whole change in
  your head.
