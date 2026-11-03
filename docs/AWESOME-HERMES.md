# Awesome Hermes, for piabrota

[Português](AWESOME-HERMES.ptBR.md)

A curated list of what exists for [Hermes Agent](https://github.com/NousResearch/hermes-agent) and
what this box does with it. It is not a copy of the bigger lists: each entry was judged against one
small, live machine and its owner's goals, and says why it is in, to try, or out. How Hermes runs
here is in [`HERMES.md`](HERMES.md).

**The yardstick.** A Hostinger KVM 1 (1 vCPU, 4 GB of RAM, Hermes capped at 1 GB), NixOS with
everything declared in `hermes.nix`, Claude Sonnet through the owner's subscription and no other
provider, Telegram as the only chat, a read-only GitHub token. Out: anything that needs Node, Go,
Docker or a browser on the box, a paid API, a web dashboard, or that phones home; anything without
an OSI licence. The goals it serves: [marola](https://marola.dev) (bathing water and beach safety
in Brazil), [piabrota/alerts](https://github.com/piabrota/alerts) (alerts from official agencies),
ocean and wave-model research, piabrota's FOSS repositories, and keeping the subscription's usage
low.

**Legend.** ✅ in use here · 🧪 worth a test · ⛔ left out, with the reason.

**How it was checked.** Read on 2026-11-02 and 2026-11-03 against Hermes at the commit
`flake.lock` pins (`d9f15af`, v0.22.x): every setting below exists in its
`hermes_cli/config_defaults.py`. Third-party code was read, never run. Stars and dates are from that
day; they move.

## Contents

- [Official](#official)
- [Built in, in use here](#built-in-in-use-here)
- [Settings](#settings)
- [Community add-ons](#community-add-ons)
- [Guides and posts](#guides-and-posts)
- [Other lists](#other-lists)
- [Gaps: what piabrota has to write](#gaps-what-piabrota-has-to-write)

## Official

- ✅ [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent): the agent, its
  flake and its NixOS module (`nixosModules.default`), the input `hermes-agent` here. Nix is a
  Tier 2 platform there: best effort.
- ✅ [Nix & NixOS setup](https://hermes-agent.nousresearch.com/docs/getting-started/nix-setup):
  the module's options; how `hermes.nix` was written.
- ✅ The guides shipped in the repository (`website/docs/guides/`): `automate-with-cron.md`,
  `cron-script-only.md`, `tips.md`; and `user-guide/features/heartbeat.md`. More current than any
  blog post.
- [Releases](https://github.com/NousResearch/hermes-agent/releases): the change record (v0.22.1 to
  v0.22.6 from 2026-10-14 to 2026-11-02). There was no 2026 post on Nous Research's blog.

## Built in, in use here

- ✅ **Gateway on Telegram**, polling, one allowed user.
- ✅ **Cron scheduler**, results to the Telegram home channel.
- ✅ **Built-in memory** (`MEMORY.md`, `USER.md`), no external provider.
- ✅ **Bundled skills**: `github`, `arxiv`, `grounded-citations`, `obsidian`,
  `weekly-review-planning`, `document-to-action-items`, `codebase-inspection` and the rest.
- ✅ **Optional skills** (`optional-skills/` at the pin, copied into the store): `watchers`,
  `rss-feeds`, `duckduckgo-search`, `research-paper-writing`, `ast-grep`.
- ✅ **MCP servers** from the approved catalog (`optional-mcps/`), remote, no key:
  [DeepWiki](https://mcp.deepwiki.com) and [Context7](https://context7.com).
- ✅ **Identity and brief**: `hermes/SOUL.md` (rules from piabrota's dogma) and `hermes/AGENTS.md`.
- 🧪 **A2A** (`plugins/platforms/a2a`, protocol v1.0, standard library only): Hermes as a peer of a
  coding agent. Without a token it binds 127.0.0.1 only; reach it through an SSH tunnel, never an
  open port. Needs a decision on where the coding agent runs.
- 🧪 **`/usage`** reads the subscription's 5-hour and weekly windows, and `hermes insights --days 7`
  shows usage over time: the cost dashboard, without a third-party one.
- ⛔ **Mixture of agents**: needs other providers. **Kanban** and **profiles**: one person, one
  profile. **Checkpoints**: for coding on the box, which this box does not do. **OTLP monitoring**:
  needs a collector. **Voice, image and video generation**: heavy, and paid APIs.

## Settings

Each is in `hermes.nix`, with the reason next to it.

| Setting | Here | Default | Why |
|---|---|---|---|
| `model.provider`, `model.default` | `anthropic`, `claude-sonnet-5-5` | | Sonnet through the subscription |
| `fallback_providers`, `delegation.fallback_providers` | `[ ]` | | Sonnet only: no other model, ever |
| `delegation.max_concurrent_children`, `max_iterations`, `max_spawn_depth` | 2, 50, 1 | 10, 250, 1 | Small fan-out for one vCPU and the quota |
| `agent.max_turns` | 60 | unlimited | A run cannot loop forever |
| `tool_loop_guardrails.hard_stop_enabled` | true | false | Stops a tool loop in chat too |
| `prompt_caching.cache_ttl` | `auto` | `5m` | 1 h cache for chat, 5 min for cron: Hermes measures about 42 % less cache-write cost when a chat resumes after a pause |
| `mcp.auto_reload_on_config_change` | false | true | A reload drops the prompt cache; here only a deploy changes the config |
| `agent.agent_cache.max_size` | 16 | 128 | Each cached agent holds a transcript in RAM |
| `cron.max_parallel_jobs` | 1 | unbounded | Two digests at once can hit the 1 GB cap |
| `code_execution.max_session_kernels` | 1 | 4 | RAM |
| `gateway.max_inbound_media_bytes` | 20 MiB | 128 MiB | Media is read whole into RAM |
| `sessions.auto_prune`, `retention_days` | true, 45 | false, 90 | Gateway sessions never reset; `state.db` would only grow |
| `security.allow_lazy_installs` | false | true | No pip install at run time: Nix owns the dependencies |
| `model_catalog.enabled` | false | true | No fetch from Nous every 20 minutes |
| `HERMES_TELEGRAM_DISABLE_FALLBACK_IPS` | true | unset | No DNS-over-HTTPS lookups of Telegram through Google and Cloudflare |
| `telegram.reactions` | true | false | 👀 and ✅ instead of "still working" messages, with no tokens |
| `cron.wrap_response` | false | true | Cron results without the header and footer |
| `updates.check`, `telemetry.shared_metrics.enabled` | false, false | true, false | Nix owns updates; nothing is sent to Nous |
| `timezone` | `America/Sao_Paulo` | server time | Jobs at the owner's hour |

🧪 To test before adopting:

- **`platform_toolsets.telegram`**: the default bundle offers browser, image, TTS and vision tools
  the box cannot use, and their schemas cost tokens on every call. Trim it to what is used; check
  the names with `hermes tools` first.
- **Per-job cron options** (`automate-with-cron.md`): `enabled_toolsets` per job, a low reasoning
  effort for cheap jobs, `--continuity` so a watcher does not repeat itself, and a script that
  prints `{"wakeAgent": false}` (or `no_agent`) so a quiet tick makes no model call at all.
- **`memory.nudge_interval`, `skills.creation_nudge_interval`** from 10 to 20 or 30: the review
  after a turn replays the conversation, on the quota.
- **`compression.proactive_prune_tokens`** around 48 000: trims old tool output with no model
  call, but breaks the cache once each time; measure first.
- **`compression.idle_compact_after_seconds`** around 3 600, and
  **`gateway.message_timestamps.enabled`** for digests.
- **`memory.write_approval`, `skills.write_approval`**: stage what Hermes writes to its memory and
  skills for `/memory pending` and `/skills pending`. A trust decision for the owner.
- ⛔ **`compression.micro_compact`**: breaks the prompt cache on every turn. ⛔ **`curator.consolidate`**:
  model calls; the default deterministic prune is enough.

## Community add-ons

From [awesome-hermes-agent](https://github.com/0xNyk/awesome-hermes-agent) and a GitHub search.

- ✅ [scross01/hermes-custom-dangerous-patterns-plugin](https://github.com/scross01/hermes-custom-dangerous-patterns-plugin)
  (MIT, v0.5.2): a `pre_tool_call` hook that blocks terminal commands by regex. Here it enforces
  `hermes/dangerous-patterns.yaml`: no GitHub writes, no secrets, no `sudo`, no installs. No
  network, no subprocess.
- ✅ [markoblogo/abvx-agent-skills](https://github.com/markoblogo/abvx-agent-skills), the skill
  `evidence-ledger-research` (MIT, markdown only): source, date, unit and table-cell discipline for
  numbers taken from bulletins, PDFs and papers.
- 🧪 [bablobanov/hermes-agent-telegram-dashboard](https://github.com/bablobanov/hermes-agent-telegram-dashboard)
  (MIT, 7 ★): one pinned Telegram status message, edited in place, with no model call; in the
  plugin catalog at the pin. A cheap VPS-health view. Read its code before pinning it.
- 🧪 [8bit64k/cronalytics](https://github.com/8bit64k/cronalytics) (MIT, 115 ★): cost, failures and
  drift per cron job, no network. Needs a writable plugin directory and a path patch.
- 🧪 [ogallotti/rtk-hermes](https://github.com/ogallotti/rtk-hermes) (MIT, 302 ★, the module's own
  example): compresses terminal output before it reaches the model, with `pkgs.rtk`. Test its hook
  order against the deny list first.
- 🧪 [Socialpranker/agentburn](https://github.com/Socialpranker/agentburn) (MIT, 113 ★): which
  5-hour window burned the quota. Run it on a laptop against copied logs; its skill calls `uvx`, an
  unpinned download.
- 🧪 [kenpritchard/hermes-delegation-gate](https://github.com/kenpritchard/hermes-delegation-gate)
  (MIT, 99 lines): asks for `/approve` before subagents fan out. Cron runs fail closed with it.
- 🧪 CI only, never on the box: [mauricemohr88-debug/hermes-plugin-guard](https://github.com/mauricemohr88-debug/hermes-plugin-guard)
  (MIT) scans pinned plugins; [hermes-labs-ai/lintlang](https://github.com/hermes-labs-ai/lintlang)
  (Apache-2.0) lints `SOUL.md`, `AGENTS.md` and skills.
- ⛔ Too heavy for 1 GB, or a server or a cloud: [hermes-lcm](https://github.com/stephenschoettler/hermes-lcm)
  (replaces the context engine, extra summary calls), and the memory providers (hindsight, mem0,
  honcho, supermemory, Mnemosyne).
- ⛔ Unsafe or self-modifying: tree-ring-memory (downloads its own binary and updates itself),
  curator-evolver (rewrites skills on its own), oh-my-hermes (hooks every call, its workflow
  commits), hermes-backup-recovery (tars the whole home, secrets included: back up from NixOS
  instead).
- ⛔ Another platform or a credential grab: cronwatch (Feishu, reads `.env`), cron-status-alert
  (Discord), telegram-checklist (a Telethon user session; the Bot API version needs a business
  account).
- ⛔ Node or a web dashboard: [garrytan/gbrain](https://github.com/garrytan/gbrain), hermes-hud,
  hermes-ai-usage, agent-analytics. Paid APIs: web-search-plus, Consensus, Extracto (sends URLs to
  r.jina.ai). No licence: [NousResearch/hermes-agent-self-evolution](https://github.com/NousResearch/hermes-agent-self-evolution),
  hermes-weather-plugin.
- ⛔ Covered already: [Iampattanayak/hermes-nixos](https://github.com/Iampattanayak/hermes-nixos)
  (the upstream module does it), asimons81/hermes-a2a-bridge (archived; A2A is built in).

## Guides and posts

- Holme Bengt, ["Why your Hermes feels slow and costs too much"](https://buttondown.com/HolmeBengt),
  2026-08-02: cron jobs load every toolset by default, so give each one its own; a smaller memory
  limit. Its cost figures are one person's.
- The r/hermesagent megathread (June 2026): the fixed prompt overhead, and how much trimming
  toolsets saves. Not verified here.
- runtimewire.com on v0.20.0 (voice and A2A): background.

## Other lists

- [0xNyk/awesome-hermes-agent](https://github.com/0xNyk/awesome-hermes-agent) (about 5.9 k ★): the
  big directory this list started from. Its "Check the trust boundary" section is worth reading.
- [0xarkstar/awesome-hermes-agent](https://github.com/0xarkstar/awesome-hermes-agent),
  [frankxai/awesome-hermes-agents](https://github.com/frankxai/awesome-hermes-agents) and
  [frankxai/awesome-hermes-agent-skills](https://github.com/frankxai/awesome-hermes-agent-skills)
  (a safety gate for skills), and lists in Chinese:
  [jefferyjob/awesome-hermes-agent-zh](https://github.com/jefferyjob/awesome-hermes-agent-zh).

## Gaps: what piabrota has to write

Nothing found covers Brazil or the ocean. These are piabrota's own skills to write, on top of
`watchers` and `evidence-ledger-research`, with endpoints taken from code that already polls them:

- **Bathing water** from FEPAM (RS), IMA (SC), IAT (PR), INEA (RJ), INEMA (BA), for marola: see
  [astrbot_dw_ext_br_south_waterq](https://github.com/h0ffmann/astrbot_dw_ext_br_south_waterq).
- **Official alerts** from CEMADEN, Defesa Civil and INMET, as CAP 1.2, for piabrota/alerts.
- **Ocean research**: WAVEWATCH III releases and the arXiv categories of wave modelling.
- **gramatico as a skill**: Brazilian Portuguese that reads once, for every pt-BR answer.
