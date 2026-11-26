# marola.dev on piabrota2

`marola-site.nix` (`piabrota.marolaSite`) runs [marola-site](https://github.com/marola-dev/marola-site)
on piabrota2: its Haskell server, `marola-server`, with the Elm map page and the static pages it serves,
behind nginx with Let's Encrypt. `marola-site/default.nix` pins a commit and builds that repository's own
`nix/package.nix`. The unit and the nginx settings follow marola-site's
[docs/5-hosting.md](https://github.com/marola-dev/marola-site/blob/main/docs/5-hosting.md), which is the
contract: read it before you change one.

## What runs

| Unit | Does |
|---|---|
| `marola-site` | `marola-server` on `127.0.0.1:8095` as the user `marola`, `MemoryMax=256M`, the file system read-only except `/var/lib/marola` (`marola.db`, `csrf.key`, `studies/`). |
| `marola-boards.timer` | Every 3 hours, when `boards.mirrorFrom` is set: copies each area's `latest.json` and boards from that URL into `/var/lib/marola-boards` (`MAROLA_DATA`). An area whose copy fails keeps its old boards. |
| `marola-boards-build.timer` | Four times a day (01:01, 07:01, 13:01 and 19:01 America/Sao_Paulo; the first run of a day is at 01:01 local, so the board's `today` is right after midnight), when `boards.build.enable` is set (on at piabrota2): runs the app image that the pinned marola-site commit names in `marola-image` with podman, `--site` over its `site/areas.json`, as marola-site's `site.yml` does, and puts each area it built into `/var/lib/marola-boards`. An area it did not build keeps its old boards. The beach lists stay in `/var/lib/marola-boards-build/site/beaches`; the committed lists in the pinned site's `site/beaches` are copied there before each build, so a new area ships its list with the pin and Overpass is asked only for an area with none. piabrota2 is in Brazil (LACNIC: `BR`), which INEA and INEMA require. Use it or the mirror, not both. |
| `marola-tiles` | The base map's tiles file, `/var/lib/marola/tiles/marola.pmtiles` (`MAROLA_TILES`, about 216 MB; marola-site's docs/5-hosting.md, "The base map"). Cut on the box by marola-site's own `scripts/basemap_extract.sh` (pmtiles, tile-join, node) from the Protomaps build its `site/basemap.version` pins, for the areas of its `site/areas.json`; written beside the live file, then renamed. `/var/lib/marola/tiles/.stamp` holds a hash of the pin and the areas: a run that finds the same stamp does nothing. `marola-tiles-kick` starts it (without waiting) on the first deploy and on every deploy that changes the pin or the areas. Protomaps keeps about a week of daily builds: a pin older than that fails here, the old file stays, and marola-site moves its pin. Without the file the map page shows its beach list and "the map did not load". |
| `marola-boards-build-kick` | Starts `marola-boards-build` (without waiting for it) on the first deploy with the build on and on every deploy that moves `boards.build.image` or `site/areas.json`, so a new image or a new area builds at once instead of at the next timer run. |
| `marola-boards.yml` (GitHub Actions) | Every 6 hours, from outside: `piabrota marola-boards-check` (`scala/scripts/MarolaBoardsCheck.scala`) reads each area's `latest.json` and fails when one is older than 12 hours, so two failed builds in a row mail the owner. The build stays on the box: INEA and INEMA refuse GitHub's US runners. |
| `marola-backup.timer` | Daily: `marola.db` (SQLite's `.backup`), `csrf.key` and `studies/` into `/var/backups/marola`; database copies older than 14 days are deleted. Same disk: copy it off the box if the studies matter. |
| nginx | `domain` and each name in `aliases` (the same site, a vhost and a certificate each) over HTTPS, HSTS, 1 MB bodies except 21 MB on `/submit`, `/en/submit` and `/api/v1/studies` (not buffered); `X-Forwarded-For` replaced with `$remote_addr`. Each name in `redirects` answers 301 to `domain`. |

## DNS

No Cloudflare (the owner, 2026-11-13): piabrota2 (`187.41.117.18`) serves `marola.dev` and
`marola.piabrota.art` itself, each its own nginx vhost with its own Let's Encrypt certificate (`domain`,
`aliases`), and `www.marola.dev` answers 301 to `marola.dev` (`redirects`). `marola.piabrota.art` is on
Porkbun with the other piabrota.art names ([SITE.md](SITE.md#dns-on-porkbun)). `marola.dev` was on
Cloudflare, which served the Worker `marola` (marola-site's `wrangler.jsonc`, MIP-0078).

Each name needs its A record at piabrota2 before the deploy that serves it, or its ACME order fails
(`acme-retry.nix` then retries every 20 minutes, and the other names keep their certificates).

## Moving marola.dev here

1. Cloudflare, Workers & Pages, `marola`, Settings, Domains & Routes: remove the custom domain
   `marola.dev`. Then delete the Worker, or leave it: nothing deploys to it any more (marola-site's
   `site.yml` is gone).
2. DNS of `marola.dev`: `A marola.dev` and `A www` → `187.41.117.18`, with no proxy. Either keep the zone
   on Cloudflare with the grey cloud (**DNS only**), or move the nameservers to the registrar's or to
   Porkbun and drop the Cloudflare zone. Proxied, the ACME HTTP challenge and the server's per-address
   rate limit see Cloudflare, not the visitor. Remove any `AAAA` record that does not point here. A low
   TTL (60 s) makes a rollback fast.
3. Wait until `dig +short marola.dev www.marola.dev` answers `187.41.117.18`, then merge. The deploy
   orders the two certificates.
4. Check `https://marola.dev/`, `/about.html`, `/partners.html`, `/ecomonitoramento.html`,
   `/en/ecomonitoramento.html`, `/en/studies`, `/api/v1/skill.md`, `/data/floripa/latest.json`,
   `/data/complexo-lagunar/latest.json`, `/data/parana/latest.json`, `https://www.marola.dev/` (301) and
   `https://marola.piabrota.art/`. On the box (as `observer`): `systemctl status marola-site nginx`,
   `journalctl -u acme-order-renew-marola.dev`.

The `ecc34e3` pin (2026-11-25) adds the `complexo-lagunar` area to `site/areas.json` and the
`ecomonitoramento` page. The areas change makes `marola-tiles` re-cut the file on the first deploy
after the pin; the next `marola-boards-build` timer run builds the CL boards. The map's CL selector
answers before the boards exist (the area list is static), but the beaches and water points appear
only after that run. The board build did not start on this pin itself: the `marola-image` file did
not move and the old kick watched only the image, so the timer was the one that ran. The kick now
watches `site/areas.json` too: a deploy that adds an area (such as `complexo-lagunar`) starts the
build at once.

The `d48f391` pin (2026-11-25, marola-site#241) brings the Complexo Lagunar view — the camera fits
its lagoons, the Canto das Águas pin links to the institute, and CL opens on the bathing-water layer
with IMA/SC's 31 points — and `/embed`, the chrome-less map a partner frames. The areas file changed,
so `marola-tiles` re-cuts the file on the first deploy after this pin, and the board kick starts a
build at once. The embed's `frame-ancestors` comes from `embedFrom` (`MAROLA_EMBED_FROM`, one origin
per line, empty: `'none'`); the host sets Canto das Águas, so only that site may frame the map. After
the deploy, `curl -sI https://marola.dev/embed | grep -i frame-ancestors` answers
`https://cantodasaguas.org`, and `https://marola.dev/` still answers `'none'`.

The `57c25dc` pin (2026-11-26, the squash merge of marola-site#278, after #276 and #277) adds the Litoral do Paraná — the Ilha do Mel view,
IAT/PR's 59 bathing-water points and 67 OpenStreetMap trails — the saturated light base-map palette,
and the full-size Spotify player. `site/areas.json` changed, so `marola-tiles` re-cuts the file on the
first deploy after this pin, with the new area's box at zoom 10 to 15 (Brazil at zoom 7 to 9 already
covers it), and `marola-boards-build-kick` starts a board build at once. The area selector answers
before the boards exist; its beaches appear after that run, and its water points come from the site's
own `data/water/parana.json`, not from the board. The host's `MAROLA_TILES` file is the only host-side
piece; the rest is in the pinned site.

The `605cac5` pin (2026-11-26, the squash merge of marola-site#279) keeps the Paraná map on the
Litoral at Ilha do Mel and adds the state-wide data behind it: IAT/PR's 76 points (59 Litoral, 16
Costa Oeste, 1 Norte), 247 OpenStreetMap trails in 18 groups with T1–T6 difficulty labels, the
committed 46-beach snapshot, the three highest peaks (Pico Paraná, Pico Caratuva and Pico Itapiroca)
and the scuba layer with the two Florianópolis dive sites. Water samples are drawn once and enrich
the beaches; the footer names IAT/PR when the board has no water source. The about page links five
Archify HTML figures at `/architecture`, `/data-flow`, `/studies-flow`, `/deploy-flow` and
`/develop-flow`, and the contact nav opens `mailto:admin@marola.dev`. `site/areas.json` changed (the
Litoral bounds and the peak pins), so `marola-tiles` re-cuts the file and
`marola-boards-build-kick` starts a board build at once. The Paraná board is deterministic now: the
build copies the pinned `site/beaches` into its work folder and reads
`m25.5345_m48.3107_r70.0_n80.json`, the 46 named beaches of the state, instead of an Overpass
query. The figures are static HTML in the pinned site; the server serves them
from `/`.

Between step 2 and the end of the deploy (a few minutes), marola.dev answers with no site: the
default server of `configuration.nix` refuses names with no vhost.

**The board build needs a token.** `ghcr.io/marola-dev/marola-app` is a private package. Make a GitHub
token that can read it (a classic token with `read:packages`, from the account in `boards.build.registryUser`)
and put it on the box; the unit reads it with `LoadCredential`, logs in, pulls the pinned digest and forgets
the login:

```console
sudo install -d -m 0700 /etc/marola
sudo install -m 0600 /dev/stdin /etc/marola/ghcr-token   # paste, Enter, then Ctrl-D
sudo wc -c /etc/marola/ghcr-token                        # 0 means nothing was pasted
sudo systemctl start marola-boards-build; journalctl -u marola-boards-build -n 40 --no-pager
```

The start waits for the whole build (up to 90 minutes: four areas on one core take about 45, and the timeout that was 45 killed the run of 2026-11-25 10:41 at exactly 45 minutes). Each run tries twice, and a run that fails
still publishes the areas it finished. A failed run does not leave the unit failed (`ExecStart=-`), so a
deploy that starts it is not rolled back. A deploy never stops or restarts a running build
(`restartIfChanged = false`), since a restart would hold the switch for the whole build; read the exit code in the journal (`status=125/n/a, ignoring`
is a refused pull), and `marola-boards.yml` reports boards that go stale.

A pull that answers `manifest unknown` right after `Login Succeeded!` most often means the token cannot
read the package, not that the image is gone: ghcr hides a private package from a token without
`read:packages`. A `gh` login token has no `read:packages`.

The token on the box today is the owner's `gh` login token, which can do far more than pull one image.
Replace it with a classic token that has only `read:packages`, with the same `install` line.

If the package is made public, set `boards.build.tokenFile = null`. When marola-site's `marola-image` moves,
moving the marola-site pin here moves the image too.

If the GitHub login is wanted, the owner makes the OAuth app (callback
`https://marola.dev/auth/github/callback`, no scope), sets `github.clientId`, and writes the secret on the
box:

```console
sudo install -d -m 0700 /etc/marola
sudo install -m 0600 /dev/stdin /etc/marola/github-client-secret   # paste, then Ctrl-D
```

The secret reaches the server with `LoadCredential`, never through the store or the environment. With
no `clientId`, `/auth/github/login` answers 503 and the rest of the site works.

## Rollback

- **marola.dev, off the box**: there is no other host. Until the Worker `marola` is deleted, putting
  the custom domain `marola.dev` back on it (minutes) serves its last deploy, which no longer updates.
- **The server, to an older build**: move `rev` and `hash` in `marola-site/default.nix` back and merge.
  marola-site's tables only grow, so an older server reads a newer database; never delete
  `/var/lib/marola/studies` on a rollback.
- **The whole box**: `sudo nixos-rebuild switch --rollback`, then revert the commit ([DEPLOY.md](DEPLOY.md)).

## Moving the pin

`.github/workflows/marola-site-pin.yml` does it: every 20 minutes (or at once on a `repository_dispatch` of
type `marola-site-main`) it moves the pin to marola-site's `main` with `piabrota pins one marola-site`,
builds the package, and opens or updates one PR on `agents/marola-site-pin`. The owner's merge deploys.
By hand: `just marola-site-pin [rev]`, which changes `rev` and `hash` together.
A marola-site change to `front/package-lock.json` or the Haskell packages can need a nixpkgs override in
its `nix/package.nix`; the build failure names the package.
