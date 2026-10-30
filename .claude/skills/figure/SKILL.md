---
name: figure
description: "Add, change or explain a figure in this repo's Markdown (README.md, docs/, wiki/): an Archify picture drawn from docs/archify/<slug>.json with a reading card, in English and in its pt-BR mirror. Use when asked for a diagram, a flowchart or a picture of how nix-os works, or to update one after its prose changed."
---

> From [piabrota/pirsig](https://github.com/piabrota/pirsig/blob/main/.claude/skills/figure/SKILL.md)
> (MPL-2.0), the same discipline as piabrota/gramatico and the org profile: adapted here to English
> sources with pt-BR mirrors, piabrota's look, and the wiki's copies. pirsig's `psg` sections are
> left out.

# figure

A figure is an Archify picture of something the prose next to it says. Every figure has a reading
card, and every figure is in two languages: English in `README.md` and the English wiki pages,
pt-BR in the pt-BR wiki pages.

## Steps

1. **Read the prose the figure sits beside.** Draw only what it says; the text is the source of
   truth, and a figure that disagrees with it is a bug in the figure.
2. **Write the source** as `docs/archify/<slug>.json` (Archify's typed JSON IR; read the vendored
   [`archify` skill](../archify/SKILL.md) for the schema of each `diagram_type`), and its pt-BR
   mirror as `docs/archify/pt/<slug>.json`: the same ids and layout, the labels translated,
   `meta.locale` `pt-BR`. At most about 10 boxes, short labels, no jargon.
3. **Run `just figure`.** The vendored archify (`.claude/skills/archify`, the pinned submodule
   `vendor/archify`) validates and checks each source (`finalize`: schema, layout, routes, real
   browser); piabrota's look (`docs/archify/piabrota.css`, from piabrota/.github) is set over it;
   headless Chrome takes `docs/img/<slug>.png` (`docs/img/pt/<slug>.png`); the same PNG is copied
   to `wiki/img/`, because the wiki is its own repository and cannot load a file from this one.
   `docs/archify/crop.tsv` trims empty space under a picture (`<slug>\t<height>`).
4. **Embed it**: in `README.md` as `![alt](docs/img/<slug>.png)`, in the English wiki page as
   `![alt](img/<slug>.png)`, in the pt-BR wiki page as `![alt](img/pt/<slug>.png)`. The alt text
   says what the figure shows.
5. **Write the reading card** right under each embed, in the page's language:

   ```
   <details open>
   <summary>How to read this figure</summary>

   **Takeaway.** one plain sentence, what to remember

   **How to read.** direction, what shapes and arrows mean

   **Not shown.** what was left out on purpose

   **Evidence.** file, paragraph or command, with ⚠ if unchecked

   </details>
   ```

   In pt-BR: `Como ler esta figura`, **Em uma frase.**, **Como ler.**, **Fora da figura.**,
   **Fonte.** Evidence names the file or section the figure summarises; a discrepancy found between
   figure and text, or a claim not checked, is stated there with ⚠, not hidden.
6. **Check**: `just figure-check` fails when a source has no PNG, the wiki's copy differs, no page
   shows it, or a source, the look, the crop or the Archify pin changed since the PNG. Look at each
   PNG at full size and shrunk to 800 px wide: every label must read.

## Rules

- Commit the JSON, `docs/archify/figures.lock`, the PNGs and their wiki copies; never the HTML
  (`build/`).
- Every box and label traces to a file you read; the card's evidence names it.
- `just figure` needs node, jq, perl and Chrome (`CHROME` names another binary; Archify's own browser
  check uses `ARCHIFY_CHROME`), and the network for the Google Fonts. It runs where the agent runs,
  never on the VPS, and adds nothing to the system closure.
- Never edit `vendor/archify`. To move the pin: `git -C vendor/archify fetch --depth 1 origin <sha>`,
  check it out, `just figure`, and commit the new pin with the new PNGs and lock.
