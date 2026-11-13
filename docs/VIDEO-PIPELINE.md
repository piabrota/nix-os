# Video lab: a spec for faceless YouTube videos on piabrota2

Status: **draft spec, 2026-11-04.** This file is the plan. Hermes runs it later, with subagents and
`omp`. The only code today is the dummy pipeline in `video-lab/dummy/`. English only, by the
owner's order.

## 1. Goal

Make videos of up to 15 minutes, with a target of 10 minutes, for a faceless channel. The
pipeline is open source, runs without a GPU on `piabrota2` (KVM 4), and sends the heavy work to the
owner's PC when it is on.

A person reviews every video before it goes out. The pipeline does not publish by itself.

## 2. Decisions the owner must make first

| # | Decision | Why it blocks |
|---|---|---|
| D1 | Niche and language of the channel | Sets the script rules, the voices and the source types. |
| D2 | Images: stock and public domain, or generated on the owner's PC | Sets the licence list and the PC load. |
| D3 | Upload: by hand in YouTube Studio, or by API after an audit | The API holds uploads private until the project passes an audit. |
| D4 | Where the heavy work runs: this box only, or the owner's PC too | Issue 117 (Ollama on the PC) is the same link. |
| D5 | Who reviews each video, and how fast | The review gate (stage 9) needs a name. |

Until D1 to D5 have an answer, only phases 0 and 1 (section 8) can run.

## 3. Limits that shape the design

Measured on piabrota2 on 2026-11-04, unless noted.

- 4 vCPU, 16 GB RAM, no GPU. The memory caps of the other units add up to 13.25 GiB. About 2.4 GiB stays
  free. **One video job at a time.**
- Render test: one still image with a slow zoom, 1080p30, 10 s of video. `veryfast` took 1.9 s with a
  peak of 395 MiB. `medium` took 3.2 s with a peak of 638 MiB. For 10 min, this means about 2 to 3
  min in the best case. Real scenes cost more. Phase 3 measures it.
- `ffmpeg` on the box has `libx264`, `libx265`, `libsvtav1`, `libvpx-vp9`, `libass`, `libfreetype`,
  and the filters `drawtext`, `subtitles`, `zoompan`, `xfade`, `loudnorm`, `sidechaincompress`.
- Disk: 157 GB free. The Nix store is cleaned each week.
- `allowUnfree` is off. No Docker, no browser, no heavy resident service on the box. Node is the owner's
  exception for Paperclip only.
- An agent never deploys. Install tools with `nix shell nixpkgs#<name>` first. A change of the system
  is a normal pull request, and the owner merges it.

## 4. The stages and their files

Each video has one folder: `work/<slug>/`. Each stage reads files of the stages before it and writes
its own files. A stage that fails leaves no half file (write to a temporary name, then rename).

```text
1 brief -> 2 script -> 3 voice -> 4 timing+captions -> 5 visuals -> 6 music+mix
        -> 7 assemble+render -> 8 thumbnail+metadata -> 9 review gate -> 10 publish
```

| Stage | Input | Output | Tool (box unless noted) |
|---|---|---|---|
| 1 Brief | topic, sources the owner approves | `brief.json` (topic, angle, length target, sources, language) | Hermes |
| 2 Script | `brief.json` | `script.json` (scenes: id, narration text, visual hint, rough seconds) | Hermes with Claude. Haiku subagents gather facts. |
| 3 Voice | `script.json` | `voice/<scene>.wav`, `voice.json` (voice id, licence) | Kokoro or Piper (CPU) |
| 4 Timing | `voice/*.wav` | `timing.json` (word times), `captions.ass` | `whisper.cpp` |
| 5 Visuals | `script.json`, `timing.json` | `visuals/<scene>.png` or `.mp4`, `assets.json` | stock or CC0 sources, Manim (CPU), Ken Burns with `ffmpeg`; generated images on the PC |
| 6 Audio mix | `voice/*.wav`, music choice | `mix.wav` (loudness set, music ducked under voice) | `ffmpeg` (`loudnorm`, `sidechaincompress`) |
| 7 Render | all of the above | `video.mp4` | `ffmpeg` with `libx264` |
| 8 Metadata | `script.json`, `video.mp4` | `thumb.png`, `meta.json` (title, description, tags, AI label, chapters) | ImageMagick, Hermes |
| 9 Review gate | stage 8 files | `review.md` signed by a person | the owner |
| 10 Publish | `video.mp4`, `meta.json` | the video, `published.json` | YouTube Studio by hand, or the API |

`assets.json` lists every asset: file, source URL, licence, author, and the attribution text. A
video with an asset that has no licence line does not pass stage 9.

## 5. Tools and what they cost

Licences were read on 2026-11-04 from the GitHub API and from the Hugging Face model cards.
Download sizes come from `nix build --dry-run`.

**Use first**

| Tool | Role | Licence | Size on the box |
|---|---|---|---|
| `ffmpeg` | all assembly and render | LGPL/GPL | already installed |
| `whisper.cpp` | word times for captions | MIT | 162 MiB (506 MiB unpacked) |
| Kokoro-82M (`python3Packages.kokoro`) | CPU voice | code Apache-2.0, weights Apache-2.0 | 584 MiB (2.6 GiB unpacked) |
| Piper (`piper-tts` 1.8.0) | faster CPU voice | GPL-3.0; check the licence of each voice | 845 MiB (3.2 GiB unpacked) |
| ImageMagick | thumbnails | Apache-2.0 | 16 MiB |
| Manim (`manim` 0.22.1) | diagrams and step animations | MIT | 606 MiB (1.7 GiB unpacked) |

Third-party benchmarks (not measured here) give a real-time factor of about 0.05 for Piper and about 0.46 for
Kokoro on a CPU. Phase 2 measures both on this box and picks one.

**On the owner's PC only (GPU)**

FLUX.1-schnell (weights Apache-2.0), Wan2.1 (Apache-2.0), Chatterbox (MIT), ComfyUI (GPL-3.0) as the hub.
Check the licence of LTX-Video weights ("other") before use.

**Do not use**

- F5-TTS weights (CC-BY-NC), Fish Speech weights (CC-BY-NC-SA), FLUX.1-dev (non-commercial).
- MusicGen weights (CC-BY-NC) and Stable Audio Open (community licence). Use CC0 or CC-BY music with
  the attribution in `assets.json`.
- `edge-tts`: it calls an unofficial online service of a third party.
- `MoneyPrinterV2` (AGPL-3.0) and Remotion (not an open source licence).
- Revideo and Motion Canvas: they need Node and a headless browser.
- Any voice that clones a real person, and any music that is not licensed.

**Reference, not a dependency:** MoneyPrinterTurbo (MIT, active). It supports 16:9 at 1080p, Pexels,
Pixabay, Kokoro and Chatterbox. Its focus is short videos, and its quality at 10 min is not checked.

## 6. Who does what

Hermes (Sonnet) is the orchestrator. It plans, reviews every diff, decides, opens the pull
requests and talks to the owner. It does not write code with its own file tools.

**Haiku subagents** (`delegate_task`). Read-only fan-out only: at least three independent jobs at a
time, and never a decision or a diff. Hermes checks every result.

- S-A: read the model card and licence of each tool in section 5, and report changes.
- S-B: read the terms of one stock source each (Pexels, Pixabay, Wikimedia, NASA, Internet Archive) and
  list what they allow for a monetised video.
- S-C: collect primary sources and quotes for one script topic, with links, for Hermes to check.
- S-D: draft ten title and tag options for a finished script.

**`omp`** (Sonnet). One run at a time, at most 15 minutes, from a task file in
`omp-tasks/video-<ticket>.md` with a progress file. It writes and tests code for one ticket. Before a
run longer than 10 minutes, Hermes checks `systemctl show hermes-agent -p NRestarts` and
`gh run list --workflow deploy.yml --limit 1`. It does not start while a deploy is in progress. The
owner does not merge a pull request of `nix-os` during a run.

**Paperclip** (optional, after pull request 119): one `showrunner` agent on `hermes_gateway` and one
`engineer` agent on `pi_local`, with a budget cap for each. This is not needed for phases 0 to 3.

**The owner** picks the niche, approves the sources, reviews each video at stage 9, and merges.

Parallel limit: one `omp` run and up to three Haiku subagents at the same time.

## 7. Task file for omp (template)

```text
# Task: <ticket id and one line> (repository: piabrota/nix-os, branch hermes/<slug>)
Read AGENTS.md and docs/VIDEO-PIPELINE.md. Touch only: <list of paths>.
Do not commit, push or open pull requests. Do not read secrets. Do not change .github/.
Progress file: omp-progress.txt in the repository root. Read it first. Append one line per finished step.
Input: <files and their format>. Output: <files and their format>.
Done when: <one command and the output it must give>.
Limits: peak memory <N> MiB, wall time <N> min. Report what you could not check.
```

## 8. Work plan

Each phase ends with an artifact and a number. Do not start a phase before the one before it is done.

**Phase 0: decisions.** Owner answers D1 to D5. Subagents S-A and S-B run in parallel. Done when
`docs/VIDEO-PIPELINE.md` holds the answers and the licence table has no blank.

**Phase 1: the dummy pipeline (this pull request).** Run `just video-dummy`. It must write
`video-lab/out/dummy/dummy.mp4` and `report.json`. Done when `ffprobe` shows a video and an audio stream and
a duration near 30 s. It proves stages 5 to 7 and the report. It tests nothing else.

**Phase 2: voice and timing.** Install by `nix shell`: `whisper-cpp`, then Kokoro and Piper. Make one
`script.json` of about 1,500 words. For each voice record: wall time, real-time factor, peak memory,
and a person's score for the sound (1 to 5). Run `whisper.cpp` on the result and record the word
error. Done when one voice is chosen and the numbers are in `docs/VIDEO-PIPELINE.md`. Ticket for `omp`:
`video-lab/stages/voice.py` and `timing.py` with the contract of section 4.

**Phase 3: render budget.** Make a 10-minute synthetic timeline with 60 scenes, captions, a cross
fade and a mix. Record wall time and peak memory for `veryfast`, `medium` and `libsvtav1`. Done when the
budget is set: peak memory below 3 GiB, and total render time below 30 min. If it is not, move the render
to the owner's PC.

**Phase 4: visuals.** Build the scene types: a Ken Burns image, a stock clip with a crop, a text card,
and a Manim diagram. Record `assets.json` for each. Done when one 2-minute mini episode renders with all four
types and passes a read of `assets.json`.

**Phase 5: script quality.** Hermes writes the script from the brief, with source links. Subagent S-C
collects the sources. A person reads the first three scripts and marks problems. Done when two
scripts in a row pass without a factual change.

**Phase 6: first full episode.** Run stages 1 to 8 for a 10-minute video. The owner reviews it at stage 9.
Done when the owner approves or lists the changes. Publish by hand.

**Phase 7: scale and automate.** Add a queue, a night run with `systemd-run --user -p MemoryMax=3G
-p CPUWeight=20`, cleanup of `work/` after upload, and the API upload if D3 says so. A cron job
starts a job only when `kvm4-health` is healthy.

## 9. What to install and test first

Install by `nix shell`, one tool at a time. Record the size on disk after each.

1. Nothing for phase 1. The `ffmpeg` of the box is enough.
2. `nix shell nixpkgs#whisper-cpp` then a 30 s test file.
3. `nix shell nixpkgs#python3Packages.kokoro` (584 MiB). If the model files need a download, record the URL
   and the licence before you fetch.
4. `nix shell nixpkgs#piper-tts` (845 MiB).
5. `nix shell nixpkgs#imagemagick` for the thumbnail.
6. `nix shell nixpkgs#manim` only at phase 4.

Smoke checks, in this order. Each prints a number, and none is a formal test:

1. `just video-dummy` makes an MP4 (phase 1).
2. `ffprobe` shows H.264 video and AAC audio, 1280x720, about 30 s.
3. TTS: 500 characters, three runs; record real-time factor and peak memory.
4. `whisper.cpp` on the TTS output; compare the words with the script.
5. Render: 10 s of the real timeline; scale the numbers to 10 min before you run the full render.
6. Full 10-minute render, once, at low priority (`nice -n 10`).

## 10. Rules for the box

- One job at a time. Run heavy work with `nice -n 10`. Check `kvm4-health` first.
- Keep `work/` and `out/` outside git. After a video is published, keep only `video.mp4`, `meta.json`
  and `assets.json`.
- Never put a key in a file of this repository. The Pexels key, if any, goes in a file on the box
  that only the job reads.
- A stage writes a temporary file and renames it. A run that stops leaves no half file.

## 11. Policy and risk

- **Monetisation.** Since 15 July 2025 the YouTube policy "inauthentic content" excludes content that
  is repetitive or mass-produced. A channel of one template, a synthetic voice and stock clips can fail.
  What helps: an original, researched script, a real edit, a person who reviews every video, and
  variety. Source: <https://support.google.com/youtube/answer/1311392>.
- **AI label.** Realistic synthetic content needs the disclosure in YouTube Studio. Put the choice in
  `meta.json` and review it at stage 9. Source: <https://support.google.com/youtube/answer/14328491>.
- **Upload by API.** The method `videos.insert` from an unverified API project makes the video private.
  A compliance audit lifts this. Test with a private test channel before you plan on it. Source:
  <https://developers.google.com/youtube/data/guides/quota_and_compliance_audits>. The quota cost
  of an upload was not read: check the quota calculator of Google.
- **Sensitive topics.** If the niche is true crime or similar: do not name a private person, do not claim a
  guilt that a court did not find, and add sources on screen. This is a stage 9 check.
- **Not allowed in this project:** the transcript or video of a channel that is not yours, a cloned voice
  of a real person, music or footage without a licence line, and any step made to avoid a YouTube
  check or detection.

## 12. Open questions

1. Which language and voice for the channel? Kokoro and Piper differ a lot by language.
2. Does the owner want a fixed visual style (colours, fonts, an intro)? It goes in
   `video-lab/style.json` at phase 4.
3. Is a Pexels key acceptable, or only public-domain sources?
4. Is the owner's PC on in the evenings? That decides the use of generated images.

## 13. The dummy pipeline

`video-lab/dummy/run.py` makes a 30 s, 1280x720 video from nothing but `ffmpeg` and `ffprobe`:
five scenes of a moving gradient with text, one tone per scene as the voice, a soft subtitle track, a
cross fade, and a loudness pass. It writes `video-lab/out/dummy/dummy.mp4` and `report.json` (duration,
size, streams, wall time, peak memory). It is a check that the render path works, nothing more. Run it with
`just video-dummy`, or with `nix shell nixpkgs#ffmpeg -c python3 video-lab/dummy/run.py` on a machine
without `ffmpeg`.
