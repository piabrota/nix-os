# Moving Hermes from KVM 1 to KVM 4

A checklist, in order. After it, **VPS 1 (KVM 1, `piabrota`)** serves the public web only, and
**VPS 2 (KVM 4, `kvm4`)** runs Hermes, its GitHub App, its dashboard on `hermes.piabrota.art`,
and PGX. [www.piabrota.art/hosts](https://www.piabrota.art/hosts) and the README's first figure
show the split. English only.

**One rule:** do not merge the pull request that moves Hermes until KVM 4 has had its first deploy
and runs Hermes. That merge takes Hermes off KVM 1, and `deploy.yml` skips KVM 4 until it has
the secret `DEPLOY_HOST_KVM4`. Merged too early, Hermes is down until KVM 4 is up.

Commands that start with `ssh kvm1` or `ssh kvm4` run from your computer: `kvm1` is
`h0ffmann@piabrota.art`, `kvm4` is `h0ffmann@<KVM 4 IPv4>` (or `root@` before the first
deploy, as the template set up).

## 1. The new VPS (KVM 4), before the merge

Hermes on KVM 1 keeps working during all of section 1.

- [ ] **Empty VPS.** Follow [docs/DEPLOY.md](DEPLOY.md), "A second host", steps 1 to 5: the
  NixOS template with your SSH key and a snapshot, a look at the hostname, the host key and
  `/etc/nixos/`, the hostname in `hosts/kvm4/default.nix`, the secret `DEPLOY_HOST_KVM4` and
  kvm4's line in `DEPLOY_KNOWN_HOSTS`, port 22. Nothing is cloned on the VPS. The hostname
  (`piabrota2`, the VPS name in hPanel) is already in this same pull request. After the first
  deploy, check that `hostname` on the VPS prints `piabrota2`. Hostinger's own address for the VPS,
  `srv2125808.hstgr.cloud`, does not change.
- [ ] **Firewall.** In hPanel, open TCP 80 and 443 on KVM 4 too, beside 22: Let's Encrypt checks
  port 80, and the dashboard is on 443.
- [ ] **DNS.** At Porkbun (the name servers of `piabrota.art`), add one record:
  type `A`, host `hermes`, answer KVM 4's IPv4 address, TTL 600. Take the address from hPanel,
  **VPS > Overview**. Do not touch the records for `piabrota.art` and `www`: they stay on KVM 1.
  Add no `AAAA` record yet. KVM 4 has an IPv6 address, and Let's Encrypt prefers it when a record
  exists, so the IPv6 firewall of hPanel must open ports 80 and 443 first. There is no `CAA`
  record on the domain, so Let's Encrypt may issue. Check it:
  `dig +short hermes.piabrota.art` prints the address. Without the record, the ACME order for the
  dashboard fails on the first deploy, and deploy-rs rolls KVM 4 back.
- [ ] **First deploy** ("A second host", step 6), from your computer on this branch, not from
  GitHub: a manual run of `deploy.yml` on a branch other than `main` only builds.

  ```console
  git switch claude/project-hermes-web-dashboard
  DEPLOY_HOST=<KVM 4 IPv4> just deploy root kvm4   # or h0ffmann, whichever the template set up
  ```

- [ ] **The dashboard's password**, on KVM 4 ([docs/HERMES.md](HERMES.md), "The web
  dashboard", "Turning it on", step 2). Until the file exists, the dashboard answers 500.
- [ ] **Check KVM 4 after its first deploy.**

  ```console
  ssh deploy@<KVM 4 IPv4> true                       # the deploy user works: CI can deploy
  ssh kvm4 systemctl is-active hermes-agent hermes-backend nginx
  curl -s -o /dev/null -w '%{http_code}\n' https://hermes.piabrota.art/   # 401
  ```

  Hermes runs here with no secrets yet, so with no chat platform: it does not answer on Telegram
  and cannot clash with KVM 1.

## 2. The cutover (Hermes is down for a few minutes)

Do these steps in one sitting, right before the merge. Two gateways on one token of Telegram,
Discord or Slack clash (Telegram answers 409 Conflict), so KVM 1's stops before KVM 4's gets the
token.

- [ ] **Stop Hermes on KVM 1.** Hermes runs each cron job in its own user scope, so stopping the
  unit can leave a job that still writes `state.db` and still posts from KVM 1. Stop the user
  manager of the `hermes` user too (if that unit exists), and check that no process of `hermes`
  is left before the copy starts. `pgrep` must print nothing.

  ```console
  ssh kvm1 sudo systemctl stop hermes-agent hermes-github-token.timer hermes-github-token
  ssh kvm1 'sudo systemctl stop "user@$(id -u hermes).service"'
  ssh kvm1 pgrep -u hermes -a
  ```

- [ ] **Stop Hermes on KVM 4**, so nothing writes while the state arrives. KVM 4 ran Hermes in
  section 1, so it has its own `state.db`, WAL files and sessions. Move them aside first: an
  extract over them can mix two databases.

  ```console
  ssh kvm4 sudo systemctl stop hermes-agent hermes-backend
  ssh kvm4 'sudo mv /var/lib/hermes /var/lib/hermes.kvm4-first'
  ```

- [ ] **Copy the state and the secrets** from KVM 1 to KVM 4, through your computer (the two VPSs
  have no SSH access to each other). `/var/lib/hermes` holds the memory, the sessions, the cron
  jobs and the skills Hermes wrote; `/var/lib/hermes-secrets` holds `hermes.env` (the Claude
  token, the bot tokens and allowed users) and `github-app.env` (the App's key). Nothing is
  printed or written on your disk.

  The copy leaves out `config.yaml`. Activation deep-merges the settings of `hermes.nix` into the
  `config.yaml` on disk and never deletes a key, so KVM 1's file would bring back its old limits.
  Activation writes a fresh `config.yaml` from `hermes.nix` instead. A setting that you changed
  by hand with `hermes config set` on KVM 1 is not carried over.

  ```console
  set -o pipefail
  ssh kvm1 'sudo tar -C /var/lib -czf - hermes hermes-secrets' \
    | ssh kvm4 'sudo tar -C /var/lib --exclude=hermes/.hermes/config.yaml -xzf -'
  ssh kvm4 'sudo chown -R hermes:hermes /var/lib/hermes \
    && sudo chown -R root:root /var/lib/hermes-secrets && sudo chmod 700 /var/lib/hermes-secrets \
    && sudo find /var/lib/hermes-secrets -type f -exec chmod 600 {} +'
  ```

  If the copy prints an error, run `ssh kvm4 sudo rm -rf /var/lib/hermes` and copy again. The
  old state of KVM 4 is safe in `/var/lib/hermes.kvm4-first`.

- [ ] **Check the copy.** Count the files on both sides. The two numbers must match, except for
  `config.yaml`: KVM 4 has one file less.

  ```console
  ssh kvm1 'sudo find /var/lib/hermes /var/lib/hermes-secrets | wc -l'
  ssh kvm4 'sudo find /var/lib/hermes /var/lib/hermes-secrets | wc -l'
  ```

- [ ] **Start Hermes on KVM 4.** Activation copies `hermes.env` into Hermes's `.env` and rewrites
  the plugin links, which still point at KVM 1's store paths.

  ```console
  ssh kvm4 'sudo /run/current-system/bin/switch-to-configuration switch \
    && sudo systemctl restart hermes-agent hermes-backend hermes-github-token'
  ```

- [ ] **Check Hermes on KVM 4.**
  - `DEPLOY_HOST=<KVM 4 IPv4> just remote-hermes-check`: the unit, the plugins, the skills, omp.
  - Send Hermes a message on Telegram or Discord; it answers.
  - Open `https://hermes.piabrota.art`, log in, and see the old sessions under **Sessions**.
- [ ] **Optional: PGX's data.** Nothing uses PGX today, and it is for data you can lose. To keep
  it anyway: `ssh kvm1 sudo systemctl stop pgx`, and also `ssh kvm4 sudo systemctl stop pgx`
  before the extract, then the same tar pipe for `/var/lib/pgx`, then `chown -R pgx:pgx` and
  `systemctl restart pgx` on KVM 4.
- [ ] **Merge the pull request** (with #84 in it, or after #84). `deploy.yml` deploys both:
  KVM 1 loses Hermes, its GitHub App and PGX; KVM 4 gets the same system it already runs. Merge
  soon after the cutover: until then, any other deploy to KVM 1 starts its Hermes again, and the
  two gateways clash on the token.

## 3. The existing VPS (KVM 1), after the merge

- [ ] **Check that KVM 1 dropped Hermes**, and that the web still answers.

  ```console
  ssh kvm1 systemctl status hermes-agent      # Unit hermes-agent.service could not be found.
  curl -sI https://www.piabrota.art/ | head -1
  curl -sI https://www.piabrota.art/hosts/ | head -1
  ```

- [ ] **Wait a week, then delete what is left on KVM 1.** Until then a revert of the merge brings
  Hermes back on KVM 1 with its old state. After a week:

  ```console
  ssh kvm1 sudo rm -rf /var/lib/hermes /var/lib/hermes-secrets /var/lib/pgx
  ```

  The `hermes` and `pgx` users and groups may stay in `/etc/passwd`; they own nothing and run
  nothing.
- [ ] **Delete KVM 4's first state**, after the check of section 2 passes:
  `ssh kvm4 sudo rm -rf /var/lib/hermes.kvm4-first`.
- [ ] **Update the numbers.** After a deploy, `just remote-specs` (KVM 1) and
  `DEPLOY_HOST=<KVM 4 IPv4> just remote-specs` (KVM 4) give the real figures; change
  `AGENTS.md`, "Resource budget", if they differ from Hostinger's plan list.

## If something goes wrong

- KVM 4's first deploy fails: deploy-rs rolls it back by itself, and KVM 1 still runs Hermes.
  Fix it in this pull request and deploy again by hand.
- Hermes on KVM 4 misbehaves after the cutover: stop it on KVM 4, start it on KVM 1
  (`systemctl start hermes-agent hermes-github-token.timer`), and leave this pull request
  unmerged. If it was already merged, revert the merge: the next deploy puts Hermes back on KVM 1,
  whose state is still there.
