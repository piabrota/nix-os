# Deploys (GitOps)

Every change to the VPS goes through GitHub. A push to `main` runs `.github/workflows/deploy.yml`:

1. The GitHub runner builds the whole system of each host (`nixosConfigurations.piabrota`,
   `nixosConfigurations.piabrota2`; see "A second host"). The VPS builds
   nothing, so its small CPU, RAM and disk are not used for compiles. The build job saves the
   system's closure to GitHub's Actions cache under the commit's key. The deploy job restores that
   cache and does not build again, and the next merge builds only what changed.
2. [deploy-rs](https://github.com/serokell/deploy-rs) copies the result to the VPS over SSH. The
   VPS downloads what `cache.nixos.org` has by itself; the runner uploads only the rest.
3. deploy-rs activates the new system and then opens a new SSH connection. If that connection
   fails within 60 seconds (a bad firewall or sshd change), the VPS rolls back to the previous
   generation by itself ("magic rollback").
4. The job deletes every system generation but the last five (the five that GRUB lists). It
   does not collect garbage: Nix does that when free disk falls under 2 GiB, and once a week.
5. The job prints `piabrota specs` from the VPS into the run summary.

Every pull request runs `.github/workflows/ci.yml`: `nixpkgs-fmt`, `statix`, `deadnix`,
the figure check, a parse of every justfile with the `just` of Ubuntu 24.04 (1.21.0), and the
build of the scripts' binary with its tests (`nix build .#piabrota`, `scala/README.md`). The rest
builds nothing. The full `nix flake check` (it builds the system, the VM test and
checks the deploy-rs node) takes about 10 minutes, so it runs only by hand:
`gh workflow run ci.yml --ref <branch>`. The build of each merge in `deploy.yml` is the gate: if it
fails, nothing reaches the VPS.

## One-time setup

Do these steps once, in this order.

### 1. Make the deploy key

On your own machine (not the VPS):

```sh
ssh-keygen -t ed25519 -N '' -C github-actions-deploy -f piabrota-deploy
```

- Put the content of `piabrota-deploy.pub` on its own line in `keys/deploy.pub`, and commit it.
  `deploy.nix` gives it to the `deploy` user.
- Keep `piabrota-deploy` (the private key) for step 3. Do not commit it.

### 2. Get the address and the host key of the VPS

- In hPanel, open **VPS > Overview** and copy the IPv4 address. Use the IP and not
  `piabrota.art`, because a DNS proxy or CDN in front of the domain does not forward SSH.
- On the VPS (`ssh h0ffmann@<ip>`), print the host key:

  ```sh
  cat /etc/ssh/ssh_host_ed25519_key.pub
  ```

  Write it as one `known_hosts` line: `<ip> ssh-ed25519 AAAA...`. You can also run
  `ssh-keyscan -t ed25519 <ip>` from your machine, but then compare the result with the
  file above.

### 3. Add the secrets in GitHub

In `piabrota/nix-os`, open **Settings > Environments**, create the environment `prod`,
and add three secrets to it:

| Secret | Value |
|---|---|
| `DEPLOY_SSH_KEY` | the whole content of `piabrota-deploy` (the private key) |
| `DEPLOY_HOST` | the IPv4 address of step 2 |
| `DEPLOY_KNOWN_HOSTS` | the `known_hosts` line of step 2 |

In the same page, set **Deployment branches** to `main` only. The deploy key can become root on
the VPS (deploy-rs activates through `sudo`), so only `main` must reach it.

### 4. Open SSH in the Hostinger firewall

GitHub runners connect from many addresses. In hPanel, open **VPS > Security > Firewall**. If a
firewall is active, it must accept TCP port 22 from any address. Password login is already off
(`piabrota.nix`), so only keys can log in.

### 5. The first deploy, by hand

The `deploy` user does not exist on the VPS until a system that has it is active, so the first
deploy uses your own account. Before it, check that the VPS has nothing that is not in this
repository: look at `/etc/nixos/` on the VPS (for example a `hardware-configuration.nix` or a
change made there by hand). Add what is missing to the repository first.

Do it in one of two ways.

**From GitHub (no Nix needed on your machine).** This needs the workflow on `main`, so merge
first; the deploy of that merge fails at SSH and changes nothing.

1. On the VPS, as `h0ffmann`, let the CI key log in as you for this one run:

   ```sh
   echo 'ssh-ed25519 AAAA… github-actions-deploy' >> ~/.ssh/authorized_keys
   ```

   The line is the one in `keys/deploy.pub`.
2. In GitHub, open **Actions > deploy > Run workflow**, set **SSH user** to `h0ffmann`, and run
   it. It deploys as you, and the system it activates has the `deploy` user.
3. On the VPS, remove the line again, so the CI key is no longer `h0ffmann`'s:

   ```sh
   sed -i '/github-actions-deploy$/d' ~/.ssh/authorized_keys
   ```

**From your machine, with Nix**, in a clone of this repository:

```sh
DEPLOY_HOST=<ip> just deploy h0ffmann
```

This builds on your machine, copies to the VPS and activates, with the same rollback as CI.

After either one, `ssh deploy@<ip>` works with the key of step 1. From then on, every merge to
`main` deploys by itself, and you can start a deploy again from the **Actions** tab
(`deploy`, **Run workflow**, SSH user `deploy`).

## A second host

The repository deploys two hosts: `piabrota` (KVM 1) and `piabrota2` (KVM 4). Each is a directory in
`hosts/` that imports `configuration.nix` (what both share) and the roles it runs. Every merge
builds both systems in one job and deploys each in its own job. A host that has no address secret
is skipped with a notice, so `piabrota` keeps deploying while `piabrota2` is being set up.

One name stands for one VPS: the VPS name in hPanel = `hosts/<name>/` = `nixosConfigurations.<name>` =
`deploy.nodes.<name>`. KVM 1's `networking.hostName` is the exception: it is Hostinger's own name,
`srv2108887`, which cloud-init needs. A new host takes the VPS name as its directory, its
configuration and its deploy node. The address-map line in `deploy.yml` and `freeze.yml` uses that
name too. `kvm4` in those two workflows is the old name of `piabrota2`: the flake keeps it as an
alias node until a human edits the workflows.

To bring `piabrota2` up from a new, empty VPS, once. Nothing is cloned or built on the VPS: the
repository stays on GitHub (and on your machine), and the VPS only receives the built system.

1. **hPanel, the OS.** Install the NixOS template on the KVM 4 VPS (**VPS > OS & Panel >
   Operating System**, as in docs/FORK.md), with your SSH public key. `configuration.nix`'s boot
   and disk settings are that template's. Take a snapshot (**Snapshots & Backups**), so you can
   go back to a clean system.
2. **The VPS, a look.** Log in with the account the template set up for your key (`root` or
   `h0ffmann`). Note the hostname (`hostname`, srvNNNNNNN), print the host key
   (`cat /etc/ssh/ssh_host_ed25519_key.pub`) and look at `/etc/nixos/`. If its
   `hardware-configuration.nix` names another disk or label than `/dev/sda` and `nixos`, add it
   to `hosts/piabrota2/` and import it.
3. **The repository.** In a pull request, set `networking.hostName` in `hosts/piabrota2/default.nix`
   to the VPS name (`piabrota2`), with a comment that names Hostinger's first hostname. Merge it;
   piabrota2 is still skipped, because it has no address secret yet.
4. **GitHub.** In the `prod` environment, add the secret `DEPLOY_HOST_KVM4` (the IPv4 address
   from **VPS > Overview**), and add the line `<ip> ssh-ed25519 AAAA...` to `DEPLOY_KNOWN_HOSTS`,
   under piabrota's line. `DEPLOY_SSH_KEY` stays the same: `keys/deploy.pub` is on both hosts.
5. **hPanel, the firewall.** Open TCP port 22 from any address, as in step 4 above.
6. **The first deploy**, before the `deploy` user exists on the VPS, in one of two ways:
   - From your machine, with Nix, in a clone of this repository:
     `DEPLOY_HOST=<ip> just deploy root piabrota2` (or `h0ffmann` instead of `root`, whichever
     account step 2 used).
   - From GitHub, if the account is `h0ffmann`: add the line of `keys/deploy.pub` to
     `~h0ffmann/.ssh/authorized_keys` on the VPS, run **Actions > deploy > Run workflow** with
     **Host** `kvm4` (the name `deploy.yml` still uses for `piabrota2`) and **SSH user** `h0ffmann`, then remove the line again (step 5 above shows
     the commands).
   After it, `ssh deploy@<ip>` works, and every merge to `main` deploys piabrota2 too.
7. **Hermes's secrets.** Write `/var/lib/hermes-secrets/hermes.env` (and `github-app.env` for
   the GitHub App) on the VPS, as docs/HERMES.md says. Copy them from piabrota at the cutover
   (MIGRATION-KVM4.md): two gateways on one Telegram token both fail. Hermes starts with no
   platform until the file exists, so step 6 does not wait on it.

Hermes, its GitHub App, its dashboard and PGX moved from piabrota to piabrota2; piabrota serves the
public web only. [MIGRATION-KVM4.md](MIGRATION-KVM4.md) is the checklist of that move: piabrota2's
first deploy before the merge, the cutover of the state and the secrets, and what is left on
piabrota.

## Every day

- Change the configuration in a pull request. CI builds it. Merge, and the deploy runs.
- `just specs` on the VPS, or `DEPLOY_HOST=<ip> just remote-specs` from your machine, prints
  the CPU, RAM, disk, kernel and NixOS generation.
- To go back, revert the commit and merge the revert. In an emergency, on the VPS:
  `sudo nixos-rebuild switch --rollback`. The next merge to `main` deploys again over it.
- To update nixpkgs: `nix flake update` in a pull request.

### Daily commands

From your machine, in this repository (`just --list` shows them all):

| Command | What it does |
|---|---|
| `just daily` | The morning look, read only: `remote-health` of both boxes, their failed units, then `certs`. |
| `just box`, `just box2` | A shell on piabrota, on piabrota2. |
| `just logs <unit> [user] [host]` | The last 100 lines of a unit's journal on a box. |
| `just prs` | The open pull requests of piabrota/nix-os. |
| `just b`, `c`, `h`, `s`, `t`, `p` | `build`, `check`, `remote-health`, `remote-specs`, `scala-test`, `site-pins`. |

On a box, for every user (`tools.nix`, all read only):

| Alias | Runs |
|---|---|
| `failed`, `timers` | the failed units; the timers and when they run next |
| `logs <unit>`, `follow <unit>` | the last 200 lines of a unit's journal; the journal as it grows |
| `errors` | the warnings and errors since the boot |
| `hs`, `hlog` | Hermes's unit status; its journal as it grows (piabrota2) |
| `hm <args>` | the Hermes CLI as its own user, `sudo -u hermes hermes` (piabrota2) |
| `gens`, `changed`, `ver` | the system generations; what changed since the boot (`dix`); the NixOS version |
| `ports`, `mem`, `disk` | the listening TCP ports; the memory; the local disks (`duf`) |

## Restarting the services by hand

`just remote-restart` restarts the services of a box over SSH, as `h0ffmann` through the existing
passwordless `sudo` (`piabrota.nix`). It changes no Nix option, no unit and no sudo or polkit
rule. **Only a human runs it. An agent never does**, as an agent never deploys: Hermes's deny list
blocks `sudo` and `systemctl restart`.

It runs `piabrota restart-services` on the box ([`scala/scripts/RestartServices.scala`](../scala/scripts/RestartServices.scala)). A group acts
only on the units the box has, so the same command works on piabrota and piabrota2: a group the
box lacks gives one `skip: <group>: not on this box` line. The table is the allow list. No other
unit is touched: not `sshd`, the network, `systemd-*`, `acme-*`, `nix-daemon`, `deploy*`,
`qemu-guest-agent` or `cloud-init*`.

|Group|Units|Verb|What the restart costs|
|---|---|---|---|
|`metrics`|`metrics-collect.timer`, `metrics-pull.timer`, then `metrics-collect.service`, `metrics-pull.service`|restart the timers, start the oneshots once|Nothing. There is no metrics daemon: the timers fire oneshot services, and the run makes the page fresh.|
|`web`|`nginx`|`reload`|No connection drops. The NixOS unit's `ExecReload` runs `nginx -t` first, so the command adds no second test; a bad config leaves the old workers.|
|`pgx`|`pgx`|restart|Drops the open database connections.|
|`room`|`room-listeners`|restart|The live listeners count starts from zero.|
|`loco`|every `loco-<app>.service` (not the `loco-<app>-backup.service` oneshot)|restart|The app is down for a few seconds.|
|`rig`|`openrig`|restart|Ends every live seat. The plan says how many tmux sessions run. Bring a rig back with the skill `hermes-rig`.|
|`hermes`|`hermes-agent`, then `hermes-backend`|restart|`hermes-agent` ends every running agent task, a coding run included. `hermes-backend` closes the dashboard for a few seconds.|

`all` (the default) runs metrics, web, pgx, room, loco, rig, hermes in that order. The unit that
holds the agent's own session is last, so a failure on the way shows while your session lives.
For `hermes`, the command restarts `hermes-agent`, waits until it is `active` (at most 60 s), and
only then restarts `hermes-backend`: a dashboard that starts with no gateway can start a stray
one outside the unit (the loop of 2026-11-05). Then the command checks that every `gateway run`
process is in the cgroup of `hermes-agent.service`, and prints `ok` or
`WARN stray gateway pid N in <cgroup>`.

```console
just remote-restart                                  # every service this box has, after the prompt
just remote-restart hermes                           # one group: metrics web pgx room loco rig hermes
just remote-restart list                             # the plan; changes nothing
just remote-restart "hermes --dry-run"               # the plan and the exact systemctl lines; changes nothing
just remote-restart "all --yes"                      # no prompt
just remote-restart all h0ffmann <address>           # the other box (piabrota2: its address)
```

Put the flags inside the quoted first argument. Unquoted, `just` reads `--yes` and `--dry-run` as its own options. The command prints the plan, each unit with its verb
and its cost, and asks `Proceed? [y/N]`. It asks on the terminal (`ssh -t`, `/dev/tty`), not on
stdin. With no terminal and no `--yes` it refuses. Afterwards it prints a table (unit, `is-active`,
`NRestarts`, `ActiveEnterTimestamp`). It prints no journal line and no environment, because a
line can hold a secret: read the journal on the box with the `journalctl` command it names. Each
run puts its command line in the `sudo` line of the box's journal.

|Exit|Meaning|
|---|---|
|0|Every unit is as wanted: active, or a finished oneshot. A group that the box lacks is not an error.|
|1|A unit is not as wanted (the line names it and gives `journalctl -u <unit> -n 50`), or a stray gateway runs.|
|2|Usage error, no root, the prompt was answered no, or there was no terminal and no `--yes`.|

`scala/scripts/RestartServices.test.scala` tests it offline (`just scala-test`).

## Disk

Every deploy deletes all system generations but the last five. `deploy.nix` keeps the same five
generations in the boot menu, collects store paths older than 14 days each week, collects
garbage when free disk falls under 2 GiB (until 8 GiB are free: `min-free`, `max-free`),
deduplicates the store once a week (not during a deploy), and leaves the nixpkgs source (about
200 MiB) out of the system. The VPS runs at most one build job on one core, so a build that
starts there by mistake cannot use all the RAM.
