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
  kvm4's line in `DEPLOY_KNOWN_HOSTS`, port 22. Nothing is cloned on the VPS. The hostname goes
  into this same pull request: send it (srvNNNNNNN, from hPanel or `hostname`) and it is committed
  here, or commit it yourself.
- [ ] **Firewall.** In hPanel, open TCP 80 and 443 on KVM 4 too, beside 22: Let's Encrypt checks
  port 80, and the dashboard is on 443.
- [ ] **DNS.** At Porkbun, an `A` record `hermes.piabrota.art` with KVM 4's IPv4 address (an
  `AAAA` only if KVM 4 has IPv6). Check it: `dig +short hermes.piabrota.art`. Without it the ACME
  order for the dashboard fails on the first deploy, and deploy-rs rolls KVM 4 back.
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

Do these steps in one sitting, right before the merge. Two gateways on one Telegram token both
fail (409 Conflict), so KVM 1's stops before KVM 4's gets the token.

- [ ] **Stop Hermes on KVM 1.**

  ```console
  ssh kvm1 sudo systemctl stop hermes-agent hermes-github-token.timer hermes-github-token
  ```

- [ ] **Stop Hermes on KVM 4**, so nothing writes while the state arrives.

  ```console
  ssh kvm4 sudo systemctl stop hermes-agent hermes-backend
  ```

- [ ] **Copy the state and the secrets** from KVM 1 to KVM 4, through your computer (the two VPSs
  have no SSH access to each other). `/var/lib/hermes` holds the memory, the sessions, the cron
  jobs and the skills Hermes wrote; `/var/lib/hermes-secrets` holds `hermes.env` (the Claude
  token, the bot tokens and allowed users) and `github-app.env` (the App's key). Nothing is
  printed or written on your disk.

  ```console
  ssh kvm1 'sudo tar -C /var/lib -czf - hermes hermes-secrets' \
    | ssh kvm4 'sudo tar -C /var/lib -xzf -'
  ssh kvm4 'sudo chown -R hermes:hermes /var/lib/hermes \
    && sudo chown -R root:root /var/lib/hermes-secrets && sudo chmod 700 /var/lib/hermes-secrets \
    && sudo chmod 600 /var/lib/hermes-secrets/*'
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
  it anyway: `ssh kvm1 sudo systemctl stop pgx`, the same tar pipe for `/var/lib/pgx`, then
  `chown -R pgx:pgx` and `systemctl restart pgx` on KVM 4.
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
