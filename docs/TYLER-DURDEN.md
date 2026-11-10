# tyler-durden-bot

[Português](TYLER-DURDEN.ptBR.md)

tyler-durden-bot summarizes each large pull request opened on `h0ffmann/proof` in one comment: a
TLDR, an ELI5, a summary, and a risk from very low to critical with its confidence. It is the GitHub
App **tyler-durden-bot**, owned by h0ffmann. It is not a new service: it is a webhook route of
Hermes (`hermes.nix`) on piabrota2, with its own Hermes profile, `tyler-durden`, whose GitHub token
is the App's, so the comment shows as `tyler-durden-bot[bot]` and never as piabrota-hermes.

`tyler-durden-bot.nix` declares it, **off** (`piabrota.tylerDurden.enable = false` in
`hosts/piabrota2`). With it off, the system is the same as without the module.

## How a pull request becomes a comment

1. GitHub posts the `pull_request` event, signed with the App's webhook secret, to
   `https://tyler.piabrota.art/p/tyler-durden/webhooks/tyler-durden`. nginx passes that one path,
   POST only, to Hermes's webhook port on 127.0.0.1 (8644); everything else is a 404.
2. Hermes checks the signature (`WEBHOOK_SECRET`), keeps only `action: opened`, and runs the route
   script `tyler-durden-bot.py`.
3. The script reads the pull request's files with the App's token and counts its changed lines as
   code, comment or markdown, overall and by language (by extension). Below every threshold of the
   config it prints `[SILENT]`, and no model runs.
4. Otherwise the agent of the `tyler-durden` profile writes the comment with the skill
   `tyler-durden-bot`, with no terminal, files or web (`toolsets = [ "clarify" ]`), and Hermes posts
   it with `gh pr comment` and the profile's `GH_TOKEN`.

A push, a reopen or a draft made ready does not run it again.

## Where things are

| What | Where |
|---|---|
| The script, the skill, the config (watchlist, `[trigger]`, `[sections]`, `[quality]`) and the App's manifest | piabrota/agents, `tyler-durden-bot/` and `apps/tyler-durden-bot.json`, pinned by commit in `tyler-durden-bot.nix` (`agents`) |
| The route, the profile's `config.yaml` and `SOUL.md`, the vhost, the token unit | `tyler-durden-bot.nix` |
| The App's ID and key | `/var/lib/tyler-durden-secrets/app.env` on the box, root only |
| The webhook secret | `WEBHOOK_SECRET` in `/var/lib/hermes-secrets/hermes.env` on the box |
| The token (one hour, `h0ffmann/proof` only, Pull requests write) | `/run/tyler-durden-bot/token` and the profile's `.env`, written by `tyler-durden-token` every 45 minutes |

Changing a threshold, a section or the budget is a pull request on piabrota/agents, then one here
that moves the pin.

## Turning it on

The owner, once:

1. Create the App on h0ffmann's account (Settings, Developer settings, GitHub Apps) from
   piabrota/agents' `apps/tyler-durden-bot.json`: Pull requests read and write, Metadata read, the
   Pull request event, the webhook URL above, and a webhook secret (`openssl rand -hex 32`).
   Install it on `h0ffmann/proof` only.
2. Point the A record of `tyler.piabrota.art` at piabrota2 (docs/SITE.md, "DNS on Porkbun").
3. On the box, as root:

   ```sh
   install -d -m 0700 /var/lib/tyler-durden-secrets
   printf 'GH_APP_ID=%s\nGH_APP_PRIVATE_KEY_B64=%s\n' <app-id> "$(base64 -w0 tyler-durden-bot.*.pem)" \
     > /var/lib/tyler-durden-secrets/app.env
   chmod 0600 /var/lib/tyler-durden-secrets/app.env
   echo 'WEBHOOK_SECRET=<the webhook secret>' >> /var/lib/hermes-secrets/hermes.env
   ```

4. A pull request here with `piabrota.tylerDurden.enable = true` in `hosts/piabrota2`. The merge
   deploys it.

## Checking it

- `systemctl status tyler-durden-token` says "token for one hour"; `journalctl -u hermes-agent | grep webhook`
  shows the route and each event.
- In the App's settings, Advanced, Recent Deliveries: a 200 with `ignored` is a filtered event (not
  opened, or below the thresholds); a 202 started the agent.
- Open a test pull request of more than 1000 lines on `h0ffmann/proof`.

## Turning it off

`piabrota.tylerDurden.enable = false`, or uninstall the App from `h0ffmann/proof`.

## Not checked

Written against Hermes v0.23.0's documentation and code, not run on the box yet:

- that the route script is found in the profile's `scripts/` (it is installed in both homes);
- that Hermes reads the profile's `.env` again after the token unit rewrites it, every 45 minutes;
  if not, `GH_TOKEN` expires after an hour and `gh` falls back to its stored login, which is
  piabrota-hermes: check the first comments' author;
- that the global `WEBHOOK_SECRET` from the env file reaches a route that sets no secret.
