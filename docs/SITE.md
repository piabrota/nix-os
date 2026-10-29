# The static site on piabrota.art

`site.nix` serves the files in `site/` on `piabrota.art` and `www.piabrota.art`, through nginx
with a Let's Encrypt certificate. It is off until DNS points at the VPS.

| Desktop | Phone (390 px) |
|---|---|
| ![The site in light mode, desktop](images/site-desktop-light.png) | ![The site in light mode, phone](images/site-mobile-light.png) |
| ![The site in dark mode, desktop](images/site-desktop-dark.png) | ![The site in dark mode, phone](images/site-mobile-dark.png) |

The page follows the visitor's light or dark setting. To change its design, the agent skills
`frontend-design`, `web-design-guidelines` and `open-pencil` are in `.claude/skills/`
([their README](../.claude/skills/README.md)).

## Turn it on

1. **Manual, Porkbun.** Today `piabrota.art` is a Porkbun URL forward (`pixie.porkbun.com`). Remove
   the forward, then set an `A` record for `piabrota.art` and for `www.piabrota.art` to the VPS's
   IPv4 address (the `DEPLOY_HOST` secret). Remove any `AAAA` or `ALIAS` record that points
   elsewhere: Let's Encrypt tries IPv6 first when it finds one.
2. Wait until both names resolve to the VPS from outside:

   ```sh
   dig +short piabrota.art A
   dig +short www.piabrota.art A
   ```

3. Open a PR that sets `piabrota.site.enable = true;` (in `configuration.nix`). The merge deploys
   it, and the first switch orders the certificate.

If DNS is wrong, the ACME unit fails on the switch, deploy-rs reports the activation as failed and
rolls back. Fix DNS and merge again.

`piabrota.art/nixos` answers with a 302 to this repository, as the Porkbun forward did, so the
README link keeps working. Add more in `piabrota.site.redirects`.

## Change the site

Edit the files in `site/` and open a PR. The site is part of the system closure: a merge deploys
it, and a rollback brings the old page back with the old system. Keep it small and static (HTML,
CSS, images): there is no build step and no runtime.

`checks.site-example` builds the system with the site on, so CI catches a broken `site.nix`
before the flag is flipped.

## What it costs

nginx and the ACME client (lego) enter the closure the first time something uses nginx: the site
or a Loco app. Idle nginx uses a few MiB of RAM. Measure with `dix` as `AGENTS.md` asks.
