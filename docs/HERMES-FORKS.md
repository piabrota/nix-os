# Hermes forks and business editions

A survey of forks and business editions of [Hermes Agent](https://github.com/NousResearch/hermes-agent)
for very small companies and startups. Read on 2026-11-03. This file is in English only, by the
owner's order. It is research: the configuration runs none of these projects.

## Answer

Keep the upstream Hermes Agent for now. No fork in this list is a better fit than upstream for
one owner on a 1 vCPU, 4 GB box.

- If a second person needs their own agent, use upstream
  [profiles](https://hermes-agent.nousresearch.com/docs/user-guide/profiles). A profile has its own
  config, keys, memory, sessions, skills and gateway state. No fork is necessary.
- If the company needs roles, approvals and an audit log, test Maia first (single tenant).
- If one deployment must serve many isolated users, read hermes-agent-mt first (thin fork).
- If the company wants no server at all, Hermes Business is the hosted option.

Confidence: medium. I read the READMEs, licences, release lists and repository metadata. I did not
run any of these projects.

## How to read the table

GitHub marks a repository as a fork only when it keeps the fork link. Most of these do not. The
**Kind** column comes from the README and the LICENSE file, not from the GitHub flag.

| Project | Kind | Aim | Licence | Stars | Last push | Release |
|---|---|---|---|---|---|---|
| [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) | Upstream | Personal agent | MIT | 260168 | 2026-11-03 | not checked |
| [cyborg-garden/hermes-agent-mt](https://github.com/cyborg-garden/hermes-agent-mt) | Thin fork | Multi-tenant deployments | MIT | 14 | 2026-11-03 | none |
| [cyborg-garden/swarm-map](https://github.com/cyborg-garden/swarm-map) | Control plane for the fork above | Admin for many agents | AGPL-3.0 | 26 | 2026-11-03 | not checked |
| [and270/maia](https://github.com/and270/maia) | Modified distribution | One-tenant corporate assistant | MIT | 1 | 2026-07-20 | v0.1.0 (2026-07-20) |
| [eggyrooch-blip/hermes-multitenancy](https://github.com/eggyrooch-blip/hermes-multitenancy) | Plugin on stock core | One Feishu bot for many users | MIT | 26 | 2026-11-03 | none |
| [SeerBench/hermes-multiuser-web-service](https://github.com/SeerBench/hermes-multiuser-web-service) | Fork plus one adapter | Multi-user web chat | MIT | 2 | 2026-10-19 | none |
| [RemiPelloux/OpenAgents](https://github.com/RemiPelloux/OpenAgents) | Rename fork | Branding and onboarding | MIT | 1 | 2026-10-05 | none |
| [kwkuh/chathermes](https://github.com/kwkuh/chathermes) | SaaS boilerplate on upstream | Sell an agent per paying user | AGPL-3.0 plus addenda (not OSI) | 11 | 2026-07-31 | none |
| [Colin4k1024/hermesx](https://github.com/Colin4k1024/hermesx) | Go rewrite, diverged from a fork | Multi-tenant control plane | MIT | 14 | 2026-09-03 | v2.0.0 (2026-05-07) in the release list; the README names v2.3.0 |

Stars and dates come from `gh api repos/<owner>/<repo>` on 2026-11-03.

## Official business editions

**Hermes Business and Hermes Enterprise** (Nous Research). Source: the
[Nous Portal page](https://portal.nousresearch.com/business).

- Business is a team account on Nous infrastructure. It has one shared balance, per-member spend
  caps, hosted agents for each member and a shared skill library. Each team gets an isolated
  tenant on Nous servers.
- Enterprise runs on infrastructure that the customer controls. It adds SSO and SLAs.
  Nous does not publish its size needs or its price.
- Load on this VPS: none for Business. The agents run at Nous. Nous publishes no sizing for Enterprise.
- Costs that are not CPU or RAM:
  - The Team Gateway relay turns off direct Telegram, Slack and Discord connections, unless
    `GATEWAY_RELAY_ALLOW_DIRECT_PLATFORMS=true` is set
    ([issue 141175](https://github.com/NousResearch/hermes-agent/issues/141175)). This box uses
    direct Telegram and Discord.
  - The models come from the Nous API or from the customer's provider keys. This box uses the
    owner's Claude subscription and no API key. I did not check if that works in Business.
  - A trade article gives $20 to $200 a month for the hosted tiers
    ([AI Agent Chronicle](https://aiagentchronicle.com/articles/2026-10-12-nous-research-raises-90m-to-bring-its-open-source-hermes-agent-directly-to-busin/)).
    The official page shows no price. Treat the number as unverified.
  - A community blog says that, on 2026-10-02, shared skills were still pre-launch in the public
    code ([hermesagents.net](https://hermesagents.net/blog/hermes-business-and-enterprise-explained)).
    Treat this as unverified.

## Projects

**hermes-agent-mt.** Its FORK-NOTICE says: 2 core patches (memory scoped per group or direct
message, and safe context IDs) and about 8 adapter changes (Signal, Mattermost, Telegram). It
says a CI job rebases it on upstream each week. I did not check that job. The fork ships as a
container image, with one container for each agent. Swarm Map manages the containers. The image
path changed with two org renames. Old paths still pull and return old code
([FORK-NOTICE](https://github.com/cyborg-garden/hermes-agent-mt/blob/main/FORK-NOTICE.md)).
This is the best-maintained fork in the list. It does not fit this box: the yardstick in
[AWESOME-HERMES.md](AWESOME-HERMES.md) excludes anything that needs Docker on the box.

**Maia (AmpliIA).** A private, one-tenant corporate assistant based on the Hermes code. Its README
lists: role-aware conversations, deny-by-default folder policies by role, team or user, approvals
by a human for edits, commands and cron jobs, layered corporate, team and user knowledge, an
append-only audit log and an optional SIEM webhook. Its LICENSE is MIT and keeps the Nous
copyright line. It is the closest match to "a small company with roles and an audit trail". The
risk is maintenance: one release (v0.1.0) and no push for more than three months, while upstream
changes each day. I did not check if it builds with Nix.

**hermes-multitenancy.** A plugin, not a fork. It uses upstream's `pre_gateway_dispatch` hook to
send each Feishu user to their own profile. It makes no patch to the core, so upgrades stay easy.
It supports Feishu only. A company on Slack, Discord or Telegram cannot use it as it is.

**hermes-multiuser-web-service.** A fork that adds a `web_chat` adapter and per-user isolation.
Accounts and billing pass to an OpenAI-compatible gateway (new-api). It has 2 stars. It suits a
company that wants a web chat for staff and already runs such a gateway.

**OpenAgents.** A rename of Hermes with a "company workspace" scaffold and a visual workflow
builder. I found no technical change that upstream lacks. Skip it.

**ChatHermes.** A multi-tenant SaaS boilerplate (magic-link login, Stripe, one agent for each
paying user) that runs on Hermes. Its licence is AGPL-3.0 with a required-attribution addendum, a
trademark reservation and a cloud carve-out. I did not read the addendum terms. A startup that
wants to sell agents needs a lawyer to read them first.

**HermesX.** A Go control plane with PostgreSQL row-level security, RBAC, audit logs and
Kubernetes. Its README says it started as a fork of Hermes and then diverged. It is not
Hermes any more. It supports SaaS mode only. It is too large for this box.

## What upstream already has for teams

- Profiles: several independent agents on one machine
  ([docs](https://hermes-agent.nousresearch.com/docs/user-guide/profiles)).
- A kanban board for work across profiles
  ([docs](https://hermes-agent.nousresearch.com/docs/user-guide/features/kanban)).
- Per-platform lists of allowed users, which this box uses already.
- Known gap: an upstream issue says memory operations skip the hook system, so a plugin cannot
  isolate tenants alone ([issue 34352](https://github.com/NousResearch/hermes-agent/issues/34352)).
  That is the reason hermes-agent-mt patches the core. I read the issue summary only.

## Fit for this box

The box has 1 vCPU and 4 GB of RAM. Hermes is capped at 1 GB. On 2026-11-03 it used about 378 MiB
of program memory and 537 MiB of file cache that the kernel can free. It had no out-of-memory
kills. The yardstick in [AWESOME-HERMES.md](AWESOME-HERMES.md) excludes anything that needs Node, Go,
Docker or a browser on the box. The resource budget in AGENTS.md excludes heavy runtimes and
resident daemons. A container for each agent, or a Go control plane on Kubernetes, breaks these rules.

## Not checked

- I ran no project. All facts come from READMEs, licence files, release lists and the GitHub API.
- I did not check the weekly rebase of hermes-agent-mt, or how far Maia is behind upstream.
- I did not read the ChatHermes addendum terms or the Maia source.
- Release data for upstream, Swarm Map and hermes-multitenancy is partial.
- No ASD-STE100 checker is installed on this box. I applied the rules by hand.
