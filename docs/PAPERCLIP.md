# Paperclip on piabrota2

[Paperclip](https://github.com/paperclipai/paperclip) (MIT) runs on piabrota2 (KVM 4) at
<https://paperclip.piabrota.art>. `paperclip.nix` sets it up. This file is in English only, by the
owner's order.

Paperclip is a control plane for a "company" of AI agents: goals, an org chart, tasks, budgets
and a heartbeat that wakes the agents. It is not an agent itself. Its agents here run in the Hermes
that already runs on the box, in omp, or in Claude Code.

## What is installed

| Part | Where | Notes |
|---|---|---|
| Paperclip server | unit `paperclip`, `127.0.0.1:3100` | The npm release `paperclipai` 2026.1023.0 on Node.js 24 (`paperclip/package.nix`). `MemoryMax=2G`, `CPUWeight=50`. State in `/var/lib/paperclip`. |
| Database | unit `postgresql`, PostgreSQL 17 | A Unix socket only (port 5433), peer authentication. `MemoryMax=1G`. PGX keeps `127.0.0.1:5432`. |
| Signing secrets | `/var/lib/paperclip-secrets/paperclip.env` | The unit `paperclip-secrets` makes them the first time and keeps them. Never in the repository. |
| Web | nginx, `paperclip.piabrota.art` | TLS from Let's Encrypt, WebSockets, a rate limit on `/api/auth/`. |
| Configuration | the store | Nix writes `config.json`, read-only. A change is a pull request. |
| Commands | `paperclipai`, `paperclip-hermes-key` | `paperclipai` runs as the `paperclip` user with the server's configuration and secrets. `paperclip-hermes-key` is for `sudo` (see "Setup"). |

The mode is `authenticated` with `public` exposure: Paperclip's own login (Better Auth) and sign-up
closed. Telemetry and update checks are off. Paperclip makes a `pg_dump` of its database once a day
into `/var/lib/paperclip/backups` and keeps it for 7 days.

## Adapters

| Adapter | State | Notes |
|---|---|---|
| `hermes_gateway` | Works. Needs the key of `paperclip-hermes-key`. | The task runs in the Hermes of `hermes.nix`: its subscription, deny list, skills and memory. |
| `pi_local` | Works through omp. | Runs omp with the same Claude subscription token as Hermes. A shim (`paperclip/pi-to-omp.sh`, command `paperclip-pi`) turns Paperclip's call for `pi` into a call for omp. The shim uses `--no-session`, so a run has no memory of the run before. Claude models only. Tools: `read`, `bash`, `edit`, `write`, `grep`. |
| `claude_local` | Works. | Runs Claude Code (`claude` 2.1.303, from nixpkgs) with the same Claude subscription token as Hermes. Claude Code is unfree: `paperclip.nix` lets in this one package by name (`allowUnfreePredicate`), and nothing else. Leave the agent's filesystem and network scopes off: they need `bwrap`, and the unit forbids namespaces. |
| The other `*_local` adapters | Do not work here. | They need CLIs that the box does not have. |

```text
hermes_gateway: Paperclip (127.0.0.1:3100) --POST /v1/runs, Bearer API_SERVER_KEY--> Hermes API server (127.0.0.1:8642)
                Hermes terminal (curl)  --Bearer PAPERCLIP_API_KEY------------------> Paperclip API (127.0.0.1:3100/api)
pi_local:       Paperclip --paperclip-pi--> omp wrapper (omp/wrapper.nix, hermes/omp.yml) --> Claude
claude_local:   Paperclip --claude (Claude Code, on the unit's PATH)----------------------> Claude
```

No traffic between Paperclip and Hermes leaves the box. `piabrota.paperclip.hermes.enable` (on when
Hermes is on) sets `API_SERVER_HOST` and `API_SERVER_PORT` (Hermes opens its API server only when
its secrets file has `API_SERVER_KEY`) and `PAPERCLIP_API_URL`. It passes `PAPERCLIP_API_KEY`
to Hermes's terminal, but not `API_SERVER_KEY`. It also gives Hermes Paperclip's own `paperclip`
skill (from the release) and `jq` for its scripts. Hermes's deny list and approval prompts apply
to every `hermes_gateway` run.

`piabrota.paperclip.omp.enable` (on when Hermes is on) sets `PAPERCLIP_PI_COMMAND` to the shim and
adds the token step (see "The token"). The rules of `hermes/omp.yml` apply to every `pi_local` run.

`piabrota.paperclip.claude.enable` (on when Hermes is on) puts Claude Code on the unit's PATH,
allows that one unfree package, and adds the same token step. Hermes's deny list and `hermes/omp.yml`
do not apply to `claude_local` runs: Paperclip passes Claude Code its own permission settings.

## Setup

1. **DNS.** Done: `paperclip.piabrota.art` points at piabrota2 (check: `dig +short paperclip.piabrota.art`).
2. **A new database only: the first admin.** Sign-up is closed, and Paperclip has no other way to
   make the first account. On the box:

   ```console
   echo PAPERCLIP_AUTH_DISABLE_SIGN_UP=false | sudo tee -a /var/lib/paperclip-secrets/paperclip.env
   sudo systemctl restart paperclip
   paperclipai auth bootstrap-ceo
   ```

   Open the site and create your account. Then open the invite URL that `bootstrap-ceo` printed.
   It makes you the instance admin. Remove the line from the file and restart `paperclip`.
   Then create the company in the UI.
3. **The Hermes key.** On the box, run `sudo paperclip-hermes-key`. It adds a random
   `API_SERVER_KEY` to Hermes's secrets file, once. It never prints the key unless you add `--show`.
4. **Apply it.** The activation, not the service, copies that file into Hermes's `.env`:

   ```console
   sudo /run/current-system/bin/switch-to-configuration switch
   sudo systemctl reload hermes-agent
   ```
5. **Agent with `hermes_gateway`.** In the UI, add an agent with the adapter **Hermes Gateway**:
   - API base URL: `http://127.0.0.1:8642`
   - API key: the output of `sudo paperclip-hermes-key --show` (Paperclip stores it encrypted)
   - Paperclip API URL: `http://127.0.0.1:3100`
   - Session key strategy: `issue` (one Hermes session for each task)

   The environment test must say "Hermes Gateway health endpoint is reachable". Then create an API
   key on the agent's page. Add it to Hermes's secrets file as `PAPERCLIP_API_KEY=<the pcp_... key>`,
   and repeat step 4. Hermes then reads and updates its tasks with the `paperclip` skill.
6. **Agent with `pi_local`.** In the UI, add an agent with the adapter **Pi**:
   - Command: empty (the unit's `PAPERCLIP_PI_COMMAND` is the shim)
   - Model: `anthropic/claude-sonnet-5-5` or `anthropic/claude-haiku-4-5`
   - Working directory: a folder under `/var/lib/paperclip`, for example `/var/lib/paperclip/work/<agent>`
     (Paperclip makes it)

   Then open the agent's configuration, and in the heartbeat settings set **Max concurrent runs** to
   `1` (see "Limits").
7. **Agent with `claude_local`.** In the UI, add an agent with the adapter **Claude Code** (or keep
   one made with it):
   - Command: empty (`claude` is on the unit's PATH)
   - Model: `claude-sonnet-5-5` or `claude-haiku-4-5`
   - Working directory: a folder under `/var/lib/paperclip`, the only place the unit may write
   - Filesystem and network scope: off (see "Adapters")

   The environment test must pass its hello probe. Set **Max concurrent runs** to `1`, then resume
   the agent if it is paused.

## The token

`pi_local` and `claude_local` use the same Claude subscription token as Hermes. At each start,
`paperclip` runs a root step (`ExecStartPre=+`) that copies one line, `CLAUDE_CODE_OAUTH_TOKEN`,
from Hermes's secrets file into `/var/lib/paperclip-secrets/claude.env`. Only the `paperclip` user reads that file.
The repository holds no copy. To rotate the token, change it in Hermes's secrets file and run
`sudo systemctl restart paperclip`. One subscription means that Hermes and Paperclip share its
limits. An agent that has a shell could read its own environment. So `hermes/omp.yml` denies
`/proc/*/environ` and `/proc/self/*` in omp's bash tool. This is a guardrail and not a boundary.
Claude Code has no such rule here. Give `pi_local` and `claude_local` agents only work that you
accept with this token.

## Limits

- The `MemoryMax=2G` of the unit also holds each omp child (about 0.5 to 0.8 GiB). Run one omp
  agent at a time. Paperclip's default is 20 concurrent runs for each agent. In the agent's
  configuration, heartbeat settings, set **Max concurrent runs** to `1`. The field is for one
  agent. If you add a second `pi_local` agent, the owner decides how to share the memory.
- A Claude Code child is in the same `MemoryMax=2G`. Set **Max concurrent runs** to `1` for a
  `claude_local` agent too.
- Every omp run stops after 35 minutes (the wrapper's `timeout`).
- A run has no session memory.

## Cost

Claude Code adds 283.4 MiB to piabrota2's system (measured on the box on 2026-11-04: the binary is
273 MiB; alsa-lib, ripgrep, bubblewrap, socat and libcap are the rest). Hydra does not build
unfree packages, so CI downloads its release from downloads.claude.ai; nothing is compiled.

Measured on 2026-11-04, not on the box. The package is 564 MiB in the store (815 MiB with
Node.js 24). The build downloads 113 MiB of npm tarballs. The idle server holds about 590 MiB RSS.
PostgreSQL has 128 MiB of shared buffers. piabrota2 has 16 GB. The caps of the big units add up to
13.25 GiB (Hermes 8G, dashboard 2G, Paperclip 2G, PostgreSQL 1G, PGX 256M), so they must not all
reach their caps at once. A run costs Claude usage on the subscription. Paperclip's budgets limit
how often agents wake.

## Not included

- `hermes_local` and the `*_local` adapters other than `pi_local` and `claude_local` (see "Adapters").
- The embedded PostgreSQL (Paperclip refuses it in public mode), the Docker image,
  `paperclip-runnerd` and the remote runners.

## Updating

The package is the npm release. To move to a new one:

1. Download the release's `package.json` (`npm view paperclipai@<version> dist.tarball`).
2. Put its dependencies in `paperclip/package.json`, without `optionalDependencies`. Add
   `@img/sharp-linux-x64` and `@img/sharp-libvips-linux-x64` at the versions that `sharp` asks for.
3. Make the lock with Node.js 24's npm: `npm install --package-lock-only --ignore-scripts`, then
   again with `--os=darwin --cpu=arm64` (npm leaves `fsevents` out of a lock made on Linux, and
   `npm ci` then refuses it).
4. Set `version`, the `src` hash and the `npmDeps` hash in `paperclip/package.nix`, and build
   `piabrota2`.

Read the release notes for a change to the configuration schema, to the `hermes_gateway` adapter or
to the arguments of `pi_local`. Then run `just paperclip-test`.

## Turning it off

`piabrota.paperclip.enable = false;` in `hosts/piabrota2/default.nix`. The data stays in
`/var/lib/paperclip` and in the `paperclip` database. Remove `API_SERVER_KEY` from Hermes's
secrets to close its API server. `piabrota.paperclip.omp.enable = false;` removes only the shim and
the token step.
