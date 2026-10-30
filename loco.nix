# Loco (loco.rs) apps on this box: one sandboxed service per app, SQLite in its state
# directory, nginx in front with Let's Encrypt: on its own domain, or on a path of the site's. With no app declared it adds nothing, so the
# box stays as small as it is until the first app lands. See docs/LOCO.md.
{ config, lib, pkgs, ... }:
let
  inherit (lib) mkIf mkOption types mapAttrs' nameValuePair filterAttrs;
  cfg = config.piabrota.loco;
  site = config.piabrota.site;
  hasApps = cfg.apps != { };
  onDomain = filterAttrs (_: a: a.domain != null) cfg.apps;
  onPath = filterAttrs (_: a: a.path != null) cfg.apps;
  proxy = app: {
    proxyPass = "http://127.0.0.1:${toString app.port}";
    proxyWebsockets = true;
  };

  appModule = { name, config, ... }: {
    options = {
      package = mkOption {
        type = types.package;
        description = "The app, built by its own flake: `bin/<name>-cli`, and `share/<name>/` with `config/` (and `assets/` if it serves any).";
      };
      bin = mkOption {
        type = types.str;
        default = "${name}-cli";
        description = "The binary under `bin/` (cargo names it `<crate>-cli`).";
      };
      workingDirectory = mkOption {
        type = types.str;
        default = "${config.package}/share/${name}";
        defaultText = lib.literalExpression ''"''${package}/share/<name>"'';
        description = "Where Loco finds `config/production.yaml` and `assets/`. Read-only: the store.";
      };
      domain = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "app.piabrota.art";
        description = "The name nginx serves the app on, with its own certificate. Its DNS A record must point at the box before the deploy, or ACME fails. Set this or `path`.";
      };
      path = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "/notes";
        description = "A path on the static site's host (`piabrota.site.domain`) that nginx sends to the app, unchanged: the app's routes must start with it. No new DNS record or certificate. Set this or `domain`.";
      };
      port = mkOption {
        type = types.port;
        description = "Loopback port the app listens on. One per app.";
      };
      environment = mkOption {
        type = types.attrsOf types.str;
        default = { };
        description = "More variables for the app. Never a secret: these land in the store.";
      };
      environmentFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "/var/lib/loco-secrets/myapp.env";
        description = "A file on the box, written by hand, with the secrets (`JWT_SECRET=...`, SMTP). Never in this repo.";
      };
      extraArgs = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "--server-and-worker" ];
        description = "Arguments after `start`.";
      };
      memoryMax = mkOption {
        type = types.str;
        default = "256M";
        description = "systemd MemoryMax: the box is small, so a leak kills the app, not sshd.";
      };
    };
  };
in
{
  options.piabrota.loco = {
    apps = mkOption {
      type = types.attrsOf (types.submodule appModule);
      default = { };
      description = "Loco apps to run, by name.";
    };
    acmeEmail = mkOption {
      type = types.str;
      default = "hoffmann@poli.ufrj.br";
      description = "Contact for Let's Encrypt.";
    };
  };

  config = mkIf hasApps (lib.mkMerge [{
    assertions = [
      {
        assertion = lib.length (lib.unique (lib.mapAttrsToList (_: a: a.port) cfg.apps)) == lib.length (lib.attrNames cfg.apps);
        message = "piabrota.loco.apps: two apps share a port.";
      }
      {
        assertion = lib.all (a: (a.domain == null) != (a.path == null)) (lib.attrValues cfg.apps);
        message = "piabrota.loco.apps: each app needs exactly one of `domain` and `path`.";
      }
      {
        assertion = onPath == { } || site.enable;
        message = "piabrota.loco.apps: an app on a `path` needs the static site (piabrota.site.enable), whose host it shares.";
      }
    ];

    # One system user per app, so its nightly backup can run as that user: a root sqlite3 on a
    # WAL database leaves root-owned -shm/-wal files the app can no longer open.
    users.users = mapAttrs'
      (name: _: nameValuePair "loco-${name}" {
        isSystemUser = true;
        group = "loco-${name}";
      })
      cfg.apps;
    users.groups = mapAttrs' (name: _: nameValuePair "loco-${name}" { }) cfg.apps;

    systemd.services = lib.mkMerge (lib.mapAttrsToList
      (name: app:
        let
          state = "/var/lib/loco-${name}";
          sandbox = {
            User = "loco-${name}";
            Group = "loco-${name}";
            StateDirectory = "loco-${name}";
            StateDirectoryMode = "0700";
            UMask = "0077";
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
            RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
            RestrictNamespaces = true;
            RestrictRealtime = true;
            RestrictSUIDSGID = true;
            LockPersonality = true;
            MemoryDenyWriteExecute = true;
            SystemCallArchitectures = "native";
            SystemCallFilter = [ "@system-service" "~@privileged" ];
          };
        in
        {
          "loco-${name}" = {
            description = "Loco app ${name}";
            wantedBy = [ "multi-user.target" ];
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];
            environment = {
              LOCO_ENV = "production";
              # The generated production.yaml reads these through get_env; older templates use NODE_PORT.
              BINDING = "127.0.0.1";
              PORT = toString app.port;
              NODE_PORT = toString app.port;
              HOST = "https://${if app.domain != null then app.domain else site.domain}";
              DATABASE_URL = "sqlite://${state}/db.sqlite?mode=rwc";
            } // app.environment;
            serviceConfig = sandbox // {
              ExecStart = lib.escapeShellArgs ([ "${app.package}/bin/${app.bin}" "start" ] ++ app.extraArgs);
              WorkingDirectory = app.workingDirectory;
              EnvironmentFile = lib.optional (app.environmentFile != null) app.environmentFile;
              Restart = "on-failure";
              RestartSec = 5;
              MemoryMax = app.memoryMax;
            };
          };

          # A consistent copy every night, seven kept. sqlite3's .backup is safe while the app
          # writes; a cp of a live WAL database is not.
          "loco-${name}-backup" = {
            description = "Back up the SQLite database of Loco app ${name}";
            startAt = "daily";
            path = [ pkgs.sqlite pkgs.coreutils pkgs.findutils ];
            serviceConfig = sandbox // {
              Type = "oneshot";
            };
            script = ''
              mkdir -p ${state}/backup
              if [ -f ${state}/db.sqlite ]; then
                sqlite3 ${state}/db.sqlite ".backup '${state}/backup/db-$(date +%F).sqlite'"
              fi
              find ${state}/backup -name 'db-*.sqlite' -mtime +7 -delete
            '';
          };
        })
      cfg.apps);
  }
    {
      services.nginx = {
        enable = true;
        recommendedProxySettings = true;
        recommendedTlsSettings = true;
        recommendedGzipSettings = true;
        recommendedOptimisation = true;
        serverTokens = false;
        virtualHosts = lib.mkMerge [
          (mapAttrs'
            (_: app: nameValuePair app.domain {
              enableACME = true;
              forceSSL = true;
              locations."/" = proxy app;
            })
            onDomain)
          # Apps on a path share the site's virtual host and certificate: the exact path and
          # everything below it go to the app.
          (lib.optionalAttrs (onPath != { }) {
            ${site.domain}.locations = lib.mkMerge (lib.mapAttrsToList
              (_: app:
                let
                  # The site answers on HTTP too (addSSL); an app never does: a password or a
                  # session cookie must not cross in clear.
                  secure = proxy app // {
                    extraConfig = "if ($scheme = http) { return 301 https://$host$request_uri; }";
                  };
                in
                {
                  "= ${app.path}" = secure;
                  "${app.path}/" = secure;
                })
              onPath);
          })
        ];
      };

      security.acme = {
        acceptTerms = true;
        defaults.email = cfg.acmeEmail;
      };

      networking.firewall.allowedTCPPorts = [ 80 443 ];

      # For looking into a database by hand (sudo sqlite3 /var/lib/loco-<app>/db.sqlite).
      environment.systemPackages = [ pkgs.sqlite ];
    }]);
}
