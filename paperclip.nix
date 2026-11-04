# Paperclip (github.com/paperclipai/paperclip), a control plane for a "company" of AI agents, at
# https://paperclip.piabrota.art, with Hermes as its agent. See docs/PAPERCLIP.md.
#
# Paperclip is the Node server of its npm release (paperclip/package.nix) as the unit `paperclip`
# on 127.0.0.1:3100, behind nginx with ACME. Its data is in PostgreSQL 17 (NixOS's own server, a
# Unix socket only: Paperclip refuses its embedded PostgreSQL when it faces the internet) and in
# /var/lib/paperclip. It runs in "authenticated, public" mode: its own login (Better Auth), with
# sign-up closed; docs/PAPERCLIP.md has the one-time opening for the first admin.
#
# The integration: Paperclip's `hermes_gateway` adapter calls the Hermes gateway that already
# runs here (hermes.nix) over its API server on 127.0.0.1:8642, so a Paperclip task runs in that
# Hermes, with its Claude subscription, its deny list and its skills, and no second agent process.
# Hermes calls back with Paperclip's skill and an agent key. Both keys live only on the box
# (API_SERVER_KEY and PAPERCLIP_API_KEY in /var/lib/hermes-secrets/hermes.env). Without
# API_SERVER_KEY Hermes opens no API server, and Paperclip runs with no agent.
#
# The second path: Paperclip's `pi_local` adapter runs the box's `omp` (omp/wrapper.nix) through a
# shim, with the same Claude subscription token as Hermes. `claude_local` cannot work here: its
# `claude` CLI is unfree.
# paperclip.piabrota.art must point at the box before this is on, or the ACME order fails on the
# deploy.
{ config, lib, pkgs, ... }:
let
  inherit (lib) mkEnableOption mkIf mkMerge mkOption types;
  cfg = config.piabrota.paperclip;
  pkg = cfg.package;
  home = "/var/lib/paperclip";
  secretsFile = "/var/lib/paperclip-secrets/paperclip.env";
  pg = config.services.postgresql.package;
  pgPort = toString config.services.postgresql.settings.port;
  url = "https://${cfg.domain}";
  local = "http://127.0.0.1:${toString cfg.port}";
  # What onboard would write, as Paperclip's schema has it (server/shared config-schema): read-only
  # in the store, so the UI and the CLI cannot change it; a change is a pull request.
  configFile = (pkgs.formats.json { }).generate "paperclip-config.json" {
    "$meta" = { version = 1; updatedAt = "1970-01-01T00:00:00.000Z"; source = "configure"; };
    database = {
      mode = "postgres";
      connectionString = "postgres:///paperclip";
      # pg_dump of the whole database, once a day, kept a week.
      backup = { enabled = true; intervalMinutes = 1440; retentionDays = 7; dir = "${home}/backups"; };
    };
    logging = { mode = "file"; logDir = "${home}/logs"; };
    server = {
      deploymentMode = "authenticated";
      exposure = "public";
      bind = "loopback";
      host = "127.0.0.1";
      inherit (cfg) port;
      allowedHostnames = [ cfg.domain ];
      serveUi = true;
    };
    telemetry.enabled = false;
    updates.checkEnabled = false;
    auth = { baseUrlMode = "explicit"; publicBaseUrl = url; disableSignUp = true; };
    storage = { provider = "local_disk"; localDisk.baseDir = "${home}/storage"; };
    secrets = {
      provider = "local_encrypted";
      strictMode = false;
      localEncrypted.keyFilePath = "${home}/secrets/master.key";
    };
  };
  env = {
    NODE_ENV = "production";
    HOME = home;
    PAPERCLIP_HOME = home;
    PAPERCLIP_INSTANCE_ID = "default";
    PAPERCLIP_CONFIG = "${configFile}";
    PAPERCLIP_PUBLIC_URL = url;
    # No host in the URL: postgres.js then takes PGHOST, the socket's directory, and the unit's
    # user, which peer authentication maps to the role of the same name.
    DATABASE_URL = "postgres:///paperclip";
    PGHOST = "/run/postgresql";
    PGPORT = pgPort;
    PAPERCLIP_PG_DUMP_PATH = "${pg}/bin/pg_dump";
    PAPERCLIP_TELEMETRY_DISABLED = "1";
    DO_NOT_TRACK = "1";
    # Below MemoryMax, so V8 collects garbage before the kernel kills the unit.
    NODE_OPTIONS = "--max-old-space-size=1536";
  };
  envArgs = lib.mapAttrsToList (n: v: "${n}=${v}") env;
  # `paperclipai auth bootstrap-ceo`, `paperclipai doctor` and the other admin commands: the CLI
  # as the paperclip user, with the server's configuration and secrets.
  cli = pkgs.writeShellScriptBin "paperclipai" ''
    exec /run/wrappers/bin/sudo -u paperclip ${pkgs.runtimeShell} -c \
      'set -a; . ${secretsFile}; set +a; exec "$@"' paperclipai \
      ${pkgs.coreutils}/bin/env ${lib.escapeShellArgs envArgs} ${lib.getExe pkg} "$@"
  '';
  # Paperclip's own skill for its agents (how to read a task, update it and report), copied from
  # the release; the category folder names it in Hermes. Its scripts have store shebangs (bash and
  # node): these two are all that may stay, so the skill never pulls in the whole package.
  hermesSkills = pkgs.runCommand "paperclip-hermes-skills" { allowedReferences = [ pkgs.bashNonInteractive pkg.nodejs ]; } ''
    mkdir -p $out/paperclip
    cp -r ${pkg}/${pkg.skills}/paperclip $out/paperclip/paperclip
  '';
  # `writeShellApplication` writes its own shebang line, so the scripts' first line goes.
  withoutShebang = file: lib.concatStringsSep "\n" (lib.drop 1 (lib.splitString "\n" (builtins.readFile file)));
  # `pi_local` calls the command in PAPERCLIP_PI_COMMAND, `pi` by default; this shim calls omp.
  piShim = pkgs.writeShellApplication {
    name = "paperclip-pi";
    runtimeInputs = [ (pkgs.callPackage ./omp/wrapper.nix { }) ];
    text = withoutShebang ./paperclip/pi-to-omp.sh;
  };
  hermesKey = pkgs.writeShellApplication {
    name = "paperclip-hermes-key";
    runtimeInputs = [ pkgs.coreutils pkgs.gnugrep pkgs.openssl ];
    text = withoutShebang ./paperclip/hermes-key.sh;
  };
  # Runs as root (the `+` of ExecStartPre) at each start: copies the one line CLAUDE_CODE_OAUTH_TOKEN
  # of Hermes's secrets file, and nothing else, to a file that only the paperclip user reads. The
  # file is empty when the line or the source is missing.
  claudeEnv = "/var/lib/paperclip-secrets/claude.env";
  claudeToken = pkgs.writeShellScript "paperclip-claude-token" ''
    export PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.gnugrep ]}
    umask 077
    grep '^CLAUDE_CODE_OAUTH_TOKEN=' /var/lib/hermes-secrets/hermes.env 2>/dev/null | tail -n 1 > ${claudeEnv}.new
    chown paperclip:paperclip ${claudeEnv}.new
    chmod 600 ${claudeEnv}.new
    mv ${claudeEnv}.new ${claudeEnv}
  '';
in
{
  options.piabrota.paperclip = {
    enable = mkEnableOption "Paperclip at its domain, with Hermes as its agent (docs/PAPERCLIP.md)";
    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ./paperclip/package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ./paperclip/package.nix { }";
      description = "Paperclip's npm release.";
    };
    domain = mkOption {
      type = types.str;
      default = "paperclip.piabrota.art";
      description = "The name nginx serves Paperclip on. Its DNS A record must point at the box.";
    };
    port = mkOption {
      type = types.port;
      default = 3100;
      description = "Paperclip's loopback port (upstream's default).";
    };
    htpasswdFile = mkOption {
      # A string, not a path: a path literal copies the file into the world-readable store.
      type = types.str;
      default = config.piabrota.hermesWeb.htpasswdFile;
      defaultText = lib.literalExpression "config.piabrota.hermesWeb.htpasswdFile";
      description = ''
        The basic-auth users in front of the site, the same file as hermes.piabrota.art's by
        default (docs/HERMES.md, "The web dashboard"). Without it nginx answers every request
        with a 500. Hermes and the CLI call Paperclip on 127.0.0.1, past nginx, so they need no
        password.
      '';
    };
    memoryMax = mkOption {
      type = types.str;
      default = "2G";
      description = "systemd MemoryMax of the unit. Idle, the server holds about 600 MiB.";
    };
    hermes = {
      enable = mkOption {
        type = types.bool;
        default = config.services.hermes-agent.enable;
        defaultText = lib.literalExpression "config.services.hermes-agent.enable";
        description = ''
          Open Hermes's API server on loopback for Paperclip's hermes_gateway adapter, and give
          Hermes the Paperclip skill, its URL and the passthrough of its agent key.
        '';
      };
      port = mkOption {
        type = types.port;
        default = 8642;
        description = "The Hermes API server's loopback port (upstream's default).";
      };
    };
    omp = {
      enable = mkOption {
        type = types.bool;
        default = config.services.hermes-agent.enable;
        defaultText = lib.literalExpression "config.services.hermes-agent.enable";
        description = ''
          Run Paperclip's pi_local adapter on the box's omp, through a shim, with Hermes's Claude
          subscription token (copied to a file only the paperclip user reads at each start).
        '';
      };
    };
    hermesSkillDirs = mkOption {
      type = types.listOf types.str;
      default = [ ];
      internal = true;
      description = "Skill directories for Hermes; hermes.nix appends them to skills.external_dirs.";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      users.users.paperclip = {
        isSystemUser = true;
        group = "paperclip";
        inherit home;
      };
      users.groups.paperclip = { };

      environment.systemPackages = [ cli ];

      # The database server, for Paperclip only: its socket, no TCP (PGX has 127.0.0.1:5432), and
      # peer authentication, so only the paperclip user reaches the paperclip database.
      services.postgresql = {
        enable = true;
        package = pkgs.postgresql_17;
        enableTCPIP = false;
        settings = {
          listen_addresses = lib.mkForce "";
          port = 5433;
          max_connections = 40;
          shared_buffers = "128MB";
        };
        ensureDatabases = [ "paperclip" ];
        ensureUsers = [{
          name = "paperclip";
          ensureDBOwnership = true;
        }];
      };
      systemd.services.postgresql.serviceConfig.MemoryMax = "1G";

      # The paperclip user's own, so the CLI above reads them too; the server has them anyway.
      systemd.tmpfiles.rules = [ "d /var/lib/paperclip-secrets 0700 paperclip paperclip -" ];

      # Paperclip's signing secrets, made on the box the first time and kept: Better Auth's session
      # key, the key that signs approval-gated tool actions and the agents' JWT key. A missing line
      # is added; an existing one is never changed (a new one ends every session). The file is also
      # where PAPERCLIP_AUTH_DISABLE_SIGN_UP=false opens sign-up for the first admin.
      systemd.services.paperclip-secrets = {
        description = "Paperclip's signing secrets";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          UMask = "0077";
        };
        path = [ pkgs.coreutils pkgs.gnugrep pkgs.openssl ];
        script = ''
          touch ${secretsFile}
          for name in BETTER_AUTH_SECRET PAPERCLIP_TOOL_ACTION_SIGNING_SECRET PAPERCLIP_AGENT_JWT_SECRET; do
            grep -q "^$name=" ${secretsFile} || echo "$name=$(openssl rand -hex 32)" >> ${secretsFile}
          done
          chown paperclip:paperclip ${secretsFile}
          chmod 600 ${secretsFile}
        '';
      };

      systemd.services.paperclip = {
        description = "Paperclip, a control plane for AI agents";
        documentation = [ "https://docs.paperclip.ing" ];
        wantedBy = [ "multi-user.target" ];
        requires = [ "postgresql.target" "paperclip-secrets.service" ];
        after = [ "network.target" "postgresql.target" "paperclip-secrets.service" ];
        environment = env;
        # psql and pg_dump for its backups.
        path = [ pg ];
        serviceConfig = {
          ExecStart = "${lib.getExe pkg.nodejs} ${pkg}/${pkg.server}";
          User = "paperclip";
          Group = "paperclip";
          EnvironmentFile = secretsFile;
          StateDirectory = "paperclip";
          StateDirectoryMode = "0700";
          WorkingDirectory = home;
          UMask = "0077";
          Restart = "on-failure";
          RestartSec = 5;
          # Upstream's grace: work in flight gets 30 s to settle, then the cleanup.
          TimeoutStopSec = 90;
          MemoryMax = cfg.memoryMax;
          CPUWeight = 50;
          NoNewPrivileges = true;
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectKernelLogs = true;
          ProtectProc = "invisible";
          CapabilityBoundingSet = "";
          ProtectControlGroups = true;
          ProtectClock = true;
          ProtectHostname = true;
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
          # AF_NETLINK: os.networkInterfaces() at startup reads the addresses over netlink;
          # without it Node fails with EAFNOSUPPORT (97) and the server exits.
          RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" "AF_NETLINK" ];
          SystemCallArchitectures = "native";
          SystemCallFilter = [ "@system-service" "~@privileged" ];
          SystemCallErrorNumber = "EPERM";
        };
      };

      services.nginx = {
        enable = true;
        recommendedTlsSettings = true;
        serverTokens = false;
        # Slows a password guesser on the login; the app's page loads stay within the burst.
        appendHttpConfig = ''
          limit_req_zone $binary_remote_addr zone=paperclip_auth:1m rate=2r/s;
        '';
        virtualHosts.${cfg.domain} = {
          forceSSL = true;
          enableACME = true;
          basicAuthFile = cfg.htpasswdFile;
          extraConfig = ''
            add_header X-Frame-Options DENY always;
            add_header Referrer-Policy no-referrer always;
            add_header X-Content-Type-Options nosniff always;
            add_header Strict-Transport-Security "max-age=31536000" always;
          '';
          locations = {
            "/" = {
              proxyPass = local;
              proxyWebsockets = true;
              recommendedProxySettings = true;
              # Live updates are server-sent events and WebSockets; attachments are uploads.
              # The browser's Basic credentials stay at nginx; Paperclip's UI uses its session cookie.
              extraConfig = ''
                proxy_set_header Authorization "";
                proxy_buffering off;
                proxy_read_timeout 1h;
                proxy_send_timeout 1h;
                client_max_body_size 32m;
              '';
            };
            "/api/auth/" = {
              proxyPass = local;
              recommendedProxySettings = true;
              extraConfig = ''
                proxy_set_header Authorization "";
                limit_req zone=paperclip_auth burst=20 nodelay;
                limit_req_status 429;
              '';
            };
          };
        };
      };

      security.acme = {
        acceptTerms = true;
        defaults.email = config.piabrota.loco.acmeEmail;
      };

      networking.firewall.allowedTCPPorts = [ 80 443 ];
    }

    (mkIf cfg.omp.enable {
      assertions = [{
        assertion = config.services.hermes-agent.enable;
        message = "piabrota.paperclip.omp needs services.hermes-agent (hermes.nix) on the same host: it uses Hermes's omp wrapper and token.";
      }];
      systemd.services.paperclip = {
        environment.PAPERCLIP_PI_COMMAND = "${piShim}/bin/paperclip-pi";
        serviceConfig = {
          # `-` lets Paperclip start if this step fails: the token is for the agents, not the server.
          ExecStartPre = [ "-+${claudeToken}" ];
          # The leading `-` makes the file optional.
          EnvironmentFile = [ "-${claudeEnv}" ];
        };
      };
    })

    (mkIf cfg.hermes.enable {
      assertions = [{
        assertion = config.services.hermes-agent.enable;
        message = "piabrota.paperclip.hermes needs services.hermes-agent (hermes.nix) on the same host.";
      }];
      services.hermes-agent = {
        # Not secret: where the API server listens (loopback, which upstream also defaults to) and
        # where Paperclip is. The API server starts only when hermes.env has API_SERVER_KEY (16
        # characters or more).
        environment = {
          API_SERVER_HOST = "127.0.0.1";
          API_SERVER_PORT = toString cfg.hermes.port;
          PAPERCLIP_API_URL = local;
        };
        # Hermes's terminal drops secrets from its children's environment; these two reach curl
        # for Paperclip's skill. API_SERVER_KEY is not one of them.
        settings.terminal.env_passthrough = [ "PAPERCLIP_API_URL" "PAPERCLIP_API_KEY" ];
        # The skill's scripts use jq.
        extraPackages = [ pkgs.jq ];
      };
      # hermes.nix adds it to skills.external_dirs.
      piabrota.paperclip.hermesSkillDirs = [ "${hermesSkills}" ];
      systemd.services.hermes-agent.reloadTriggers = [ hermesSkills ];
      environment.systemPackages = [ hermesKey ];
    })
  ]);
}
