# DESIGN.md

The look of www.piabrota.art (`site/`), in rules. It is picasso's look
([h0ffmann/picasso](https://github.com/h0ffmann/picasso), `site/static/style.css`) in piabrota's
colours, the one piabrota/.github's figures already wear (`docs/archify/piabrota.css`), and its page
is built as [h0ffmann/closed-source](https://h0ffmann.github.io/closed-source/)'s is: numbers in the
hero, tiles with tags, a bar of anchors, then detail in sections. The sister sites, piabrota/gramatico
and h0ffmann/closed-source, keep the same manner with their own palettes. closed-source's tiles
each have their own colour; here they do not, because this page has one red.

## One sentence

A dark sheet, one red, and every state said in words before colour.

## Tokens

Dark first; light when the visitor asks for it (`prefers-color-scheme`). Same names as picasso.
The round switch at the end of the bar (☀ or ☾, `parts.theme`) gives the page the other scheme: a
checkbox that `style.css` reads with `:has()`, so no script, and the choice lasts until the page
changes. Its two blocks repeat the tokens; `scala/design/Kit.test.scala` checks them. Every page also says
`<meta name="color-scheme" content="dark light">`, so a browser paints the right canvas first.

| Token | Dark | Light | It means |
|---|---|---|---|
| `--bg` | `#0B0D12` | `#FFFFFF` | the page |
| `--surface` | `#14171F` | `#F4F5F7` | a card, a pill, a button at rest |
| `--border` | `#2A303C` | `#D8DCE3` | every line |
| `--text`, `--muted` | `#EDEFF3`, `#9AA3B2` | `#0B0D12`, `#4F5868` | text, and what is secondary |
| `--accent` | `#BC2318` | `#BC2318` | the logo's red: the one filled button, the current design, the glow |
| `--accent-text` | `#FF6B5E` | `#A51D14` | the same red where it must be read: links, the eyebrow, `§` numbers |
| `--sea` | `#0B5FA5` | `#0B5FA5` | the sea: the fill of ww3-gpu's tile, the wave model (the owner, 2026-11-11). White on it is 6.6:1 |
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
- A: tiles in a grid of the profile's lanes, the incubating lane last; three tiles are filled,
  across the row: ww3-gpu's in `--sea`, first, before mu's (the owner, 2026-11-11), then mu's
  (the company chart) and proof's (the incubating project) in `--accent`.
  B: the wordmark, and the tiles of A right after it. C: one terminal on `--surface`.
- **/hermes** is not a design and has no place in the switcher: its hero carries the hermes mark
  (below, "Marks") where the others carry a drawing, its numbers are facts in mono, and its
  YAML sits in C's terminal, in a `<pre>` that scrolls sideways on a phone. It ends at the foot,
  without the shared sections.
- **Services**, on A, the first section: one link card for each name piabrota2 serves on its own
  (`services` in `mockups/data.nix`): the mark, the name in Fjalla One, an uppercase pill that says
  whether it is `public` (green) or needs the `login` (dashed), the line, and the host in mono and
  `--accent-text`, pinned to the bottom of the card. The name's link covers the card. The mockups do not draw them.
- **Tiles**, on A: the logo, the tags (the state pill, the language, own or personal), the name in Fjalla One, the
  blurb, the licence and the address, then the commit line: the same slots in the same order in every
  tile. The logo box is 44 px, the tags row keeps room for two lines, and the footer (the licence and
  address, then the commits) sits at the bottom of the tile, so the footers of a row line up. A tile
  with no commit line keeps its licence line at the bottom. The name's link covers the tile. Hover
  scales it 1.5%.
- **The card grids** (tiles, services, board, partners) have no empty cell. One column below 600 px;
  two from 600 px, on 4 tracks; three from 960 px, on 6 tracks. A card spans 2 tracks, the cards of
  a row have one height, and the gap is 14 px both ways. The last row stretches: at 3 up, one card
  left takes the row and two share it in halves; at 2 up, one card left takes the row. The filled
  tiles (ww3-gpu, mu, proof) take a row and are not counted. A plain tile that stretches turns to a row: the
  logo and the tags on the left, the name, the blurb and the footer on the right. The four layers
  are 1, 2 and 4 up; on the figures page the cards are 1 and 2 up, and an odd last card takes the
  row with its preview at the side. At 3 up the board's cards stack the avatar over the text.
- **Commit counts**, on a tile (A and B) and on a row of C's terminal: one quiet line,
  the word `commits` in Inter, 11 px, uppercase, then `35 human · 72 agent` in JetBrains Mono, 12 px,
  both in `--muted`. No new colour. A tooltip says what the count is and the day it was read. A
  project with no counts shows no line and no zero. On a tile the line sits above the link that
  covers it, so the tooltip shows; on a phone it wraps, and in C it takes a row of its own.
- **The numbers** in the hero are `<dl>` pairs, counted from the facts, never typed.
- **The bar of anchors** stays at the top while the page scrolls, and scrolls sideways on a phone.
- **skills.piabrota.art** (`skills-site/`) wears the same look: these tokens, type and shapes, its own CSS in `skills-site/src/www.gleam`, the 技 drawing in `--accent-text` as its hero drawing, and a card for each skill.

## What every design shares

The project tiles (A and B; C lists the same projects in its terminal, each with its blurb) are the
one list of the projects: there is no second one. A tile holds the state pill, the language, the
origin (`own` is the org's; `personal` is a repository that dojo pins and a person keeps), the name,
the blurb, a quiet line with the licence, the address and the last push, a `repository ↗` link when
the tile's own link goes to the project's site, the paper badge and the commit counts.

Every design ends with the same sections, in this order (`src/piabrota_site/community.gleam`):

- **Structure**: a card a layer, the chart, the umbrella, the products and the brain, each with its
  role in mono.
- **Why it is open**: the three reasons of the org profile, word for word.
- **Dogma**: the ten invariants of piabrota/mu, shortened only where a list or a link would not fit.
  The list numbers them, in `--accent-text`.
- **Board**: a card a person, with the avatar, the name (or the `@login`), the line from the org
  profile's Board, the GitHub pill (avatar and `@login`, mono) and, when the person has a website,
  the website pill (the host, in `--accent-text`, `↗`).
- **Partners**: a card a partner, with its logo, its name in Fjalla One and its one line, linked to
  its site. Below them, the "Work with us" box: the one place with two buttons outside the hero.
- **Forks, a PUBLIC inventory**: every fork under piabrota, as h0ffmann/h0ffmann lists its own:
  the year it was forked, `piabrota/<name>` in mono, then mono marks (`forked <day>`,
  `started <year>`, the licence, the sync with upstream, the language), where it came from, and its
  description. "PUBLIC" stays in capitals: GitHub
  keeps a fork of a public repository public, and the capitals say so.

The top band names the four languages. A project's card carries its repository's logo, loaded at a pinned commit from
`raw.githubusercontent.com`; a repository with no logo yet shows its text mark. Partner cards share one
height, so their logos line up. Avatars and logos load from where GitHub publishes them (`avatars.githubusercontent.com`), as the
sister sites load their icons; none is stored here. The names and logos are their owners' marks.

## Marks

What piabrota runs with no repository logo of its own (Hermes, OpenRig, the metrics page, the room)
gets a mark drawn in `src/piabrota_site/marks.gleam`: the piabrota mark's red square with a 22
radius, and one drawing in its cream (`#F7F3EA`), with `--bg`'s ink for a detail. No other colour,
no text in the mark, no Unicode glyph (a glyph is drawn by whatever font the visitor has). Hermes is
a caduceus, OpenRig three seats tied to a hub, metrics three rising bars, the room a room seen from
its open side with a window on the sea. They are inline SVG, so no file is stored. They are
piabrota's drawings, not the upstream projects' logos.

## The icon

The piabrota mark (the open green eye on red, the drawing of `parts.eye`) is the favicon of every
site under piabrota.art: the site, `skills.piabrota.art`, `/figures/`, `/notes`, and the dashboards on the
other names. Its one source is `favicon/favicon.svg`. Change the mark there and in `parts.eye`
together: `checks.favicon` compares them. No page stores or draws an icon of its own.

## The link preview

Every page names `/og.png` as its `og:image` and `twitter:image`, at `https://www.piabrota.art`
(`page.origin`), with its size, an alt text, `og:title`, `og:description` and `og:url`. The image
is `og/og.svg` drawn at 1200x627 (1.91:1, what LinkedIn asks for) by resvg on the builder, with the
site's three faces (Fjalla One from Google's CDN, Inter and JetBrains Mono from nixpkgs); no font
reaches the box. Without it LinkedIn takes the 180 px apple-touch-icon and shows it blurred.
LinkedIn keeps a preview for days: after a change, ask again in its Post Inspector.

## Motion

One entrance, and only when the reader allows motion: the hero rises 8 px. Hover lifts a card
2 px. No page loads JavaScript, except Google's analytics tag when
`piabrota.site.analytics.measurementId` is set (`page.analytics`).

## The kit

`design/` owns the tokens for the sites built outside `site/` ([docs/DESIGN-KIT.md](../docs/DESIGN-KIT.md)):
`design/css/tokens.css` repeats the table above, and `scala/design/Kit.test.scala` fails when it or this table
differs from `site/static/style.css`. Change a token in all three in one pull request. The kit also holds
one small CSS module for each part of a page, the list of sites (`design/sites.nix`) and the brand bar
that goes into pages from other repositories.

## Where else the look is used

The same tokens and type dress four things that are not the site's Gleam pages:

- **proof.piabrota.art and pirsig.piabrota.art**: the indexes are made by the kit (`piabrota proof-index`, scala/design/Index.scala),
  with the hero, numbered sections and card grids of this file. The pages from h0ffmann/proof and
  piabrota/pirsig keep their own looks and get the brand bar.
- **The figures** at `/figures/`: the index is a page frame like `/hosts/` in this `style.css`
  (`.figures-grid`, `.figure-card`), written by `figures-site/default.nix`; each figure page has a bar
  of 44 px with the dark tokens, from the same file.
- **The docs page of the Hermes dashboard**, `hermes-web/docs/index.html`: one file with its CSS
  inside, because the dashboard shows it in an iframe.
- **The dashboard theme and the TUI skin of Hermes**: `hermes/dashboard-themes/piabrota.yaml` and
  `hermes/skins/piabrota.yaml`, the dark tokens only. The skin colours the Chat tab.

## Facts

Every fact comes from `mockups/data.nix` (the org profile, piabrota/mu's dogma, dojo's repos, GitHub
for each repository, and `gh repo list piabrota --fork` for the forks, each list with its date),
through `site/data.nix`. Refresh the forks there when the org forks something. The words the
page says in its own voice (headings, button labels, the lede of C) are in `src/`.

## Before you change the look

1. Change this file in the same pull request.
2. `just site`, serve `result-site/`, and look at each page at 1280 px and at 390 px, in dark and
   in light.
3. Tab through a page: every link and button shows its focus ring.
