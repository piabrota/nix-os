# PGX (pgx.dev), a lightweight Postgres-compatible engine, as the unit `pgx`: one process that
# speaks the PostgreSQL 18 wire protocol and SQL, for the workloads here that need Postgres (rax's
# store on KubeSolo) without a PostgreSQL server or Docker. State in /var/lib/pgx, port 5432, the
# superuser password generated on the first start (`pgx url <db>` shows it). PGX is v0.1 and says
# it is for disposable databases: data you keep stays in SQLite (docs/LOCO.md). See docs/PGX.md.
{ config, lib, pkgs, ... }:
let
  inherit (lib) mkEnableOption mkIf mkOption types;
  cfg = config.piabrota.pgx;
  home = "/var/lib/pgx";
  run = "/run/pgx";
  env = { PGX_HOME = home; PGX_RUN_DIR = run; };
  # Who may connect over TCP, besides this host: KubeSolo's pods, when it is on.
  clients = lib.optional config.piabrota.kubesolo.enable "10.42.0.0/16";
  hba = pkgs.writeText "pg_hba.conf" (''
    # Written by pgx.nix on every start. The socket's directory admits the pgx group only; TCP
    # needs the password.
    local  all  all                trust
    host   all  all  127.0.0.1/32  scram-sha-256
    host   all  all  ::1/128       scram-sha-256
  '' + lib.concatMapStrings (net: "host   all  all  ${net}  scram-sha-256\n") clients);
  # `pgx ls`, `pgx create ax`, `pgx url ax` for an admin: the CLI runs as the pgx user.
  cli = pkgs.writeShellScriptBin "pgx" ''
    exec /run/wrappers/bin/sudo -u pgx env PGX_HOME=${home} PGX_RUN_DIR=${run} ${lib.getExe cfg.package} "$@"
  '';
in
{
  options.piabrota.pgx = {
    enable = mkEnableOption "PGX, a lightweight Postgres-compatible database (docs/PGX.md)";
    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ./pgx/package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ./pgx/package.nix { }";
      description = "The pgx release (the CLI, the engine and its share/).";
    };
    memoryMax = mkOption {
      type = types.str;
      default = "256M";
      description = "systemd MemoryMax of the unit. PGX's own memory watchdog reads this limit.";
    };
  };

  config = mkIf cfg.enable {
    users.users.pgx = {
      isSystemUser = true;
      group = "pgx";
      inherit home;
    };
    users.groups.pgx = { };

    environment.systemPackages = [ cli ];

    systemd.services.pgx = {
      description = "PGX, a Postgres-compatible database";
      documentation = [ "https://pgx.dev" ];
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      environment = env;
      # The first start copies the release's base cluster. Listening on every address is the only
      # way pods reach it: cni0 appears after this unit starts. The firewall opens no port, and
      # pg_hba.conf (rewritten on every start) refuses any network but loopback and the pods'.
      preStart = ''
        if [ ! -f ${home}/config.json ]; then
          PGX_LISTEN='*' ${lib.getExe cfg.package} init --port 5432 --durability full
        fi
        install -m 600 ${hba} ${home}/data/pg_hba.conf
      '';
      serviceConfig = {
        ExecStart = "${lib.getExe cfg.package} serve";
        User = "pgx";
        Group = "pgx";
        StateDirectory = "pgx";
        StateDirectoryMode = "0700";
        RuntimeDirectory = "pgx";
        RuntimeDirectoryMode = "0750";
        UMask = "0077";
        Restart = "on-failure";
        RestartSec = 5;
        # Fast shutdown, as nixpkgs' postgresql: SIGINT rolls back open transactions and stops.
        KillSignal = "SIGINT";
        KillMode = "mixed";
        TimeoutStopSec = 60;
        MemoryMax = cfg.memoryMax;
        CapabilityBoundingSet = "";
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectClock = true;
        ProtectHostname = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        ProtectProc = "invisible";
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_NETLINK" "AF_UNIX" ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [ "@system-service" "~@privileged" ];
      };
    };
  };
}
