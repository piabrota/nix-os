# Drawings

## `mu.svg`

无 (*mu*), by Matheus Hoffmann ([@h0ffmann](https://github.com/h0ffmann)), 2026: the only drawing
in this repository. The Nix files in `drawings/` write it in two formats from one geometry; the
flake's `mu-art` package holds the output:

| File | Command | What it is |
|---|---|---|
| `mu.svg` | `just drawing` | The README drawing |
| `mu.desmos.json` | `just drawing` | The same drawing as a Desmos graph state |

The tests run in `nix flake check` (the `drawing` check, `lib.runTests` in `drawings/default.nix`).
They check that the committed files are the output of `mu-art`, and that every Desmos expression,
read back from its LaTeX, stays within 0.01 of the line it stands for.

**What it shows.** The character 无, *mu*, "no thing", brushed in its four strokes in the standard
order: the short top horizontal, the long horizontal, the falling stroke ノ that starts at the top
line and sweeps out to the lower left, and the last stroke, which comes down from the long
horizontal, bends right along the bottom and lifts in a hook.

**Why this mu.** [pirsig](https://github.com/h0ffmann/pirsig)'s logo is 無, *mu*, the answer that
is neither yes nor no in *Zen and the Art of Motorcycle Maintenance* (chapter 26). This repository
draws the other character for the same word: 无, the simplified form of 無 and an old variant of it.
Same word, fewer strokes, for a machine with few resources.

**How it is drawn.** As pirsig's: each stroke is a list of hand-placed points with a brush width at
each. A Catmull-Rom spline runs through them; each piece is a cubic Bézier and each Bézier is one
Desmos parametric expression, `(a+bt+ct^{2}+dt^{3}, …)` for `0 ≤ t ≤ 1`, cut in four so the width
changes smoothly. The pen is `drawings/pen.nix`; the drawing is `drawings/mu.nix`. Both are pure
Nix, evaluated without a build: the pen was Rust until 2026-10-29. Nix has no fused multiply-add,
so `pen.nix` emulates one (`fma`); with it the files are byte for byte what the Rust pen
wrote.

**The look is [picasso](https://github.com/h0ffmann/picasso)'s**: one ink, `#1f2328` on light pages
and `#e6edf3` on dark ones (`prefers-color-scheme`), round ends, nothing else. To see the Desmos
expressions over the geometry, run `nix build .#mu-art` and open `result/mu-check.svg`: the
geometry in blue, each expression sampled in orange inside it.

### Open the Desmos file

The file is a Desmos graph state (`version` 11). Desmos uses y up, so each y value is `240 - y` of
the SVG (the canvas is 240 × 240).

1. Open `https://www.desmos.com/calculator`.
2. Open the browser console.
3. Run `Calc.setState(<the content of mu.desmos.json>)`.

⚠ Not checked in Desmos itself; the check is local, as in pirsig.

### Credits

- The stroke order of 无 follows [KanjiVG](https://kanjivg.tagaini.net/) (`kanji/065e0.svg`,
  © Ulrich Apel, CC BY-SA 3.0), used as a reference: the points and widths here are drawn by hand,
  and no KanjiVG path is copied.
- The pen and the method are pirsig's (`crates/pirsig-drawings`, at `450e4da`, ported to Nix), and the
  SVG-plus-Desmos check comes from there through [piabrota/alerts](https://github.com/piabrota/alerts).
- The look follows [picasso](https://github.com/h0ffmann/picasso).
