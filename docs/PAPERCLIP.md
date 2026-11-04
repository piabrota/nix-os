# Paperclip on piabrota2

[Paperclip](https://github.com/paperclipai/paperclip) (MIT) runs on piabrota2 (KVM 4) at
<https://paperclip.piabrota.art>, with Hermes as its agent. `paperclip.nix` sets it up. This file
is in English only, by the owner's order.

Paperclip is a control plane for a "company" of AI agents: goals, an org chart, tasks, budgets
and a heartbeat that wakes the agents. It is not an agent itself. Here its one agent is the Hermes
that already runs on the box.

## What is installed

| Part | Where | Notes |
|---|---|---|
| Paperclip server | unit `paperclip`, `127.0.0.1:3100` | The npm release `paperclipai` 2026.1023.0 on Node.js 24 (`paperclip/package.nix`). `MemoryMax=2G`, `CPUWeight=50`. State in `/var/lib/paperclip`. |
| Database | unit `postgresql`, PostgreSQL 17 | A Unix socket only (`/run/postgresql`, port 5433), no TCP, peer authentication: only the `paperclip` user reaches the `paperclip` database. `MemoryMax=1G`. PGX keeps `127.0.0.1:5432`. |
| Signing secrets | `/var/lib/paperclip-secrets/paperclip.env` | Made on the box by the unit `paperclip-secrets` the first time, kept after: `BETTER_AUTH_SECRET`, `PAPERCLIP_TOOL_ACTION_SIGNING_SECRET`, `PAPERCLIP_AGENT_JWT_SECRET`. Never in the repository. |
| Web | nginx, `paperclip.piabrota.art` | TLS from Let's Encrypt, WebSockets, a rate limit on `/api/auth/`. |
| Configuration | the store | `config.json` is written by Nix and read-only: the UI and the CLI cannot change the instance settings. A change is a pull request. |
| Admin CLI | `paperclipai` on the PATH | Runs as the `paperclip` user with the server's configuration and secrets (`sudo` inside). |

The mode is `authenticated` with `public` exposure: Paperclip's own login (Better Auth) and sign-up
closed. Telemetry and update checks are off. Paperclip makes a `pg_dump` of its database once a day
into `/var/lib/paperclip/backups` and keeps it for 7 days.

## How Hermes and Paperclip talk

Paperclip's built-in `hermes_gateway` adapter calls a Hermes that is already running, over the
Hermes API server. It does not start a second Hermes.

```text
Paperclip (127.0.0.1:3100) --POST /v1/runs, Bearer API_SERVER_KEY--> Hermes API server (127.0.0.1:8642)
Hermes terminal (curl)  --Bearer PAPERCLIP_API_KEY------------------> Paperclip API (127.0.0.1:3100/api)
```

So a Paperclip task runs inside the Hermes of `hermes.nix`: its Claude subscription, its deny list,
tripwire, its skills and its memory. No traffic between the two leaves the box.

What `paperclip.nix` adds to Hermes (`piabrota.paperclip.hermes.enable`, on when Hermes is on):

- `API_SERVER_HOST=127.0.0.1` and `API_SERVER_PORT=8642`. Hermes opens its API server only when
  `/var/lib/hermes-secrets/hermes.env` has `API_SERVER_KEY` (16 characters or more). Without it,
  nothing listens, and Paperclip has no agent.
- `PAPERCLIP_API_URL=http://127.0.0.1:3100`, and `terminal.env_passthrough` for
  `PAPERCLIP_API_URL` and `PAPERCLIP_API_KEY`, so that `curl` in Hermes's terminal gets them.
  Hermes removes other secrets from its children's environment; `API_SERVER_KEY` is not passed.
- Paperclip's own `paperclip` skill (how to read a task, update it, comment and report), copied from
  the release into `skills.external_dirs`, and `jq` for its scripts.

Hermes's deny list and its approval prompts still apply to every command a Paperclip task runs.

## One-time setup

Do these steps in order. Steps 1 and 2 are before the merge, because the merge deploys.

1. **DNS.** Add an `A` record `paperclip.piabrota.art` → piabrota2's address (the same as
   `hermes.piabrota.art`, `187.41.117.18` on 2026-11-04). Without it the ACME order fails on the
   deploy, and deploy-rs rolls the box back. Check: `dig +short paperclip.piabrota.art`.
2. **The Hermes gateway key.** On the box, add a random key to Hermes's secrets and keep a copy for
   step 6 (the deploy's activation copies it into Hermes's `.env`):

   ```console
   key=$(openssl rand -hex 32)
   echo "API_SERVER_KEY=$key" | sudo tee -a /var/lib/hermes-secrets/hermes.env >/dev/null
   echo "$key"
   ```

3. **Merge** the pull request. The deploy starts PostgreSQL, Paperclip and the API server of
   Hermes. Check: `curl -s http://127.0.0.1:3100/api/health` and
   `curl -s -H "Authorization: Bearer $key" http://127.0.0.1:8642/health` on the box.
4. **Open sign-up for the first admin.** Sign-up is closed, and Paperclip has no other way to make
   the first account. On the box:

   ```console
   echo PAPERCLIP_AUTH_DISABLE_SIGN_UP=false | sudo tee -a /var/lib/paperclip-secrets/paperclip.env
   sudo systemctl restart paperclip
   paperclipai auth bootstrap-ceo
   ```

   Open <https://paperclip.piabrota.art>, create your account, then open the invite URL that
   `bootstrap-ceo` printed: it makes you the instance admin. Then close sign-up again: remove that
   line from the file and `sudo systemctl restart paperclip`.
5. **A company.** In the UI, create the company (for example "piabrota").
6. **Hermes as an agent.** In the company, add an agent with the adapter **Hermes Gateway**:
   - API base URL: `http://127.0.0.1:8642`
   - API key: the key from step 2 (Paperclip stores it encrypted, as a secret reference)
   - Paperclip API URL: `http://127.0.0.1:3100`
   - Session key strategy: `issue` (one Hermes session for each task)

   The adapter's environment test must say "Hermes Gateway health endpoint is reachable".
7. **Hermes's key for Paperclip.** In the agent's page, create an API key. On the box, add it to
   Hermes's secrets and reload Hermes:

   ```console
   echo "PAPERCLIP_API_KEY=<the pcp_... key>" | sudo tee -a /var/lib/hermes-secrets/hermes.env >/dev/null
   sudo /run/current-system/bin/switch-to-configuration switch
   sudo systemctl reload hermes-agent
   ```

   The activation, not the service, copies `hermes.env` into Hermes's `.env` (docs/HERMES.md);
   the reload lets the turns in flight finish first.

   Hermes then reads and updates its tasks with the `paperclip` skill.

The flow from step 4 to 7 was run on a copy of the unit (its command, environment and
`config.json`) against PostgreSQL 17 on 2026-11-04, with a stand-in for the Hermes API server:
the bootstrap invite made the admin, the environment test reached `/health` with the Bearer key,
and the agent key authenticated `GET /api/agents/me`. The real Hermes API server was not run.

## Cost

Measured on 2026-11-04 (Linux x86_64, PostgreSQL 17.11, Node.js 24.22.1), not on the box:

| Item | Value |
|---|---|
| Paperclip package in the store | 564 MiB (815 MiB with Node.js 24 and its libraries) |
| Download to build it | 113 MiB of npm tarballs (3.9 GiB with the optional platform binaries, which are left out) |
| Server memory, idle | about 590 MiB RSS |
| PostgreSQL | 128 MiB of shared buffers; Paperclip opens 10 connections |

piabrota2 has 16 GB (Hostinger's plan list; the kernel sees 15.6 GiB). The caps of the big units add
up to 13.25 GiB: Hermes 8G, its dashboard 2G, Paperclip 2G, PostgreSQL 1G and PGX 256M. That leaves
about 2.4 GiB for the kernel, nginx, sshd and the page cache, so the units must not all reach their
caps at once. At rest they use far less (Paperclip about 590 MiB). The earlier study of this file
(2026-11-03, for KVM 1) said no to the 1 vCPU box; those limits do not apply to KVM 4.

What Paperclip costs in Claude usage is the Hermes runs it starts: each heartbeat that wakes Hermes
is a Hermes turn on the subscription. Paperclip's budgets limit how often that happens.

## Not included

- Paperclip's local adapters (`claude_local`, `codex_local` and the others) and `hermes_local`:
  they start CLIs that the box does not have. Use `hermes_gateway`.
- The embedded PostgreSQL and the Docker image: Paperclip refuses the embedded one in public mode,
  and this repository runs no Docker.
- `paperclip-runnerd` and the remote runners (Daytona and the like).

## Updating

The package is the npm release. To move to a new one:

1. Download the release's `package.json` (`npm view paperclipai@<version> dist.tarball`).
2. Put its dependencies in `paperclip/package.json`, without `optionalDependencies`, and add
   `@img/sharp-linux-x64` and `@img/sharp-libvips-linux-x64` at the versions that `sharp` asks for.
3. Make the lock with Node.js 24's npm: `npm install --package-lock-only --ignore-scripts`, then
   again with `--os=darwin --cpu=arm64` (npm leaves `fsevents` out of a lock made on Linux, and
   `npm ci` then refuses it).
4. Set `version`, the `src` hash and the `npmDeps` hash in `paperclip/package.nix`, and build
   `piabrota2`.

Read the release notes for a change to the configuration schema or the `hermes_gateway` adapter.

## Turning it off

`piabrota.paperclip.enable = false;` in `hosts/piabrota2/default.nix`. The data stays in
`/var/lib/paperclip` and in the `paperclip` database. Remove `API_SERVER_KEY` from Hermes's
secrets to close its API server.
