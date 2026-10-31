# PGX: Postgres without a PostgreSQL server

[Português](PGX.ptBR.md)

[PGX](https://pgx.dev) ([pgrundev/pgx](https://github.com/pgrundev/pgx)) is a Postgres-compatible
database engine written in Rust: one process that speaks the PostgreSQL 18 wire protocol and SQL.
This box runs it as the unit `pgx` (`pgx.nix`) for what needs Postgres here, today rax's store on
KubeSolo, instead of a PostgreSQL server or a Docker container.

## What it is, and what it is not

| | |
|---|---|
| Version | v0.1.2 (2026-10-27), first released 2026-10-21 |
| Licence | AGPL-3.0. Run unmodified here; a change to PGX served to others would have to be published |
| Compatibility | PostgreSQL 18.6: 219 of 231 files of PostgreSQL's own regression suite byte-exact, the other 12 differ in `EXPLAIN` text only (the project's figures). rax's store tests pass on it (below) |
| Not there | C extensions (PostGIS, TimescaleDB), PL/Python, PL/Perl; `pg_dump` is not in the release |
| Its own warning | "For disposable databases, not production data": the project calls v0.1 "not a production primary, a system of record, or an HA or PITR database" |

PGX's default profile turns `fsync` off. This module initialises it with `--durability full`
(PostgreSQL's defaults: `fsync`, `synchronous_commit` and `full_page_writes` on), which the test
checks. Even so: **data you keep goes to SQLite**, as the Loco apps do ([`LOCO.md`](LOCO.md)). PGX
here holds stores you could rebuild, such as rax's tasks.

## Cost

| | |
|---|---|
| Closure | **≈ +99 MiB**: the release (the engine, 56 MiB, the CLI, and `share/`: timezones, contrib scripts and the 39 MiB base cluster). Its libraries, glibc and libstdc++, are in the system already. ⚠ `dix` did not run: the system is x86_64 and the machine here builds aarch64 (measured on the aarch64 release, 99.3 MiB) |
| Download | The release is not on cache.nixos.org: the runner downloads it (32 MB) from GitHub and deploy-rs copies it to the VPS once per version. Nothing is compiled |
| RAM | 45 MiB idle, 68 MiB after rax's store tests (measured in a container, 2026-10-30). `MemoryMax=256M`; PGX's memory watchdog reads that limit and refuses queries (SQLSTATE 53200) before the kernel kills it |
| Disk, in use | `/var/lib/pgx`: the base cluster (39 MiB) plus the databases and their WAL ⚠ WAL can grow to `max_wal_size` (1 GB, PostgreSQL's default) under heavy writes |
| CPU | Idle with nothing to do; no limit on the unit |

## What `pgx.nix` does

- Packages the release (`pgx/package.nix`): `autoPatchelfHook` points both binaries at the store's
  glibc and libstdc++. nixpkgs has no pgx.
- Runs `pgx serve` as the `pgx` user, with the state in `/var/lib/pgx` (mode 0700) and the socket
  in `/run/pgx` (mode 0750, the `pgx` group only). On the first start it copies the base cluster
  (`pgx init --port 5432 --durability full`) and generates the superuser's password, which stays
  in `/var/lib/pgx/config.json`.
- Listens on every address, port 5432: pods reach the host through `cni0`, which appears only
  after KubeSolo starts. **The firewall opens no port**, and `pg_hba.conf`, rewritten on every
  start, admits the socket (the `pgx` group only) and, over TCP with the password
  (`scram-sha-256`), loopback and, with KubeSolo on, the pods (`10.42.0.0/16`).
- The same sandbox as the Loco apps: no capabilities, read-only system, private `/tmp` and
  devices, `@system-service` system calls.
- Puts a `pgx` command on the path that runs the CLI as the `pgx` user.
- For each `piabrota.pgx.kubeSecrets.<name>` (today `ax-store`), the unit `pgx-kube-secrets` creates
  the database if it is missing and writes its URL (the password, the host `10.42.0.1`,
  `sslmode=disable`) as a Kubernetes Secret with one key, `url`, by server-side apply with `curl`
  and KubeSolo's admin certificate (handed over by systemd's `LoadCredential`; no `kubectl` on the
  box). It does not hold up a deploy: it retries every 30 s until the API answers.

`checks.pgx` (`pgx/test.nix`) boots a VM with the module, creates a database, connects over TCP
with the password and without it, restarts the unit, finds the row again and reads the memory
limit in the log. CI runs it with `nix flake check`.

## Using it

On the VPS:

```console
pgx ls                    # databases
pgx create ax             # a database
pgx url ax                # its URL, with the password: postgres://postgres:…@127.0.0.1:5432/ax
pgx drop ax               # remove it
```

Any PostgreSQL client or driver works with that URL. From a pod, replace `127.0.0.1` with the
host's `cni0` address (10.42.0.1, seen on the box). rax on KubeSolo
takes the URL from a Secret that `pgx.nix` writes: [`KUBESOLO.md`](KUBESOLO.md), "Run, reach, remove".

**Tested with rax**: `cargo test -p rax-store` from piabrota/rax with `RAX_TEST_POSTGRES_URL`
pointed at PGX 0.1.2, 11 of 11 (the conformance suite, concurrent schema creation, advisory
locks, lease renewal and takeover, `ON CONFLICT`, `FOR UPDATE`).

## Backups

None. The release has no `pg_dump`, and the data here is meant to be rebuilt. If that changes,
copy with `pg_dump` from another machine through an SSH tunnel to port 5432, or move the data to
SQLite.

## Updating

Change `version` and both hashes in `pgx/package.nix` (the release's `.sha256` files have them in
hex; `nix hash convert --to sri sha256:<hex>`). The data directory is PostgreSQL 18's format and
stays; read the release notes for anything else.

## Turning it off

Set `piabrota.pgx.enable = false` in `configuration.nix` and merge: the unit and the release leave
the system. `/var/lib/pgx` stays on the disk; remove it by hand (`sudo rm -r /var/lib/pgx`) when it
is no longer wanted. rax's pod then fails to reach its store until it gets another one.

## Sources

The project's README, `docs/pgx/layout.md`, `crates/bin/pgx/src/conf.rs` (the profile and
`pg_hba.conf` it writes) and `crates/bin/pgx/src/cli.rs` (the commands and the `PGX_*` variables),
at v0.1.2. Measurements: this repository, 2026-10-30.
