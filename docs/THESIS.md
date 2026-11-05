# The thesis rig: wave-forecaster-thesis

[Português](THESIS.ptBR.md)

Six OpenRig seats, all on Claude Code, write one final-year project of the Escola Politécnica of UFRJ
in Portuguese, one section at a time, and hand in one PDF. A toolkit with no model and no network, the
command `thesis`, does the mechanical work. It claims the section, builds the PDF, runs the gates and
records the verdict. This page explains the parts, the contract between them, what each gate measures
and cannot prove, and the deployment notes. The rest of the OpenRig setup is in
[`OPENRIG.md`](OPENRIG.md). The files are `thesis/`, `openrig/specs/rigs/wave-forecaster-thesis/`,
`openrig/specs/agents/thesis-*/` and the option `piabrota.openrig.thesis.enable` of `openrig.nix`.

**How to read it.** Each number comes from a file of this repository (`thesis/profile.json`, the
scripts in `thesis/lib/`, the specs) or from the report of the run that built the toolkit
(2026-11-05). `⚠` marks what nobody checked. "Not measured" means that nobody measured it. **No seat
has run this rig yet.** What is proved is `thesis` on a sample thesis (see "What is proved and what is
not").

## What it is for, and what it is not

**It is for** writing, with a method, the text of a final-year project whose content already exists.
The owner owns the facts, the data, the decisions and the sources. The rig splits the text into
independent sections, writes each one, checks its form and its sources, and builds the PDF in the
Poli template.

**It is not a ghost-writer.** The owner gives the facts, the data, the decisions and the sources. The
rig writes, checks and typesets. The owner reads, signs and deposits. In detail:

- A seat never invents a number, a result, a reference or an experience of the author. Where only the
  author knows, the text carries the marker `**[AUTHOR: ...]**`. `thesis submit` refuses the section
  while the marker is there.
- The ficha catalográfica comes from the SiBI generator (<http://fichacatalografica.sibi.ufrj.br/>).
  The template keeps a sheet for it. A person puts the card on that sheet.
- The signatures, the advisor's approval and the deposit are the owner's.
- The rig publishes nowhere. It writes only to the outbox (`/var/lib/rig-outbox/wave-forecaster-thesis`).
- A final-year project is the student's own original work. No gate proves originality (rule U39 of
  `thesis ufrj-check` is `CANNOT-CHECK`). The person who uses the rig answers for what that person signs.

## The parts and how they connect

![The thesis rig: the owner gives the brief to the editor, which writes thesis.json; the librarian keeps the sources and refs.bib; three writers each take one section with thesis fetch and hand it in with thesis submit; the thesis toolkit, with pandoc, the Lua filter, the template and pdfLaTeX, runs the gates; the reviewer records the verdict with a hash; assemble builds the PDF and runs pdf-qa and ufrj-check; publish puts the PDF in the outbox, where Hermes and the owner read it; the six seats run on Claude Code in the openrig unit of 2G.](img/thesis-rig.png)

Interactive page: <https://www.piabrota.art/figures/thesis-rig/>

<details open>
<summary>How to read this figure</summary>

**Takeaway.** Six Claude Code seats write independent sections, a toolkit with no model checks and builds them, and one PDF leaves in an outbox that the owner reads.

**How to read.** Top to bottom and left to right, one lane for each role. The top strip marks the five phases. The red border marks where a person comes in. Each arrow carries the command or the file that passes from one part to the next. The bottom arrow shows what the harness gives the toolkit.

**Not shown.** The three writers are one box. The peers that exchange messages (`collaborates_with`), the list of the four gates (see the table below), the project files and the consent prompt of Claude Code.

**Evidence.** [`docs/archify/thesis-rig.json`](archify/thesis-rig.json), the source of the figure; `openrig/specs/rigs/wave-forecaster-thesis/rig.yaml`, `thesis/thesis`, `openrig.nix`. ⚠ No seat has run this rig: the arrows are the design, not a run.

</details>

### The six seats

The seat names are `<pod>-<member>@wave-forecaster-thesis`. The three writers use the same spec
(`thesis-writer`). Only the folder, and so the name, differs. All seats run `runtime: claude-code`
on the model `claude-sonnet-5-5`, with `permission_policy: builtin:yolo`.

|Seat|May|May not|Commands|Files|
|---|---|---|---|---|
|`plan-editor` (editor)|Plan from the owner's brief. Edit `thesis.json`, `notes/` and `data/`. Assemble and publish.|Use the web. Edit `sections/**` (a tool rule `Edit(...)`). Write prose, a `status` or a claim. Start a seat.|`thesis new`, `sections`, `status`, `assemble`, `pdf-qa`, `publish`|`thesis.json`, `notes/facts.md`, `notes/glossary.md`|
|`writing-librarian`|Use the web (`WebFetch`, `WebSearch`: the only seat that may). Write `sources/`, `refs.bib`, `REFERENCES.md`.|Edit a section, `thesis.json` or `review/`. Invent a reference. Mark `verified` what it did not fetch.|`rig send` (to answer)|`sources/<key>.md`, `refs.bib`, `REFERENCES.md`|
|`writing-writer-a`, `-b`, `-c`|Claim and write one section at a time.|Use the web. Read the text of another section. Touch the file of another seat, `thesis.json`, a `status` or a claim by hand.|`thesis fetch`, `release`, `build-section`, `slop`, `readability`, `cite-check`, `cite-score`, `submit`|`sections/<id>.md`|
|`review-reviewer`|Run the gates, write in `review/`, record the verdict.|Use the web. Edit `sections/**` (a tool rule). Judge a section that it wrote (`verdict` refuses).|`thesis readability`, `slop`, `cite-check`, `cite-score`, `review-report`, `verdict`, `ufrj-check`, `pdf-qa`|`review/<id>.review.md`, `review/final.md`|

The web is denied (`deny: [WebFetch, WebSearch]`) for every member except the librarian. A `deny`
rule that names the tool removes the tool from the seat, also in bypass mode. The `allow` of the
librarian only records its intent, because in bypass mode `allow` does not constrain. ⚠ Nobody proved
the native enforcement of these rules. The rules of `/etc/claude-code/managed-settings.json` apply to
every seat. They are not a sandbox. The hard sandbox is the one of the unit `openrig`.

### The `thesis` command

POSIX sh, `jq`, `awk`, pandoc and pdfLaTeX. No Python, no network, no model. Each command runs with a
`PATH` that holds only these tools.

|Group|Commands|
|---|---|
|Editor|`thesis new <slug> [--template <name>]`, `sections [<slug>]`, `status <slug>`|
|Writer|`fetch <slug> [<id>] [--as <seat>]`, `release`, `build-section`, `submit`|
|Reviewer|`lint`, `readability`, `slop`, `cite-check`, `cite-score`, `ufrj-check`, `review-report <slug> <id\|final>`, `verdict <slug> <id> accept\|revise --by <seat> [--note <file>]`|
|Assembly|`assemble <slug>`, `pdf-qa <slug>`, `publish <slug> [--replace]`|

A seat gives its name with `--as`, with `THESIS_SEAT`, or by the member folder where it stands. The
folders come from `THESIS_HOME` (default `/var/lib/openrig/work/wave-forecaster-thesis`) and
`THESIS_OUTBOX` (default `/var/lib/rig-outbox/wave-forecaster-thesis`).

## The project tree and the contract

`thesis new <slug>` makes `projects/<slug>/` in `THESIS_HOME`:

|Path|What it is|Who writes it|
|---|---|---|
|`thesis.json`|Title, author, advisor, course, month, year, template, sections (`id`, `role`, `order`, `brief`, `sources`, `target_words`). Here `status` is only `todo` or `omit`.|The editor|
|`sections/<id>.md`|One section in pandoc Markdown.|The writer that claimed it|
|`sources/<key>.md`|The capture of one source: `URL:`, `Retrieved:`, `DOI check:` and one quoted passage (a line that starts with `>`).|The librarian|
|`refs.bib`|The BibTeX entries.|The librarian|
|`REFERENCES.md`|The table `Key / Status / Checked against / Note`.|The librarian|
|`notes/`|`facts.md`, `glossary.md`, `thesis.log` and the questions `<id>.questions.md`.|The editor (and the toolkit, for the log)|
|`state/<id>.json`|The state of one section: `status`, `by`, `sha`, `round`, `accepted_sha`.|Only `thesis`|
|`claims/<id>.claim`|Who claimed the section, and when.|Only `thesis`|
|`review/`|`<id>.gates.md` (the machine), `<id>.review.md` (the reviewer), `<id>.verdict.md`, `final.md`.|The reviewer and `thesis`|
|`build/`|`thesis.pdf`, `qa.json`, `main.log`, `assembled.json`, the TeX tree.|Only `thesis`|
|`figures/`, `assets/`|The figures of the text. The UFRJ logo (`assets.ufrj_logo`).|The editor, the owner|

The assembled PDF is also in `THESIS_HOME/out/<slug>/thesis.pdf`. `thesis new` does not make `data/`,
and the seat norms tell the editor to put the owner's data there. The editor makes the folder. ⚠

### One section, from claim to verdict

1. **`thesis fetch <slug> [--as <seat>]`** claims the next free section, in order, and prints the
   work order. The claim is a file made with `set -C` (noclobber). The creation is atomic, so two
   writers never claim the same section. A seat that holds a claim resumes it before it takes a new
   one. A claim older than 7200 s (`limits.claim_stale_s`) is stale. The next `fetch` takes it over
   under a lock (`mkdir`). With no free section, `fetch` exits with code 3.
2. **The writer writes** `sections/<id>.md` and runs `build-section`, `slop`, `readability`,
   `cite-check` and `cite-score` as often as needed.
3. **`thesis submit <slug> <id>`** works only for the holder of the claim. It runs `lint`,
   `build-section`, `cite-check`, `slop` and `readability`. If one fails, the section is not handed in
   and the command lists the reasons. If all pass, `state/<id>.json` records `status: drafted`, the
   author and the `sha256` of the text, and the claim goes away.
4. **The reviewer** runs the gates (`review-report` collects the result in `review/<id>.gates.md`),
   reads the section against `sources/<key>.md`, `notes/facts.md` and `data/`, and writes
   `review/<id>.review.md` by hand.
5. **`thesis verdict <slug> <id> accept|revise --by <seat>`** works only for a `drafted` or `linted`
   section, by another author (the writer does not judge), whose text still has the `sha256` of the
   `submit`.
   - `accept` needs `review/<id>.review.md`, runs the gates on the current text and refuses if one
     failed. It records `accepted_sha`.
   - `revise` gives the claim back to the writer and counts one round. At the 4th round
     (`max_review_rounds` is 3) the command refuses and says to ask the owner.
6. **An edit after `accept` changes the `sha256`.** The section becomes `changed`. It needs a new
   `submit` and a new `verdict`.
7. **`thesis assemble <slug>`** needs a valid `thesis.json` and every section that is not omitted
   `accepted` with today's hash. Then it runs `lint` with no markers, the `cite-check` of the whole
   work, builds the PDF and runs `pdf-qa`. It writes `build/assembled.json` with the hash of each
   section.
8. **`thesis publish <slug>`** needs a `qa.json` with `pass`, a PDF newer than `thesis.json`, the
   hashes of `assembled.json` equal to today's hashes, and a destination folder that does not exist
   (or `--replace`). It copies `thesis.pdf`, `qa.json`, `REFERENCES.md` and `review/` to the outbox.

**What this does not guarantee.** The hash is a convention of files, not a signature. All seats run as
the same user `openrig`, and `state/<id>.json` is an ordinary file. The norms forbid a hand edit. No
permission stops it (an inference from the tools). The verdict is as good as the reading of the
reviewer, which is another seat of the same model.

## The template

### The first template: forecast-energy-demand

The template is the repository [h0ffmann/forecast-energy-demand](https://github.com/h0ffmann/forecast-energy-demand),
the owner's own, at the commit `a9a35ee4223037469c0ed35b22ecf510417de86e` (2026-04-17), pinned by
hash in `thesis/default.nix`. The repository has no licence file. The owner wrote it and said to use
it. Only the files that the overlay uses go into the package: `docs/project/pt/project_main.tex` (only
the `\documentclass` line is read), `shared/thesis_pack.tex`, `shared/page.sty`, `shared/portland.sty`
and the Poli logo as a PDF. The package copies nothing into this repository.

### The overlay

The overlay (`thesis/templates/forecast-energy-demand/overlay/`: `main.latex`, `preamble.tex`,
`preview.latex`) fills the gaps of the template against the UFRJ rules. It never edits a pinned file.
It adds (from `template.json`):

- the capa, the folha de rosto and the folha de aprovação, filled from `thesis.json` (the `cover.tex`
  of the template has fixed text);
- the sheet for the ficha catalográfica (a placeholder: the card comes from the SiBI);
- the resumo and abstract sheets, with reference and keywords, and the dedicatória and agradecimentos
  sheets;
- roman page numbers in the pre-textual part and a sheet counter for the ficha;
- a Times body font (TeX Gyre Termes), single spacing in long quotes, captions and references, and ABNT
  captions;
- the references chapter, the appendices and the lists of figures and tables.

It keeps the margins, the 1.5 spacing and the page style of `shared/page.sty` and `thesis_pack.tex`.
The run that built the toolkit set the chapter titles to 24 pt (it was 24.88) to meet "Times 24".

### Why `coppe.bst` is not used

The `project_main.tex` of the template asks for `\bibliographystyle{coppe}`. The repository does not
hold `coppe.bst`, and TeX Live in nixpkgs does not have it (the run checked the names in
`texlive.pkgs`). So pandoc makes the references with `pandoc --citeproc` and the ABNT author-date CSL
of the repository citation-style-language/styles, at the commit `b0114efe` (hash in
`thesis/default.nix`, licence CC BY-SA 3.0). There is one change: the surname in the in-text citation
is in capitals ("(TOLMAN, 2009)"). The file says so in a comment, as the licence asks.

The tests found these defects in that CSL:

- It drops the `booktitle` of an `@inproceedings` when there is no `eventtitle` (so `cite-check`
  requires both).
- It letters entries with the same author and year badly (`a2022`, and also on the access date).
  `cite-check` warns.

⚠ The accuracy of the CSL against NBR 6023:2025 and NBR 10520:2023 is **not verified**.

### Pandoc, the Lua filter and raw TeX

Pandoc reads the Markdown of each section and writes LaTeX. It also fills `main.latex` with the data
of `thesis.json`, escaped for LaTeX. Pandoc makes the references with `--citeproc`. The filter
`thesis/filters/thesis.lua` runs before that and does three things:

1. the cross-references (`@fig:name`, `@tbl:name`, `@eq:name`, `@sec:name`, `@cap:<id>`), in place of
   `pandoc-crossref`, whose closure is 5.5 GiB;
2. the scope of labels: the section id goes into the label, so two sections can use the same name;
3. the safety: in math, only the macros of the list `math_macros` pass (206 in `profile.json`), and
   `^^`, `%` and `#` are refused. Image paths stay in `figures/`.

The reader runs with `markdown-raw_tex-raw_attribute-raw_html-yaml_metadata_block-latex_macros-auto_identifiers`.
**Raw TeX is off on purpose.** A seat that writes `\write18` or `\input` does not reach TeX. Math is
the only path where the text of the author reaches TeX as written, and that is why it has the list of
macros. pdfLaTeX runs with `-no-shell-escape`, `-halt-on-error` and a limit of 120 s (`tex_timeout_s`).
Pandoc has 60 s (`pandoc_timeout_s`).

The engine is pdfLaTeX, not XeTeX. Tectonic, which the CI of the template uses, fetches its bundle from
the network. So `lint` and `build-section` refuse an emoji (pdfLaTeX does not draw it). The build
does not break without a warning.

### The template interface and the second template

The commands read only the `template.json` of `thesis/templates/<name>/` (the key `interface` is 1):
the source and commit, the engine and its flags, the bibliography mode and the CSL, the main file, the
pinned folders, the overlay and the default sections (10 sections: resumo, abstract, agradecimentos,
introdução, fundamentação, relacionados, desenvolvimento, resultados, conclusões and apêndices;
agradecimentos and apêndices start as `omit`). `thesis new <slug> --template <name>` chooses the
template.

To add [CoppeTeX](https://github.com/COPPE-UFRJ/CoppeTeX) (`ufrj.cls[grad]` with `ufrj-poli`, GPL-3,
biblatex with ABNT styles, PDF/A-2b), make a new folder with its own `template.json`, its own overlay
and its pinned files. No command changes. **Not done:** its pinned files, the change of the bibliography
mode to biblatex and the TeX set do not exist yet. Its package is GPL-3, so check the licence before
it mixes with MPL-2.0. ⚠

## The four gates

A gate is a simple local rule. No gate uses a model or the network. The numbers are in
`thesis/profile.json`, and **no other file holds a limit**. The list `unverified` of the same file says
that these numbers are guesses of the author of the toolkit.

|Gate|Command|What it measures|Numbers|What it does **not** prove|
|---|---|---|---|---|
|1. readable pt-BR|`thesis readability`|The length of sentences and paragraphs, the passive voice, a Flesch-style index for Portuguese, anglicisms outside the glossary, mixed terms, figures and tables cited.|Mean sentence up to 28 words. A long sentence has more than 40 words and may be up to 8 % of the sentences. Paragraph up to 220 words. One-sentence paragraphs up to 25 %. Passive up to 30 %. Flesch-pt from 25. 3 distinct anglicisms fail (69 listed). The ratios count only with 5 sentences or more.|That the text is clear, correct or true. The "-se" passive is not counted. The Flesch constants (Martins et al., 1996) are from memory, and the syllable counter is a heuristic.|
|2. slop|`thesis slop`|Surface patterns of model-written text: stock phrases (100 listed), dashes, lists of three, the same opening on three sentences, low variation in sentence length, summary endings, repeated 4-grams, hedges (19), bold lead-ins, a restated heading, transition words (24).|A score from 0 to 100, the sum of 11 signals with weights. It fails at 35 or more. Under 120 words it does not score.|Authorship. See below.|
|3. UFRJ|`thesis ufrj-check`|The graphic and structure patterns of the final project, in the PDF and in `thesis.json`: PASS, FAIL or CANNOT-CHECK, with the source of the rule. See "UFRJ rules".|Minimum margins 25, 25, 30, 30 mm. A4. Body 12 pt. Title up to 24 pt. Resumo and abstract up to 250 words, with 3 to 6 keywords.|The form of each reference, the colour of figures, originality, spelling and the SiBI Manual.|
|4. citations|`thesis cite-check`, `cite-score`|Each cited key is in `refs.bib`, has a `verified` row in `REFERENCES.md` and a `sources/<key>.md` with `URL`, `Retrieved`, `DOI check` and one passage. The required fields for each type. Numbered citations. An inline quote over 40 words.|The statuses `verified`, `partial`, `unverified`. `cite-score` only informs: target 0.60 (high), 0.30 (medium), 0.08 (low).|That the source says what the sentence claims. The reviewer reads that.|

### Slop, frankly

Gate 2 **is not an AI detector**. It counts surface patterns with lists and weights that the author of
the toolkit chose. Nobody compared it with an external detector. It promises no score in any outside
tool. A person also writes some of these patterns, and a model text can pass. A paraphrase of the same
sentence keeps the pattern and the empty content.

**The real fix** is different. Rewrite from the facts (the number, the source, the decision). Add
what only the author knows, in `**[AUTHOR: ...]**` markers, and never invent an experience. The seat
norms say this, and so does the message of the command. Do not play against the score.

### The human verdict

`thesis review-report` runs `lint`, `readability`, `slop`, `cite-check` and `cite-score` on one
section and writes `review/<id>.gates.md`. It leaves three questions without a machine answer. Does
the source say what the sentence says? Can a student of the course read the text with ease? Did
anyone invent a fact? The reviewer answers in `review/<id>.review.md`.

## UFRJ rules

|Source|State|What it holds|
|---|---|---|
|R: Resolução nº 05/2012 of the Escola Politécnica, Annex "Normas de Elaboração Gráfica do Projeto de Graduação"|**In force**|Portuguese. A4. Spacing 1.5 or 2. Times 12. Title up to Times 24. Justified text. Minimum margins 25, 25, 30 and 30 mm. Capa, folha de rosto, folha de aprovação, ficha catalográfica, resumo and abstract, sumário. Roman numerals before the text and arabic after it. Table caption above and figure caption below. One reference system. Original work.|
|N: Norma Gráfica 2026|**A proposal** for the Congregação, not approved. The 2012 text stays in force until then.|A cover with the UFRJ logo on the left and the Poli logo on the right, the institution name in three lines. Folha de rosto and folha de aprovação with no logo. The "natureza" sentence. Resumo, then abstract, each on its own sheet, up to 250 words. The card from the SiBI generator. NBR 6023:2025 and NBR 10520:2023.|
|M: SiBI Manual for UFRJ academic works (9th ed., 2025)|⚠ Read only as search snippets, not in full|Spacing 1.5 in the text. Single spacing in long quotes, footnotes, references and captions.|

`thesis ufrj-check <slug>` prints one line for each rule, in the form
`PASS|FAIL|CANNOT-CHECK [source] Uxx rule: detail`, and a last line with the totals. It exits with an
error if there is a `FAIL`. On the sample thesis it gave **34 PASS, 0 FAIL and 7 CANNOT-CHECK**.

The 7 `CANNOT-CHECK` rules are what **stays with the owner**:

|Rule|What no script checks|
|---|---|
|U13|whether a figure inside a chapter is a logo|
|U20|the ficha catalográfica itself (from the SiBI generator)|
|U27|the form of each reference and each citation against NBR 6023:2025 and NBR 10520:2023|
|U36|the colour inside figures (they must read in black and white)|
|U39|originality and credit to third parties|
|U40|the current orthography|
|U41|the SiBI Manual, read only in snippets|

Also by hand: the signatures, the advisor's approval and the deposit. **The template does not carry
the UFRJ logo.** The owner puts a file (PDF, PNG or JPEG) in `assets/` and sets `assets.ufrj_logo` in
`thesis.json`. Without it, rule U11 gives `FAIL`. `thesis new` sets `Engenharia Eletrônica e de
Computação` as the course. The course list of `profile.json` has 14 entries.

## Citations in the closed-source way

The owner asked for professional citation like that of the repository
[h0ffmann/closed-source](https://github.com/h0ffmann/closed-source) (*The god that failed*, text under
CC BY 4.0, commit `6b3aae557f69ab89ec747364311978928dd0ca71`). The rules of that repository, as applied here:

- **Never invent a reference.** The librarian fetches each source before the key exists, and records the
  check in `REFERENCES.md`.
- **Statuses.** `verified`: fetched, and the details match. `partial`: fetched, and one detail is
  unconfirmed (the detail leaves `refs.bib`, and the note says `unconfirmed: field`). `unverified`: not
  fetched, and **it must not be cited**.
- **`cite-check`** fails if a cited key is not in `refs.bib`, has no row, has a status other than
  `verified`, has no `sources/<key>.md`, or lacks a required field of its type (the lists for each type
  come from the memory of the author, not from the standard). It also fails on two rows or two
  entries for one key, on an entry that no section cites, and on an `unconfirmed` field left in
  `refs.bib`. No machine checks that the source supports the sentence.
- **Marks in the text.** `**[AUTHOR: ...]**` for what only the author knows, and `**[ANALYSIS]**` for
  interpretation, in a paragraph apart from the fact. `lint` refuses both marks, in `submit` and in
  the assembly. They belong to the editor and the owner, and they leave the text before the hand-in.
- **`cite-score`.** It is the idea of the `citation-score` skill of closed-source: the share of
  sentences of 3 words or more that carry a citation mark. It counts marks, not truth. No target is a
  goal for every section. Here it only informs (`--strict` makes it a gate).

Credits: the `AGENTS.md` of forecast-energy-demand sketches the thesis agents (a Portuguese review, a
consistency check of numbers, a citation agent) and gave the ideas of long sentences, passive voice
and claims with no `\cite{}`. The Vale rules of closed-source, in English, gave the idea of the slop
signals for Portuguese, without the files. CoppeTeX (GPL-3) is a possible second template. The CSL
belongs to the citation-style-language project (CC BY-SA 3.0).

## Deployment notes

These notes are for the person who deploys: the owner, with Hermes when the owner asks.

1. **Merge the PR of the rig.** A person merges. `deploy.yml` runs on the push to `main`. With the
   option off (the default), the rig is only a definition. The specs go into `/etc/openrig/specs`.
   `thesis`, `claude`, the folders, the outbox and `managed-settings.json` do not. Nobody measured
   whether the unit `openrig` restarts in this deploy. Before the merge, check that no seat works:
   `rig ps --nodes --active`.
2. **Turn the option on, in a small PR.** In `hosts/piabrota2/default.nix`, next to
   `piabrota.openrig.waveForecaster.enable = false;`, set `piabrota.openrig.thesis.enable = true;`. The
   unfree exception for `claude-code` is already in `unfree.nix`. The Claude pieces (the `claude` of
   `seatClaude` and `managed-settings.json`) turn on when the port rig **or** the thesis rig is on. In
   the PR, measure the growth with `just build piabrota2` before and after, and
   `nix run nixpkgs#dix -- diff <old> <new>`. **The growth of the system is not measured.** The
   closure of the package `thesis` is 727.3 MiB (pandoc 283, poppler-utils 143, TeX set 483.2 with perl
   and ghostscript, shared parts counted once), and Claude Code brings about +280 MiB
   (`docs/OPENRIG.md`). Do not add the two without checking, because they share paths. With the option,
   `nix build --dry-run` listed 11 derivations to build, against 3 without it. The size of what the
   box fetches is not measured.
3. **What this deploy restarts.** It changes the unit `openrig` (`path`, `StateDirectory`,
   `ReadWritePaths`), so systemd restarts the unit and **ends every live seat**
   (`KillMode=control-group`; see "What a deploy does to the seats" in [`OPENRIG.md`](OPENRIG.md)).
   Nothing starts a rig afterwards. Deploy while the box is quiet.
4. **Disk.** Look at `df -h /` and the disk line of `kvm4-health` before and after. The plan disk is
   200 GB (`AGENTS.md`). The space that the package uses beyond its closure is not measured. The GC
   runs every week and removes paths older than 14 days.
5. **Check.** After the deploy:

   ```console
   systemctl status openrig
   rig status                                   # must say "Daemon running"
   test -f /etc/claude-code/managed-settings.json && echo managed-ok
   ls -ld /var/lib/rig-outbox /var/lib/rig-outbox/wave-forecaster-thesis   # openrig:hermes, 0750
   sudo -u openrig bash -lc 'command -v thesis claude pandoc pdflatex pdftotext'
   sudo ls /var/lib/openrig/work/wave-forecaster-thesis   # editor writer-a writer-b writer-c librarian reviewer projects out
   ```

   The `sudo -u openrig bash -lc` is for the owner (Hermes does not use `sudo`). A login shell builds
   the `PATH` of the profile of the user `openrig`. A seat pane uses the same profile.
6. **Import the rig.** A spec is not a rig. The UI lists the rig only after the import.

   ```console
   rig spec validate /etc/openrig/specs/rigs/wave-forecaster-thesis/rig.yaml
   rig import /etc/openrig/specs/rigs/wave-forecaster-thesis/rig.yaml --materialize-only
   rig ps --nodes --rig wave-forecaster-thesis
   ```

   The import records the six seats and starts none. ⚠ Nobody ran `rig spec validate` on this spec
   here.
7. **First launch of a seat and the consent prompt.** A seat that never ran starts with
   `rig launch wave-forecaster-thesis plan.editor`. A seat that ran before starts with
   `rig seat launch plan-editor@wave-forecaster-thesis --fresh --reason "<why>"`. Claude Code asks once
   to accept its bypass-permissions warning, and OpenRig shows the seat as `attention_required`.
   **Show the pane to the owner** (`rig capture plan-editor@wave-forecaster-thesis --lines 40`) **and let
   the owner answer** (`rig seat continue` or the UI). Hermes never answers a consent prompt. ⚠ Nobody
   proved whether a first-run trust dialog also appears.
8. **The login.** The unit gives each seat `ANTHROPIC_API_KEY` that holds the owner's subscription
   token, and `seatClaude` moves it to `CLAUDE_CODE_OAUTH_TOKEN`. There is no API key. If `rig capture`
   shows a login error, tell the owner. Do not look for another token.
9. **The memory spike.** Nobody measured the memory of a Claude Code seat. The unit has
   `MemoryHigh=1536M` and `MemoryMax=2G`. Start one seat, let it work, and read
   `systemctl show openrig -p MemoryCurrent -p MemoryPeak`. Then start two and read again. Record the
   numbers in a PR that changes [`OPENRIG.md`](OPENRIG.md). **Until then, two seats at most.** Run the three
   writers together only after the owner measures and raises the limit.
10. **Run by phases, two seats at a time.** Never together with another rig.

    |Phase|Seats|What happens|It ends when|
    |---|---|---|---|
    |0, brief|none|The owner decides title, author, advisor, course, sections, results and sources, and gives them to the operator, who sends them to the editor.|The editor has everything.|
    |1, plan|editor and librarian|The editor runs `thesis new` and fills `thesis.json`, `notes/glossary.md` and `notes/facts.md`. The librarian verifies the sources and writes `refs.bib` and `REFERENCES.md`.|`thesis status <slug>` shows every section `todo` with verified sources. Stop both.|
    |2, writing|writer-a and writer-b, then writer-c|Each one repeats `thesis fetch`, writes, `thesis submit`. A writer that needs a source asks the librarian, which starts in place of a writer.|No section is `todo`.|
    |3, review|reviewer, with the editor or one writer|The gates, the reading against the sources, the verdict. A `revise` goes back to a writer, which starts in place of another seat. At most 3 rounds for a section.|Every section is `accepted`.|
    |4, assembly|editor and reviewer|The editor runs `assemble` and `pdf-qa`. The reviewer runs the final gates and writes `review/final.md`. The editor runs `publish`.|The PDF is in the outbox. The owner reads it and decides.|

11. **How Hermes reads the outbox.** Hermes is in the group `hermes`, which reads
    `/var/lib/rig-outbox/wave-forecaster-thesis` (owner `openrig`, group `hermes`, 0750, a default ACL
    for the group). The folder `<slug>/` holds `thesis.pdf`, `qa.json`, `REFERENCES.md` and `review/`.
    Hermes reads `qa.json` and `review/final.md`, and tells the owner what is missing. It does not
    read `/var/lib/openrig` (its deny list blocks that). The files go away after 14 days.
12. **Backup.** The state is in `/var/lib/openrig/work/wave-forecaster-thesis` (`projects/` and
    `out/`). Nothing on this box copies it: no backup is set up for that folder. The owner copies
    `projects/<slug>` and the PDF off the box at the end of each phase, for example
    `sudo tar -C /var/lib/openrig/work/wave-forecaster-thesis -czf <target>/<slug>.tar.gz projects/<slug>`.
13. **Change the rig.** Edit the specs or `thesis/` in a PR. The merge updates `/etc/openrig/specs`, and
    a running seat keeps the old text. A rig keeps the spec it was made from: get the owner's yes, run
    `rig archive wave-forecaster-thesis` and import again (step 6). A change to `thesis/` reaches the
    seat through the deploy and a relaunch of the seat.
14. **Roll back.** Set `piabrota.openrig.thesis.enable = false;` and deploy. The unit restarts, the
    seats end, and `thesis` leaves the `PATH`. The state in
    `/var/lib/openrig/work/wave-forecaster-thesis` stays. What removes the PDFs of the outbox after
    14 days is the rule `d ... 14d` that the option creates. Without the option the rule goes away,
    and the files stay until someone deletes them (an inference, not tested). Copy the PDFs first.

### What can go wrong

|Symptom|Probable cause|Short fix|
|---|---|---|
|`claude: command not found` in a pane|The option is off, the deploy has not finished, or the seat started before the deploy and keeps the old `PATH`.|Check the option and `readlink /run/current-system`. Relaunch the seat with `rig seat launch <seat> --fresh --reason "<why>"`.|
|`thesis: command not found`|The same.|The same. Check with `sudo -u openrig bash -lc 'command -v thesis'`.|
|`assemble` stops on the TeX timeout|pdfLaTeX ran over 120 s (`tex_timeout_s`; the limit is a guess). On the sample thesis the assembly took 2.5 to 3 s.|Read `build/main.log`. Look for a huge figure or a reference loop. Change the limit in `profile.json` in a PR, or use `THESIS_TEX_TIMEOUT`.|
|A claim is stuck|A writer stopped half way. The claim is stale only after 7200 s.|The holder runs `thesis release <slug> <id> --as <seat>`. Another seat uses `--force`, or waits until the claim is stale and runs `thesis fetch`.|
|`assemble` refuses|A section is not `accepted` (an edit after `accept` counts as `changed`), `thesis.json` is incomplete (`A PREENCHER`, the UFRJ logo), a `**[AUTHOR ...]**` marker is left, or the `cite-check` of the whole work fails (an entry that no section cites, a row with no entry).|`thesis status <slug>` lists what blocks. Fix it, run `submit` and `verdict` again, then `assemble`.|
|`verdict revise` refuses|The section already had 3 rounds.|Ask the owner.|
|`publish` refuses|The folder exists in the outbox, or `thesis.json` is newer than the PDF, or a section changed after the assembly.|`thesis publish <slug> --replace`, or assemble again.|

## What is proved and what is not

**Proved** (run of 2026-11-05, no seat):

- The real `thesis` on a sample thesis (15 pages, 8 sections, a PDF of about 100 KB):
  `thesis/test/run.sh` gave **60 checks, 0 failed**. They cover names, parallel `fetch`, refusal of a
  marker, `accept`, edit and `assemble`, `cite-check` with an unverified and a verified source, `slop`
  with a failure and with a pass, escaped raw TeX, the list of math macros, hostile characters,
  an emoji refused, a missing template file, TeX stopped by the timeout and `publish` without
  `--replace`.
- `shellcheck` clean, and `nixpkgs-fmt`, `statix` and `deadnix` with no finding on the Nix files.
- The evaluation of `piabrota` (equal to `main`) and of `piabrota2`, with the option off and on.
- In the tests: the assembly takes 2.5 to 3 s, and the largest process (pdfLaTeX) peaks at 135 MiB.
- The names and paths of the specs match `thesis`: no mismatch.

**Not proved:**

- A real run with Claude Code seats: the start, the login, the bypass warning, the messages between
  seats, the tool `deny` rules.
- The memory of Claude Code.
- The accuracy of the CSL against NBR 6023:2025 and NBR 10520:2023.
- Every number of the `unverified` list of `profile.json`: the time, claim and round limits; the
  readability limits and the Flesch constant; the slop weights; the targets of `cite-score`; the lists
  of required fields for each type; the lists of anglicisms and mixed terms; the spacing tolerance,
  measured only on the sample PDF.
- The SiBI Manual, read only in snippets.
- The growth of the system with `dix`, the size of the fetch and the Nix test `passthru.tests.run`
  (only `run.sh` against the built package ran).

## Limits and risks

- **The 2G unit.** OpenRig, tmux and every seat share `MemoryMax=2G` (`MemoryHigh=1536M`). That is why
  two seats run at a time, and why the phases exist.
- **The memory of a Claude Code seat** is not measured (see the spike, step 9).
- **The package size:** a closure of 727.3 MiB, plus Claude Code. Rule 1 of "Resource budget" in
  `AGENTS.md` asks for a reason for more than a few MiB, and the PR of the option must carry the `dix`
  measure.
- **pdfLaTeX, not XeTeX.** pdfLaTeX does not use the system fonts, an emoji is refused, and a character
  outside the list `allowed_chars` is refused with a clear message.
- **CSL defects** (above): `booktitle` dropped without `eventtitle`, `a2022` letters in the wrong place.
- **The pt-BR heuristics run on the English abstract.** `readability` does not tell the languages
  apart. The abstract can fail or pass by chance. ⚠
- **What the sample PDF showed as poor.** The chapter title comes with "Capítulo 1" and a lot of white
  space, "WAVEWATCH" is hyphenated in the body (a hyphenation exception is missing) and the math is in
  Computer Modern beside the Termes text. The folha de rosto and the folha de aprovação no longer
  hyphenate.
- **Four mismatches between the specs and `thesis`** (nothing was fixed here; ⚠ each needs a PR):
  1. The norms tell the writer to mark analysis with `**[ANALYSIS]**`, and `submit` refuses that mark.
     A writer who follows the norms cannot hand in the section.
  2. The `role.md` of the reviewer runs `pdftoppm`, but only the command `thesis` is on the `PATH` of
     the seat (poppler is inside the wrapper of `thesis`).
  3. The work order says to ask in `notes/<id>.questions.md` and to keep writing, and the `role.md` of
     the writer says to free the section (`thesis release`) and tell the editor.
  4. `thesis new` does not make `data/`, which the norms name.
- **Seats can err in a way the gate does not see.** The gates look at the form. The human verdict and
  the owner's reading catch the rest.
- **All six seats are the same model.** The reviewer is not an independent second pair of eyes.

## Credits

- [h0ffmann/forecast-energy-demand](https://github.com/h0ffmann/forecast-energy-demand): the first
  template and the ideas of its `AGENTS.md`.
- [h0ffmann/closed-source](https://github.com/h0ffmann/closed-source) (CC BY 4.0): the citation
  invariants, `REFERENCES.md` and the idea of `citation-score`.
- [COPPE-UFRJ/CoppeTeX](https://github.com/COPPE-UFRJ/CoppeTeX) (GPL-3): the possible second template
  and the 2026 graphic norm proposal.
- [citation-style-language/styles](https://github.com/citation-style-language/styles): the ABNT CSL.
- [OpenRig](https://github.com/mvschwarz/openrig), by mvschwarz (Apache-2.0).
- Claude Code, by Anthropic.
