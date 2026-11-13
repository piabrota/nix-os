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
| `marola-boards-build.timer` | Four times a day (01, 07, 13, 19 UTC), when `boards.build.enable` is set (on at piabrota2): runs the app image that the pinned marola-site commit names in `marola-image` with podman, `--site` over its `site/areas.json`, as marola-site's `site.yml` does, and puts each area it built into `/var/lib/marola-boards`. An area it did not build keeps its old boards. The beach lists stay in `/var/lib/marola-boards-build/site/beaches`, so Overpass is asked only for an area with none. piabrota2 is in Brazil (LACNIC: `BR`), which INEA and INEMA require. Use it or the mirror, not both. |
| `marola-boards-build-kick` | Starts `marola-boards-build` (without waiting for it) on the first deploy with the build on and on every deploy that moves `boards.build.image`, so a new image builds at once instead of at the next timer run. |
| `marola-site-publish` | When `worker.enable` is set (on at piabrota2): what marola-site's `site.yml` did on GitHub Actions, minus the board build and GitHub Pages. After every `marola-boards-build` run (failed or not: `ExecStopPost`) and on every deploy that moves the marola-site pin (`marola-site-publish-kick`), it puts the legacy page of the pinned commit (`site/static`) together with the boards of `/var/lib/marola-boards`, writes `llms.txt`, `sitemap.xml`, `security.txt` and `mapbox-config.js` with marola-site's own scripts, adds the `smoke/`, `coverage/` and `stats/` panels of its `site-data` branch, refuses a site with a missing file or a file off `site.yml`'s allowlist, and runs `wrangler deploy` to the Worker `marola` that serves marola.dev. wrangler runs with podman in a node image pinned by digest (`worker.nodeImage`, `worker.wranglerVersion`), because nixpkgs' wrangler is a 2.2 GiB closure. The Cloudflare token and the Mapbox token are files on the box (below). |
| `marola-boards.yml` (GitHub Actions) | Every 6 hours, from outside: `scripts/marola_boards_check.sh` reads each area's `latest.json` and fails when one is older than 12 hours, so two failed builds in a row mail the owner. The build stays on the box: INEA and INEMA refuse GitHub's US runners. |
| `marola-backup.timer` | Daily: `marola.db` (SQLite's `.backup`), `csrf.key` and `studies/` into `/var/backups/marola`; database copies older than 14 days are deleted. Same disk: copy it off the box if the studies matter. |
| nginx | `domain` over HTTPS, HSTS, 1 MB bodies except 21 MB on `/submit`, `/en/submit` and `/api/v1/studies` (not buffered); `X-Forwarded-For` replaced with `$remote_addr`. Each name in `redirects` answers 301 to `domain`. |

## DNS

`marola.dev` and `www.marola.dev` are on **Cloudflare**, not Porkbun: today they resolve to Cloudflare's
proxy, which serves the Worker `marola` (marola-site's `wrangler.jsonc`, MIP-0078). `marola.piabrota.art`
is on Porkbun with the other piabrota.art names ([SITE.md](SITE.md#dns-on-porkbun)).

Each name needs its A record at piabrota2's address before the deploy that serves it, or the ACME order
fails.

## Cutover

**Step 1: marola.piabrota.art (this change).** marola.dev stays on the Worker.

1. Porkbun: an `A` record `marola` → piabrota2's address (the one `hermes.piabrota.art` has).
2. Merge. The deploy starts the server and orders the certificate.
3. Check `https://marola.piabrota.art/`, `/about.html`, `/en/studies`, `/api/v1/skill.md` and a board
   (`/data/floripa/latest.json`). On the box (as `observer`): `systemctl status marola-site`,
   `journalctl -u marola-boards`.

**Step 2: marola.dev.** Do it when step 1 looks right.

1. Cloudflare, Workers & Pages, `marola`, Settings, Domains & Routes: note the `*.workers.dev` address,
   then remove the custom domain `marola.dev`. In the same hour, set `worker.enable = false` in
   `hosts/piabrota2/default.nix` (step 3), or the next `marola-site-publish` run attaches marola.dev to
   the Worker again through the `routes` entry of marola-site's `wrangler.jsonc`; remove that entry
   there too.
2. Cloudflare DNS of marola.dev: `A marola.dev` and `A www` → piabrota2's address, **DNS only** (grey
   cloud). Proxied, the ACME HTTP challenge and the server's per-address rate limit see Cloudflare, not
   the visitor. A low TTL (60 s) makes a rollback fast.
3. In `hosts/piabrota2/default.nix`: `domain = "marola.dev"`, `redirects = [ "www.marola.dev"
   "marola.piabrota.art" ]`, and `boards.mirrorFrom` = the Worker's `https://<name>.workers.dev/data`
   (with marola.dev it would copy from itself). Merge.
4. Between step 2.2 and the end of the deploy (a few minutes), marola.dev answers with no site: the
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

The start waits for the whole build (up to 45 minutes). Each run tries twice, and a run that fails
still publishes the areas it finished.

The token on the box today is the owner's `gh` login token, which can do far more than pull one image.
Replace it with a classic token that has only `read:packages` (or a fine-grained one limited to the
package), with the same `install` line.

If the package is made public, set `boards.build.tokenFile = null`. When marola-site's `marola-image` moves,
moving the marola-site pin here moves the image too.

**The Worker publish needs two files.** The same values `site.yml` read from marola-site's repository
secrets and variables: a Cloudflare API token that may edit Workers scripts of the account
(`CLOUDFLARE_API_TOKEN`, a narrow token made for this, not a global key), the account id
(`CLOUDFLARE_ACCOUNT_ID`) and the public `pk.` Mapbox token restricted to marola.dev's URLs
(`MAPBOX_PUBLIC_TOKEN`). A `MAPBOX_STYLE` variable, if set there, goes in `worker.mapboxStyle`.

```console
sudo install -m 0600 /dev/stdin /etc/marola/cloudflare.env   # CLOUDFLARE_API_TOKEN=…, Enter, CLOUDFLARE_ACCOUNT_ID=…, Enter, Ctrl-D
sudo install -m 0600 /dev/stdin /etc/marola/mapbox-token     # pk.…, Enter, Ctrl-D
sudo systemctl start marola-site-publish; journalctl -u marola-site-publish -n 40 --no-pager
```

Without either file the unit fails at its start and marola.dev keeps the last site the Worker got.
GitHub Pages no longer gets a copy: its last `site.yml` deploy stays there, stale.

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

- **The site, to the Worker** (minutes): put the custom domain `marola.dev` back on the Worker
  (or restore `routes` in `wrangler.jsonc`, set `worker.enable = true` and merge), which replaces the A
  records.
- **The server, to an older build**: move `rev` and `hash` in `marola-site/default.nix` back and merge.
  marola-site's tables only grow, so an older server reads a newer database; never delete
  `/var/lib/marola/studies` on a rollback.
- **The whole box**: `sudo nixos-rebuild switch --rollback`, then revert the commit ([DEPLOY.md](DEPLOY.md)).

## Moving the pin

Change `rev` and `hash` in `marola-site/default.nix` together (`nix hash path` on `git archive <rev>`).
A marola-site change to `front/package-lock.json` or the Haskell packages can need a nixpkgs override in
its `nix/package.nix`; the build failure names the package.
