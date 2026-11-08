# Hermes Agent on piabrota

[Português](HERMES.ptBR.md)

[Hermes Agent](https://github.com/NousResearch/hermes-agent) is Nous Research's agent: a Python
program that talks over chat platforms (Telegram, Discord, Slack and others), uses tools and runs
scheduled jobs. This box runs it as the unit `hermes-agent` (`hermes.nix`): its messaging gateway,
which answers on the platforms it has tokens for.

The project publishes a flake with a package and a NixOS module (`nixosModules.default`). This
repository's `flake.nix` takes it as the input `hermes-agent`, and `hermes.nix` only picks the
options. For the project, Nix and NixOS are a Tier 2 platform: the flake and the module are kept
"best effort", and a commit to their `main` can break them. So `flake.nix` pins the input to a release
tag, and `flake.lock` holds the commit of that tag. The weekly flake update (`flake-update.yml`)
cannot move it off the release.

What exists for Hermes, and what this box takes from it: [`AWESOME-HERMES.md`](AWESOME-HERMES.md).

## What `hermes.nix` picks

| | |
|---|---|
| Mode | Native: a systemd service on the host, with the module's sandbox (`ProtectSystem=strict`, `NoNewPrivileges`, `PrivateTmp`). Not container mode, which would need Docker or Podman. |
| Host | piabrota2 (KVM 4), the second VPS, since the move from piabrota (KVM 1) in [MIGRATION-KVM4.md](MIGRATION-KVM4.md). `hermes.nix` sets what does not depend on the machine and leaves the rest at upstream's defaults: the `full` package, 10 subagents at a time, 128 cached agents, no limit on parallel cron jobs, 4 kernels, 128 MiB media. `hosts/piabrota2` caps the gateway at `MemoryMax=8G` and `CPUWeight=50`. |
| Package | The flake's default, `full`, about 700 MB more (voice, Bedrock, Modal and the like). It adds the extras `anthropic` (Anthropic's SDK), `messaging` (Telegram, Discord, Slack), `mcp` and `ddgs`. |
| Model | `claude-sonnet-5-5` through the `anthropic` provider, with `claude-haiku-5-5` for subagents and three cheap side tasks (see "Run settings"), on the owner's subscription: `CLAUDE_CODE_OAUTH_TOKEN` (from `claude setup-token`), as piabrota/agents does. No API key. |
| Secrets | `/var/lib/hermes-secrets/hermes.env`, written by hand on the box, readable by root only. Never in the repository or the store. |
| Limits | `MemoryMax=8G` (half of 16 GB) and `CPUWeight=50` (half the share of other units) on the gateway, so sshd and a deploy keep room. The dashboard's unit has `MemoryMax=2G` ("The web dashboard"). |
| State | `/var/lib/hermes` (`HERMES_HOME` is `/var/lib/hermes/.hermes`): the configuration, the memory, the sessions and the `.env`. |
| CLI | `hermes` on the PATH (`addToSystemPackages`), on the service's own state; `h0ffmann` runs it with `sudo -u hermes hermes ...` and is not in the `hermes` group (the dashboard's Chat tab needs a private group). |

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
| Skills export | The `no_agent` cron job `skills-export`, daily at 01:45 `America/Sao_Paulo`, runs `~/.hermes/scripts/export-skills.sh` (`hermes/scripts/export-skills.sh`). It copies the skills Hermes made, and the nix-os skills it loads, into a pull request on piabrota/skills. Cron gives it the unit's `PATH`, which has no `awk` and no `perl`, so the script adds `/run/current-system/sw/bin` and stops with `skills export failed: <tool> is not on the PATH` for a missing tool. The message goes to the Discord home channel. | `hermesHomeFiles."scripts/export-skills.sh"` | none |
| CLI | `hermes` on the PATH, on the service's own state; `h0ffmann` runs it with `sudo -u hermes hermes ...`. He is not in the `hermes` group: upstream refuses the gateway control socket when that group has another member, and the dashboard Chat tab cannot attach. | `addToSystemPackages` | none |
| MCP servers | DeepWiki and Context7, remote, no key; nothing runs on the box for them. | `mcpServers`; `settings.mcp.auto_reload_on_config_change = false` | none |
| Web dashboard | Upstream's `hermes dashboard`, the unit `hermes-backend`, on 127.0.0.1:9119 only; nginx serves it at `https://hermes.piabrota.art` with TLS and basic auth (`hermes-web.nix`, see "The web dashboard"). | none: `piabrota.hermesWeb` in `hermes-web.nix` | none: the basic-auth file is `/var/lib/hermes-web-secrets/htpasswd` |

With no allowed-users list for a platform, the gateway refuses everyone on it. With no secrets
file, it starts with no platform and runs only the scheduled jobs.

## Run settings

What `hermes.nix` sets beyond the model and the add-ons, for one vCPU, 1 GB and a subscription's
quota. The survey of each key at the pinned commit is in [`AWESOME-HERMES.md`](AWESOME-HERMES.md).

| Setting | Value | Why |
|---|---|---|
| `fallback_providers` (main and `delegation`) | empty | Claude models only. If Anthropic fails, the turn fails; it never goes to another provider. |
| `model.default` | `claude-sonnet-5-5` | Sonnet is the high-level model: it plans, writes, reviews and decides. |
| `delegation.model`, `auxiliary.title_generation`, `auxiliary.skills_hub`, `auxiliary.goal_judge` | `claude-haiku-5-5` | Haiku is the low-level model: subagents for read-only fan-out, and three cheap side tasks (titles, skill matching, the `/goal` judge). Hermes has no per-call router: Sonnet decides to delegate, and `hermes/SOUL.md` says when. A subagent starts with a fresh context on another model and Sonnet checks its answer, so Sonnet runs a single grep, list or fetch itself and delegates only three or more read-only tasks, or a read of more than about 20 files. Compression, the dangerous-command approval and the post-turn review stay on Sonnet. |
| `delegation` | at most 2 children, 50 iterations each, one level deep | Small fan-out, for one vCPU and the quota. |
| `agent.max_turns`, `tool_loop_guardrails.hard_stop_enabled` | 60, on | A bound on a run, and a hard stop on tool loops. |
| `goals.max_turns` | 6 (default 20) | `/goal` is Hermes's Ralph loop: it continues a task on its own until the judge says done. Each turn can use up to 60 model calls, so 6 turns keep one goal within the quota; `/goal resume` gives 6 more. |
| `compression.threshold` | 0.40 (default 0.50) | Hermes compresses the conversation when the prompt reaches this share of the context window. Sonnet has 1,000,000 tokens, so 0.40 is about 400,000 tokens. Hermes floors the ratio at 0.75 only for windows under 512K tokens, so a lower value holds here. Each compression rewrites the cached prompt prefix once; every later turn costs less because the context is smaller. Compression runs on Sonnet. Change the value in `hermes.nix`. A second net, session hygiene, fires at 85 % and is not configurable. Core does not reset idle sessions; the community plugin `hermes-session-reset-policy` does, and it is not installed. |
| `prompt_caching.cache_ttl` | `auto` | 1 h for chat (people pause), 5 min for cron and subagents. |
| `mcp.auto_reload_on_config_change` | off | A config change does not reload the MCP servers (which would drop the prompt cache); only a deploy changes the config. |
| `agent.agent_cache.max_size` | 16 | Fewer cached agents, to save RAM. |
| `code_execution.max_session_kernels` | 1 | One code kernel at a time. |
| `sessions` | prune after 45 days, then vacuum `state.db` | Disk. |
| `security.allow_lazy_installs` | off | Nix owns the dependencies: no `pip install` at run time. |
| `model_catalog.enabled`, `updates.check`, `telemetry.shared_metrics.enabled` | off | No model catalog fetched from Nous, no update checks (Nix owns updates), nothing sent to Nous. |

Hermes does not restart by itself when a deploy changes its files: activation rewrites
`config.yaml`, `.env`, `SOUL.md`, `AGENTS.md` and the plugin links, but the unit does not change.
So `hermes.nix` lists them as `reloadTriggers` of `hermes-agent` (the settings, the environment,
the MCP servers, the optional skills, the plugins and the two documents). When you add a new kind
of input to the module, add it there too, or a deploy will leave the old process running with the
old configuration.

A reload is a graceful restart. `ExecReload` sends `SIGUSR1`; the gateway takes no new work, lets
the turns, cron jobs and subagents in flight finish (at most `agent.restart_after_turn_timeout`,
600 s here), and exits with code 75. Then the new configuration starts. Before this, a deploy
stopped the unit with `SIGTERM` and cut the turn in flight, also when the merge was Hermes's own
PR. A new Hermes package changes the unit's `ExecStart`, and that still restarts it at once. While
it drains, a new message waits until the gateway is back.

The main process of the unit is `hermes/scripts/gateway-wrapper.sh`, not the gateway. It passes
`SIGUSR1` and `SIGTERM` on to the gateway. The gateway runs with `--external-supervisor`. This
tells it that systemd owns it, so a reload exits with code 75 and does not start a detached
gateway.

On code 75 the wrapper starts the gateway again itself, at once, with no pause. The unit stays
active, and `RestartSec` is not part of a reload. Before, systemd waited 5 s (`Restart=always`).
In that gap the Chat tab of the dashboard (`hermes-backend`) found no gateway and started a second
one. That gateway is outside `hermes-agent`. The new gateway of the unit then said "already serves"
and exited at once, and systemd restarted it every 6 s (2026-11-05). A gateway that exits 75 more
than 5 times in 60 s makes the wrapper exit 1, and systemd restarts the unit and counts it.

When another gateway serves the host, the new gateway exits at once with code 75 (older versions
may use 0). A reload also exits 75, so the wrapper uses the run time to tell them apart. A reload
comes after a long run, because the gateway drains its work first. A foreign gateway makes the new
one exit within 20 s. If that happens and `gateway.pid` names another live process, the wrapper
does not exit and does not count a reload. It logs `another gateway (pid N) serves this host (the
gateway exited S): waiting for it to exit` and checks every 5 s. When that process ends, the
wrapper starts its own gateway. `SIGTERM` ends the wait at once. The test is
`hermes/scripts/gateway-wrapper.test.sh`.

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
| `mcp`, `ddgs` | extras | The MCP client (without it the servers below do nothing) and DuckDuckGo search, with no key. Since v0.23.0 `ddgs` is a web search provider, not a skill: Hermes picks it when no other web key is set. |
| DeepWiki, Context7 | remote MCP servers, no key | Questions about public repositories (piabrota, marola-dev, nixpkgs) and current library docs. Nothing runs on the box for them. |
| `watchers`, `rss-feeds` | optional skills | Poll RSS, JSON APIs and GitHub with dedup on Hermes's cron: bathing-water bulletins, Defesa Civil and INMET alerts, ocean news |
| `research-paper-writing` | optional skill | Papers, with the bundled `arxiv` and `grounded-citations` |
| `ast-grep` | optional skill, plus `pkgs.ast-grep` | Structural code search |
| `gh` | package | For the bundled `github` skill. Put a fine-grained token with read access only in the env file as `GITHUB_TOKEN`: it reads, and it cannot push or merge. |

The optional skills are one read-only directory in `skills.external_dirs`, taken from the
project's `optional-skills/` at the pinned commit. The bundled skills (`arxiv`, `github`,
`obsidian`, `weekly-review-planning` and the rest) come with the package. Left out, because they
need Node, Go or Homebrew on the box: `pr-lens`, `qmd`, `llm-wiki`, `blogwatcher`, `archify`. Left
out for the box's size: voice, the `mlops` skills, a local browser and `computer-use`.

The owner's own skills ([h0ffmann/skills](https://github.com/h0ffmann/skills)) are a second
read-only directory in `skills.external_dirs`, pinned by commit. Each one is a command in chat:
see [`HERMES-SKILLS.md`](HERMES-SKILLS.md) for the list, what is left out and why, and why it is
not a git submodule.

## Community add-ons

Picked from [awesome-hermes-agent](https://github.com/0xNyk/awesome-hermes-agent) and from Nous's
plugin catalog (`plugin-catalog/` at the pinned hermes-agent commit) on 2026-11-03, each read before pinning (license, last commit, every entry point, and what it runs, reads and
sends), and pinned by commit in `hermes.nix`:

| Add-on | Kind | What for |
|---|---|---|
| [custom-dangerous-patterns](https://github.com/scross01/hermes-custom-dangerous-patterns-plugin) v0.5.2 (MIT) | plugin | Blocks terminal commands that match `hermes/dangerous-patterns.yaml`: writes to GitHub (`git push`, `gh pr merge`, `gh api -X POST` and the rest), reads of secrets, `sudo` and rebuilds, and installs or `curl \| sh`. The list lives in the store, so the agent cannot edit it. |
| [evidence-ledger-research](https://github.com/markoblogo/abvx-agent-skills) (MIT) | skill | Source, date, unit and table-cell discipline when it extracts numbers from bulletins, PDFs and papers. |
| [tripwire](https://github.com/percyhendrux123-prog/hermes-tripwire) v0.1.1 (MIT) | plugin | Writes one JSON line for each refused action (a tool blocked by the deny list or another hook, or an approval that was denied, cancelled or timed out) to `/var/lib/hermes/.hermes/tripwire/events.jsonl`. It keeps no tool arguments, results or message text, and makes no network calls. A file `~/.hermes/tripwire/TEST_BLOCK` that holds `default <tool>` blocks that one tool, to test an alert; delete the file to stop it. |
| [inbox](https://github.com/NousResearch/hermes-labs-plugins/tree/main/inbox) (MIT, Nous Research Labs) | plugin | `hermes inbox` (and `--json`): a read-only list of failed or paused cron jobs, stalled subagents, orphaned processes, work that is running and the next cron runs. A CLI command only: no tools and no hooks in chat. |
| [telegram-business](https://github.com/NousResearch/hermes-labs-plugins/tree/main/telegram-business) (MIT, Nous Research Labs) | plugin | Drafts replies to the customers of a Telegram Business account and sends a reply only when the owner taps Send; `/biz` on Telegram. It does nothing until a Business account (Telegram Premium) connects the bot. Drafts go to Sonnet. |
| [workflow-record](https://github.com/NousResearch/hermes-labs-plugins/tree/main/workflow-record) (MIT, Nous Research Labs) | plugin | `hermes record` records a browser workflow over CDP, and its skill lets `/learn` turn it into a skill. It does nothing here: the box runs no browser. |
| [github-copilot](https://github.com/NousResearch/hermes-labs-plugins/tree/main/github-copilot) (MIT, Nous Research Labs) | plugin | GitHub Copilot as a model provider. It does nothing here: the model and the fallbacks name Anthropic only, and it calls GitHub only for a profile that chose Copilot. |
| [error-ledger, aux-ledger, approval-ledger, stop-ledger](https://github.com/olric3015/hermes-plugins) (MIT) | plugins | Local ledgers, read in chat: `/errors` (failed Anthropic calls by cause), `/aux` (tokens of the Haiku side tasks), `/approval-log` (how often each deny-list rule asked, and the answers), `/stop-log` (turns stopped with `/stop` or `/new`). Metadata only, no prompt text, no network; each file is trimmed past 2 MB. |
| [progress-squash](https://github.com/pierrenode/hermes-progress-squash) (MIT) | plugin | Collapses the redraws of a progress bar in terminal output to one line before the model reads it. No network, no files. |
| [public-holidays](https://github.com/Akloenx123/hermes-public-holidays) (MIT) | plugin | Holidays and workday maths (Brazil and its states included), computed in code, for cron digests and deadlines. GET to `date.nager.at` with a country code and a year, no key. |
| [gh-ref, wiki-ref](https://github.com/EloquentBrush0x/hermes-context-refs) (MIT) | plugins | `@gh:owner/repo#N` attaches a public issue or pull request (anonymous GET to `api.github.com`); `@wiki:<title>` attaches a Wikipedia section. No token, no files. |
| [memory-rewind](https://github.com/AhmetArif0/hermes-memory-rewind) v1.3.2 (MIT) | plugin | A version history of `memories/MEMORY.md`, `memories/USER.md`, `SOUL.md` and `skills/`, in a bare git repository in `plugin-data/memory-rewind/`, written by a background thread after each change. `/memory-history` in chat (read-only); `sudo -u hermes hermes memory-rewind restore <version> memory` on the box puts a file back and prints the command that undoes it. Local `git` only, no network; it never reads `.env`, `auth.json` or the databases. Its disk use grows with each change; not measured on piabrota2 yet. `SOUL.md` comes from the store on every activation, so a restore of it lasts until the next deploy. |
| [hermes-guide](https://github.com/iap/hermes-guide) v0.8.12 (MIT) | plugin | `/hermes-doctor` in chat and `hermes guide` on the box: ten read-only checks (config, MCP, skills, commands, hooks, plugins, memories, sessions, storage, update). Its report quotes short snippets of memory and the session ids and token counts of runaway sessions. Each run makes one `git ls-remote` of its own repository for a release notice (none with `--fast`); `proactive` (the checks at every session start and end) stays off. Its 22 troubleshooting skills are a separate tap and are not installed. |
| [hermes-plugin-guard](https://github.com/mauricemohr88-debug/hermes-plugin-guard) v0.2.1 (MIT) | plugin | `hermes plugin-guard scan <directory> --fail-on high`: a static scan of a candidate plugin (manifest, Python, dependencies, secrets) that never imports or runs it. One read-only tool, `plugin_guard_review_candidate`, for a plugin installed but not enabled; here every plugin comes from Nix and is enabled, so the CLI is the path. No network. Only `src/` is installed, without the scanner's unsafe test fixtures. The gate for every plugin proposed after it (`hermes/AGENTS.md`, "Plugins"). |
| [kvm4-health](../hermes/skills/kvm4-health/SKILL.md) (this repository) | skill | `kvm4-health`: memory, swap, pressure, load, disk and the journal, and for `hermes-agent`, `hermes-backend`, `pgx`, `paperclip`, `postgresql` and the `hermes` user's slice (where cron jobs run) the memory now and `MemoryPeak` against `MemoryMax`, tasks and restarts; growth of `/` a day and of `hermes-agent` with no restart, from a sample every 30 minutes. `WARN` and `CRIT` thresholds are `KH_*` variables. The watchdog is a `no_agent` cron job on `~/.hermes/scripts/kvm4-health-alert.sh`: no model call, and a message only when the findings change (again every 6 hours, and once on recovery). Hermes creates the job once, from the skill. Read-only on the system; it writes only `plugin-data/kvm4-health/`. `just remote-health` runs it from your computer. |
| [rbi](../hermes/skills/rbi/SKILL.md) (this repository) | skill | `/rbi <prompt>`, "refine before implementing". It fixes spelling and grammar, puts one idea on each line, labels goal, constraints, deliverable and a `Done when` check, and reads what the prompt names before it asks. When something that changes the result is open, it says the request back, asks one question at a time, lays out two or three approaches with a pick and asks for a yes to a short design before it builds a project. Then it plans the steps for run time (what runs in parallel; who does each step: you, subagents, omp or the owner) and does the work. Flags in the prompt: `--dry` stops after the plan, `--go` opts out of the questions, `--pt` turns on ponytail, which is off otherwise: the omp task gets lean-code rules, then a read-only omp review with the `ponytail-review` skill, and a fix run only for confirmed Must fix findings. The talking steps follow the `brainstorming` skill of [obra/superpowers](https://github.com/obra/superpowers) (MIT), which is also installed as a plugin (next row): `/rbi` is the explicit way, and the plugin is the automatic way. No network, no script, no new permission. A merge restarts `hermes-agent`, because the skills directory is part of its settings. |
| [superpowers](https://github.com/obra/superpowers) v7.0.2 (MIT) | plugin | A community plugin (not in Nous's catalog), read at v7.0.2 and pinned by commit. It adds 15 skills: `brainstorming`, `writing-plans`, `subagent-driven-development`, `systematic-debugging`, `test-driven-development` and others. Its `pre_llm_call` hook adds a bootstrap text (about 5 KB) to the first turn of each session that is not a subagent, cron sessions included. The text tells the model to look for a matching skill before it acts. Its `brainstorming` skill asks one question at a time and wants an approved design before any build. The plugin code has no network call. The visual companion of `brainstorming` needs node, which this box does not have, so it stays inert. The scan with `hermes plugin-guard` gave one low finding (no SECURITY.md). |
| [hermes-cron](https://github.com/itpartypattaya/hermes-cron) v1.5.2 (MIT) | skill | Rules for cron jobs: pause, disable or remove; and `no_agent`, the `wakeAgent` pre-check and `[SILENT]`, so that a quiet tick makes no model call. Its read-only doctor script needs `python3`, which is not on Hermes's `PATH` here; the rules work without it. |

### Two ways to send a fuzzy prompt

A prompt with typing errors, ideas stuck together or a missing reason can go two ways. Both are on.

| | `/rbi <prompt>` | superpowers (automatic) |
|---|---|---|
| How it starts | You type the command. | The bootstrap text loads on the first turn of each session. The model decides by itself to use a skill. |
| What it does | Fixes spelling and grammar, puts one idea on each line, plans the steps for run time and says who does each step: Hermes, subagents, omp or you. | `brainstorming` asks one question at a time and writes a design. `writing-plans` writes the steps. Other skills cover tests, debugging and review. |
| Questions | One message, at most once for a task. A small change goes straight on. | One question at a time, and a project waits for an approved design. |
| Flags | `--dry` stops after the plan. `--go` skips the questions. `--pt` turns on ponytail. | None. Say in words that you want no questions. |
| Cost | No hook, no extra text. | About 5 KB on the first turn of a session. The model cache keeps it after that. |

Use `/rbi` when you want the prompt cleaned and the work planned for run time. Let superpowers act
when you describe an idea and want a design talk. If the two disagree on a prompt that starts with
`/rbi`, Hermes follows `/rbi` and the owner's rules (SOUL.md and the deny list). The plugin cannot
widen a permission. To remove it, delete its block and its two list entries in `hermes.nix`. `/rbi` stays, because it
needs no plugin.

Limits from the list's operational playbooks: `agent.max_turns = 60`; subagents at most 2 at a
time, 50 iterations each, one level deep; `tool_loop_guardrails.hard_stop_enabled`; no update
checks (Nix owns updates) and no shared metrics.

From the plan in [#88](https://github.com/piabrota/nix-os/issues/88) (wave 1), postponed, with
the reason: bubblewrap (official, 1.3.0) hides `~/.config/gh` from every sandboxed command, where
`hermes-github.nix` writes gh's token, so `gh` stops working; its default limit of 256 MB of
address space per command also stops omp and other large programs. It needs `GH_TOKEN` passed
another way and a drill on piabrota2 first. cronwatch and cron-status-alert are not needed: since
0.22.4 Hermes sends one failure notice per incident of a cron job to the job's target
(`failure_deliver`, `cron.failure_repeat_alert_hours`), and the two plugins alert on Feishu and
Discord only. The backup of `$HERMES_HOME` needs an `age` public key from the owner; it is a
separate PR, with `hermes backup` and a systemd timer instead of a shell plugin.

Left out, with the reason: cronalytics (needs a writable plugin directory), rtk-hermes (its hook
order with the deny list is untested), agentburn (its skill runs `uvx`, an unpinned download),
hermes-lcm and the memory providers (too heavy for 1 GB, or a server or a cloud), and every item
that needs Node, a paid API or a web dashboard, or has no licence. Nothing on the list covers
Brazilian alerts, bathing water or ocean science: those are piabrota's own skills to write.

## omp, the coding worker

[oh-my-pi](https://github.com/can1357/oh-my-pi) (omp, MIT, Stencil Labs, a fork of Mario Zechner's
Pi) is a terminal coding agent on Bun with Rust natives. Hermes hands it every task that writes or
reviews code through the `hermes-omp` skill (`hermes/skills/hermes-omp/SKILL.md`, the third
`skills.external_dirs` entry): Hermes makes a `hermes/*` branch, writes the task to a file in
`/var/lib/hermes/workspace/omp-tasks/`, runs `omp -p --max-time 15m` in the working tree, reads
the diff, and then commits, pushes and opens the pull request itself. omp never pushes. How to see
and tune each layer: [HERMES-OMP.md](HERMES-OMP.md).

- **Version.** `omp/package.nix` takes the release binary of the tag `v18.16.0` (`omp-linux-x64`,
  pinned by its hash), not the flake: from source, omp is a Rust (fat LTO) and bun2nix build with
  its own nixpkgs, which no binary cache has, and it took about 20 minutes on the runner. The
  binary needs only glibc; autoPatchelf sets its interpreter. The weekly flake update does not
  move it, so a new release is a PR that changes `version` and `hash`. The VPS builds nothing.
- **The wrapper.** `omp` on Hermes's PATH is a wrapper (`ompWrapped` in `hermes.nix`). It points
  omp at `hermes/omp.yml` as a config overlay, which is read-only in the store and outranks omp's
  own `config.yml` and a cloned repository's `.omp/`. It passes `CLAUDE_CODE_OAUTH_TOKEN` as
  `ANTHROPIC_OAUTH_TOKEN`, the same subscription and the same limits as Hermes, and turns off
  OpenTelemetry, titles and the eval kernels.
- **Its own deny list.** Hermes's deny list and tripwire see only the outer `omp` command. So
  `hermes/omp.yml` gives omp's bash tool the rules that matter: no `git push`, no `gh`, no
  installs, no `sudo`, no `curl` or `wget`, no reads of the secrets or the environment. The
  folders of Hermes's state, the secrets, `~/.ssh` and `gh`'s config are restricted, which in print
  mode means refused.
- **Memory.** omp runs in Hermes's cgroup (`MemoryMax=8G`). LSP, the Python and JS kernels, the
  memory backend, the advisor and the browser are off. The wrapper starts omp with
  `choom -n 500`, so the kernel's OOM killer stops omp before the gateway.
- **Models.** Sonnet (`claude-sonnet-5-5`) for the work and for the subagents (`task`), Haiku
  (`claude-haiku-4-5`) for the side roles (`smol`, `commit`, `tiny`, `memory`, `advisor`,
  `judge`). The thinking level is pinned to `high`. There is no fallback, so no role reaches
  another provider or a local model.
- **Prompt.** The wrapper appends `hermes/omp-append-system.md` to omp's system prompt: small
  diffs, a stated check, no claim of done without output, no commit or push. omp reads the file
  at that path, and a path on the command line turns off its search for `APPEND_SYSTEM.md`, so a
  cloned repository cannot replace these rules (`main.ts` and `system-prompt.ts` at v18.16.0).

Not checked before the merge: omp's memory peak on the box, and that a `claude setup-token` token
works as `ANTHROPIC_OAUTH_TOKEN`. After the deploy, run one task and read
`systemctl show hermes-agent -p MemoryPeak`.

## The owner's plugins

`pirsig-notes` and `pirsig-videos`, in `hermes/plugins/`, send smart notes and video readings to
piabrota/pirsig as pull requests on `hermes/*` branches. They need yt-dlp (`yt-dlp-light`) and the
GitHub App below. See [HERMES-PLUGINS.md](HERMES-PLUGINS.md).

## One-time setup on the box

Without the secrets file, activation only warns (`cannot read environmentFile`) and the gateway
starts with no platform, running only the scheduled jobs. A deploy never fails because of it.

1. Make the subscription token on your computer: `claude setup-token`.
2. Make a bot on the platform you want. On Telegram: talk to
   [@BotFather](https://t.me/BotFather), `/newbot`, and keep the token. Your numeric ID comes from
   [@userinfobot](https://t.me/userinfobot).
3. On the box, write the file (paste the lines and end with Ctrl-D):

   ```console
   ssh h0ffmann@hermes.piabrota.art
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
`hermes-github.nix` keeps the App's key root-only and gives Hermes one-hour tokens. The unit
`hermes-github-token` mints them every 45 minutes for piabrota, marola-dev and h0ffmann, with the
rights of contents, pull requests and issues (not workflows). `git` gets the token through a
credential helper that picks the account by the repository's owner, and `gh` gets it too. Hermes
pushes only `hermes/*` branches: `hermes/dangerous-patterns.yaml` blocks merges and every other
push, and a ruleset on each default branch blocks a push to it at GitHub. Without the key file the
unit does nothing.

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

`just remote-hermes-check` (from your machine, as `h0ffmann`; `scripts/hermes-check.sh`) checks
the add-ons of the last deploy in one run, read-only: the unit and when it started, each plugin
linked and enabled, the `hermes-omp` skill, `omp --version` and `yt-dlp --version`, and plugin
errors in the journal. It prints `FAIL` for each missing part and never reads the secrets.
`just remote-health` prints the health of a box (`hermes/skills/kvm4-health`): memory, disk, CPU, and
each Hermes unit against its `MemoryMax`. It asks KVM 1 (`piabrota.art`, or `DEPLOY_HOST`). For
another box, give the host as the second argument: `just remote-health h0ffmann <address>`. A unit
that the box does not run is not a finding. The journal warns only above its own 200 MiB cap
(`KH_JOURNAL_MIB=220`). Exit 1 means a `WARN` or `CRIT` line; the recipe then says so.

The log says which platforms connected; "No messaging platforms enabled" means the `.env` has no
platform token. Two warnings are expected: the Discord adapter's "Opus codec not found" (voice is
left out), and the deny-list plugin saying it cannot write its integrity hash next to a file in
the store (the list is read-only on purpose). To check that a deploy took effect, compare
`systemctl show hermes-agent -p ActiveEnterTimestamp` with the time of the deploy: the unit
restarts when its inputs change, after the work in flight ends (see "Run settings"), so the time
can be up to 10 minutes after the deploy.

## The web dashboard

Hermes has its own browser admin panel, `hermes dashboard`: sessions, cron jobs, skills, MCP
servers, the config, logs and a Chat tab that runs Hermes's TUI in a terminal in the browser. Its
web app is part of the Hermes package that `hermes.nix` installs, so it adds no download.
`hermes-web.nix` turns it on with the upstream module's `backend.mode = "dashboard"`:

- **The unit `hermes-backend`**, a second process beside the gateway, with the same user, package
  and `HERMES_HOME`. It binds to `127.0.0.1:9119`; the firewall never opens that port.
  `MemoryMax=2G`, since the Chat tab runs an agent in this unit.
- **nginx is the gate**, on `hermes.piabrota.art`: Let's Encrypt (HTTP answers with a redirect),
  HTTP basic auth against a bcrypt file on the box, at most 10 requests a second per address
  (burst 60). Upstream's own login stays off: a loopback bind does not start it, and upstream says
  its username/password provider is for a trusted network only.
- **What nginx changes on the way.** The backend refuses a `Host` or a WebSocket `Origin` that is
  not its loopback address (its DNS-rebinding guard), so nginx sends `Host: 127.0.0.1:9119` and no
  `Origin`, `X-Forwarded-For` or `Authorization`. Before that, nginx refuses (403) any request
  whose `Origin` is not `https://hermes.piabrota.art`, so another site cannot use the browser's
  basic-auth login to write.
- **No secret reaches the browser.** `POST /api/env/reveal` (shows a value of `.env`) is refused,
  and so is every write to `/api/env`: activation writes `.env` from the secrets file on each
  deploy, so an edit there is lost anyway. `GET /api/audio/voice-config` is refused too: it hands
  a cloud STT or TTS key to the browser when a voice provider is set. The page still lists the
  names of the variables, with their values redacted.
- **Nix owns the config.** A change made in the Config page lasts only until the next deploy
  writes `config.yaml` again. Change `hermes.nix` in a PR instead.
- **The Documentation tab shows piabrota's page**, `hermes-web/docs/index.html`, not Nous
  Research's docs. Upstream frames `https://hermes-agent.nousresearch.com/docs/`, a literal in the
  built JS bundle. nginx replaces it with `/piabrota-docs/` on the way (`sub_filter`) and serves
  that directory from the store, behind the same basic auth; that location alone sends `X-Frame-Options: SAMEORIGIN`
  so the tab can frame it, and the rest of the dashboard keeps `DENY`. `checks.hermes-docs-url` fails when a Hermes bump renames the address. The page has the look of www.piabrota.art: one file with its CSS inside, which loads the site's fonts from Google Fonts. To
  show another page, edit the file or set `piabrota.hermesWeb.docs` to another directory with an
  `index.html`. The bundle's assets are cached as immutable: after the first deploy, reload the
  dashboard once with the cache off (Ctrl+Shift+R).
- **The dashboard wears piabrota's look.** `hermes/dashboard-themes/piabrota.yaml` is the dashboard
  theme, and `hermes/skins/piabrota.yaml` is the skin of the TUI. The Chat tab embeds the TUI, and
  the TUI takes its colours from the skin, not from the theme. Both files use the dark tokens of
  `site/DESIGN.md`. `hermes.nix` installs them with `hermesHomeFiles` and sets `dashboard.theme` and
  `display.skin` to `piabrota`. The theme loads Fjalla One, Inter and JetBrains Mono from Google
  Fonts (`fontUrl`). A theme picked in the dashboard lasts only until the next deploy writes
  `config.yaml`.
- **The Chat tab needs a private `hermes` group.** Upstream refuses the gateway control socket when
  the group of the group-writable home has a member besides the owner. If the Chat tab shows
  "retrying", run `sudo -u hermes hermes gateway status` and check that nobody else is in the
  group: `getent group hermes` must list no member.

### Turning it on

Do the two steps below before the PR that turns it on is merged. Without the DNS record the ACME
order fails on the deploy, and deploy-rs rolls the box back.

1. **DNS.** An `A` record `hermes.piabrota.art` with KVM 4's IPv4 address (an `AAAA`
   record only if KVM 4 has IPv6). Check it:
   `dig +short hermes.piabrota.art`.
2. **The password file.** On the box, make one bcrypt line with a long random password. Keep the
   password in your password manager; it is not stored anywhere else:

   ```console
   ssh h0ffmann@hermes.piabrota.art
   sudo install -d -m 750 -o root -g nginx /var/lib/hermes-web-secrets
   pw=$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 40)
   [ ${#pw} -eq 40 ] && echo "$pw" && \
   nix shell nixpkgs#apacheHttpd -c htpasswd -nbB -C 12 owner "$pw" \
     | sudo install -m 640 -o root -g nginx /dev/stdin /var/lib/hermes-web-secrets/htpasswd
   curl -s -o /dev/null -w '%{http_code}\n' -u "owner:$pw" https://hermes.piabrota.art/   # 200
   curl -s -o /dev/null -w '%{http_code}\n' -u 'owner:' https://hermes.piabrota.art/      # 401
   unset pw
   ```

   Copy the password that `echo` prints to your password manager. It has only letters and
   digits, so no character changes when you copy it. The box has no `openssl`: do not use
   `openssl rand`. If `pw` is empty, `htpasswd` writes a file that accepts an empty password.
   The length check stops that, and the last `curl` must print 401. If it prints 200, delete
   the file at once.

   The deploy makes the directory too. Without the file nginx answers every request with a 500,
   so the dashboard stays closed until the file exists. A change to the file needs no deploy.

Then open `https://hermes.piabrota.art` and log in as `owner`.

### Checking and turning it off

- `systemctl status hermes-backend` and `journalctl -u hermes-backend` on the box.
- `curl -s -o /dev/null -w '%{http_code}\n' https://hermes.piabrota.art/` gives `401` without
  the password.
- **Turn off:** `piabrota.hermesWeb.enable = false` in `hosts/piabrota2/default.nix`, in a PR.
- **Move to another host:** set the option on the host that runs Hermes and point the DNS record
  at that host first.

## Paperclip

[Paperclip](https://github.com/paperclipai/paperclip) (`paperclip.nix`) is off for now (since 2026-11-04). When on, it runs on the same box at
`paperclip.piabrota.art`, and this Hermes is its agent. Its `hermes_gateway`
adapter sends each task to Hermes's API server on `127.0.0.1:8642`, so the task runs here, with the
same subscription, deny list and skills. Hermes answers through Paperclip's `paperclip` skill.
The API server starts only when `hermes.env` has `API_SERVER_KEY`; Hermes's key for Paperclip is
`PAPERCLIP_API_KEY` in the same file. The setup is [PAPERCLIP.md](PAPERCLIP.md).

## The /hermes page

[www.piabrota.art/hermes](https://www.piabrota.art/hermes) shows this configuration in plain YAML,
not in Nix: the settings that `hermes.nix` writes to `config.yaml`, and how the unit runs (the
package, the extras, the limits, the plugins, the files and the pinned upstream commit). The site
build reads them from the evaluated system (`site/hermes.nix`), so the page changes with every
merge that changes `hermes.nix`. It is the configuration that the last deploy of `main` sets, not a
live check of the unit: for that, see "Checking it".

No secret reaches the page. The site never reads the env files and does not name them; a key that
names a token, a key, a secret, a password or allowed users is dropped; and the build stops if a
secret's name gets through. Store paths keep their name and lose their hash.

## Updating and turning it off

- **Update:** the pin is a release tag. A new release is one PR with three changes: the tag in
  `flake.nix` (`hermes-agent.url`), `nix flake update hermes-agent`, and `hermesVersion` in
  `hermes.nix` (and the badge in `README.md`). The weekly `flake-update.yml` PR does not move this
  input. CI builds the PR with the closure difference (`dix`); the merge deploys it.
- **Turn off:** take `../../hermes.nix` out of the host's `imports` (`hosts/<name>/default.nix`) in a PR. The deploy stops
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
