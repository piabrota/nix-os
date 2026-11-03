# The owner's Hermes plugins

Two Hermes plugins send work from a chat to the pirsig brain
([piabrota/pirsig](https://github.com/piabrota/pirsig)) as pull requests. The owner writes in
Discord; Hermes writes the notes, checks them and opens one pull request; the owner reads it and
merges. English only, by the owner's order.

| Plugin | Tools | Bundled skill | Writes to |
|---|---|---|---|
| `pirsig-notes` | `pirsig_note_search`, `pirsig_notes_submit` | `pirsig-notes:smart-notes` | `brain/Inbox/<id>-<slug>.md` |
| `pirsig-videos` | `pirsig_video_fetch`, `pirsig_video_check`, `pirsig_video_submit` | `pirsig-videos:video-indexer` | `brain/Videos/<date>-<slug>/` |

The code is in `hermes/plugins/`: one directory per plugin, `common/brain.py` (the checkout of the
brain and the pull request, shared by both), and `tests/`. `hermes.nix` copies `brain.py` into
each plugin's directory at build time (`ownPlugin`), so each one stays a self-contained plugin
directory, as the module wants.

## One repository or three

**Keep both plugins here, in this repository, for now.** Reasons:

- They have one consumer, this box. Hermes on another machine, or another person, does not use
  them yet.
- A plugin in its own repository is a pin by commit in `hermes.nix`: each change is two pull
  requests (the plugin, then the pin bump). Here it is one, and it deploys with the merge.
- The two share their git and pull-request code. Two repositories would copy it; one repository
  keeps one copy.
- The guardrails stay in one review: the deny list (`hermes/dangerous-patterns.yaml`), the
  GitHub App (`hermes-github.nix`) and the code that pushes are read together.

**When to move them out:** when a second machine or person wants them, or when they need their own
release cycle. Then move them together to one repository (for example `piabrota/hermes-pirsig`,
two plugin directories and `common/`), not to one repository each, and pin it by commit like the
community plugins. The directory layout already fits that move: `extraPlugins` takes a fetched
directory the same way.

## How a note gets into pirsig

1. The owner asks in chat: "save this as notes in pirsig".
2. Hermes loads `pirsig-notes:smart-notes` (gramatico's smart-note rules, piabrota/gramatico at
   `d57371a`): one idea per note, own words, the title as a claim, `status: unverified` until a
   source is read, people by nickname.
3. `pirsig_note_search` finds existing notes to link to. Every note links to another note with a
   reason, or names the note that should exist (`⚠`).
4. Hermes shows the notes. When the owner says send, `pirsig_notes_submit` checks the mechanical
   rules (types, statuses, sources, links, tags, at most 500 words, no email addresses), writes the
   files and opens the pull request.
5. The owner merges and runs `psg fork import brain`. The files have no `pirsig:` key and no zid,
   so pirsig gives each one a zid and imports its `## Links` with their reasons, and
   `psg fork export` never rewrites them (`src/vault.rs` in pirsig).

## How a video gets into pirsig

pirsig's own method is the policy: `.claude/agents/video-indexer.md` and `scripts/videos.mjs`.
The box does steps 1 to 3 and the owner's computer does the rest, because the box has no browser
(Archify draws the PNGs in Chrome) and no `psg`.

| Step | Where |
|---|---|
| Fetch the metadata and the captions | box: `pirsig_video_fetch` (yt-dlp, `--skip-download`; the same choice of captions as `just video-fetch`) |
| Write `leitura.markdown`, `figuras.json`, `figuras/<id>.json` | box: Hermes, with the policy and gramatico's rules |
| Check coverage, keys, links, figures, style, reading time | box: `pirsig_video_check`, a port of `just video-check` without the PNG check |
| Open the pull request | box: `pirsig_video_submit` (never the transcript: it is gitignored in pirsig) |
| Draw the PNGs, index the notes | owner: `just video-figures`, `just video-check`, `just video-notes` on the branch, then merge |

The port gave the same result as `node scripts/videos.mjs check` on pirsig's indexed video
`2026-10-30-my-agentic-engineering-workflow` (51 notes, 11 figures, 01:25:40 covered, about
30 min), and the same problems on a copy with a gap and an unknown link (2026-11-03).

## Guardrails

- A plugin pushes only a new `hermes/*` branch (`hermes/notes-<slug>`, `hermes/video-<slug>`, with
  `-2`, `-3` when the name is taken) and only opens a pull request. It never merges. The deny list
  sees only the terminal tool, so `brain.py` checks the branch itself.
- A plugin writes only under `brain/` and never changes a file that is already in the repository.
- The tool descriptions and skills say: only when the owner asks, and only after the owner saw the
  notes. SOUL.md rule 2 still applies.
- The pull request text is a fixed English template. The notes themselves are in the owner's
  language.

## Cost

- `pkgs.yt-dlp-light` on Hermes's `PATH`: 32.4 MiB itself, 270.1 MiB with its closure from
  cache.nixos.org, 128 MiB of it a Python 3.13 that Hermes's own Python does not share (Hermes's
  flake has its own nixpkgs). The light build has no ffmpeg. Not measured with `dix` on the system.
- The brain checkout: shallow and sparse (`brain/`, `.claude/agents/`), about 3 MiB of files, one
  per plugin under `/var/lib/hermes/.hermes/plugin-data/`.
- Memory: yt-dlp runs only during a fetch, one video at a time, inside Hermes's 1 GB.

## Checks

- `checks.hermes-plugins` (`nix build .#checks.x86_64-linux.hermes-plugins`) and
  `just hermes-plugins-test` run `hermes/plugins/tests/`: the smart-note rules, the files and their
  links, the video checks, and a pull request end to end against a local bare repository with a
  stub `gh`.

## Not checked

- The plugins under the real Hermes gateway (`hermes plugins doctor`): no Hermes build was run for
  this change. The calls follow the plugin guide at the pinned hermes-agent commit
  (`register_tool`, `register_skill`, `get_config`, `plugins.plugin_storage`).
- yt-dlp from the VPS: YouTube can refuse a data-centre address, and yt-dlp warns when it has no
  JavaScript runtime. The tool then fails and says so.
- That the piabrota-hermes App is installed on piabrota/pirsig with contents and pull-request
  write access. Without it, the push fails.
