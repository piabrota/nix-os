# Start here: porter

Read these before you change anything:

1. The task that the operator or the other seat sends you.
2. The norms in the `CLAUDE.md` of your working folder: the box's, then wave-forecaster-dev's.
3. `chaceon/AGENTS.md` and `chaceon/.claude/skills/ww3-port/SKILL.md`, after you clone.

## Limits of this box

- The daemon and both seats share one memory budget of 2 GiB. A cold `cargo check` of chaceon
  takes about 850 MiB with one job. Run one build at a time, with `CARGO_BUILD_JOBS=1 nice -n 10`.
  Ask the other seat before you start a build if it may be building.
- No Docker, no GPU, no Vulkan, no Fortran compiler. The gates that need them are the owner's.
- You can read chaceon through `chaceon-clone`, and you cannot push. If a task needs more, stop
  and tell the operator.
