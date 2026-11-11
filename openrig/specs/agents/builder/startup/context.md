# Start here: builder

Read these before you change anything:

1. The task file that the operator names in the task.
2. `AGENTS.md` in the repository that the task names.
3. The norms in the `AGENTS.md` of your working folder.

## Limits of this box

- All seats and the OpenRig daemon share one memory budget (the unit `openrig`).
- Run one build at a time in your seat. Start each heavy command with `nice -n 10`.
- Keep a clone shallow: `git clone --depth 1 --filter=blob:none`.
- You cannot reach a secret, and you cannot push. If a task needs either, stop and tell the
  operator.
