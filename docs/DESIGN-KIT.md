# The design kit

`design/` is the one source of the look for the sites that are not built in `site/`. It holds the
tokens of [site/DESIGN.md](../site/DESIGN.md), a small CSS module for each part of a page, the list
of piabrota sites, and functions that write HTML. A page takes only the modules it uses.

Today `proof.piabrota.art` and `pirsig.piabrota.art` use it. Their indexes are made by the kit
(`proof-site/index.mjs`). The pages that come from other repositories get the brand bar.

## Files

|File|What it is|
|---|---|
|`design/css/tokens.css`|The tokens: dark first, light under `prefers-color-scheme`. `design/test.mjs` compares them with the table of `site/DESIGN.md` and with `site/static/style.css`.|
|`design/css/*.css`|One module each. Every class starts with `pb-`. A module needs only `tokens.css` and `base.css`.|
|`design/sites.nix`|The list of sites, and the hosts that are not sites.|
|`design/kit.mjs`|Functions that return HTML. They escape all text and refuse a link with a script scheme.|
|`design/inject.mjs`|A build step: the brand bar into every `.html` file of a folder.|
|`design/test.mjs`|`node --test design/test.mjs` (`just design-test`).|

## The modules

|Module|Class|Use|
|---|---|---|
|`base`|`pb-wrap`|Reset, type scale, links, focus ring, reduced motion. Always in the page.|
|`chrome`|`pb-chrome`|The brand and the sites. `--page`: the header of a kit page. `--bar`: the strip for a foreign page.|
|`hero`|`pb-top`, `pb-hero`|Corner glow, eyebrow, title with a muted tail, lede, numbers (`<dl>`), buttons, an optional mark.|
|`section`|`pb-section`|A heading with a `§ 01` number (counted by CSS, never typed) and a count.|
|`cards`|`pb-cards`, `pb-card`|A grid with no empty cell: 1 column below 600 px, 2 from 600, 3 from 960. The last row fills the row.|
|`pills`|`pb-pill`|A state or a tag. Tones: `ok`, `warn`, `none`, `accent`.|
|`footer`|`pb-footer`|One line and the public sites.|
|`prose`|`pb-prose`|Long text.|

`page({ lang, title, description, modules, head, icons, body })` inlines `tokens`, `base`, then the
modules asked, in a fixed order. `icons` is the HTML of `favicon/links.nix`. The page loads no script.

## Add a module

1. Write `design/css/<name>.css`. Use only the tokens. Start every class with `pb-`.
2. Add the name to `MODULES` in `design/kit.mjs`, in the order of the page.
3. Add a function to `design/kit.mjs` if the module has markup, and a test to `design/test.mjs`.

`design/test.mjs` fails when a class has no prefix or when one module names another.

## Add a site

Add it to `design/sites.nix`: `id`, `label`, `url`, `host`, `line`, `access`. Set `access = "login"` for
a site that needs a login: it stays out of the nav. `checks.design-sites` fails when a virtual host
under `piabrota.art` is in neither `sites` nor `hidden`, or when a site names a host that no system
serves. The check evaluates the two systems and builds nothing.

## The brand bar

`design/inject.mjs` puts the bar right after the opening `<body>` tag of every page that came from
another repository. The bar is a 44 px strip in the page flow. It is always dark. It shows the eye and
`piabrota`, a link back to the site's index, and the public sites with the current one marked.

- It adds one element and one `<style>`. It never edits the CSS, the scripts or the text of the page.
- Every selector of the bar holds `.pb-chrome`. The bar declares its own dark tokens and resets its own
  elements, so the page's rules do not reach it and its rules do not reach the page.
- The marker `data-pb-chrome` makes a second run do nothing.
- The build fails when a file has no `<body>` tag. It also fails when a page of the output has no bar.
  The two indexes are the only exceptions.
- archify pages put their toolbar at the top with `position: absolute`. On such a page the bar adds one
  rule that moves the toolbar down by the height of the bar. The bar is hidden in embed and present mode.

## Stage 2

These files still hold their own copy of the tokens. A later stage moves them to the kit.

|File|What it copies|
|---|---|
|`site/static/style.css`|The tokens, the buttons, the pills, the numbered sections and the card grid of the home. The kit copies it. The drift test keeps the two the same.|
|`skills-site/src/www.gleam`|The tokens and the shapes, inline in the Gleam module.|
|`metrics/index.html`|The tokens and the type, inline in one file.|
|`figures-site/default.nix`|The eye and the bar of 44 px for each figure page, and the index frame of `site/static/style.css`.|
|`hermes-web/docs/index.html`|The tokens, inline, because the dashboard shows it in an iframe.|
|`docs/archify/piabrota.css`|The dark tokens for the archify figures of the README.|
|`hermes/dashboard-themes/piabrota.yaml`, `hermes/skins/piabrota.yaml`|The dark tokens only.|
|`site/src/piabrota_site/parts.gleam`, `favicon/favicon.svg`|The eye. `checks.favicon` compares them.|
