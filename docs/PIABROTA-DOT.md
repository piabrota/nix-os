# piabrota-dot

piabrota-dot is a bot with no model. Once a day it checks for a new release of Hermes Agent or
OpenRig and opens a pull request on piabrota/nix-os. It is its own GitHub App (`piabrota-dot[bot]`).
`piabrota-dot.nix` sets it up; the code is in `piabrota-dot/`.

## What it is and what it never does

- It is a script (`piabrota-dot/run.sh`: git, gh, jq and nix). It calls no model and uses no network
  except GitHub and the `nix` downloads.
- It opens, or refreshes, **one** pull request for each component, on the fixed branch
  `piabrota-dot/hermes` or `piabrota-dot/openrig`. It changes only the pin files: `flake.nix`,
  `flake.lock` and `hermes.nix` (Hermes); `openrig/package.nix` (OpenRig). If the diff touches any
  other file, it opens no pull request and opens an issue.
- If a new release does not evaluate (`nix eval`), it opens **one** issue for that release and no
  pull request.
- It touches only the pull requests and issues that it opened itself.
- It **never** changes the ruleset, never pushes to `main`, never uses `workflows` or
  `administration`. Its token reaches only `piabrota/nix-os`.
- The merge is **off**. See "The merge switch".
- It does not build and it starts nothing: `deploy.yml` does that, at the merge.

## A day at 14:00

1. The timer `piabrota-dot.timer` fires at 14:00 `America/Sao_Paulo`.
2. The unit `piabrota-dot-token` (root) makes a new one-hour token for `piabrota/nix-os` only.
3. The unit `piabrota-dot` (user `piabrota-dot`) updates the clone in `/var/lib/piabrota-dot/nix-os`.
4. For `hermes`, then `openrig`, it runs `scripts/<component>-bump.sh --check` from the clone. Exit 0:
   current. Exit 10: a newer release exists. Any other exit: failure.
5. With a newer release: it runs the bump script, checks the list of files, evaluates `piabrota` and
   `piabrota2` (evaluation only, no build), commits, pushes the branch and opens or refreshes the pull
   request, with the label `piabrota-dot`.
6. It writes `/var/lib/piabrota-dot/last-run.txt`. The first line is `piabrota-dot: nothing new` when
   nothing changed.
7. At 14:15 a Hermes cron job (no agent) delivers that file to Discord, once, when it changed. A day
   with nothing new sends no message.

A second run on the same day with nothing new changes nothing and prints nothing. The unit has
`MemoryMax=3G`: each evaluation peaks at about 0.95 GB of resident memory (measured on this box), one
after the other.

## Why two stages

Hermes is an agent and **never** merges. piabrota-dot can merge (if the owner turns it on). If the
bot's token were in Hermes's reach, Hermes could merge. So:

- The App's key is in `/var/lib/piabrota-secrets/piabrota-dot.env`, root only.
- The unit `piabrota-dot-token` (root) reads the key and writes the token to `/run/piabrota-dot/token`
  (mode 0400, owner `piabrota-dot`). The folder is `root:piabrota-dot` 0750.
- The user `piabrota-dot` has no shell, no `sudo`, and is not in the `hermes` group. The `hermes` user
  is not in the `piabrota-dot` group. It reads neither the token nor the key.
- The Hermes cron job, which runs as `hermes`, only **reads** `last-run.txt`, which is public and holds
  no secret. The state folder is mode 0751 (not 0750): Hermes can enter it and read that one file by
  name, but cannot list it. Everything else is in 0700 subfolders.

## Create the GitHub App

Once, in the browser:

1. GitHub, **Settings**, **Developer settings**, **GitHub Apps**, **New GitHub App**. (For the
   organisation: github.com/organizations/piabrota/settings/apps.)
2. Name `piabrota-dot`. Homepage: `https://piabrota.art`. **Webhook** off.
3. Under **Repository permissions**: **Contents** read and write, **Pull requests** read and write,
   **Issues** read and write, **Metadata** read. Nothing else (no Workflows, no Administration).
4. **Where can this GitHub App be installed**: only on this account.
5. **Create GitHub App**. Note the **App ID**.
6. On the App's page, **Generate a private key**. A `.pem` downloads.
7. **Install App**: install it only on `piabrota/nix-os` (**Only select repositories**).

## Put the key on the box

The format is the one of `hermes-github.nix`: the lines `GH_APP_ID` and `GH_APP_PRIVATE_KEY_B64`. The
names are the same, so you repeat a step that you know.

```console
base64 < piabrota-dot.*.private-key.pem | tr -d '\n'     # on your computer: copy the output
ssh h0ffmann@hermes.piabrota.art
sudo install -d -m 700 /var/lib/piabrota-secrets
sudo install -m 600 /dev/stdin /var/lib/piabrota-secrets/piabrota-dot.env    # paste, end with Ctrl-D
GH_APP_ID=<the App ID>
GH_APP_PRIVATE_KEY_B64=<the base64 line>
```

The commands do not print the key. Delete the `.pem` from your computer when it works: you can
generate another any time.

## Test by hand

```console
sudo systemctl start piabrota-dot-token
journalctl -u piabrota-dot-token -n 5     # "piabrota/nix-os: token for one hour"
sudo -u piabrota-dot piabrota-dot --dry-run
```

`--dry-run` runs every step (clone, bump, `nix eval`) and **prints** each GitHub write without making
it. It does not write `last-run.txt` either. Run by hand, it has no unit sandbox and writes to the
terminal, not to the journal. For a real run, the same as at 14:00:

```console
sudo systemctl start piabrota-dot
journalctl -u piabrota-dot -n 40
cat /var/lib/piabrota-dot/last-run.txt
```

A real run opens real pull requests.

## The delivery at 14:15

Only after the merge, once, as `hermes` (the owner creates the job; the code does not):

```console
sudo -u hermes hermes cron create "15 14 * * *" --name piabrota-dot-report \
  --no-agent --script piabrota-dot-report.sh --deliver discord:<channel ID>
sudo -u hermes hermes cron list
sudo -u hermes hermes cron run <id>      # one run: it prints nothing when nothing changed
```

Use the same target as the `skills-export` job (see `hermes cron list`). The time zone
`America/Sao_Paulo` comes from Hermes's `settings.timezone`. The script
(`hermes/scripts/piabrota-dot-report.sh`, installed by `hermesHomeFiles`) keeps what it delivered in
`$HERMES_HOME/piabrota-dot-delivered`. The `time:` line is left out of the comparison. A failure
(`piabrota-dot failed: ...`) is delivered once.

## The merge switch

`piabrota.dot.merge.hermes` and `piabrota.dot.merge.openrig`. Both are `false`. **Turning one on is a
decision of the owner.**

- A merge to `main` is a deploy.
- An **OpenRig** merge: the daemon runs new database migrations at its first start. They only go
  forward. First run `rig snapshot` and copy the daemon database. The merge restarts the `openrig` unit
  and ends every live seat.
- A **Hermes** merge: it restarts `hermes-agent` and `hermes-backend` and ends the agent's own runs.

With the switch on, the bot merges **its own** pull request for that component only if **all** of
this holds: the author is `piabrota-dot[bot]`; it is not a draft; the head is the commit the bot
pushed; the diff touches only the pin files; every check run and status on the head is finished and
green (an empty list is **not** green; a pending check waits for the next day). The merge is `squash`,
through the API, **once**. If the ruleset refuses, the bot does not retry, does not look for a way
round, and writes `merge refused by the ruleset` in `last-run.txt`.

**The ruleset is the real gate.** The owner sets it in GitHub. This code does not bypass it and must
not. The App has no permission to change the ruleset. Without required checks in the ruleset, the only
brake on a merge is the bot's own gate.

## Stop it

- Remove the key: `sudo rm /var/lib/piabrota-secrets/piabrota-dot.env`. Both units then do nothing and
  do not fail. The last token stays valid for one hour at most.
- Or set `piabrota.dot.enable = false` in `hosts/piabrota2/default.nix` and deploy.
- Remove the cron job: `sudo -u hermes hermes cron remove <id>`.
- To stop only the merge: `merge.hermes = false` and `merge.openrig = false`.

## What it checks and what it does not

It checks: that the bump script changes only the pin files; that `piabrota` and `piabrota2` evaluate
(`nix eval ...toplevel.drvPath`); that the GitHub checks are green (only for the merge).

It does not check: the build (`deploy.yml` does it, at the merge); a live start of Hermes or OpenRig;
the OpenRig migrations; how the ruleset behaves.

## Files

| File | What it is |
|---|---|
| `piabrota-dot.nix` | The `piabrota.dot.*` options, the user, the two units and the two timers. |
| `piabrota-dot/run.sh` | The daily step. |
| `piabrota-dot/mint-token.sh` | Makes the one-hour token (root). |
| `piabrota-dot/git-credential.sh` | Gives the token to git without a URL. |
| `piabrota-dot/test/run.sh` | Offline tests: `sh piabrota-dot/test/run.sh`. |
| `hermes/scripts/piabrota-dot-report.sh` | The 14:15 delivery. |
