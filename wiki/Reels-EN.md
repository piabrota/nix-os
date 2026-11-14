# Reels

[Português](Reels)

The Reels Fabric is an [OpenRig](https://github.com/mvschwarz/openrig) rig that makes one vertical
video of 15 s or 30 s (1080x1920) for Instagram. The full guide is
[`docs/REELS.md`](https://github.com/piabrota/nix-os/blob/main/docs/REELS.md). Its facts were measured
on `piabrota2` on 2026-11-05 (the toolkit) and 2026-11-08 (Blender) or read from the code, and no live
run of the rig has happened yet.

## In short

- **Claude only.** No image, video, voice or music API. Every pixel and every sound comes from code
  that a seat runs on the box (`ffmpeg`, `resvg`, `jq`, Scala).
- **The screenplay comes first.** One file, `screenplay.json`, is the source. `reel lint` checks its
  rules and `reel approve` records its SHA-256. With no valid approval, nothing after the screenplay
  runs.
- **A film crew, five seats.** The pod `crew`: the creative director (`creative-director`) writes the
  screenplay, the producer-editor (`producer-editor`) approves it and builds the reel, the 3D artist
  (`artist-3d`) makes the 3D shots, the music director (`music-director`) makes the sound, and QA
  checks. The executive producer is the owner, a human, and not a seat. All run `omp`.
- **Five phases, two seats at a time.** The unit `openrig` has `MemoryMax=2G`: story and look,
  picture, 3D shots, sound, and check and publish, with the `rig` commands of `rig.yaml`.
- **Measured:** the 30 s example renders in 105 to 120 s, with a peak of 540 MiB in one `ffmpeg`, and
  makes 5.3 MiB. The 15 s one: 47 to 65 s, 508 MiB, 2.8 MiB.
- **Off.** The option `piabrota.openrig.reels.enable` is off. When on, it adds the toolkit, two
  fonts (the owner's exception to "no fonts"), the folders and the outbox
  `/var/lib/rig-outbox/reels-fabric`.
- **Blender, a second option.** `piabrota.openrig.reels.blender.enable`, off: Blender headless, the
  owner's exception to "no GUI" (2026-11-08). It needs the option above. `reel blender` renders with
  Cycles on the CPU only: EEVEE does not work on this box. One 1080x1920 frame took 8.3 s and
  536 MiB. The 55 minutes for a 15 s reel are an extrapolation, not a measure.

## What is not proved

A live run of the seats, Instagram's acceptance, and the sound: nobody has listened to it. A Blender
render inside the unit `openrig`, and with Blender 5.1.1 (the version of the pinned nixpkgs), has not
run either. No footage, no photo, no voice and no real music: the look is type on a dark sheet, and
the 3D shots are simple scenes. Several numbers (the safe area, the reading speed, the loudness) are
guesses and are listed in "The numbers that are unverified" of the guide.
