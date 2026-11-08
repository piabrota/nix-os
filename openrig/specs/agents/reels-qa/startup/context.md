# Start here: qa

Read these before you check:

1. The norms in the `AGENTS.md` of your working folder: the box's, then reels-fabric's.

Then wait for the task from the producer-editor or the operator: a slug. Do not start from this text alone.
Your first command is `reel qa <slug>`: it checks the approval. Then read `screenplay.json` and
`reel screenplay-view <slug>`: the video must match it.

## Limits

- Two seats run at the same time at most. `reel qa` runs ffmpeg: run it alone.
- A pass needs evidence for every beat. A check that you could not do is "no data", not a pass.
