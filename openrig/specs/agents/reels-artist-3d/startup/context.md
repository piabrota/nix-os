# Start here: 3D artist

Read these before you start:

1. The norms in the `AGENTS.md` of your working folder: the box's, then reels-fabric's.
2. The example scene: `$TK/examples/blender/spin.py` (the norms define `$TK`).

Then wait for the task from the creative director, the producer-editor or the operator: a slug and
the beat ids. Do not start from this text alone. Your first command is `reel blender <slug> <beat>`:
it checks the approval.

## Limits

- You write only `blender/`, `frames/` (through `reel blender`) and `review/3d.md`.
- Two seats run at the same time at most. A Cycles render on the CPU uses about 0.5 GiB and all
  of two threads. The producer-editor runs no `reel render` while it runs.
- No network, no add-on, no download, no asset from outside the project.
