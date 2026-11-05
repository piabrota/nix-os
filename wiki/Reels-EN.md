# Reels

[Português](Reels)

The Reels Fabric is an [OpenRig](https://github.com/mvschwarz/openrig) rig that makes one vertical
video of 15 s or 30 s (1080x1920) for Instagram. The full guide is
[`docs/REELS.md`](https://github.com/piabrota/nix-os/blob/main/docs/REELS.md). Its facts were measured
on `piabrota2` on 2026-11-05 or read from the code, and no live run of the rig has happened yet.

## In short

- **Claude only.** No image, video, voice or music API. Every pixel and every sound comes from code
  that a seat runs on the box (`ffmpeg`, `resvg`, `jq`, shell).
- **The screenplay comes first.** One file, `screenplay.json`, is the source. `reel lint` checks its
  rules and `reel approve` records its SHA-256. With no valid approval, nothing after the screenplay
  runs.
- **Five seats, two pods.** `story` (the writer writes, the script editor reviews and approves) and
  `studio` (the director plans, the maker builds, QA checks). All run `omp`.
- **Three phases, two seats at a time.** The unit `openrig` has `MemoryMax=2G`: story, studio and QA,
  with the `rig` commands of `rig.yaml`.
- **Measured:** the 30 s example renders in 105 to 120 s, with a peak of 540 MiB in one `ffmpeg`, and
  makes 5.3 MiB. The 15 s one: 47 to 65 s, 508 MiB, 2.8 MiB.
- **Off.** The option `piabrota.openrig.reels.enable` is off. When on, it adds the toolkit, two
  fonts (the owner's exception to "no fonts"), the folders and the outbox
  `/var/lib/rig-outbox/reels-fabric`.

## What is not proved

A live run of the seats, Instagram's acceptance, and the sound: nobody has listened to it. No footage,
no photo, no voice and no real music: the look is type on a dark sheet. Several numbers (the safe
area, the reading speed, the loudness) are guesses and are listed in "The numbers that are
unverified" of the guide.
