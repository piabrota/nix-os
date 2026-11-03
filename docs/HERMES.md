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

What exists for Hermes, and what this box takes from it: [`AWESOME-HERMES.md`](AWESOME-HERMES.md).

## What `hermes.nix` picks

| | |
|---|---|
| Mode | Native: a systemd service on the host, with the module's sandbox (`ProtectSystem=strict`, `NoNewPrivileges`, `PrivateTmp`). Not container mode, which would need Docker or Podman. |
| Package | `minimal`, plus the extras `anthropic` (Anthropic's SDK) and `messaging` (Telegram, Discord, Slack). The flake's default, `full`, adds about 700 MB more (voice, Bedrock, Modal and the like). |
| Model | `claude-sonnet-5-5` through the `anthropic` provider, with `claude-haiku-4-5` for subagents and two cheap side tasks (see "Run settings"), on the owner's subscription: `CLAUDE_CODE_OAUTH_TOKEN` (from `claude setup-token`), as piabrota/agents does. No API key. |
| Secrets | `/var/lib/hermes-secrets/hermes.env`, written by hand on the box, readable by root only. Never in the repository or the store. |
| Limits | `MemoryMax=1G` (a quarter of the RAM) and `CPUWeight=50`: sshd, nginx and the apps get the CPU first. |
| State | `/var/lib/hermes` (`HERMES_HOME` is `/var/lib/hermes/.hermes`): the configuration, the memory, the sessions and the `.env`. |
| CLI | `hermes` on the PATH (`addToSystemPackages`), on the service's own state; `h0ffmann` is in the `hermes` group. |

The configuration lives in Nix: on NixOS, `hermes setup`, `hermes config set` and
`hermes gateway install` refuse to change what the module manages. Change `hermes.nix` in a PR.

## Interfaces

How people and jobs reach Hermes, and where each piece is set. The rule for all of them: the
choice is in `hermes.nix`, and a token or an allowed-users list is in the secrets file on the
box (never here, never a value in a PR).

| Interface | How it runs here | In `hermes.nix` | On the box (`hermes.env`) |
|---|---|---|---|
| Telegram | Polling mode, no open port. Answers only the allowed users. Reactions (👀, ✅) replace "still working" messages. | `settings.telegram.reactions`; `HERMES_TELEGRAM_DISABLE_FALLBACK_IPS` (no DNS-over-HTTPS lookups of Telegram through third parties); media read into RAM capped at 20 MiB (`gateway.max_inbound_media_bytes`) | `TELEGRAM_BOT_TOKEN`, `TELEGRAM_ALLOWED_USERS` |
| Discord | A bot in the owner's server, answers only the allowed user. No voice: the `full` package is not installed, so the Opus warning in the log is expected. | `DISCORD_MAX_ATTACHMENT_BYTES` at 20 MiB, the same cap as Telegram | `DISCORD_BOT_TOKEN`, `DISCORD_ALLOWED_USERS` |
| Slack | In the `messaging` extra; no setup is kept here beyond the variable names (see "One-time setup"). | none | `SLACK_BOT_TOKEN`, `SLACK_APP_TOKEN`, `SLACK_ALLOWED_USERS` |
| Cron | Hermes's own scheduler, inside the gateway: one job at a time, results to the home channel (`/sethome`, see "Discord"), without the header and footer. Dates in `America/Sao_Paulo`. | `settings.cron.max_parallel_jobs = 1`, `settings.cron.wrap_response = false`, `settings.timezone` | none |
| CLI | `hermes` on the PATH, on the service's own state, for users in the `hermes` group (`h0ffmann`). | `addToSystemPackages`, `users.users.h0ffmann.extraGroups` | none |
| MCP servers | DeepWiki and Context7, remote, no key; nothing runs on the box for them. | `mcpServers`; `settings.mcp.auto_reload_on_config_change = false` | none |

With no allowed-users list for a platform, the gateway refuses everyone on it. With no secrets
file, it starts with no platform and runs only the scheduled jobs.

## Run settings

What `hermes.nix` sets beyond the model and the add-ons, for one vCPU, 1 GB and a subscription's
quota. The survey of each key at the pinned commit is in [`AWESOME-HERMES.md`](AWESOME-HERMES.md).

| Setting | Value | Why |
|---|---|---|
| `fallback_providers` (main and `delegation`) | empty | Claude models only. If Anthropic fails, the turn fails; it never goes to another provider. |
| `model.default` | `claude-sonnet-5-5` | Sonnet is the high-level model: it plans, writes, reviews and decides. |
| `delegation.model`, `auxiliary.title_generation`, `auxiliary.skills_hub` | `claude-haiku-4-5` | Haiku is the low-level model: subagents (simple greps, lookups, lists) and two cheap side tasks. Hermes has no per-call router: Sonnet decides to delegate, and `hermes/SOUL.md` says when. Compression, the dangerous-command approval and the post-turn review stay on Sonnet. |
| `delegation` | at most 2 children, 50 iterations each, one level deep | Small fan-out, for one vCPU and the quota. |
| `agent.max_turns`, `tool_loop_guardrails.hard_stop_enabled` | 60, on | A bound on a run, and a hard stop on tool loops. |
| `prompt_caching.cache_ttl` | `auto` | 1 h for chat (people pause), 5 min for cron and subagents. |
| `mcp.auto_reload_on_config_change` | off | A config change does not reload the MCP servers (which would drop the prompt cache); only a deploy changes the config. |
| `agent.agent_cache.max_size` | 16 | Fewer cached agents, to save RAM. |
| `code_execution.max_session_kernels` | 1 | One code kernel at a time. |
| `sessions` | prune after 45 days, then vacuum `state.db` | Disk. |
| `security.allow_lazy_installs` | off | Nix owns the dependencies: no `pip install` at run time. |
| `model_catalog.enabled`, `updates.check`, `telemetry.shared_metrics.enabled` | off | No model catalog fetched from Nous, no update checks (Nix owns updates), nothing sent to Nous. |

Hermes does not restart by itself when a deploy changes its files: activation rewrites
`config.yaml`, `.env`, `SOUL.md`, `AGENTS.md` and the plugin links, but the unit does not change.
So `hermes.nix` lists them as `restartTriggers` of `hermes-agent` (the settings, the environment,
the MCP servers, the optional skills, the plugins and the two documents). When you add a new kind
of input to the module, add it there too, or a deploy will leave the old process running with the
old configuration.

## Who it is

`hermes/SOUL.md` is its identity: piabrota-hermes, on this VPS, on Claude Sonnet, with what it has
and does not have, and rules taken from piabrota's dogma (`piabrota/mu`, `DOGMA.md`): it never
reads or repeats a secret, never pushes or merges, takes alerts from official sources only, and
cites what it claims. It has one hard rule from the owner: every message with good news (an improvement, a fix
that worked, a check back to healthy) starts with **piou a melhoria**. It also explains that the "Claude Code" line at the start of its prompt is
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

## Community add-ons

Picked from [awesome-hermes-agent](https://github.com/0xNyk/awesome-hermes-agent) on 2026-11-03,
each read before pinning (license, last commit, every entry point, and what it runs, reads and
sends), and pinned by commit in `hermes.nix`:

| Add-on | Kind | What for |
|---|---|---|
| [custom-dangerous-patterns](https://github.com/scross01/hermes-custom-dangerous-patterns-plugin) v0.5.2 (MIT) | plugin | Blocks terminal commands that match `hermes/dangerous-patterns.yaml`: writes to GitHub (`git push`, `gh pr merge`, `gh api -X POST` and the rest), reads of secrets, `sudo` and rebuilds, and installs or `curl \| sh`. The list lives in the store, so the agent cannot edit it. |
| [evidence-ledger-research](https://github.com/markoblogo/abvx-agent-skills) (MIT) | skill | Source, date, unit and table-cell discipline when it extracts numbers from bulletins, PDFs and papers. |

Limits from the list's operational playbooks: `agent.max_turns = 60`; subagents at most 2 at a
time, 50 iterations each, one level deep; `tool_loop_guardrails.hard_stop_enabled`; no update
checks (Nix owns updates) and no shared metrics.

Left out, with the reason: cronalytics (needs a writable plugin directory), rtk-hermes (its hook
order with the deny list is untested), agentburn (its skill runs `uvx`, an unpinned download),
hermes-lcm and the memory providers (too heavy for 1 GB, or a server or a cloud), and every item
that needs Node, a paid API or a web dashboard, or has no licence. Nothing on the list covers
Brazilian alerts, bathing water or ocean science: those are piabrota's own skills to write.

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

## Discord

Hermes's `messaging` extra already has discord.py; Discord needs only a bot and two lines in the
secrets file. From the project's guide (`website/docs/user-guide/messaging/discord.md` at the pin):

1. At the [Discord Developer Portal](https://discord.com/developers/applications): **New
   Application**, then **Bot**. Under **Privileged Gateway Intents**, turn on **Message Content
   Intent** and **Server Members Intent** (without the first, Discord refuses the connection).
   **Reset Token** and keep it.
2. Invite it to your server: **Installation** (or OAuth2), scopes `bot` and
   `applications.commands`, permissions 309237763136 (view, send, embeds, files, history, threads,
   reactions; no voice).
3. Your user ID: Discord **Settings → Advanced → Developer Mode** on, then right-click your name,
   **Copy User ID**.
4. On the box, add to `/var/lib/hermes-secrets/hermes.env` (`sudo nano`):

   ```text
   DISCORD_BOT_TOKEN=...
   DISCORD_ALLOWED_USERS=<your user ID>
   ```

   Then `sudo /run/current-system/bin/switch-to-configuration switch && sudo systemctl restart
   hermes-agent`. The log says when Discord connects.

In a server channel it answers only when @mentioned, in a thread of its own; in a DM, always. It
never pings `@everyone`, `@here` or a role (the defaults, and `SOUL.md` says so). `hermes.nix`
caps attachments at 20 MiB, as for Telegram. Send `/sethome` in the channel where scheduled
results should go.

## Write access to GitHub

When the owner asks, Hermes clones a repository, works on a `hermes/*` branch, pushes it and opens
a pull request, as **piabrota-hermes[bot]**, its own GitHub App. It never merges: the owner does.
`hermes-github.nix` keeps the App's key root-only and gives Hermes one-hour tokens.

1. **Create the App** (once): github.com/organizations/piabrota/settings/apps → **New GitHub App**.
   Name `piabrota-hermes`, any homepage (piabrota.art), **Webhook** off. Repository permissions:
   **Contents** read and write, **Pull requests** read and write, **Issues** read and write,
   Metadata read; nothing else (no Workflows, no Administration). Where it can be installed:
   **Any account**, so it can go on marola-dev and h0ffmann too.
2. **Generate a private key** on the App's page (a `.pem` downloads), and note the **App ID**.
3. **Install it** (App page → **Install App**) on piabrota, marola-dev and h0ffmann, on all
   repositories or the ones Hermes may work on.
4. **Protect the default branches**: in each organisation, Settings → Rules → Rulesets → **New
   branch ruleset**, target the default branch, **Restrict deletions**, **Block force pushes**,
   **Require a pull request before merging**, with no bypass for the App. GitHub then refuses a
   push to `main` even if the deny list were to miss one.
5. **Put the key on the box** (from your computer, then on the VPS):

   ```console
   base64 < piabrota-hermes.*.private-key.pem | tr -d '\n'   # on your computer: copy the output
   sudo install -m 600 /dev/stdin /var/lib/hermes-secrets/github-app.env   # on the VPS, then paste:
   GH_APP_ID=<the App ID>
   GH_APP_PRIVATE_KEY_B64=<the base64 line>
   ```

   End with Ctrl-D, then `sudo systemctl start hermes-github-token` and
   `journalctl -u hermes-github-token` (one line per account: "token for one hour"). Delete the
   `.pem` from your computer once it works; a new one can be generated any time.

Then ask on Telegram or Discord: "abre um PR em piabrota/nix-os que …". Hermes answers with the
link. If you used a read-only `GITHUB_TOKEN` before, remove it from `hermes.env`: the App replaces
it.

## Checking it

```console
systemctl status hermes-agent
journalctl -u hermes-agent -n 100
hermes status
hermes doctor
```

The log says which platforms connected; "No messaging platforms enabled" means the `.env` has no
platform token. Two warnings are expected: the Discord adapter's "Opus codec not found" (voice is
left out), and the deny-list plugin saying it cannot write its integrity hash next to a file in
the store (the list is read-only on purpose). To check that a deploy took effect, compare
`systemctl show hermes-agent -p ActiveEnterTimestamp` with the time of the deploy: the unit
restarts when its inputs change (see "Run settings").

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
- Seen running on the box on 2026-11-03: the unit active, `MemoryMax` 1 GiB, `CPUWeight` 50, and
  about 350 MiB in use at one reading, with Telegram connected in polling mode. One reading is not
  a peak: the use under load and the closure size on the VPS were not measured.
