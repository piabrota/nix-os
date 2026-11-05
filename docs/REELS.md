# The Reels Fabric

The files are `openrig/specs/rigs/reels-fabric/`, `openrig/specs/agents/reels-*/`, `reels/` (the
toolkit `reel`), the option `piabrota.openrig.reels.enable` in `openrig.nix`, and this page. The
wiki's `Reels` pages summarise it. Facts here were measured on `piabrota2` on 2026-11-05 or read from
the code. What is not proved is in "What is not proved".

## What it is

The Reels Fabric is an [OpenRig](OPENRIG.md) rig that makes one vertical video, 15 s or 30 s,
1080x1920, for Instagram Reels. Five seats work in two pods. The `story` pod writes and approves a
screenplay. The `studio` pod directs, builds and checks the video from that screenplay. The seats
use one toolkit, `reel`, made of POSIX shell, `jq`, `ffmpeg` and `resvg`.

The rig is a definition only. The option is off, nobody starts the rig, and the owner decides when
to test it.

## The owner's constraints

The owner's order (2026-11-05): "Create a comprehensive Reels Fabric to generate high quality videos,
in Instagram format, 30 seconds, defined as a rig. It must not use generative video or media APIs:
Claude only. Reels configs are 15 s or 30 s. The screenplay must be a first-class citizen."

- **Claude only.** The one model is Claude (Sonnet, through the subscription, as in the other rigs).
  No service makes an image, a video, a voice or a piece of music. No stock footage and no download.
  Code that a seat runs on the box makes every pixel and every sound.
- **15 s or 30 s, 1080x1920, 30 fps.** `reels/profile.json` has no other format.
- **The screenplay comes first.** One file, `screenplay.json`, is the source of the reel. Every other
  file comes from it and cites its beat ids. Nothing after the screenplay runs unless it is approved.

## The screenplay

`screenplay.json`, schema `reels.screenplay/1`. The top level has `slug`, `title`, `format` (15 or 30),
`logline`, `audience`, `language`, `loop` (true or false), `claims`, `look` (`style`: `piabrota`,
`paper` or `mono`) and `music` (`preset`, `bpm`). `beats` is the list of beats. A beat has:

|Field|Meaning|
|---|---|
|`id`|`b01`, `b02`, in order|
|`t_in`, `t_out`|Seconds. The beats touch each other, the first starts at 0 and the last ends at `format`.|
|`role`|`hook`, `setup`, `turn`, `proof`, `payoff`, `cta` or `loop`|
|`visual`|`describe` (words), `scene` and `params`. The scenes are `title_card`, `big_number`, `bullet_reveal`, `quote`, `split_compare`, `timeline`, `diagram_reveal`, `kinetic_text` and `outro_loop`.|
|`text`|The on-screen lines. `*word*` marks the emphasis.|
|`sound`|`music` (`on`, `low`, `off`), `sfx` (`{name, at}`: `whoosh`, `tick`, `hit`, `riser`, `pop`) and `silence`|
|`transition`, `transition_s`|How the beat comes in, for example `cut`, `fade` or `slideleft`|
|`claims`, `note`|The ids of the claims that the beat states, and a note|

Every claim has an `id`, a `text`, a `source` and a `status` (`own`, `sourced` or `needs-check`; the
lint refuses `needs-check`). There is no `vo` field: the voice-over is off in v1 and the lint rejects
the field while `voice` is false in the profile.

A real example. This is the top of `reels/examples/30/screenplay.json` and its first beat. The other
claims and the other seven beats are cut.

```json
{
  "schema": "reels.screenplay/1",
  "slug": "marola-praia-30",
  "title": "A praia boa hoje? Ou sem dados.",
  "format": 30,
  "language": "pt-BR",
  "loop": true,
  "claims": [
    { "id": "c5", "text": "A marola diz que praia está boa para nadar hoje e a melhor hora de amanhã", "source": "marola.dev, página inicial (resumo do dono, 2026-11-03)", "status": "sourced" }
  ],
  "look": { "style": "piabrota" },
  "music": { "preset": "pulse", "bpm": 96 },
  "beats": [
    {
      "id": "b01", "t_in": 0, "t_out": 2.8, "role": "hook",
      "visual": { "describe": "Dark sheet. The question lands word by word in big type, one word in red.", "scene": "kinetic_text", "params": {} },
      "text": ["Essa praia está boa", "pra *nadar* hoje?"],
      "sound": { "music": "on", "sfx": [{ "name": "hit", "at": 0.0 }] },
      "transition": "cut",
      "claims": ["c5"]
    }
  ]
}
```

The words on screen are in `language`. The files and the messages of the seats are in English.

## The gate

`reel lint` checks the schema and the rules. An error blocks the approval. A warning does not.
The main rules:

- The beats are contiguous and end at 15 or 30 s. A beat is at least 0.8 s.
- The first beat is the hook. It ends by 3 s and should have text.
- The reading speed is at most 15 characters a second, with at most 5 lines and 28 characters a line.
- A `cta` or a `loop` role is allowed only in the last beat. If `loop` is true, the last beat uses
  `outro_loop`.
- Every claim has a source or `own`. A beat cites only claims that exist.
- The look names a style. A `TODO` anywhere is an error.
- The reel has some sound: music or at least one effect, and at most 6 effects in a beat
  (`sfx_per_beat`). QA holds the loudness to a target, so a silent file would never pass.
- No control character and no string over 1000 characters. A symbol or an emoji that the two fonts
  may not draw is a warning.

`reel approve <slug> [--by <name>]` runs the lint. If it passes, it writes `screenplay.approved` in the
project: the line `<sha256>  screenplay.json` first, and the time and the name on line 2. Every
stage reads the screenplay and the approval again, and runs the lint again: an approval written by
hand does not skip the rules. It also checks that the slug in the file is the folder's, and it
refuses a link in place of either file.

Then `reel shotlist`, `still`, `scene`, `music`, `mix`, `render`, `qa`, `contact-sheet` and `publish`
check the hash first. They stop with a clear line if the file is missing or the screenplay changed:

```console
$ reel render demo
reel: screenplay.json of demo changed after its approval, or the approval is not in the form of reel approve (now 6ec284fe): the writer fixes it, then lint and approve again
```

This ran on 2026-11-05: a changed title made `render` and `publish` stop with that line. A 31 s
screenplay, a hook that ends at 4 s and a line of 46 characters each failed `reel lint` with one
`ERROR` line for the broken rule.

Only the writer edits `screenplay.json`. The script editor approves after a review. The owner may
approve too. Hermes never approves.

## The seats

|Pod|Seat|Reads|Writes|
|---|---|---|---|
|`story`|`story-writer@reels-fabric`|The owner's brief, the toolkit's examples|`brief.md`, `screenplay.json`|
|`story`|`story-script-editor@reels-fabric`|`brief.md`, `screenplay.json`, `reel lint`, `reel screenplay-view`, `reel timing-report`|`review/screenplay.review.md`, and `screenplay.approved` through `reel approve`|
|`studio`|`studio-director@reels-fabric`|The approved screenplay|`direction/shotlist.json`, `direction/svg/`, `direction/storyboard/<beat>.png`|
|`studio`|`studio-maker@reels-fabric`|The screenplay and the shotlist|`build/`, `out/<slug>/reel.mp4` (through `reel render`), `review/build.md`|
|`studio`|`studio-qa@reels-fabric`|`reel.mp4`, `qa.json`, the frames, the screenplay|`out/<slug>/qa.json` and `qa/` (through `reel qa`), `review/qa.md`, the outbox (through `reel publish`)|

All five seats run `omp` on `anthropic/claude-sonnet-5-5`, without approval prompts
(`permission_policy: builtin:yolo`, as in the other rigs). A member can run `runtime: claude-code`
with one line (see [`RUNTIMES.md`](RUNTIMES.md)). The edges are `delegates_to` and form a chain:
writer, script editor, director, maker, QA. Each seat sends the next one the slug and a path, never
the content. A verdict (approve, revise, pass, fail) comes with evidence and a round number. After
3 rounds a loop stops and the owner decides.

What a seat does not do:

- The writer is the only seat that edits the screenplay. A change goes back to it.
- The script editor writes only the review file. It never edits the screenplay, not even a typo.
- The director writes only `direction/`. A change that the screenplay needs goes back to the writer.
- The maker cannot add a scene template: the toolkit is in the Nix store, read only. It reports the
  gap with the beat id. It does not render a clip by hand with `ffmpeg`.
- QA reads only. It cannot listen: it writes the loudness as a number and the sound as "no data".
- No seat starts or stops a seat, and no seat has a network.

## The phases

The unit `openrig` has `MemoryMax=2G` and `MemoryHigh=1536M`. One omp seat takes about 340 MiB and
the idle daemon about 220 MiB (`hermes/skills/hermes-omp/references/openrig-seats.md`, measured on
2026-11-04). A render adds one `ffmpeg` of up to 540 MiB (see "Measured numbers"). So the rule is
**two seats at the same time, no more**, and one `reel` command at a time. The rig has five seats, so
the operator starts them in three phases. The commands are those of `rig.yaml`:

```console
rig import /etc/openrig/specs/rigs/reels-fabric/rig.yaml --materialize-only   # records five seats, starts none

# phase 1, story
rig launch reels-fabric story.writer
rig launch reels-fabric story.script-editor
rig send story-writer@reels-fabric "<slug>, <15|30>, <the owner's brief>" --verify
# done when `reel approve` has written screenplay.approved (at most 3 rounds)
rig seat stop story-writer@reels-fabric --reason "phase 1 done"
rig seat stop story-script-editor@reels-fabric --reason "phase 1 done"

# phase 2, studio
rig launch reels-fabric studio.director
rig launch reels-fabric studio.maker
rig send studio-director@reels-fabric "<slug>, <project path>, direct it" --verify
# done when the shotlist and the storyboard exist and out/<slug>/reel.mp4 exists; then stop the director

# phase 3, qa
rig launch reels-fabric studio.qa          # the maker is still up: two seats
rig send studio-qa@reels-fabric "<slug>, <out path>, check it" --verify
# done when `reel publish` has run; then stop both
```

`rig launch` starts a seat that never ran. `rig seat launch <seat> --fresh --reason "<why>"` starts a
blank conversation in a seat that ran before. A seat with nobody to send to ends with a final answer,
and the operator starts the next seat. A QA fail goes to a seat that is stopped by then: start it in
place of the director or the maker, so that two seats run. Run `kvm4-health` before each phase and
`rig snapshot reels-fabric` before you stop. A rig keeps the spec it was made from: after a change
to the spec, `rig archive reels-fabric` and import it again. Do not run it at the same time as another
rig.

The owner decides the brief, the start of phase 2 and what to do with the published reel. The owner
may read `reel screenplay-view <slug>` before phase 2. Nothing here posts to Instagram.

## The project folders

`REELS_HOME` is `/var/lib/openrig/work/reels-fabric`. The option makes these folders (`StateDirectory`
of the unit, mode 0700, owner `openrig`): one for each seat (`writer`, `script-editor`, `director`,
`maker`, `qa`), `projects` and `out`.

```text
$REELS_HOME/
  projects/<slug>/
    brief.md                      writer
    screenplay.json               writer, the one source
    screenplay.approved           reel approve: SHA-256 of screenplay.json
    review/                       screenplay.review.md, build.md, qa.md
    direction/                    shotlist.json, storyboard/<beat>.png, svg/
    build/                        reel writes it: scenes/, audio/, layers/, cache/
  out/<slug>/
    reel.mp4  render.json  qa.json
    qa/                           hook.png, <beat>.png, <beat>-start.png, contact-sheet.png
$REELS_OUTBOX/<slug>/             reel publish: reel.mp4, qa.json, screenplay.json, review/
```

`REELS_OUTBOX` is `/var/lib/rig-outbox/reels-fabric`. A slug has lowercase letters, digits and `-`, at
most 41 characters. The seat folders hold the norms (`AGENTS.md`) of each seat and nothing else.

## The toolkit

`reel help` lists the commands. The first group needs no approval:

|Command|Does|
|---|---|
|`reel new <slug> <15\|30> [--example]`|Makes the project folder and a screenplay skeleton, or a copy of the example|
|`reel lint <slug\|file.json>`|The rules of the screenplay, and of the shotlist if there is one|
|`reel screenplay-view <slug\|file>`|The screenplay as a two-column script: picture, and text with sound|
|`reel timing-report <slug\|file>`|The table read: reading speed and hold time of each beat. It exits 1 when a beat is too fast.|
|`reel approve <slug> [--by <name>]`|Writes `screenplay.approved` when the lint passes|

These refuse to run without a valid approval:

|Command|Does|
|---|---|
|`reel shotlist <slug> [--force]`|The default `direction/shotlist.json`, one shot for each beat, for the director to refine|
|`reel still <slug> <beat> [--at <s>] [-o <file>]`|One frame of a beat. The default file is `direction/storyboard/<beat>.png`.|
|`reel scene <slug> <beat>`|The clip of one beat, in `build/scenes/`|
|`reel music <slug>`|The procedural music bed, `build/audio/music.wav`|
|`reel mix <slug>`|Music and sound effects, normalised, `build/audio/mix.wav`|
|`reel render <slug>`|The sound, the clips and the assembly: `out/<slug>/reel.mp4` and `render.json`. It needs the shotlist.|
|`reel qa <slug>`|Facts, loudness, frames and safe area: `out/<slug>/qa.json` and `qa/`. It exits 1 on a fail.|
|`reel contact-sheet <slug>`|`out/<slug>/qa/contact-sheet.png`, all the beat frames in one picture|
|`reel publish <slug> [--replace]`|Copies the video to the outbox. It needs a passing `qa.json` of this very file and this very screenplay. It never overwrites a slug without `--replace`, and never touches another slug.|

`reel render` makes the clips one by one and builds the video in stages of at most 4 inputs, so
that one `ffmpeg` stays small. A clip is kept when nothing it depends on changed. `reel qa` checks:
container, codec (`h264`), size, pixel format (`yuv420p`), frame rate, duration (within 0.05 s of 15
or 30), audio (`aac`, 48000 Hz, 2 channels, and a length within 0.1 s of the format), `+faststart` (moov before mdat), loudness, true peak, that
the render came from the approved screenplay, the hook picture at 0.5 s, and, for every beat, that the
picture is inside the safe area and has contrast. It does this with measures, with no model. QA
reads the file, never the shotlist.

An example session, with the example screenplay (it ran on 2026-11-05, from the built package, in an
empty environment):

```console
$ reel new demo 30 --example
$ reel lint demo
lint: 0 error(s), 0 warning(s)
lint: PASS
$ reel approve demo --by script-editor
approved: demo (sha256 d7fee787e42ed72cc2c694a8ca830ae3909675a1c6cb5c73681931e97a0273e3)
$ reel shotlist demo
$ reel render demo
render: .../out/demo/reel.mp4 (5520735 bytes, 120 s wall, 539.4 MiB peak in one ffmpeg)
$ reel qa demo
pass  size: 1080x1920
pass  loudness (LUFS): -14.30
qa: PASS (.../out/demo/qa.json, frames in .../out/demo/qa)
$ reel contact-sheet demo
$ reel publish demo
published: $REELS_OUTBOX/demo (5520735 bytes)
```

The variables the toolkit reads: `REELS_HOME`, `REELS_OUTBOX`, `REELS_SHARE` (its data: the profile,
the styles, the examples and the fonts) and `REELS_FONTS`. The rig sets the first two in its `env:`.
`REELS_HOME`, `REELS_SHARE`, `REELS_FONTS` and `TMPDIR` may hold only letters, digits and `/ . _ -`:
the paths reach `ffmpeg` filters and caption files. Each `ffmpeg` stops after 300 s and each `resvg`
after 60 s (`limits` in the profile), with a clear line, so a stuck process does not hold a seat.

## What it makes and what it cannot

It makes text on a dark sheet with one red accent, in the look of `site/DESIGN.md`: Fjalla One for
titles, Inter for text. The nine scenes are typographic layouts with simple drawings in SVG. The
motion is a word-by-word entrance, a slow zoom of the background (`camera.zoom` in the shotlist), 15
transitions besides `cut` (`fade`, slides, wipes, circles and more) and a gradient. The sound is a
procedural music bed (`pulse`, `ambient`, `tension`, `upbeat`) and five sound effects, all made of
sine waves and filtered noise.

It cannot make:

- footage, a photo of a place, a person, an animal or a real wave. The toolkit has no source of them.
- a voice. The voice-over is off in v1.
- real music. The bed is a loop of synthetic tones, and nobody has listened to it: the box has no ear.
  Judge it by ear before you publish.
- a look that wins a prize. The contact sheet of the example is clean and readable, and it is a
  set of cards with the lower third of the frame empty (it is the Instagram safe area). A reel of
  this kind is an explainer or a quote card in motion, not a film.

The look and the sound are the open question of this rig. The next step after a first test is to
read what the owner thinks of them.

## Measured numbers

Measured on this box (`piabrota2`) on 2026-11-05, with the built package, an empty environment, the
example screenplays and GNU `time`. The 30 s render took 105 s, 105 s and 120 s in three runs, and the
15 s render took 65 s, 47 s and 56 s: another `omp` run used the CPU at times (the load average at the
start of a run was between 0.04 and 3.9). The runs were by the user `hermes`, not inside the unit
`openrig`. The peak memory of a 30 s render was 549, 542 and 539 MiB (the toolkit changed a little
between the runs). The table has the last run of each.

|Number|30 s|15 s|
|---|---|---|
|`reel render`, wall time|120 s|56 s|
|`reel render`, peak memory (the largest `ffmpeg`)|540 MiB|508 MiB|
|`reel render`, `ffmpeg` runs|19|13|
|`reel.mp4`, size|5,520,735 bytes (5.3 MiB)|2,928,943 bytes (2.8 MiB)|
|`reel qa`, wall time, peak memory|4.2 s, 110 MiB|3.7 s, 109 MiB|
|`reel contact-sheet`, wall time|2.5 s|2.2 s|
|Loudness, true peak|-14.30 LUFS, -0.82 dBTP|-14.18 LUFS, -1.42 dBTP|
|`new`, `lint`, `approve`, `shotlist`, `publish`|each under 0.1 s|each under 0.1 s|

The file: H.264 High, `yuv420p`, 1080x1920, 30 fps, 900 frames in 30.000 s, AAC 48000 Hz stereo,
about 1.5 Mbit/s, `qa` passes. The sum: the daemon (about 220 MiB) with two seats (about 340 MiB each)
and one render (540 MiB) is about 1.4 GiB, just under `MemoryHigh=1536M` and over it if a seat grows.
So the maker and QA run one `reel` command at a time, and nothing else runs during a render.

The size of the toolkit: `reel` alone is 332 MiB with its closure (`nix path-info -S`); 199 MiB of
that, in 64 store paths, is not in the closure of the running system (compared with
`/run/current-system` on 2026-11-05). The part that is ours is 1.2 MB: the scripts, the profile, the
styles, the examples and two font files.

## Where the video goes

`reel publish` copies `reel.mp4`, `qa.json`, `screenplay.json` and `review/` to
`/var/lib/rig-outbox/reels-fabric/<slug>/`. The folder is owned by `openrig`, group `hermes`, mode
2750 (setgid, so a new file takes the group `hermes`), with a default ACL for the group. `reel publish`
also gives the group read access to what it copies, because the unit's `UMask` is 077. `systemd-tmpfiles` removes files older
than 14 days. The outbox is outside `/var/lib/openrig`, which Hermes's deny list blocks. Hermes reads
the files there and shows the owner the video path, the screenplay view, the QA verdict and the
contact sheet (which stays in `out/<slug>/qa/` and is not copied).

How the file reaches the owner is open. A video of 5.3 MiB may be under the file limit of the chat
channel, but this was not checked: check the limit before you send it. Instagram's own upload is not
done here.

## The numbers that are unverified

The keys of `unverified` in `reels/profile.json` are guesses, not facts that anyone checked against
Instagram or a standard. The lint and QA use them as they are:

|Key|Value|Meaning|
|---|---|---|
|`safe.top`, `safe.bottom`, `safe.side`|0.14, 0.35, 0.06|The share of the frame that stays free of text and drawings|
|`text.max_cps`|15|Characters a second|
|`text.max_lines`, `text.max_chars_per_line`|5, 28|The size of the text of a beat|
|`audio.target_lufs`, `audio.lufs_tolerance`|-14, 2.0|The loudness the mix aims at, and how far QA lets it go|
|`audio.true_peak`, `audio.true_peak_slack`, `audio.premix_peak`|-1.0, 0.5, -2.0|dBTP limits|
|`video.crf`|20|The quality of the final video|
|`qa.min_text_range`, `qa.edge_min`, `qa.safe_slack_px`, `qa.probe_frac`, `qa.audio_tolerance_s`|60, 40, 8, 0.7, 0.1|The thresholds and the probe point of the checks of QA|
|`limits.ffmpeg_timeout_s`, `limits.resvg_timeout_s`, `sfx_per_beat`|300, 60, 6|The time limits of `ffmpeg` and `resvg` in seconds, and the effects a beat may have|

Also unverified, because they are not facts about Instagram: that its upload accepts the file, how the
app crops and covers the frame, and how loud 14 LUFS is next to other reels. The hook time (3 s),
the shortest beat (0.8 s) and the formats are choices of this design, not guesses of a measure.

## Turn it on

Set `piabrota.openrig.reels.enable = true;` in `hosts/piabrota2/default.nix` and open a pull request.
The merge deploys it. The option adds:

- the toolkit `reel` in the profile of the user `openrig` and in the unit's `path`, with
  `ffmpeg-headless` and `jq`. The toolkit has its own `ffmpeg-headless`, `resvg`, `jq`, `coreutils` and
  `time`.
- two font files, Inter (879,708 bytes) and Fjalla One (209,052 bytes). This is the owner's exception to
  "no fonts" in `AGENTS.md`: two files in `share/reels/fonts`, no collection, no `fontconfig` of the
  system, no GUI.
- the folders of "The project folders" in the `StateDirectory` of the unit.
- the outbox `/var/lib/rig-outbox/reels-fabric` (2750 `openrig` `hermes`, 14 days, default ACL
  `group::r-X`), and `ReadWritePaths` for it. The parent `/var/lib/rig-outbox` is shared with the wave
  rig, and both options can be on.

With the option off, the specs are in `/etc/openrig/specs` as a definition only and nothing else
changes. The deploy restarts `openrig` and ends the seats (see [`OPENRIG.md`](OPENRIG.md)).

To build the toolkit without the option:

```console
nix build --impure --expr '(builtins.getFlake "path:'$PWD'").nixosConfigurations.piabrota2.pkgs.callPackage ./reels {}'
```

## A first test

1. Turn the option on and deploy. Run `rig status` and `kvm4-health`.
2. As the owner, run the import of "The phases", once.
3. Run phase 1 with a short brief: one fact, one source, 15 s. Read `reel screenplay-view <slug>`.
4. Run phase 2 and phase 3 as written.
5. Open `reel.mp4` and `qa/contact-sheet.png`. Listen to the sound. Say what is wrong with it.

To test the toolkit without a rig, run `reel new demo 15 --example` and the session above with
`REELS_HOME` and `REELS_OUTBOX` set to scratch folders.

## Risks

- **Memory.** A render goes above 450 MiB for a short time. With two seats and the daemon it leaves
  little room under `MemoryHigh`. The kernel slows the unit, it does not kill it, but a render with a
  third process may reach `MemoryMax`. `OOMPolicy=continue` takes one process.
- **CPU.** A render of 30 s ran for 105 to 120 s, at `nice -n 10`, with one video thread for the final
  encode. It slows the other units a little. It does not run on a schedule.
- **A seat is not a checker.** The lint measures what it can. A claim is "sourced" because a person
  wrote a source in the brief; the script editor cannot open a link. The sources need a human.
- **Run without approval prompts.** As in the other rigs: the deny rules of `hermes/omp.yml` are the
  guard.
- **A word of the screenplay may not fit.** Long words or other languages may be wider than the
  frame. QA checks the safe area by measure and a seat looks at the frame.

## What is not proved

- A live run of the rig: no seat has done a task of this rig. The guidance of the seats, the
  messages between them and the three phases are from the specs and not from a run.
- That OpenRig accepts the spec (`rig spec validate` is not run here: there is no `rig` in this
  worktree).
- Instagram's acceptance of the file, and how the app shows it.
- The look in the eyes of the owner, and the sound at all: nobody has listened to it.
- Hermes's read of the outbox under the `hermes-agent` sandbox, as for the wave rig.
- The numbers of "The numbers that are unverified".

## Credits

- [FFmpeg](https://ffmpeg.org) (`ffmpeg-headless` 8.1.3, with libx264 and libass; the license in
  nixpkgs is LGPL-2.1-or-later or GPL-2.0-or-later and the build with libx264 is GPL).
- [resvg](https://github.com/linebender/resvg) 0.47.0 (MPL-2.0) draws the SVG.
- [jq](https://github.com/jqlang/jq) 1.8.2 (MIT) does the screenplay logic.
- [Inter](https://rsms.me/inter/) 4.1 by Rasmus Andersson (SIL OFL 1.1), from nixpkgs.
- [Fjalla One](https://fonts.google.com/specimen/Fjalla+One) by Sorkin Type (SIL OFL 1.1: the file is
  in the `ofl/` folder of [google/fonts](https://github.com/google/fonts) and its name table names the
  license), at the commit that nixpkgs' `google-fonts` pins.
- [OpenRig](https://github.com/mvschwarz/openrig) by mvschwarz (Apache-2.0), and the toolkit itself,
  MPL-2.0, as the rest of this repository.
