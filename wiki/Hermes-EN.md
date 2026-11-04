# Hermes

[Português](Hermes)

[Hermes Agent](https://github.com/NousResearch/hermes-agent), Nous Research's agent, runs on
`kvm4` (the KVM 4 VPS) as piabrota-hermes: it answers on Telegram and Discord, runs its own
scheduled jobs and, when the owner asks, opens pull requests. This page is a map of how it runs and
how it is configured, as of [#72](https://github.com/piabrota/nix-os/pull/72) and
[#74](https://github.com/piabrota/nix-os/pull/74). The full guide is
[`docs/HERMES.md`](https://github.com/piabrota/nix-os/blob/main/docs/HERMES.md); the configuration
itself is [`hermes.nix`](https://github.com/piabrota/nix-os/blob/main/hermes.nix).

## The configuration, in YAML

[www.piabrota.art/hermes](https://www.piabrota.art/hermes) shows the whole configuration as plain
YAML: the settings that `hermes.nix` writes to `config.yaml`, and how the unit runs. The site build
reads them from the evaluated system, so the page changes with every merge that changes
`hermes.nix`. This wiki does not copy that YAML: read it there.

## The runtime

| | |
|---|---|
| Unit | `hermes-agent`, a systemd service from the NixOS module of Hermes's flake (the input `hermes-agent`, pinned in `flake.lock`). Native mode, not a container. |
| Version | The release v0.22.7 (commit `b200f5b`, 2026-11-03), pinned in `flake.lock`. |
| Host | `kvm4`, the KVM 4 VPS (`hosts/kvm4/default.nix`). |
| Package | `full`, the default of Hermes's flake, plus the extras `anthropic`, `messaging`, `mcp` and `ddgs`. |
| Limits | `MemoryMax=8G` (half the RAM) and `CPUWeight=50`: when the four cores are busy, sshd and the other units get twice Hermes's CPU share. |
| Dashboard | `hermes.piabrota.art`, behind nginx, with TLS and basic auth. Unit `hermes-backend`, `MemoryMax=2G` (`hermes-web.nix`). |
| State | `/var/lib/hermes`. The working directory is `/var/lib/hermes/workspace`. |
| Secrets | A file on the box, `/var/lib/hermes-secrets/hermes.env`, root only. Activation copies it into Hermes's `.env`. Never in the repository, the store or the `/hermes` page. |
| GitHub | Its own App, piabrota-hermes[bot] (`hermes-github.nix`): `hermes/*` branches and pull requests only, never a merge. |
| CLI | `hermes`, run by `h0ffmann` with `sudo -u hermes hermes ...`. He is not in the `hermes` group: the dashboard Chat tab needs it private. |
| Time zone | `America/Sao_Paulo`. |

## The models

Both models run on the owner's Claude subscription, never on an API key, and there is no fallback
provider: if Anthropic fails, the turn fails.

| Model | Does |
|---|---|
| `claude-sonnet-5-5` | The main model: it plans, writes, reviews and decides. It also does compression, the dangerous-command approval and the post-turn review. It runs a single grep, list or fetch itself. |
| `claude-haiku-5-5` | Subagents for read-only fan-out only (three or more tasks, or more than about 20 files), and three side tasks: session titles, skill matching and the `/goal` judge. |

Subagents: at most 2 at a time, 50 iterations each, one level deep.

## Run limits

| Setting | Value |
|---|---|
| `agent.max_turns` | 60 model calls in one run, with a hard stop on tool loops |
| `goals.max_turns` | 6 turns for one `/goal` (default 20); `/goal resume` gives 6 more |
| `cron.max_parallel_jobs` | 1 |
| `agent.agent_cache.max_size`, `code_execution.max_session_kernels` | 16, 1 |
| `gateway.max_inbound_media_bytes` | 20 MiB, and the same cap for Discord attachments |
| `sessions` | pruned after 45 days, then `state.db` is vacuumed |
| `updates.check`, `model_catalog.enabled`, `telemetry.shared_metrics.enabled`, `security.allow_lazy_installs` | off: Nix owns the updates and the dependencies, and nothing goes to Nous |

## A deploy and a restart

1. A merge to `main` runs `deploy.yml`. The runner builds the system, and deploy-rs switches the
   VPS to it ([Operations](Operations)).
2. Activation writes Hermes's `config.yaml`, `.env`, `SOUL.md`, `AGENTS.md` and plugin links
   again.
3. When any of these inputs changed, systemd reloads `hermes-agent` (`reloadTriggers`). The reload
   sends `SIGUSR1`: the gateway takes no new work, lets the turns, cron jobs and subagents in
   flight finish, and exits with code 75. `Restart=always` starts it again with the new
   configuration. A turn waits at most 600 s (`agent.restart_after_turn_timeout`). A new message
   waits until the gateway is back.
4. A new Hermes package changes the unit's `ExecStart`, and that restarts the unit at once.
5. The deploy then deletes all system generations but the last five. It does not collect garbage:
   Nix collects when free disk falls under 2 GiB (until 8 GiB are free), and `nix.gc` removes
   paths older than 14 days each week. The store is deduplicated once a week, not on each deploy.

To see that a deploy took effect, compare `systemctl show hermes-agent -p ActiveEnterTimestamp`
with the time of the deploy. Because of the drain, it can be up to 10 minutes later.

## Who it is, and what it can use

- `hermes/SOUL.md`: its identity and rules (from piabrota's dogma). `hermes/AGENTS.md`: a brief of
  the owner's projects, sources and jobs. Activation installs both on every deploy.
- Skills: five from the project's optional catalog, evidence-ledger-research, and 29 of the
  owner's skills ([`docs/HERMES-SKILLS.md`](https://github.com/piabrota/nix-os/blob/main/docs/HERMES-SKILLS.md)).
- MCP servers: DeepWiki and Context7, remote, with no key.
- Guardrail: the custom-dangerous-patterns plugin blocks the commands in
  [`hermes/dangerous-patterns.yaml`](https://github.com/piabrota/nix-os/blob/main/hermes/dangerous-patterns.yaml)
  (GitHub writes other than its own branches, secrets, `sudo`, installs). The list is in the
  store, so Hermes cannot change it.

## Change it

Change `hermes.nix` or `hermes/` in a pull request; the merge deploys it. On NixOS, `hermes setup`
and `hermes config set` refuse to change what the module manages. To check the unit on the box:

```console
systemctl status hermes-agent
journalctl -u hermes-agent -n 100
hermes status
```
