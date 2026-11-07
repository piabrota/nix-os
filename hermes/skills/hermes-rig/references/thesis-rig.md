# The thesis rig: wave-forecaster-thesis

Six Claude Code seats write one final-year project of the Escola Politécnica of UFRJ, in
Portuguese, as a PDF. The command `thesis` (no model, no network) does the mechanical work. The
guide for the owner is [`docs/THESIS.md`](../../../../docs/THESIS.md). This file is what you need to
operate the rig.

**Not run yet.** No seat has run this rig. The rig is a definition only until the owner turns on
`piabrota.openrig.thesis.enable` (off today). Without it, `/var/lib/rig-outbox/wave-forecaster-thesis`
does not exist. Start nothing without the owner's request.

## The seats

Seat names: `plan-editor`, `writing-librarian`, `writing-writer-a`, `writing-writer-b`,
`writing-writer-c`, `review-reviewer`, each `@wave-forecaster-thesis`. Only the librarian has the web.

## The phases: two seats at a time, one rig at a time

|Phase|Seats|Done when|
|---|---|---|
|0, brief|none|The owner has given title, author, advisor, course, sections, results and sources.|
|1, plan|editor, librarian|`thesis status <slug>` shows every section `todo`, sources verified. Stop both.|
|2, writing|writer-a, writer-b, then writer-c|No section is `todo`. The librarian starts in place of a writer when one needs a source.|
|3, review|reviewer, and the editor or one writer|Every section is accepted. At most 3 revise rounds, then ask the owner.|
|4, assembly|editor, reviewer|The editor ran `assemble`, `pdf-qa`, `publish`. The reviewer wrote `review/final.md`.|

The memory of a Claude Code seat is not measured. Never run more than two seats, and never start a
seat from a seat. The three writers together need the owner to measure the memory and raise the limit.

The port rig `wave-forecaster-dev` is kept up by a keeper. One rig at a time: before the first launch,
ask the owner's ok for `rig down wave-forecaster-dev`. Bring it back with
`rig up wave-forecaster-dev --existing` when the thesis seats stop.

## Start and send

```console
rig status                                    # "Daemon running"
rig import /etc/openrig/specs/rigs/wave-forecaster-thesis/rig.yaml --materialize-only   # once, owner's ok
rig launch wave-forecaster-thesis plan.editor
rig send plan-editor@wave-forecaster-thesis "<slug, the owner's brief, done means>" --verify
```

A seat that ran before: `rig seat launch <seat> --fresh --reason "<why>"`. A changed spec needs
`rig archive` (ask the owner) and a new import. Send a seat the slug and the section id, never a
whole text. Read answers with `rig capture <seat> --lines 60`.

## What to show the owner

- The Claude Code bypass warning on the first launch (`attention_required`): run `rig capture`, show
  the pane, and let the owner answer. Never answer it. Never add `--non-interruptive`.
- A login error: tell the owner. Never look for a token.
- A `verdict revise` limit (the 3rd round), an `**[AUTHOR: ...]**` question from a writer, a source the
  librarian could not verify, and a fact missing in `notes/facts.md`: these are the owner's decisions.
- Before and after a run: what started, how many seats, what you could not check.

## The outbox

`/var/lib/rig-outbox/wave-forecaster-thesis/<slug>/` (group `hermes`, read only) holds `thesis.pdf`,
`qa.json`, `REFERENCES.md` and `review/`. Read `qa.json` and `review/final.md`. Tell the owner what
the `ufrj-check` table says, and what is by hand: the ficha catalográfica (SiBI generator), the
signatures, the advisor's approval and the deposit. The files go after 14 days: ask the owner to copy
the PDF. You cannot read `/var/lib/openrig` (the projects are there).

## Never

- Never write a section, a `thesis.json`, a claim or a `state/` file. Never edit a seat's folder.
- Never publish the PDF anywhere, and never put the thesis in a repository without the owner's request.
- Never promise a score of an AI detector: `thesis slop` is a surface heuristic, not a detector.
- Never put a fact, a number or a reference in a task that the owner did not give.
- Never run this rig at the same time as another rig. Never start the daemon.

Source: `openrig/specs/rigs/wave-forecaster-thesis/rig.yaml`, `thesis/thesis`, `docs/THESIS.md`.
