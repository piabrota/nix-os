# The operator account

[Português](OPERATOR.ptBR.md)

`operator` lets a coding agent's session (Claude Code on the owner's computer) look at a host and
do a small, fixed set of things on it, without root. It is `observer` plus a sudo allow-list.
Every host gets it (`configuration.nix` imports `operator.nix`); each host's list holds only the
units that host has.

| Account | Reads | Changes |
|---|---|---|
| `observer` | every unit's log and state, `ps`, `free`, `df` | nothing |
| `operator` | the same, and files under `HERMES_HOME` except secrets | only the commands below |
| `h0ffmann` | everything | everything (passwordless sudo) |

## What it may run

Run `op-help` on the box to see the list for that host.

| Command | On | Does |
|---|---|---|
| `sudo systemctl restart <unit>.service` | `hermes-agent`, `hermes-backend`, `nginx`, `pgx`, `loco-<app>`, the ones the host has | restarts a long-running unit |
| `sudo systemctl start <unit>.service` | `nix-gc`, `nix-optimise`, `hermes-github-token`, `loco-<app>-backup`, the ones the host has | runs a timer's job now |
| `sudo -u hermes op-hermes <cmd>` | hosts with Hermes | `status`, `doctor`, `insights`, `logs`, `cron list`, `cron status`, `sessions list`, `sessions stats`, `cron run\|pause\|resume <job-id>` |
| `sudo -u hermes op-peek <path> [lines]` | hosts with Hermes | `ls -la` of a directory or the last lines (200 by default) of a file under `HERMES_HOME` |

Anything else through sudo asks for a password, and `operator` has none. It cannot deploy, change
the configuration, stop a unit, or read `/var/lib/*-secrets`.

`op-peek` resolves symlinks first, refuses a path outside `HERMES_HOME`, and refuses `.env*`,
`auth*` and any name with `secret`, `token`, `credential`, `password`, `.key` or `.pem` in it.
`operator` is not in the `hermes` group on purpose: Hermes's NixOS module makes `.env`, which holds
the Claude token and the chat tokens, readable by that group.

## Setup on the owner's computer

The key pair is `~/.ssh/piabrota_operator`; the public half is `keys/operator.pub`. Add one entry
per host to `~/.ssh/config`, next to the observer ones:

```sshconfig
Host piabrota-operator
  HostName <piabrota's IPv4>
  User operator
  IdentityFile ~/.ssh/piabrota_operator
  IdentitiesOnly yes
  UserKnownHostsFile ~/.ssh/known_hosts.piabrota
  StrictHostKeyChecking yes
  ConnectTimeout 10

Host kvm4-operator
  HostName hermes.piabrota.art
  User operator
  IdentityFile ~/.ssh/piabrota_operator
  IdentitiesOnly yes
  ConnectTimeout 10
```

Then, from Claude Code: `ssh piabrota-operator op-help`.

## Rules for an agent

AGENTS.md's "Deploy" section holds: an agent uses `operator` only for an action the owner asked
for, runs that action and nothing else, and reports what it ran. A fix to the configuration still
goes in a pull request.

## Turning it off

Empty `keys/operator.pub` (comments only) and merge: the account stays but no key opens it. To
remove it, drop `./operator.nix` from `configuration.nix`.
