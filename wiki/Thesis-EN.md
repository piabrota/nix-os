# The thesis

[Português](Thesis)

The rig `wave-forecaster-thesis` of [OpenRig](https://github.com/mvschwarz/openrig) writes a final-year
project of the Escola Politécnica of UFRJ, in Portuguese, and hands in one PDF. Six Claude Code seats
(an editor, a librarian, three writers and a reviewer) write independent sections. The command
`thesis`, with no model and no network, claims the sections, runs four gates and builds the PDF. The
full guide, with the deployment notes, is
[`docs/THESIS.md`](https://github.com/piabrota/nix-os/blob/main/docs/THESIS.md).

**It is not a ghost-writer.** The owner gives the facts, the data, the decisions and the sources. The
rig writes, checks and typesets. The owner reads, signs and deposits. The ficha catalográfica comes
from the SiBI generator.

![The thesis rig: the owner gives the brief to the editor, which writes thesis.json; the librarian keeps the sources and refs.bib; three writers each take one section with thesis fetch and hand it in with thesis submit; the thesis toolkit, with pandoc, the Lua filter, the template and pdfLaTeX, runs the gates; the reviewer records the verdict with a hash; assemble builds the PDF and runs pdf-qa and ufrj-check; publish puts the PDF in the outbox, where Hermes and the owner read it; the six seats run on Claude Code in the openrig unit of 2G.](img/thesis-rig.png)

Interactive page: <https://www.piabrota.art/figures/thesis-rig/>

<details open>
<summary>How to read this figure</summary>

**Takeaway.** Six Claude Code seats write independent sections, a toolkit with no model checks and builds them, and one PDF leaves in an outbox that the owner reads.

**How to read.** Top to bottom and left to right, one lane for each role. The top strip marks the five phases. The red border marks where a person comes in. Each arrow carries the command or the file that passes from one part to the next.

**Not shown.** The three writers are one box. Also the four gates, the project files and the consent prompt of Claude Code.

**Evidence.** [`docs/archify/thesis-rig.json`](https://github.com/piabrota/nix-os/blob/main/docs/archify/thesis-rig.json), the source of the figure; `openrig/specs/rigs/wave-forecaster-thesis/rig.yaml`, [`docs/THESIS.md`](https://github.com/piabrota/nix-os/blob/main/docs/THESIS.md). ⚠ No seat has run this rig: the arrows are the design, not a run.

</details>

## The five phases

Two seats at a time, never together with another rig. The unit `openrig` has 2G, and nobody measured
the memory of a Claude Code seat.

|Phase|Seats|What happens|
|---|---|---|
|0, brief|none|The owner decides title, author, advisor, course, sections, results and sources.|
|1, plan|editor, librarian|`thesis new`, `thesis.json`, sources verified in `REFERENCES.md`.|
|2, writing|writer-a, writer-b, then writer-c|`thesis fetch`, write, `thesis submit`.|
|3, review|reviewer|The gates and the verdict, with the hash. At most 3 rounds for a section.|
|4, assembly|editor, reviewer|`thesis assemble`, `pdf-qa`, `ufrj-check`, `thesis publish`. The owner reads the PDF.|

## The four gates

Readable pt-BR, slop, UFRJ rules and citations. They are local surface rules, with no external
detector and no promise of a score. Each gate says what it does **not** prove, and `ufrj-check` marks
what stays with the owner (the card, originality, spelling).

## How to start

1. Merge the PR of the rig. With the option off, the rig is only a definition.
2. In a small PR, set `piabrota.openrig.thesis.enable = true;` in `hosts/piabrota2/default.nix`.
3. After the deploy: `rig import /etc/openrig/specs/rigs/wave-forecaster-thesis/rig.yaml --materialize-only`.
4. Start one seat, show the consent prompt of Claude Code to the owner, measure the memory, and only
   then run by phases.

The full steps, with the commands and what can go wrong, are in
[`docs/THESIS.md`](https://github.com/piabrota/nix-os/blob/main/docs/THESIS.md), "Deployment notes".
No seat has run this rig yet.
