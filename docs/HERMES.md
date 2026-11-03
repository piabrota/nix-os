# Hermes Agent on piabrota

[Português](HERMES.ptBR.md)

[Hermes Agent](https://github.com/NousResearch/hermes-agent) is Nous Research's agent: a Python
program that talks over chat platforms (Telegram, Discord, Slack and others), uses tools and runs
scheduled jobs. This box runs it as the unit `hermes-agent` (`hermes.nix`): its messaging gateway,
which answers on the platforms it has tokens for.

The project publishes a flake with a package and a NixOS module (`nixosModules.default`). This
repository's `flake.nix` takes it as the input `hermes-agent`, and `hermes.nix` only picks the
options. For the project, Nix and NixOS are a Tier 2 platform: the flake and the module are kept
"best effort", and a commit to their `main` can break them. So `flake.lock` pins a commit, and the
weekly flake update (`flake-update.yml`) moves it only in a PR that CI builds before the merge.

## What `hermes.nix` picks

| | |
|---|---|
| Mode | Native: a systemd service on the host, with the module's sandbox (`ProtectSystem=strict`, `NoNewPrivileges`, `PrivateTmp`). Not container mode, which would need Docker or Podman. |
| Package | `minimal`, plus the extras `anthropic` (Anthropic's SDK) and `messaging` (Telegram, Discord, Slack). The flake's default, `full`, adds about 700 MB more (voice, Bedrock, Modal and the like). |
| Model | `claude-sonnet-5-5` through the `anthropic` provider, on the owner's subscription: `CLAUDE_CODE_OAUTH_TOKEN` (from `claude setup-token`), as piabrota/agents does. No API key. |
| Secrets | `/var/lib/hermes-secrets/hermes.env`, written by hand on the box, readable by root only. Never in the repository or the store. |
| Limits | `MemoryMax=1G` (a quarter of the RAM) and `CPUWeight=50`: sshd, nginx and the apps get the CPU first. |
| State | `/var/lib/hermes` (`HERMES_HOME` is `/var/lib/hermes/.hermes`): the configuration, the memory, the sessions and the `.env`. |
| CLI | `hermes` on the PATH (`addToSystemPackages`), on the service's own state; `h0ffmann` is in the `hermes` group. |

The configuration lives in Nix: on NixOS, `hermes setup`, `hermes config set` and
`hermes gateway install` refuse to change what the module manages. Change `hermes.nix` in a PR.

## Who it is

`hermes/SOUL.md` is its identity: piabrota-hermes, on this VPS, on Claude Sonnet, with what it has
and does not have, and rules taken from piabrota's dogma (`piabrota/mu`, `DOGMA.md`): it never
reads or repeats a secret, never pushes or merges, takes alerts from official sources only, and
cites what it claims. It also explains that the "Claude Code" line at the start of its prompt is
how the subscription authenticates. `hermes/AGENTS.md`, in its working directory, is the brief:
the owner, piabrota's and marola's repositories, the official sources for watchers, the jobs he
may ask for, and this VPS. Activation installs both on every deploy: change them here, in a PR.
The time zone is `America/Sao_Paulo`, and the `hermes` user reads the journal
(`systemd-journal`) for its daily check of the box.

## Add-ons

All are declared in `hermes.nix`, so they arrive with a deploy and move with the flake input.

| Add-on | Kind | What for |
|---|---|---|
| `mcp`, `ddgs` | extras | The MCP client (without it the servers below do nothing) and DuckDuckGo search, with no key |
| DeepWiki, Context7 | remote MCP servers, no key | Questions about public repositories (piabrota, marola-dev, nixpkgs) and current library docs. Nothing runs on the box for them. |
| `watchers`, `rss-feeds` | optional skills | Poll RSS, JSON APIs and GitHub with dedup on Hermes's cron: bathing-water bulletins, Defesa Civil and INMET alerts, ocean news |
| `duckduckgo-search`, `research-paper-writing` | optional skills | Web search; papers, with the bundled `arxiv` and `grounded-citations` |
| `ast-grep` | optional skill, plus `pkgs.ast-grep` | Structural code search |
| `gh` | package | For the bundled `github` skill. Put a fine-grained token with read access only in the env file as `GITHUB_TOKEN`: it reads, and it cannot push or merge. |

The optional skills are one read-only directory in `skills.external_dirs`, taken from the
project's `optional-skills/` at the pinned commit. The bundled skills (`arxiv`, `github`,
`obsidian`, `weekly-review-planning` and the rest) come with the package. Left out, because they
need Node, Go or Homebrew on the box: `pr-lens`, `qmd`, `llm-wiki`, `blogwatcher`, `archify`. Left
out for the box's size: voice, the `mlops` skills, a local browser and `computer-use`.

## One-time setup on the box

Without the secrets file, activation only warns (`cannot read environmentFile`) and the gateway
starts with no platform, running only the scheduled jobs. A deploy never fails because of it.

1. Make the subscription token on your computer: `claude setup-token`.
2. Make a bot on the platform you want. On Telegram: talk to
   [@BotFather](https://t.me/BotFather), `/newbot`, and keep the token. Your numeric ID comes from
   [@userinfobot](https://t.me/userinfobot).
3. On the box, write the file (paste the lines and end with Ctrl-D):

   ```console
   ssh h0ffmann@piabrota.art
   sudo install -m 600 /dev/stdin /var/lib/hermes-secrets/hermes.env
   CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-...
   TELEGRAM_BOT_TOKEN=123456:ABC...
   TELEGRAM_ALLOWED_USERS=<your numeric ID>
   GITHUB_TOKEN=github_pat_...   # optional: read-only, for the github skill
   ```

   Instead of Telegram: `DISCORD_BOT_TOKEN` and `DISCORD_ALLOWED_USERS`, or `SLACK_BOT_TOKEN`,
   `SLACK_APP_TOKEN` and `SLACK_ALLOWED_USERS` (the names come from the project's `.env.example`).
   Without a list of allowed users, the gateway refuses everyone (`GATEWAY_ALLOW_ALL_USERS` is
   `false` by default).
4. The system's activation, not the service, copies this file into Hermes's `.env`. Run the
   activation again and restart:

   ```console
   sudo /run/current-system/bin/switch-to-configuration switch
   sudo systemctl restart hermes-agent
   ```

   The same goes for every change to the file. The next deploy copies it too.

## Checking it

```console
systemctl status hermes-agent
journalctl -u hermes-agent -n 100
hermes status
hermes doctor
```

The log says which platforms connected; "No messaging platforms enabled" means the `.env` has no
platform token.

## Updating and turning it off

- **Update:** the weekly `flake-update.yml` PR moves the `hermes-agent` input with the rest, with
  the closure difference (`dix`). CI builds it; the merge deploys it.
- **Turn off:** take `./hermes.nix` out of `configuration.nix`'s `imports` in a PR. The deploy stops
  and removes the unit; `/var/lib/hermes` and `/var/lib/hermes-secrets` stay on the box until
  someone deletes them.

## Sources and what was not checked

- [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent): `flake.nix`,
  `nix/nixosModules.nix`, `nix/moduleCommon.nix` (the options, the activation that merges the
  `environmentFiles` into `.env`), `nix/packages.nix` (`minimal`, `full`, `messaging`),
  `hermes_cli/auth.py` (`CLAUDE_CODE_OAUTH_TOKEN` in the `anthropic` provider), `.env.example`, and
  [the Nix page](https://hermes-agent.nousresearch.com/docs/getting-started/nix-setup), read on
  2026-11-02.
- Not checked: the system has not been built or run on the box yet (CI builds the PR); RAM use and
  the closure size on the VPS were not measured.
