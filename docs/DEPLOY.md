# Deploys (GitOps)

Every change to the VPS goes through GitHub. A push to `main` runs `.github/workflows/deploy.yml`:

1. The GitHub runner builds the whole system of each host (`nixosConfigurations.piabrota`,
   `nixosConfigurations.kvm4`; see "A second host"). The VPS builds
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
5. The job prints `scripts/specs.sh` from the VPS into the run summary.

Every pull request runs `.github/workflows/ci.yml`: `nixpkgs-fmt`, `statix`, `deadnix`,
`shellcheck`, the figure check, and a parse of every justfile with the `just` of Ubuntu 24.04
(1.21.0). These build nothing. The full `nix flake check` (it builds the system, the VM test and
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

The repository deploys two hosts: `piabrota` (KVM 1) and `kvm4` (KVM 4). Each is a directory in
`hosts/` that imports `configuration.nix` (what both share) and the roles it runs. Every merge
builds both systems in one job and deploys each in its own job. A host that has no address secret
is skipped with a notice, so `piabrota` keeps deploying while `kvm4` is being set up.

To bring `kvm4` up from a new, empty VPS, once. Nothing is cloned or built on the VPS: the
repository stays on GitHub (and on your machine), and the VPS only receives the built system.

1. **hPanel, the OS.** Install the NixOS template on the KVM 4 VPS (**VPS > OS & Panel >
   Operating System**, as in docs/FORK.md), with your SSH public key. `configuration.nix`'s boot
   and disk settings are that template's. Take a snapshot (**Snapshots & Backups**), so you can
   go back to a clean system.
2. **The VPS, a look.** Log in with the account the template set up for your key (`root` or
   `h0ffmann`). Note the hostname (`hostname`, srvNNNNNNN), print the host key
   (`cat /etc/ssh/ssh_host_ed25519_key.pub`) and look at `/etc/nixos/`. If its
   `hardware-configuration.nix` names another disk or label than `/dev/sda` and `nixos`, add it
   to `hosts/kvm4/` and import it.
3. **The repository.** In a pull request, set `networking.hostName` in `hosts/kvm4/default.nix`
   to that hostname. Merge it; kvm4 is still skipped, because it has no address secret yet.
   For the move of Hermes, follow [MIGRATION-KVM4.md](MIGRATION-KVM4.md): put the hostname in
   that pull request, and do not merge it first. A merge before kvm4 runs Hermes takes Hermes
   down.
4. **GitHub.** In the `prod` environment, add the secret `DEPLOY_HOST_KVM4` (the IPv4 address
   from **VPS > Overview**), and add the line `<ip> ssh-ed25519 AAAA...` to `DEPLOY_KNOWN_HOSTS`,
   under piabrota's line. `DEPLOY_SSH_KEY` stays the same: `keys/deploy.pub` is on both hosts.
5. **hPanel, the firewall.** Open TCP port 22 from any address, as in step 4 above.
6. **The first deploy**, before the `deploy` user exists on the VPS, in one of two ways:
   - From your machine, with Nix, in a clone of this repository:
     `DEPLOY_HOST=<ip> just deploy root kvm4` (or `h0ffmann` instead of `root`, whichever
     account step 2 used).
   - From GitHub, if the account is `h0ffmann`: add the line of `keys/deploy.pub` to
     `~h0ffmann/.ssh/authorized_keys` on the VPS, run **Actions > deploy > Run workflow** with
     **Host** `kvm4` and **SSH user** `h0ffmann`, then remove the line again (step 5 above shows
     the commands).
   For the move of Hermes, follow [MIGRATION-KVM4.md](MIGRATION-KVM4.md): put the hostname in
   that pull request, and do the first deploy from your computer. A deploy from GitHub runs only
   on `main`, so it needs the merged pull request.
   After it, `ssh deploy@<ip>` works, and every merge to `main` deploys kvm4 too.
7. **Hermes's secrets.** Write `/var/lib/hermes-secrets/hermes.env` (and `github-app.env` for
   the GitHub App) on the VPS, as docs/HERMES.md says. Copy them from piabrota at the cutover
   (MIGRATION-KVM4.md): two gateways on one Telegram token both fail. Hermes starts with no
   platform until the file exists, so step 6 does not wait on it.

Hermes, its GitHub App, its dashboard and PGX moved from piabrota to kvm4; piabrota serves the
public web only. [MIGRATION-KVM4.md](MIGRATION-KVM4.md) is the checklist of that move: kvm4's
first deploy before the merge, the cutover of the state and the secrets, and what is left on
piabrota.

## Every day

- Change the configuration in a pull request. CI builds it. Merge, and the deploy runs.
- `just specs` on the VPS, or `DEPLOY_HOST=<ip> just remote-specs` from your machine, prints
  the CPU, RAM, disk, kernel and NixOS generation.
- To go back, revert the commit and merge the revert. In an emergency, on the VPS:
  `sudo nixos-rebuild switch --rollback`. The next merge to `main` deploys again over it.
- To update nixpkgs: `nix flake update` in a pull request.

## Disk

Every deploy deletes all system generations but the last five. `deploy.nix` keeps the same five
generations in the boot menu, collects store paths older than 14 days each week, collects
garbage when free disk falls under 2 GiB (until 8 GiB are free: `min-free`, `max-free`),
deduplicates the store once a week (not during a deploy), and leaves the nixpkgs source (about
200 MiB) out of the system. The VPS runs at most one build job on one core, so a build that
starts there by mistake cannot use all the RAM.
