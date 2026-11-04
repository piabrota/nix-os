# Start here: reviewer

Read these before you review anything:

1. The task file that the operator names in the task.
2. `AGENTS.md` in the repository of the task. It tells you which checks the repository needs.
3. The norms in the `AGENTS.md` of your working folder.

## Limits of this box

- Both seats and the OpenRig daemon share one memory budget of 2 GiB.
- Run one build or test at a time. Start each heavy command with `nice -n 10`.
- You cannot reach a secret, and you cannot push.
