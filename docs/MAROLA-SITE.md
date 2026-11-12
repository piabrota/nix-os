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
   then remove the custom domain `marola.dev`. In marola-site, remove the `routes` entry from
   `wrangler.jsonc` in the same hour, or the next `site.yml` deploy attaches marola.dev to the Worker
   again.
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
sudo install -m 0600 /dev/stdin /etc/marola/ghcr-token   # paste, then Ctrl-D
sudo systemctl start marola-boards-build && journalctl -u marola-boards-build -n 20
```

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

- **The site, to the Worker** (minutes): put the custom domain `marola.dev` back on the Worker
  (or restore `routes` in `wrangler.jsonc` and run `site.yml`), which replaces the A records. GitHub
  Pages still gets each `site.yml` deploy too.
- **The server, to an older build**: move `rev` and `hash` in `marola-site/default.nix` back and merge.
  marola-site's tables only grow, so an older server reads a newer database; never delete
  `/var/lib/marola/studies` on a rollback.
- **The whole box**: `sudo nixos-rebuild switch --rollback`, then revert the commit ([DEPLOY.md](DEPLOY.md)).

## Moving the pin

Change `rev` and `hash` in `marola-site/default.nix` together (`nix hash path` on `git archive <rev>`).
A marola-site change to `front/package-lock.json` or the Haskell packages can need a nixpkgs override in
its `nix/package.nix`; the build failure names the package.
