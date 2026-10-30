# Use nix-os for your own VPS

[Português](FORK.ptBR.md) (the first version; this page is its English mirror)

nix-os runs one Hostinger VPS with NixOS and deploys it from GitHub. You can fork it and run your
own VPS the same way. This page lists every change and every manual step. The steps that only you
can do (on Hostinger, on GitHub, on your machine) are marked **manual**.

The configuration, the system and the deploy node keep the name `piabrota`. That name is only a
label; you can keep it. To change it, change it in `flake.nix`, `.github/workflows/deploy.yml`
and `justfile` together.

## 1. Fork and get a VPS

1. **Manual, GitHub.** Fork `piabrota/nix-os`. On your fork, open the **Actions** tab and enable
   the workflows: GitHub turns them off on a new fork.
2. **Manual, Hostinger.** Get a KVM VPS and install the NixOS template from hPanel
   (**VPS > OS & Panel > Operating System**). `configuration.nix` is written for that template:
   BIOS GRUB on `/dev/sda`, cloud-init, the QEMU guest agent. ⚠ The menu path is how hPanel shows
   it on 2026-10-29; Hostinger can move it. piabrota runs on the **KVM 1** plan (1 vCPU core,
   4 GB RAM, 50 GB disk, 4 TB bandwidth a month); the configuration is sized for it.
3. **Manual, Hostinger.** Take a snapshot of the new VPS (**Snapshots & Backups**), so that you
   can go back to a clean system.

## 2. Make the repository yours

Edit these files in your fork:

| File | Change |
|---|---|
| `piabrota.nix` | Rename the user `h0ffmann` to your user, and put your own SSH public key in `openssh.authorizedKeys.keys`. Change the user in `nix.settings.trusted-users` too. |
| `.github/workflows/deploy.yml` | In `ssh_user`, `options: [deploy, h0ffmann]`: put your user in place of `h0ffmann`. |
| `justfile` | `remote-specs` and `remote-freeze`: your user in place of `h0ffmann`. |
| `flake.nix` | `deploy.nodes.piabrota.hostname`: your domain or IP. CI uses the `DEPLOY_HOST` secret, so this is only the default for `just deploy`. |
| `site.nix`, `site/` | In `piabrota.site`, put your own `domain`, `redirectFrom` and `redirects`, and your own files in `site/`. `configuration.nix` turns it on: set `piabrota.site.enable = false` there until DNS points at your VPS ([`SITE.md`](SITE.md)). |
| `README.md`, `docs/drawings/` | The drawing and the text describe this repository. Change them or keep them, with the credits. |

Do not remove the settings that `AGENTS.md` lists under "Do not break the machine". Hostinger
provisions the VPS through them.

## 3. The deploy key and the secrets

1. **Manual, your machine.** Make the key that GitHub Actions logs in with:

   ```sh
   ssh-keygen -t ed25519 -N '' -C github-actions-deploy -f nix-os-deploy
   ```

2. Replace the key line in `keys/deploy.pub` with the content of `nix-os-deploy.pub`, and commit
   it. This is the public half; it stays in the repository.
3. **Manual, GitHub.** In your fork, open **Settings > Environments**, create the environment
   `prod`, and add three secrets:

   | Secret | Value |
   |---|---|
   | `DEPLOY_SSH_KEY` | the content of `nix-os-deploy` (the private key) |
   | `DEPLOY_HOST` | the IPv4 address of the VPS (hPanel, **VPS > Overview**) |
   | `DEPLOY_KNOWN_HOSTS` | one line, `<ip> ssh-ed25519 AAAA…`: the IP, a space, then the output of `cat /etc/ssh/ssh_host_ed25519_key.pub` on the VPS |

   Set **Deployment branches** to `main` only. Then delete `nix-os-deploy` from your machine.
4. **Manual, Hostinger.** If the VPS firewall is on (**VPS > Security > Firewall**), accept TCP
   port 22 from any address. GitHub runners connect from many addresses.

## 4. The first deploy

The `deploy` user that CI logs in as does not exist on a new VPS. Make it once, with one of these:

- **Manual, on the VPS**, as root or as the user of the template:

  ```sh
  sudo nixos-rebuild test --flake 'github:<you>/nix-os#piabrota'
  # check from your machine: ssh -i nix-os-deploy deploy@<ip> true
  sudo nixos-rebuild switch --flake 'github:<you>/nix-os#piabrota'
  ```

  `test` does not add a boot entry, so a reboot goes back to the old system if something fails.
  This builds on the VPS, the only time it does.

- **Manual, your machine, with Nix:** `DEPLOY_HOST=<ip> just deploy <your-user>`.

## 5. From then on

Every merge to `main` builds the system on GitHub and deploys it (`docs/DEPLOY.md`). A switch
that breaks SSH rolls back by itself. Change the system in a pull request; CI builds it first.

## License and credit

nix-os is MPL-2.0 (`LICENSE`). Keep the license file and the credits in `README.md` and
`docs/drawings/README.md` in your fork.
