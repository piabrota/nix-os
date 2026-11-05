# Rules of every reels-fabric seat

These rules add to the rules of every piabrota seat. They apply to one reel of 15 s or 30 s
(1080x1920) that five seats make. The words on screen are in the screenplay's `language`. Your
files and messages are in English.

## One source: the screenplay

- `screenplay.json` (schema `reels.screenplay/1`) is the only source. Every other file comes from it
  and cites beat ids (`b01`, `b02`, ...).
- Only the writer edits it. A change goes back to the writer, through the script editor.
- `reel approve` writes `screenplay.approved`, the SHA-256 of the file. An edit after that voids it,
  and `reel` refuses every stage after the screenplay. Never write that file by hand.
- Studio seats (director, maker, qa): your first `reel` command checks the approval. If `reel` says
  "not approved" or "changed after its approval", stop and report that line to the operator. Do not
  look for a way round it.

## Files

`$REELS_HOME` is `/var/lib/openrig/work/reels-fabric` (use the full path if the variable is empty).
Write only your own files. `<project>` is `$REELS_HOME/projects/<slug>`, `<out>` is
`$REELS_HOME/out/<slug>`.

- `<project>/`: `brief.md`, `screenplay.json` (writer); `review/screenplay.review.md` (script editor),
  `review/build.md` (maker), `review/qa.md` (qa); `direction/` (director: `shotlist.json`,
  `storyboard/<beat>.png`, `svg/`); `build/` (`reel` writes it).
- `<out>/`: `reel.mp4`, `render.json`, `qa.json`, `qa/` (`reel` writes them).
- `$REELS_OUTBOX/<slug>/`: only `reel publish` writes it.

A slug has lowercase letters, digits and `-`, and at most 41 characters.

## Tools and sources

- `reel` is the only way to render, mix or publish. `reel help` lists its commands. Never edit the
  toolkit: it is in the Nix store, read only.
- Its data: `TK="$(dirname "$(readlink -f "$(command -v reel)")")/../share/reels"`.
  `$TK/profile.json` has every number, `$TK/styles/<style>.json` the colours,
  `$TK/examples/<15|30>/screenplay.json` a sample. Read a number there; never copy it into a file.
  A key in its `unverified` list is a guess, not a fact about Instagram.
- No network, no download, no stock footage, no image, video, voice or music service.
- Invent no claim. Every fact on screen is in `claims` with a source, or is `own`. If a source is
  missing, write "no data". Never guess a number.

## Handoff

- Send the next seat the slug and the path, never the content:
  `rig send studio-director@reels-fabric "<slug>, <project>, <what to do>" --verify`.
  Seats: story-writer, story-script-editor, studio-director, studio-maker, studio-qa
  (each `@reels-fabric`).
- A seat with no task waits: end your turn and wait for a message. Do not poll.
- If the next seat is not running, `rig send` fails. End with a final answer that names the slug, the
  path and the next seat. The operator starts it and sends it the task.
- Never launch, stop or restart a seat. At most two seats run at the same time (the unit has 2 GiB).
  Run one `reel` command at a time.

## Verdicts and rounds

- A verdict (approve, revise, pass, fail) needs evidence (a file, a beat id, a number), how sure you
  are, and what you did not check.
- A revise or fail loop runs at most 3 rounds for each stage. Write `Round: n` in the review file.
  After round 3, stop, list what is open and tell the operator. The owner decides.
- The owner decides, through the operator: the brief, the start of the studio phase after the
  approval, and what to do with the published reel. Nothing here posts to Instagram.
