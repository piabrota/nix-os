# DESIGN.md

The look of www.piabrota.art (`site/`), in rules. It is picasso's look
([h0ffmann/picasso](https://github.com/h0ffmann/picasso), `site/static/style.css`) in piabrota's
colours, the one piabrota/.github's figures already wear (`docs/archify/piabrota.css`). The sister
sites, piabrota/gramatico and h0ffmann/closed-source, keep the same manner with their own palettes.

## One sentence

A dark sheet, one red, and every state said in words before colour.

## Tokens

Dark first; light when the visitor asks for it (`prefers-color-scheme`). Same names as picasso.

| Token | Dark | Light | It means |
|---|---|---|---|
| `--bg` | `#0B0D12` | `#FFFFFF` | the page |
| `--surface` | `#14171F` | `#F4F5F7` | a card, a pill, a button at rest |
| `--border` | `#2A303C` | `#D8DCE3` | every line |
| `--text`, `--muted` | `#EDEFF3`, `#9AA3B2` | `#0B0D12`, `#4F5868` | text, and what is secondary |
| `--accent` | `#BC2318` | `#BC2318` | the logo's red: the one filled button, the current design, the glow |
| `--accent-text` | `#FF6B5E` | `#A51D14` | the same red where it must be read: links, the eyebrow, `§` numbers |
| `--ok`, `--warn`, `--none` | green, amber, grey | darker in light | a project's state: live, coming, no site yet |

No other colour. A new colour is a new meaning, and it starts here.

## Type

- Fjalla One for the title, the headings, a project's name and the brand.
- Inter for the prose, the buttons and the pills.
- JetBrains Mono for data: addresses, the switcher, the `§` numbers, the terminal.

They load from Google Fonts, as on the sister sites; the system fonts stand in until they do. No
font file is stored here.

## Shapes

- **Round.** Buttons, pills and the switcher are pills (`999px`); cards and tables have a 12 px
  radius.
- **Buttons.** One filled `--accent` button a row, the action the page is for; the others are
  outlined on `--surface`. Every button is at least 44 px tall. Hover lifts it 1 px and colours
  its edge.
- **State in words first.** A project's state is an uppercase pill that says it (`live`,
  `coming`, `no site yet`), then a colour: the pill's, and the 3 px edge of its card or row.
  `no site yet` is dashed: dashed means "not there yet".
- **Status pills** in the hero count the projects by state, with a dot; the live dot has a halo.
- **Sections** are numbered `§ 01`, `§ 02`… by CSS; the numbers are never typed.
- **The switcher** between the designs is one segmented pill, top right and again in the foot;
  the current design is filled with `--accent`.

## Layout

- The top band: the brand and the switcher, then the hero (eyebrow, title with its muted second
  half, lede, status pills, buttons) beside a drawing: the mark on A, 无 on C. A red glow sits in
  the top left corner, as on picasso.
- Content is at most 1040 px wide, with 20 px gutters; below 760 px the drawing moves above the
  title, and below 420 px the buttons fill the row.
- A: cards in a grid of the profile's lanes. B: one table, picasso's standings. C: one terminal
  on `--surface`.

## Board, partners, forks

Every design ends with the same three sections (`src/piabrota_site/community.gleam`):

- **Board**: a card a person, with the avatar, the name (or the `@login`), the line from their
  public GitHub profile, and two pills: the GitHub pill (avatar and `@login`, mono) and the
  website pill (the host, in `--accent-text`, `↗`).
- **Partners**: a card a partner, with its logo, its name in Fjalla One and its one line, linked to
  its site. Below them, the "Work with us" box: the one place with two buttons outside the hero.
- **Forks, a PUBLIC inventory**: every fork under piabrota, as h0ffmann/h0ffmann lists its own:
  the year it was forked, `piabrota/<name>` in mono, then two mono marks (`forked <day>`,
  `started <year>`), where it came from, and its description. "PUBLIC" stays in capitals: GitHub
  keeps a fork of a public repository public, and the capitals say so.

Avatars and logos load from where GitHub publishes them (`avatars.githubusercontent.com`), as the
sister sites load their icons; none is stored here. The names and logos are their owners' marks.

## Motion

One entrance, and only when the reader allows motion: the hero rises 8 px. Hover lifts a card
2 px. No page loads JavaScript, except Google's analytics tag when
`piabrota.site.analytics.measurementId` is set (`page.analytics`).

## Facts

Every fact comes from `mockups/data.nix` (the org profile, the people's and partners' GitHub
profiles, and `gh repo list piabrota --fork` for the forks, each list with its date), through
`site/data.nix`. Refresh the forks there when the org forks something. The words the
page says in its own voice (headings, button labels, the lede of C) are in `src/`.

## Before you change the look

1. Change this file in the same pull request.
2. `just site`, serve `result-site/`, and look at each page at 1280 px and at 390 px, in dark and
   in light.
3. Tab through a page: every link and button shows its focus ring.
