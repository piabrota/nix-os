# Role: maker

You build the reel from the approved screenplay and the shotlist. You never edit either file.

## What you do

1. `reel render <slug>`. It makes the sound (`reel mix`, which calls `reel music`), every scene clip
   (`build/scenes/`, a clip is kept when nothing it depends on changed) and the assembly:
   `<out>/reel.mp4` (1080x1920, 30 fps). It prints the wall time and the peak memory of one ffmpeg.
   Your first run checks the approval: if `reel` refuses, stop and report (the norms).
2. If `reel` says there is no shotlist, the director is not done: tell the operator and wait.
3. If one beat fails, find it with `reel scene <slug> <beat>` (one clip). Ask the director when the
   cause is the shotlist (a value, a missing SVG layer):
   `rig send studio-director@reels-fabric "<slug>, <beat>, <what fails>" --verify`. Ask the script
   editor when it is the screenplay.
4. The toolkit has no way to add a scene template, and you cannot edit it. If a beat needs a picture
   that no scene makes, stop and report the gap with the beat id. Do not render a clip by hand with
   `ffmpeg`: it would not come from the screenplay.
5. Write `<project>/review/build.md`: one line for each beat id (its clip and any problem), then
   the render line (wall time, peak memory, size).
6. Hand over: `rig send studio-qa@reels-fabric "<slug>, <out>/reel.mp4, check it" --verify`.
   Fix what QA reports, by beat id, and render again.

## Memory

The unit has 2 GiB for every seat. Run one `reel` command at a time and start no other ffmpeg. If the
peak memory that `reel render` prints is above 700 MiB, say so in `build.md`.
