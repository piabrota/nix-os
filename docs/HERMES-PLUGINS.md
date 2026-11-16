# The owner's pirsig tools for Hermes

One MCP server, `pirsig`, sends work from a chat to the pirsig brain
([piabrota/pirsig](https://github.com/piabrota/pirsig)) as pull requests. The owner writes in
Discord; Hermes writes the notes, checks them and opens one pull request; the owner reads it and
merges. English only, by the owner's order.

| Tools (`mcp__pirsig__...`) | Skill | Writes to |
|---|---|---|
| `pirsig_note_search`, `pirsig_notes_submit` | `pirsig-smart-notes` | `brain/Inbox/<id>-<slug>.md` |
| `pirsig_video_fetch`, `pirsig_video_check`, `pirsig_video_submit` | `pirsig-video-indexer` | `brain/Videos/<date>-<slug>/` |

The server is `piabrota pirsig-mcp`, a command of the scripts' binary
([`scala/pirsig/`](../scala/pirsig/Mcp.scala)): MCP over stdio, the notes tools in `Notes.scala`,
the video tools in `Videos.scala`, and `Brain.scala` (the checkout of the brain and the pull
request, shared by both). `hermes.nix` declares it in `mcpServers.pirsig` with `git`, `gh` and
`yt-dlp` on its PATH, so the model sees its tools as `mcp__pirsig__<tool>`. The two skills are in
`hermes/skills/pirsig-smart-notes/` and `hermes/skills/pirsig-video-indexer/`.

Until 2026-11-14 the same tools were two Python plugins, `pirsig-notes` and `pirsig-videos`, in
`hermes/plugins/`. The port keeps their tool names, their answers and their data directories
(`$HERMES_HOME/plugin-data/pirsig-notes`, `.../pirsig-videos`), so a checkout on the box stays
valid.

## One repository or three

**Keep the server here, in this repository, for now.** Reasons:

- It has one consumer, this box. Hermes on another machine, or another person, does not use
  it yet.
- A server in its own repository is a pin by commit in `hermes.nix`: each change is two pull
  requests (the server, then the pin bump). Here it is one, and it deploys with the merge.
- The notes and video tools share their git and pull-request code (`Brain.scala`).
- The guardrails stay in one review: the deny list (`hermes/dangerous-patterns.yaml`), the
  GitHub App (`hermes-github.nix`) and the code that pushes are read together.

**When to move it out:** when a second machine or person wants it, or when it needs its own
release cycle. Then move `scala/pirsig/` and the two skills together to one repository (for
example `piabrota/hermes-pirsig`), and pin it by commit like the community add-ons.

## How a note gets into pirsig

1. The owner asks in chat: "save this as notes in pirsig".
2. Hermes loads the skill `pirsig-smart-notes` (gramatico's smart-note rules, piabrota/gramatico at
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

- A tool pushes only a new `hermes/*` branch (`hermes/notes-<slug>`, `hermes/video-<slug>`, with
  `-2`, `-3` when the name is taken) and only opens a pull request. It never merges. The deny list
  sees only the terminal tool, not the processes of an MCP server, so `Brain.scala` checks the
  branch itself.
- A tool writes only under `brain/` and never changes a file that is already in the repository.
- The tool descriptions and skills say: only when the owner asks, and only after the owner saw the
  notes. SOUL.md rule 2 still applies.
- The pull request text is a fixed English template. The notes themselves are in the owner's
  language.

## Cost

- `pkgs.yt-dlp-light` on Hermes's `PATH`: 32.4 MiB itself, 270.1 MiB with its closure from
  cache.nixos.org, 128 MiB of it a Python 3.13 that Hermes's own Python does not share (Hermes's
  flake has its own nixpkgs). The light build has no ffmpeg. Not measured with `dix` on the system.
- The brain checkout: shallow and sparse (`brain/`, `.claude/agents/`), about 3 MiB of files, one
  per tool family under `/var/lib/hermes/.hermes/plugin-data/` (the names of the old plugins).
- The server is one `piabrota` process, a child of Hermes in its cgroup, while Hermes runs. Its
  memory was not measured.
- Memory: yt-dlp runs only during a fetch, one video at a time, inside Hermes's 1 GB.

## Checks

- `scala/pirsig/*.test.scala`, run by `just scala-test` and by the Nix build of the binary
  (`nix build .#piabrota`): the MCP messages, the smart-note rules, the files and their links, the
  video checks, and a pull request end to end against a local bare repository with a
  stub `gh`.

## Not checked

- The server under the real Hermes gateway: no Hermes build was run for the port to MCP. The
  server answers `initialize`, `tools/list` and `tools/call` over stdio, as `Mcp.test.scala` drives
  it.
- yt-dlp from the VPS: YouTube can refuse a data-centre address, and yt-dlp warns when it has no
  JavaScript runtime. The tool then fails and says so.
- That the piabrota-hermes App is installed on piabrota/pirsig with contents and pull-request
  write access. Without it, the push fails.
