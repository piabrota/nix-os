# Deploys (GitOps)

Every change to the VPS goes through GitHub. A push to `main` runs `.github/workflows/deploy.yml`:

1. The GitHub runner builds the whole system (`nixosConfigurations.piabrota`). The VPS builds
   nothing, so its small CPU, RAM and disk are not used for compiles.
2. [deploy-rs](https://github.com/serokell/deploy-rs) copies the result to the VPS over SSH. The
   VPS downloads what `cache.nixos.org` has by itself; the runner uploads only the rest (for
   example `claude-code`, which is unfree and not in the cache).
3. deploy-rs activates the new system and then opens a new SSH connection. If that connection
   fails within 60 seconds (a bad firewall or sshd change), the VPS rolls back to the previous
   generation by itself ("magic rollback").
4. The job prints `scripts/specs.sh` from the VPS into the run summary.

Every pull request runs `.github/workflows/ci.yml`: `nix flake check` (it builds the system and
checks the deploy-rs node), `nixpkgs-fmt` on the Nix files of the deploy, `shellcheck`, and a
parse of every justfile with the `just` of Ubuntu 24.04 (1.21.0).

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

In `piabrota/nix-os`, open **Settings > Environments**, create the environment `production`,
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

From your machine, with Nix, in a clone of this repository:

```sh
DEPLOY_HOST=<ip> just deploy h0ffmann
```

This builds on your machine, copies to the VPS and activates, with the same rollback as CI.
After it, `ssh deploy@<ip>` must work with the key of step 1. From then on, every merge to
`main` deploys by itself, and you can start a deploy again from the **Actions** tab
(`deploy`, **Run workflow**).

## Every day

- Change the configuration in a pull request. CI builds it. Merge, and the deploy runs.
- `just specs` on the VPS, or `DEPLOY_HOST=<ip> just remote-specs` from your machine, prints
  the CPU, RAM, disk, kernel and NixOS generation.
- To go back, revert the commit and merge the revert. In an emergency, on the VPS:
  `sudo nixos-rebuild switch --rollback`. The next merge to `main` deploys again over it.
- To update nixpkgs: `nix flake update` in a pull request.

## Disk

`deploy.nix` keeps five generations in the boot menu, collects store paths older than 14 days
each week, and deduplicates the store. The VPS runs at most one build job on one core, so a
build that starts there by mistake cannot use all the RAM.
