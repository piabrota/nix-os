# Loco apps on the VPS

`loco.nix` runs [Loco](https://loco.rs) apps: Rust web apps on SQLite. Each app is a systemd
service behind nginx, with HTTPS from Let's Encrypt and a nightly copy of its database. Until an
app is declared, the module adds nothing to the system.

## What the box gives each app

| Part | What it is |
|---|---|
| Service `loco-<app>` | `<app>-cli start` as the system user `loco-<app>`, `LOCO_ENV=production`, on `127.0.0.1:<port>`; restarts on failure; `MemoryMax=256M` by default; sandboxed (no capabilities, read-only system, private `/tmp` and devices, no new privileges) |
| SQLite | `DATABASE_URL=sqlite:///var/lib/loco-<app>/db.sqlite?mode=rwc`; the state directory is the one place the app can write |
| Backups | `loco-<app>-backup`, daily: `sqlite3 .backup` into `/var/lib/loco-<app>/backup/`, seven days kept |
| nginx | a virtual host per `domain`, HTTP to HTTPS, WebSockets proxied, gzip, no version in headers |
| ACME | a Let's Encrypt certificate per domain (lego, renewed by a timer) |
| Firewall | 80 and 443 open, only once an app exists |
| Variables | `PORT`, `NODE_PORT`, `BINDING`, `HOST`, `DATABASE_URL`, plus `environment`; secrets from `environmentFile` |

No Postgres and no Redis: both are resident daemons that this machine cannot afford. Run
background jobs in the same process: `workers.mode: BackgroundAsync`, or a SQLite queue
(`queue.kind: Sqlite`) with `extraArgs = [ "--server-and-worker" ]`.

The first app adds 83.6 MiB to the closure (lego 66 MiB, OpenSSL 4 for nginx 8.7 MiB, the sqlite
CLI, nginx 2.2 MiB), measured with `dix` on nixos-26.05 `08d3a97` on 2026-10-29. Each later app
adds only its own package.

## Add an app

1. **Package it with Nix in its own repository.** The flake's package must have the binary in
   `bin/` and the files Loco reads beside it in `share/<app>/`:

   ```nix
   packages.x86_64-linux.default = pkgs.rustPlatform.buildRustPackage {
     pname = "myapp";
     version = "0.1.0";
     src = ./.;
     cargoLock.lockFile = ./Cargo.lock;
     doCheck = false; # the tests need a database; run them in the app's own CI
     postInstall = ''
       mkdir -p $out/share/myapp
       cp -r config $out/share/myapp/
       [ -d assets ] && cp -r assets $out/share/myapp/ || true
     '';
   };
   ```

   In `config/production.yaml`, read the port, binding, host and database from the
   environment (`{{ get_env(name="PORT", default="5150") }}` and so on) and keep secrets
   such as the JWT secret as `get_env` too. Check it with `myapp-cli doctor --production`.

2. **Point DNS at the box.** An A record (and AAAA, if any) for the domain must point at the
   VPS before the deploy, or the ACME order fails.

3. **Write the secrets on the box, by hand.** Never in this repository:

   ```console
   sudo install -d -m 700 /var/lib/loco-secrets
   echo "JWT_SECRET=$(openssl rand -hex 32)" | sudo tee /var/lib/loco-secrets/myapp.env
   sudo chmod 600 /var/lib/loco-secrets/myapp.env
   ```

4. **Declare it here**, in a PR. Add the app's flake as an input and the app to a module
   (for example a new `apps.nix` imported by `configuration.nix`):

   ```nix
   # flake.nix
   inputs.myapp = {
     url = "github:piabrota/myapp";
     inputs.nixpkgs.follows = "nixpkgs";
   };
   # outputs = inputs@{ self, nixpkgs, deploy-rs, myapp }: …
   # nixosConfigurations.piabrota = nixpkgs.lib.nixosSystem { specialArgs = { inherit inputs; }; … };
   ```

   ```nix
   # apps.nix
   { inputs, ... }:
   {
     piabrota.loco.apps.myapp = {
       package = inputs.myapp.packages.x86_64-linux.default;
       domain = "myapp.piabrota.art";
       port = 5150;
       environmentFile = "/var/lib/loco-secrets/myapp.env";
     };
   }
   ```

   The merge deploys it. CI builds the app on the runner, so the VPS compiles nothing. A new
   version of the app is a `nix flake update myapp` PR.

## Look at it on the box

```console
systemctl status loco-myapp
journalctl -u loco-myapp -f
sudo sqlite3 /var/lib/loco-myapp/db.sqlite '.tables'
ls /var/lib/loco-myapp/backup/
```

`checks.loco-example` builds the system with a stand-in app, so a change to `loco.nix` is built in
CI before any real app depends on it.
