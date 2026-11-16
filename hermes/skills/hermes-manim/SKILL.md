---
name: hermes-manim
description: "Use when you render a Manim animation on this box."
version: 1.0.0
author: piabrota
license: MPL-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [Manim, Animation, Video, Math]
    related_skills: [manim-video]
---

# hermes-manim

Manim Community (`manim`) is on the PATH of this box. This skill says how to run it here.
The skill `manim-video` says how to make a good animation (story, scenes, style). Load both.

## What is installed

- `manim` 0.20.1 from the pinned nixpkgs, with Python, Cairo, Pango, ffmpeg and a LaTeX set.
  `MathTex`, `Tex`, `Text` and shapes work. `ImageMobject` does not: the Pillow of this pin
  fails in the Cairo camera. Do not use images in a scene. No other Python package is there.
- CPU only. There is no GPU and no display. Use the default Cairo renderer.
  Never use `--renderer=opengl`, `-p` or `--preview`.
- You cannot install anything. The deny list blocks `pip`, `uv` and `npx`. If a scene needs a
  package that is not there, stop and tell the owner. A new package is a PR to nix-os.

## Check first

1. Run `manim --version`. It must print `Manim Community v0.20.1`. If the command is missing,
   the deploy of the Manim PR has not reached this box: say so, and stop.
2. Run `kvm4-health` before a long render (more than 1 minute) and read the `units` lines.

## Render

1. Make one folder for each job: `/var/lib/hermes/workspace/manim/<slug>/`. Write the scene
   file there, for example `scene.py`. Never write in a repository clone.
2. Start with the lowest quality, to see the result fast:
   `manim -ql --media_dir media scene.py SceneName`
   - `-ql` is 480p at 15 fps, `-qm` is 720p at 30 fps, `-qh` is 1080p at 60 fps.
   - Use `-qm` for what you send to the owner. Use `-qh` only if he asks, and only after a `-ql`
     run worked.
   - Add `-s` to save only the last frame as a PNG. Use it to check a layout.
3. The video is in `media/videos/<scene file>/<quality>/SceneName.mp4`. Look at it before you
   send it: take a frame with `ffmpeg -sseof -0.3 -i <mp4> -frames:v 1 frame.png`, and view the
   PNG with `vision_analyze`. Check that text is not cut and nothing overlaps.
4. Send the file with `MEDIA:/absolute/path/SceneName.mp4`. Check its size with `ls -la` first.
   If the platform can refuse it, render again at a lower quality.
5. Delete `media/videos/*/*/partial_movie_files` and `media/Tex` when the job is done.

## Limits

- A smoke scene (a title, one equation and a circle, `-ql`) takes about 1.3 seconds and
  peaks near 220 MiB of memory (measured on this box). A longer or larger scene needs more.
- A render shares the 8 GB of the `hermes-agent` unit with the agent and with omp. Do not render
  while two omp runs are active. Render one scene at a time.
- A terminal call that runs longer than 600 seconds goes to the background. Start a long
  render with `background=true` and `notify=true`. Never use `sleep` to wait for it.
- Each 1080p60 minute can use hundreds of MB of disk in `media/`. Delete the folder of a
  job after you deliver it.

## Write the scene

- Start from `scripts/smoke.py` of this skill. It shows `Text`, `MathTex` and a shape.
- A scene file for an animation that the owner asked for is content, not repository code.
  Write it yourself. If the owner asks for Manim code inside a repository, use `hermes-omp`.
- The Manim version is 0.20.1. Do not copy code from old tutorials without a check: names
  changed between versions. Read the error and fix the scene. Run `-ql` again.

## Verify

Run `manim-smoke`. It renders `scripts/smoke.py` in a temporary folder and prints the
size of the video. If it fails, read the last 20 lines of its output and report them.
