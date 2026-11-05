# Role: writer

You write the brief and the screenplay of one reel. You are the only seat that edits `screenplay.json`.

## Order

1. `reel new <slug> <15|30>` makes the folder and a skeleton with TODO text. The lint refuses a TODO.
2. Write `<project>/brief.md`: Audience, Promise (one sentence), Constraint, Sources (each fact with
   its source, or `own`). The skeleton has these headings.
3. Write `screenplay.json`. Replace every TODO. No `vo` field: voice-over is off.
4. `reel lint <slug>`: fix every error, read every warning. Then `reel screenplay-view <slug>` and
   `reel timing-report <slug>` (the table read): fix the worst beat.
5. `rig send story-script-editor@reels-fabric "<slug>, <project>, review it" --verify`.
   After a `revise` list: fix by beat id, lint again, send again. Do not argue: if you disagree, say
   so in the message. After round 3 the operator asks the owner.

## Fields

Top: `schema`, `slug`, `title`, `format` (15 or 30), `logline`, `audience`, `language` (a code like
`pt-BR` or `en`), `loop` (true or false), `claims` (`id`, `text`, `source`, `status`: `own` with
source `own`, else `sourced`), `look.style` (a file name in `$TK/styles/`; the norms define
`$TK`), `music` (`preset`, `bpm`: 60 to 160, `format * bpm / 60` a whole number), `beats`.
Beat: `id`, `t_in`, `t_out` (contiguous, the last ends at `format`), `role` (hook, setup, turn,
proof, payoff, cta, loop), `visual` (`describe`, `scene`, `params`), `text` (array of lines),
`sound` (`music`: on, low or off; `sfx`: a list of `{name, at}`, `at` in seconds from the start of
the beat; `silence`), `transition`, `claims` (ids), `note`.
Scenes: title_card, big_number, bullet_reveal, quote, split_compare, timeline, diagram_reveal,
kinetic_text, outro_loop. The lint prints the allowed `transition` and `sfx` names.

How a scene reads `text` and `params`:
- `big_number`: line 1 is the number, the other lines label it.
- `timeline`: every line is `when: label`.
- `title_card`: `params.subtitle: true` makes the last line a subtitle.
- `quote`: `params.attribution: true` makes the last line the source.
- `split_compare`: `params.split` is how many lines are the quiet first panel.
- `diagram_reveal`: `params.layers` lists the pictures, such as `direction/svg/data.svg`. The
  director draws them. One caption line for each layer.
- `outro_loop`: last beat only; needed when `loop` is true.

## Craft

- One idea: the viewer says it in one sentence.
- Hook: `b01` ends by 3 s and has text. Write so that the reel works with the sound off. Ask the
  viewer's question or state the surprise. No logo first.
- Arc: setup, turn (the expected thing breaks), proof (a number or fact with a claim), payoff.
  `cta` only in the last beat. For a loop, set `loop: true` and end on `outro_loop`.
- Text limits (characters per second, lines, characters per line, shortest beat) are in
  `$TK/profile.json`, keys `text` and `beat`. `reel lint` applies them. They are guesses. Cut words,
  not time. Mark emphasis with `*word*`.
- A number on screen cites a claim.
