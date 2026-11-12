# marola-hermes

[Português](MAROLA-HERMES.ptBR.md)

marola-hermes is the chat bot of [marola](https://marola.dev), run by Hermes on piabrota2
(`marola-hermes.nix`). It is not a new service: it is the Hermes profile `marola-hermes`, served by
the same gateway as the main profile (`gateway.multiplex_profiles`). A profile that owns its own bot
credential gets its own adapter and answers as that bot; its secrets come from its own `.env` only,
never from the main profile's (upstream's `gateway/AGENTS.md` at v0.23.1).

It is off (`piabrota.marolaHermes.enable = false` in `hosts/piabrota2`).

## What it can do

| | |
|---|---|
| Platform | Telegram (polling, no open port) or Discord, whichever token is in the secrets file. |
| Model | `claude-sonnet-5-5`, on the owner's subscription (the `CLAUDE_CODE_OAUTH_TOKEN` of `hermes.env`, copied into the profile's `.env`). |
| Tools | `web`, `skills`, `todo` (`platform_toolsets`). No terminal, no files, no browser, no messages to other chats. |
| GitHub | None. Hermes's writes to the marola repositories stay with marola-pr-bot (`marola-bot.nix`). |
| Who | Only the IDs in `TELEGRAM_ALLOWED_USERS` or `DISCORD_ALLOWED_USERS`. Without a list, the gateway refuses everyone. |

## Turning it on

1. Make the bot. On Telegram: [@BotFather](https://t.me/BotFather), `/newbot`, name `marola-hermes`,
   and keep the token. On Discord: a new application with a bot in the Developer Portal.
2. On the box, write the secrets file (end with Ctrl-D):

   ```console
   ssh h0ffmann@hermes.piabrota.art
   sudo install -m 600 /dev/stdin /var/lib/marola-hermes-secrets/bot.env
   TELEGRAM_BOT_TOKEN=123456:ABC...
   TELEGRAM_ALLOWED_USERS=<numeric IDs, comma-separated>
   ```

   For Discord: `DISCORD_BOT_TOKEN` and `DISCORD_ALLOWED_USERS`. Only `TELEGRAM_*` and `DISCORD_*`
   lines are copied.
3. Set `piabrota.marolaHermes.enable = true` in `hosts/piabrota2/default.nix` in a pull request.
   The merge deploys it.
4. Restart Hermes once, so the gateway starts the new bot: `just remote-restart hermes h0ffmann <address>`.

The unit `marola-hermes-env` writes the profile's `.env`; a path unit runs it again when
`bot.env` changes. A new token still needs the restart of step 4.

## Checking it

```console
systemctl status marola-hermes-env
sudo journalctl -u hermes-agent | grep -i marola-hermes
```

Then write to the bot from an allowed account.

## Turning it off

`piabrota.marolaHermes.enable = false`, or delete `bot.env` and restart Hermes.

## Not checked

- The full system build with the module on: `nix flake check` was not run. The module was evaluated
  alone against nixpkgs with stub Hermes options (the profile files, `config.yaml` and the unit).
- That a profile's `.env` written after the gateway started is read without a restart.
