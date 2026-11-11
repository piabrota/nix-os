# The static site on www.piabrota.art

`site.nix` serves the site in `site/` (Gleam, prerendered at build time) on `www.piabrota.art`,
over HTTP and HTTPS, through nginx with a Let's Encrypt certificate. `piabrota.art` answers with a
301 to `https://www.piabrota.art`, keeping the path (NixOS's `globalRedirect` points at HTTPS when
the name has a certificate). `hosts/piabrota/default.nix` turns it on (`piabrota.site.enable = true`), on piabrota only.

The site has three designs, grown from the [mockups](MOCKUPS.md), each with a switcher to the
other two:

| Design | Desktop, dark | Desktop, light | Phone (390 px) |
|---|---|---|---|
| A · fabric, at `/` | ![Design A, fabric, dark](images/site-fabric-desktop-dark.png) | ![Design A, fabric, light](images/site-fabric-desktop-light.png) | ![Design A, fabric, phone](images/site-fabric-mobile-dark.png) |
| B · index, at `/index/` | ![Design B, index, dark](images/site-index-desktop-dark.png) | ![Design B, index, light](images/site-index-desktop-light.png) | ![Design B, index, phone](images/site-index-mobile-dark.png) |
| C · paths, at `/paths/` | ![Design C, paths, dark](images/site-paths-desktop-dark.png) | ![Design C, paths, light](images/site-paths-desktop-light.png) | ![Design C, paths, phone](images/site-paths-mobile-dark.png) |

Design A is built as [closed-source's site](https://h0ffmann.github.io/closed-source/) is: numbers in
the hero, tiles with tags, a bar of anchors, then detail in sections. Every design ends with the same
sections: the **structure** (mu, the company chart; dojo, the umbrella; the products; pirsig, the
brain), **why it is open**, the **dogma** (the ten invariants of piabrota/mu), the **FOSS inventory**
(every project with its origin, language, licence, last push and links), the **board** (each person
with a GitHub pill and their website, when they have one), the **partners** (marola.dev and
ouroboric, with their logos) and the **forks**, a PUBLIC inventory of every fork under piabrota, as
h0ffmann/h0ffmann lists its own:

![Design A, the whole page, dark: the tiles, then the structure, the dogma, the inventory, the board, the partners and the forks](images/site-fabric-full-dark.png)

All three wear picasso's look in piabrota's colours, dark first and light when the visitor asks
for it; the rules are [`site/DESIGN.md`](../site/DESIGN.md). The pages load the sister sites'
fonts (Fjalla One, Inter, JetBrains Mono) from Google Fonts, and the avatars and partner logos from
GitHub (`avatars.githubusercontent.com`), so a visit asks Google and GitHub for them; the system
fonts stand in until they load. None of them is stored here. To change a design, the agent skills `frontend-design`,
`web-design-guidelines` and `open-pencil` are in `.agents/skills/`
([their README](../.agents/skills/README.md)), and `site/DESIGN.md` changes in the same PR.

## Analytics

`piabrota.site.analytics.measurementId = "G-…";` (in `hosts/piabrota/default.nix`) adds Google Analytics 4
to every page: Google's tag (`gtag.js`), built into the pages by `site/default.nix`. Empty, the
default, means no analytics and no script at all. The ID is public (it is in every page's source),
so it can be committed. ⚠ Google Analytics sets cookies and sends visits to Google: under the LGPD
the page should say so, and a consent banner may be needed before it loads; neither is in the site
yet.

## DNS on Porkbun

Each name must point at the VPS before the site is turned on: on the first switch, Let's Encrypt
checks each one over HTTP. If one does not answer from the VPS, the ACME order fails and the name
serves a self-signed certificate, which browsers refuse (seen on 2026-11-09; the deploy itself
went on). Fix DNS, then see the end of this section.

**Manual, Porkbun** (**Domain Management > piabrota.art > DNS**; ⚠ the menu as Porkbun shows it on
2026-10-29):

1. Delete the parking records Porkbun creates for a new domain: the `ALIAS` on `piabrota.art`
   and the `CNAME` on `*.piabrota.art` (or on `www`), both to `pixie.porkbun.com`. Turn off any
   **URL Forwarding** on the domain.
2. Add these records with the VPS's IPv4 address (the `DEPLOY_HOST` secret; hPanel, **VPS >
   Overview**):

   | Type | Host | Answer | TTL |
   |---|---|---|---|
   | `A` | *(empty, the domain itself)* | `<VPS IPv4>` | 600 |
   | `A` | `www` | `<VPS IPv4>` | 600 |
   | `A` | `skills` | `<VPS IPv4>` | 600 |

   Add no `AAAA` record unless the VPS answers on IPv6: Let's Encrypt tries IPv6 first when it
   finds one.
3. Wait until the names resolve to the VPS from outside:

   ```sh
   dig +short piabrota.art A
   dig +short www.piabrota.art A
   dig +short skills.piabrota.art A
   ```

Then merge the PR that turns the site on, or run the `deploy` workflow again if it already
failed.

The names that piabrota2 serves (`proof`, `pirsig`, `grid`, `wave`, `closed` and the others under `piabrota.art`)
each need one `A` record on their host name, with piabrota2's address, before the deploy that
turns them on.

The skills website's name, `skills.piabrota.art` (`piabrota.site.skillsDomain`), is on piabrota, so
its `A` record has piabrota's address, like `www`. Add it to the table above and to the `dig`
check. Without the record the ACME order for that name fails on the deploy.

A name whose record is missing or points at the other host does not stop the deploy: the vhost
starts with a self-signed certificate, and browsers refuse it. See "Certificates" below.

## Certificates

Every name under piabrota.art is listed in `scripts/domains.txt`, with the host that serves it.
A new vhost adds its line in the same PR: CI (`scripts/cert-check.sh --coverage`) fails when a
`*.nix` file names a piabrota.art name that the list does not have.

`certs.yml` checks the certificate of every live name from outside, as a browser does, every six
hours and two minutes after each deploy: curl must connect with no warning, and the certificate
must have more than 14 days left. The run summary has one row per name; a red run mails the
owner. `just certs` runs the same check from any machine (`just certs proof.piabrota.art` for one).

When an order fails (the name has no record yet, or points at the other host), NixOS keeps its
self-signed stand-in, issued by `minica`. `acme-retry.nix` makes `acme-order-renew-<name>.service`
retry every 20 minutes, at most 9 times in 6 hours (3 failed validations an hour, under Let's
Encrypt's limit of 5); then the daily `acme-renew-<name>.timer` takes over. So once the record is
right, the real certificate comes within about 20 minutes of the next failed order. The retry
starts only after an order fails: a certificate that was already a stand-in before a deploy
waits for its daily timer. To get it at once, a human runs, from their machine:

```console
just certs-fix                                # both hosts, then `just certs`
just remote-cert-renew "all --dry-run"        # piabrota: what it would order
just remote-cert-renew skills.piabrota.art    # piabrota: this name, even if it looks fine
just remote-cert-renew all h0ffmann srv2125808.hstgr.cloud   # piabrota2
```

`scripts/cert-renew.sh` runs as root on the box (over SSH and `sudo`). It finds each certificate
in `/var/lib/acme` that is self-signed (`minica`) or ends within 14 days, starts its
`acme-order-renew-<name>.service` (no other unit) and prints the new issuer, or `FAIL` with the
`dig` and `journalctl` commands to run next. An agent never runs it. `DEPLOY_HOST` and
`DEPLOY_HOST_KVM4` change the two addresses.

Before 2026-11-10 the module retried only once a day, so proof and skills showed a warning for a
day after their records were fixed.

## What answers where

| URL | Answer |
|---|---|
| `http://www.piabrota.art/` | the site |
| `https://www.piabrota.art/` | the site: design A; B at `/index/`, C at `/paths/`, Hermes's configuration at `/hermes/` |
| `https://skills.piabrota.art/` | the skills website, from `skills-site/` (HTTP redirects to HTTPS) |
| `https://www.piabrota.art/figures/` | the figures as interactive pages, from `figures-site/`; `<slug>/` in English, `pt-BR/<slug>/` in pt-BR |
| `…/figures` | 301 to `…/figures/` |
| `…/llms.txt` | the index for AI agents, UTF-8 text (see "llms.txt" below) |
| `…/skills`, `…/skills/<page>` | 301 to `https://skills.piabrota.art/<page>` |
| `http://piabrota.art/<path>` | 301 to `https://www.piabrota.art/<path>` |
| `https://piabrota.art/<path>` | 301 to `https://www.piabrota.art/<path>` |
| `…/nixos` | 302 to this repository, so the README link keeps working |
| a name with no vhost on the host its `A` record points at | nothing: HTTP is closed with no answer, the HTTPS handshake is refused (`configuration.nix`) |

`piabrota.site.httpsOnly = true` turns plain HTTP into a redirect to HTTPS. Add redirects in
`piabrota.site.redirects`, more names in `piabrota.site.redirectFrom`.

## The icon

Every name under piabrota.art shows the eye as its tab icon. The source is `favicon/favicon.svg`;
`favicon/default.nix` builds it with `resvg`, on the builder only, into `favicon.svg`, `favicon.ico`
(PNGs of 16, 32 and 48 px) and `apple-touch-icon.png` (180 px). The output names no store path.

`favicon.nix` gives each vhost three exact locations for those files, in front of any proxy, with
`Cache-Control: public, max-age=86400`. Every vhost carries them:
`locations = config.piabrota.favicon.locations // { ... };`. Add that term to a new vhost. Basic
auth stays on them.

The pages that we write link the files: the site (`page.gleam`), `skills-site/` (on its own name),
`figures-site/`, the notes layout, the Hermes docs page and the metrics page (its CSP has
`img-src 'self'`). An app that we do not write names its own icon, so nginx answers for that name
as well:

| App | Its own icon | What nginx does |
|---|---|---|
| Hermes dashboard | `/favicon.ico` | serves the eye there |
| The room | `/favicon.svg` (the same eye) | serves the shared file there |
| proof.piabrota.art, pirsig.piabrota.art | none on the pages of proof and pirsig | serves the eye there |
| wave.piabrota.art | `/favicon.svg`, ww3-gpu's own (`ww3-site/static/`) | nothing: the site keeps its icon |
| closed.piabrota.art | `/icons/favicon.svg`, closed-source's own | nothing: the site keeps its icon |
| OpenRig | `data:,` (an empty icon) | `sub_filter` swaps the link in its HTML for the eye; `checks.openrig-icon` fails if a bump changes the literal |

None of the three sets its icon from JavaScript. `checks.favicon` tests the files and that the SVG
equals `parts.eye`.

## The proof pages at proof.piabrota.art and pirsig.piabrota.art

`proof.nix` serves two names on piabrota2, each a static vhost with its own ACME certificate. Both
are built from pinned commits by `proof-site/`, which shares the steps and the archify gate between
the two (`proof-site/common.nix`). The index of each name is made by the design kit
([DESIGN-KIT.md](DESIGN-KIT.md)) from a list of the pages that the build computes
(`proof-site/manifest.mjs`, `proof-site/index.mjs`). The brand bar of the kit goes into every other page.
The two names:

- `proof.piabrota.art` (`proof-site/default.nix`, option `domain`): h0ffmann/proof's own browsable
  index (its `site/default.nix`, built here with this flake's nixpkgs) under `/proof/`, and an
  index at `/` that lists its pages and gives its lines of Lean 4, Agda and Z3 code at the pin.
  `proof-site/loc.mjs` counts them from the pinned source with the rule of that repository's own
  badge: a line that is not blank and not only a comment, `vendor/` left out; Z3 is the Scala of
  `z3-scala/`.
- `pirsig.piabrota.art` (`proof-site/pirsig.nix`, option `pirsig.domain`): piabrota/pirsig's
  `brain/Videos/index.html` under `/videos/` and its `docs/archify/*.json` figures (drawn by the
  archify of `figures-site/`) under `/figures/`, and an index at `/`. The proof name has no
  `/pirsig/` path, and it has no redirect: the old address never answered.

Both indexes are in the tokens of `site/DESIGN.md`, dark first and light on request. `piabrota.proof.enable`
turns both names on.

The archify pages open dark, whatever the reader's setting (the owner, 2026-11-09). archify reads
`?theme=` from the address before localStorage and the system setting; nginx answers a request for
an archify page without `?theme=dark` with a 302 to that address, and the index links them with it.
The build of each output fails if an archify page is outside the folders nginx watches on its name
(`proof/docs/diagrams/{en,pt-BR}/` on proof, `figures/` on pirsig), or no longer reads `?theme=`.

To move a pin: change `proofRev` in `proof-site/default.nix`, or `pirsigRev` in
`proof-site/pirsig.nix`, and its `hash`. The hash is the NAR hash of the tree at that commit
(`nix hash path` on `git archive <commit>`). Each name needs its DNS A record at piabrota2's
address before the first deploy ([DNS on Porkbun](#dns-on-porkbun)).

## The ww3-gpu website at wave.piabrota.art

The website of h0ffmann/ww3-gpu, which GitHub Pages served at h0ffmann.github.io/ww3-gpu until
2026-11-11. Its Gleam code lives here, in `ww3-site/` (the front page, the lineage page, the
pt-BR translations, the CSS), and its facts stay in ww3-gpu: `ww3-site/default.nix` copies
ww3-gpu at a pinned commit, puts this code in its `site/`, runs the content generator
(`ww3-site/content`, which reads `docs/ADRs.md`, `docs/WFIPs/`, `notes/`, `kokkos/ports.tsv`,
`.zenodo.json`, `CITATION.cff`, `RELEASES.md`, `VERSIONS.md`, `docs/archify/` and `site/data/*.tsv`
there), both test suites and the four prerenders on node, and fails unless each page holds every
section. The output is the pages, `style.css`, `favicon.svg` and `archify/`, with no store
reference, and `llms.txt`: ww3-gpu's own index for AI agents (its root, in the
[llms.txt](https://llmstxt.org) format), copied byte for byte when the pin has one and answered
at `/llms.txt` as UTF-8 text. The commit and the number of commits shown on the page are the
pin's (`WW3_GPU_REV`, `WW3_GPU_COMMITS` from `commits` in `default.nix`), since the source has no `.git`.

The page is plain and about the research only: what it is, the numbers (commits, records, notes,
figures, port reports and `site/data/port_score.tsv`), the tools of the reference toolchain
(`VERSIONS.md`), the Archify figures, the port's benchmarks, the decisions and designs, and how to
cite it. The figures are the PNGs ww3-gpu commits for each drawing of `docs/archify/dark.tsv`,
copied byte for byte into `archify/` and shown at the size they were drawn at: half the PNG's
pixels, read from its header by the content generator and set as the image's `width` and `height`.
A figure is not shrunk to the text column; it passes the column's edges, and scrolls sideways in
its frame when the screen is narrower than the drawing. A click on a figure opens its interactive
Archify page at `https://h0ffmann.github.io/ww3-gpu/figures/<slug>/`, which ww3-gpu's `pages.yml`
publishes. The pages are not built here: Archify checks each drawing against the Git history of
ww3-gpu, and the fetched source has none. The side column also lists five repositories of
piabrota, marola-dev and ouroboric-dev, the rows of `ww3-site/data/orgs.tsv` (the most stars, the
most recent push first on a tie; the file names its date). The look follows
[reasonablypolymorphic.com](https://reasonablypolymorphic.com/) by Sandy Maguire
([@isovector](https://github.com/isovector)), a serif text column and a dark side column, written
anew in `ww3-site/static/style.css`; the foot of every page credits it.

`ww3-pin.yml` looks at ww3-gpu's `main` every hour and opens or moves one PR labelled `ww3-pin`
(`scripts/ww3-pin.sh`, `just ww3-pin [rev]` by hand), which also counts the commits up to the new
pin. The site changes when the owner merges it.
A change to the page itself (a section, a sentence, the style) is a PR here; a new sentence also
needs its row in `ww3-site/data/translations/pt-BR.tsv`, or the content generator stops the build.
`just ww3-site` builds it into `./result-ww3-site`; `nix develop .#site` has gleam and node for
`gleam test` in `ww3-site/` and `ww3-site/content`, run inside a checkout of ww3-gpu's layout.

Not here yet: ww3-gpu's `/adrs/`, `/andamento/`, `/relatorio-gta/` and `/figures/` pages, which
its `scripts/build_html.sh` and `scripts/archify.sh` build. Until they move, GitHub Pages keeps
serving them.

## The closed-source site at closed.piabrota.art

The website of h0ffmann/closed-source, the book *The god that failed*, which GitHub Pages also
serves at h0ffmann.github.io/closed-source. `closed-site/default.nix` builds it on the builder at a
pinned commit, with that repository's own steps (`just site-build` and `site/justfile`): its content
generator (`tools/fabric content`, Gleam on Erlang, with pandoc and pdfinfo) writes the content
module from the paper, then the Gleam tests, the esbuild bundle and the prerender run on node. The
output is the page, `app.js`, `style.css`, the drawings, the icon and the three PDFs, with no store
reference. nginx (`closed.nix`) serves it as static files on piabrota2.

Three things differ from the Pages build, because the sandbox has no network and the source has no
`.git`:

- The three PDFs are the release assets of the tag at the pinned commit (`release` in
  `default.nix`, each with its hash), not built again with XeLaTeX.
- The version DOIs come from `closed-site/zenodo.json`, Zenodo's reply cut to the fields the
  generator reads, not from Zenodo at build time. Fetch it again when the pin passes a release.
- The revision and the commit count come from `rev` and `commits` in `default.nix`, through a
  stand-in `git` that answers only those two questions. Pages' `links.json` is not built.

To move the pin: change `rev`, `commits` (`git rev-list --count <rev>`) and `hash` (`nix hash path`
on `git archive <rev>`), and `release` with the PDF hashes when a new tag has them. `just
closed-site` builds it into `./result-closed-site`.

The first version of this vhost (#217) passed each request to Pages, but piabrota2 timed out on
every connection to Pages (the 502 that `certs.yml` saw on 2026-11-11), so the box now keeps its
own copy. The name needs its DNS `A` record at piabrota2's address ([DNS on Porkbun](#dns-on-porkbun)).

## The ▲ grid at grid.piabrota.art

`piabrota.room.grid` (`room.nix`) serves the room's files a second time, on piabrota2, at
`grid.piabrota.art`, with the same locations. The room itself opens on the grid map when the page's
name is its `grid.host` (`src/config.js`, piabrota/room#28), or with `?grid` on any name: it picks
HIFI whatever view the visitor last stored (`?lofi` still wins, and without WebGL LOFI stays), and
its first shot is `grid`. Esc and "back to the room" step into the room on the same name, where
the gate for the sound waits. The name needs its DNS A record at piabrota2's address before the
first deploy ([DNS on Porkbun](#dns-on-porkbun)). `domain` here and `grid.host` in the room must
be the same name.

## The skills website at skills.piabrota.art

`https://skills.piabrota.art/` is the website that GitHub Pages served for
[piabrota/skills](https://github.com/piabrota/skills). It moved to `www.piabrota.art/skills/`, and
from there to its own name, like the pirsig pages.

`site.nix` serves it as a second vhost on piabrota (KVM 1): `piabrota.site.skillsDomain`, HTTPS
only, its own ACME certificate, the three icon locations, and `Cache-Control: no-cache` because a
new pin keeps the names of the pages. The root is `piabrota.site.skills`, the output of
`skills-site/`. The `www` vhost answers `/skills` and `/skills/<page>` with a 301 to the same page
on the new name (the query string stays), so old links keep working. `skillsDomain = null` removes
the vhost and the redirect. The name needs its DNS A record at piabrota's address before the first
deploy ([DNS on Porkbun](#dns-on-porkbun)).

`skills-site/` holds the Gleam program. It was copied from piabrota/skills, and it is edited here on purpose, for the look.
The look is the one of the site: [`site/DESIGN.md`](../site/DESIGN.md) has its rules.
The program keeps its CSS in `skills-site/src/www.gleam`. It writes the CSS into each page.
Each page has the brand of piabrota, a link back to `www.piabrota.art`, the three sections (skills, agents, awesome-skills) and a foot.
The home page has the install commands as terminal cards, a search box, tags and a card for each skill.
The page loads the same Google Fonts as the site, and its script asks `api.github.com` for the star count.
Change only the look and the page frame. The content, the search, the tags and the copy buttons stay as they were.
No one compiles Gleam on the VPS, and a code change here is not tested there. The build on the builder is the test.

The build reads a pinned commit of piabrota/skills (`rev` and `hash` in `skills-site/default.nix`).
A new commit of that repository shows on the site only after a PR here moves the pin. To move it:

1. Change `rev` to the new commit.
2. Get the hash with `nix-prefetch-url --unpack https://github.com/piabrota/skills/archive/<rev>.tar.gz`.
3. Convert it with `nix hash convert --hash-algo sha256 --to sri <hash>`, and put it in `hash`.

You can also set `hash` to an empty string. The failed build then prints the right one.

Gleam and Erlang run on the CI builder only. The VPS gets the HTML, which is small.
`allowedReferences = [ ]` keeps them out of the VPS closure. The pages link each other and their
favicon from the root of the name, and the other links are absolute, so nothing needs a base
path. `piabrota.site.skills = null` removes the pages and the redirect.

To preview, run `just skills-site`. It builds into `./result-skills-site`.

## llms.txt

`https://www.piabrota.art/llms.txt` (and `piabrota.art/llms.txt`, by the redirect) is an index of
piabrota for an AI agent, in the [llms.txt](https://llmstxt.org) format, in the shape of
[xerj.org/llms.txt](https://xerj.org/llms.txt): one heading, a quote, a note on how to read it,
then one line with a link for each page, service, project, part of the company, rule of the dogma,
partner and fork. `site/llms.nix` writes it from `mockups/data.nix`, so a fact changes there and
nowhere else; a page that is off (`/hermes/`, `/figures/`, the skills website) is left out.
`just llms` prints it. `piabrota.site.llms` holds the text; `null` removes the path.
`checks.site-llms` checks that it names every service, project and fork, has no relative link, and
is served as `text/plain; charset=utf-8`.

## The figures

`https://www.piabrota.art/figures/` serves each figure of `docs/archify/` as one self-contained
[archify](https://github.com/tt-a1i/archify) page: it zooms, follows the visitor's light or dark
setting, and calls no third party. `/figures/<slug>/` is the English page, `/figures/pt-BR/<slug>/`
the pt-BR mirror, and `/figures/` lists them. The README and the wiki link each figure to its page.

**The index.** `/figures/` has the page frame of `/hosts/`: the brand, the language links, the
design switcher, a hero and the foot, in the site's `style.css`. It shows one card for each figure:
the PNG of `docs/img/` as a preview, the title, the takeaway (the part of `meta.title` after the
first colon), and links to the English page, the pt-BR page and the source in this repository. The
cards' rules (`.figures-grid`, `.figure-card`) are in `site/static/style.css`.

**The bar.** Each figure page has a bar, at most 44 px high, with the brand, `← figures` and a link
to the same figure in the other language. The build puts it after the `<body>` tag. `piabrota.css`
hides everything but the drawing and fits the drawing to the window with `position: fixed`, so the
bar's CSS shows the bar again and moves the drawing down by the bar's height.

`figures-site/default.nix` builds the pages on the builder from the committed JSON
(`docs/archify/*.json`, `docs/archify/pt/*.json`) and `docs/archify/piabrota.css`. For each source it
runs `archify finalize`, as `just figure` does, and fails the build if `validate`, `deliver` or
`check` do not pass. The builder has no Chrome, so archify skips the browser check; `just figure`
runs it. Then it puts the content of `piabrota.css` and the bar's CSS into the page as a `<style>`. It
does not add the Google Fonts link that the PNGs use, so a visit to a figure calls no third party and the system fonts stand in. The index is the one page that does, as the site's other pages do (`site/DESIGN.md`, "Type"); the build fails if another page names Google Fonts.
**No HTML is committed.** A new figure needs its two JSON files and its PNG in `docs/img/` (`just figure`
writes it): the build loops over the sources, and a missing pt-BR mirror or PNG stops it. `allowedReferences = [ ]` keeps node, jq and archify
out of the VPS closure. `piabrota.site.figures = null` removes the page.

**The pin.** `rev` and `hash` in `figures-site/default.nix` name the commit of the submodule
`vendor/archify` (`git ls-files -s vendor/archify`). Move them with the submodule, in the same PR as
`just figure`:

1. Change `rev` to the new commit.
2. Get the hash with `nix-prefetch-url --unpack https://github.com/tt-a1i/archify/archive/<rev>.tar.gz`.
3. Convert it with `nix hash convert --hash-algo sha256 --to sri <hash>`, and put it in `hash`.

**Licences.** archify is MIT (`vendor/archify/LICENSE`). Its pages embed JetBrains Mono, under the SIL
Open Font License 1.1 (`THIRD_PARTY_NOTICES.md` of archify). The index page credits both.

**Size.** The eight pages are about 820 KB each, and `/figures/` is about 6.9 MiB in the VPS
closure (`nix path-info -S`), PNGs included. nginx sends them compressed (`recommendedGzipSettings`). The site sets
no `Content-Security-Policy`, so the pages' inline script and style run as built.


## The structure figure

The Structure section shows the org's fabric figure, drawn by archify in piabrota/.github. It loads from
there at a pinned commit, in English or pt-BR, and no copy lives here. `structure.image` in
`site/locale/<lang>.json` holds the address: change it when the figure changes.

## Closed projects

`closed` in `mockups/data.nix` lists a project that is not FOSS yet. It gets a tile in design A, with no
link. It stays out of the FOSS inventory, the counts and the mockups. The list is empty today, and an
empty list draws no lane. chaceon was the last entry: it is public now, so it is in `projects`, with a
link to its repository.

## Commit counts

Each project in an own repository of the org (`origin` `own`, no `repository` override; so not hermes
and not a personal project) has `commits = { human = N; agent = M; };` in `mockups/data.nix`, and the
file has one `commitsAsOf`. Design A shows them in the tile, design C in the row, and every design in
the inventory entry, in the four languages (`commits.*` in `site/locale/<lang>.json`). A project with
no `commits` shows nothing. The tooltip says what the count is and the day it was read.

- Rule: a commit is agent when its GitHub author login ends with `[bot]` or is exactly `claude`.
  Every other commit is human.
- Limit: a commit that a person made with an agent's help, under their own name, counts as human.
  The repository's rule is "no agent trail in a commit", so the agent number is a floor.
- The page never calls the network. The numbers are typed in `data.nix`, like `pushed`.
- Refresh: `just commit-counts` prints one line for each project. Paste the lines, set `commitsAsOf`,
  run `just mockups`, and open a pull request. `just commit-counts-test` tests the rule with a stub `gh`.
  [MOCKUPS.md](MOCKUPS.md#commit-counts) has the same rule.

## Languages

Design A has four languages; designs B and C stay in English. English is the source, and it wins when two
texts disagree. `en.json` holds the page's words, and the facts stay in `mockups/data.nix`. Each other file
holds the same words and those facts in its language. A key that one of them lacks stops the build.

| File | Rules |
| --- | --- |
| `pt-BR.json` | gramatico's `cientifico` skill |
| `zh-CN.json` | controlled Simplified Chinese, from `easy-translate`, and simple in the manner of `eli5` |
| `ja-JP.json` | Easy Japanese, from `easy-translate`, and simple in the manner of `eli5` |

Change the source first, then each language. The zh-CN and ja-JP pages keep their banner until a native
reader checks them. A fork's description stays as GitHub publishes it.

## Change the site

The site is Gleam with [Lustre](https://lustre.build), prerendered once at build time, as
[piabrota/gramatico](https://github.com/piabrota/gramatico) builds its site. It has the three
designs of the [mockups](MOCKUPS.md), each a page, with a switcher at the foot of each:

| URL | Design |
|---|---|
| `/` | A · fabric: the org profile as a page, the projects as cards in their lanes |
| `/index/` | B · index: an editorial list, one numbered row a project |
| `/pt-BR/`, `/zh-CN/`, `/ja-JP/` | design A in that language |
| `/paths/` | C · paths: 无 and the name, and a listing of what answers here and where the rest lives |
| `/hermes/` | Hermes Agent as `hermes.nix` configures it, in plain YAML: the hermes card in "think and write" links here ([HERMES.md](HERMES.md#the-hermes-page)) |

The facts (the projects, their blurbs, where each meets the web) come from `mockups/data.nix`, the
same file the mockups draw: the mockups and the site cannot disagree. Change a fact there.

| Path | Is |
|---|---|
| `site/src/piabrota_site/fabric.gleam`, `index.gleam`, `paths.gleam` | the three pages |
| `site/src/piabrota_site/parts.gleam` | what they share: the mark, a project's address, the switcher |
| `site/src/piabrota_site/page.gleam` | the HTML document around each page: head, theme colour, stylesheet |
| `site/src/piabrota_site/render/` | one module a page, which prints it as HTML |
| `site/data.nix` | writes `src/piabrota_site/data.gleam` from `mockups/data.nix`; that file is not committed |
| `site/hermes.nix`, `src/piabrota_site/hermes.gleam` | the /hermes page: `site/hermes.nix` writes `services.hermes-agent` of the evaluated system as YAML, without secrets, and the release tag that `flake.lock` pins (`nodes.hermes-agent.original.ref`); `site.nix` passes it to the build as `piabrota.site.hermes`. The build stops if that tag and `hermesVersion` in `hermes.nix` differ: change both in one pull request |
| `site/test/` | gleeunit tests on the rendered pages |
| `site/static/` | copied as is next to the pages (`style.css`, one body class a design) |
| `site/gleam.toml`, `site/manifest.toml` | the Gleam project and its locked hex packages |
| `site/locale/<lang>.json` | the site's words in each language; `site/data.nix` compiles them, and a key that one language lacks stops the build |
| `site/default.nix` | the build: fetches each hex package at its `manifest.toml` checksum, writes `data.gleam`, checks the format, runs the tests, prerenders the three pages, copies `static/` and the 无 drawing (`docs/drawings/mu.svg`) |
| `site/DESIGN.md` | the look, in rules: tokens, type, shapes, layout, motion |
| `site/design/` | OpenPencil drafts; never built or deployed |

```console
just site-test    # data.gleam, then gleam format and gleam test, in the site dev shell
just site         # the build the VPS gets, into ./result-site
```

After a dependency change (`gleam add`, `gleam update`), commit the new `manifest.toml`: the build
reads every package and checksum from it and runs offline.

Edit the code and open a PR. The site is part of the system closure: a merge deploys it, and a
rollback brings the old page back with the old system.

**What reaches the VPS.** Gleam, node and the hex packages run on the builder (the CI runner)
only. The output is the three pages, the files in `static/` and `mu.svg`, about 27 KiB;
`site/default.nix` sets
`allowedReferences = [ ]`, so the build fails if the output names any store path, and nothing of
the toolchain can enter the system closure. No page loads JavaScript.

## Design with OpenPencil

`.mcp.json` declares OpenPencil's MCP server, `@open-pencil/mcp` pinned to 0.16.0 and started with
`npx` (node from `nix develop .#site`, or your own). It drives the [OpenPencil](https://openpencil.dev)
desktop app, which must be open with a document loaded. `OPENPENCIL_MCP_ROOT` limits its file
access to `site/design/`. Draft or inspect a design there, then change `app.gleam` and
`static/style.css` to match it. The server runs where the agent runs, never on the VPS.

## What it costs

nginx and the ACME client (lego) enter the closure the first time something uses nginx: the site
or a Loco app. Idle nginx uses a few MiB of RAM. Measure with `dix` as `AGENTS.md` asks.
