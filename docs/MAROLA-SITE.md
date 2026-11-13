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
| `marola-boards.yml` (GitHub Actions) | Every 6 hours, from outside: `scripts/marola_boards_check.sh` reads each area's `latest.json` and fails when one is older than 12 hours, so two failed builds in a row mail the owner. The build stays on the box: INEA and INEMA refuse GitHub's US runners. |
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
4. Check `https://marola.dev/`, `/about.html`, `/en/studies`, `/api/v1/skill.md`,
   `/data/floripa/latest.json`, `https://www.marola.dev/` (301) and `https://marola.piabrota.art/`. On the
   box (as `observer`): `systemctl status marola-site nginx`, `journalctl -u acme-order-renew-marola.dev`.

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

The start waits for the whole build (up to 45 minutes). Each run tries twice, and a run that fails
still publishes the areas it finished. A failed run does not leave the unit failed (`ExecStart=-`), so a
deploy that starts it is not rolled back; read the exit code in the journal (`status=125/n/a, ignoring`
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

Change `rev` and `hash` in `marola-site/default.nix` together (`nix hash path` on `git archive <rev>`).
A marola-site change to `front/package-lock.json` or the Haskell packages can need a nixpkgs override in
its `nix/package.nix`; the build failure names the package.
