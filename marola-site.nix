# marola.dev: marola-site's Haskell server (marola-site/default.nix, a pinned commit), behind nginx
# with Let's Encrypt. The server listens on 127.0.0.1 only; the unit and the nginx settings follow
# that repository's docs/5-hosting.md, which is the contract. On piabrota2, for marola.dev and
# marola.piabrota.art (docs/MAROLA-SITE.md).
{ config, lib, pkgs, utils, ... }:
let
  scripts = pkgs.callPackage ./scala { };
  inherit (lib) mkEnableOption mkIf mkOption optionalAttrs types;
  cfg = config.piabrota.marolaSite;
  upstream = "http://127.0.0.1:${toString cfg.port}";
  # The server trusts the last X-Forwarded-For entry from 127.0.0.1, so nginx replaces the header
  # ($remote_addr), never appends to it; the contact form checks Origin against Host.
  proxyHeaders = ''
    proxy_http_version 1.1;
    proxy_set_header Connection "";
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $remote_addr;
    proxy_set_header X-Forwarded-Proto $scheme;
  '';
  state = "/var/lib/marola";
  boards = "/var/lib/marola-boards";
  # The boards as a mirror of another site's (`piabrota marola-boards-mirror`, scala/scripts).
  mirror = scripts.command {
    name = "marola-boards-mirror";
    runtimeInputs = [ pkgs.curl ];
  };
  # The base map's tiles file (marola-site's docs/5-hosting.md, "The base map"), cut on the box by
  # marola-site's own basemap_extract.sh from the Protomaps build its site/basemap.version pins, for the
  # areas of the same commit. The stamp is that pin and those areas: a deploy that changes neither
  # leaves the file alone.
  tiles = "${state}/tiles";
  tilesStamp = builtins.hashString "sha256" (builtins.readFile cfg.package.basemapVersion + builtins.readFile cfg.package.areas);
  tilesBuilder = scripts.command {
    name = "marola-tiles";
    runtimeInputs = [ pkgs.bash pkgs.coreutils pkgs.gnused pkgs.curl pkgs.nodejs_24 pkgs.pmtiles pkgs.tippecanoe ];
  };
  bcfg = cfg.boards.build;
  # The boards as marola-site's site.yml builds them, here instead of on the self-hosted runner:
  # the app image marola-site pins, `--site` over its areas.json, no LLM. piabrota2 is in Brazil
  # (LACNIC: BR), and INEA and INEMA answer only Brazilian addresses. The beach lists stay in the
  # work folder, so Overpass is asked only for an area with none.
  # (`piabrota marola-boards-build`, scala/scripts.)
  builder = scripts.command {
    name = "marola-boards-build";
    runtimeInputs = [ config.virtualisation.podman.package pkgs.coreutils ];
  };
  backup = scripts.command {
    name = "marola-backup";
    runtimeInputs = [ pkgs.sqlite pkgs.rsync pkgs.coreutils pkgs.findutils ];
  };
in
{
  options.piabrota.marolaSite = {
    enable = mkEnableOption "marola.dev, marola-site's Haskell server behind nginx";
    domain = mkOption {
      type = types.str;
      default = "marola.dev";
      description = "The name nginx serves the site on. Its DNS A record must point at the box before the deploy, or the ACME order fails.";
    };
    aliases = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "marola.piabrota.art" ];
      description = "More names that serve the same site (not a redirect), each a vhost with its own certificate, so one name's failed ACME order leaves the others' certificates alone. Each must point at the box.";
    };
    redirects = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "www.marola.dev" ];
      description = "Names that answer with a 301 to `domain`, each with its own certificate. Each must point at the box.";
    };
    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ./marola-site { };
      defaultText = lib.literalExpression "pkgs.callPackage ./marola-site { }";
      description = "marola-site's package: bin/marola-server and share/marola/dist.";
    };
    port = mkOption {
      type = types.port;
      default = 8095;
      description = "The server's port on 127.0.0.1 (MAROLA_PORT).";
    };
    studiesQuota = mkOption {
      type = types.ints.positive;
      default = 2147483648;
      description = "The most bytes the stored study PDFs may take (MAROLA_STUDIES_QUOTA).";
    };
    github = {
      clientId = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "The public client id of the GitHub OAuth app. Null: the login answers 503 and the rest of the site works.";
      };
      clientSecretFile = mkOption {
        type = types.str;
        default = "/etc/marola/github-client-secret";
        description = "The file on the box that holds the client secret (root, 0600). It reaches the server with LoadCredential, never through the store or an environment variable.";
      };
    };
    boards.mirrorFrom = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "https://marola.example.workers.dev/data";
      description = "A URL whose <area>/latest.json and boards are copied into MAROLA_DATA every few hours, until the board pipeline writes to this box. Null: no copy; the boards answer 404.";
    };
    boards.build = {
      enable = mkEnableOption "the board build on this box: marola-site's pinned app image, run with podman every few hours";
      image = mkOption {
        type = types.str;
        default = cfg.package.marolaImage;
        defaultText = lib.literalExpression "the marola-image file of the pinned marola-site commit";
        description = "The app image, by digest.";
      };
      tokenFile = mkOption {
        type = types.nullOr types.str;
        default = "/etc/marola/ghcr-token";
        description = "A file on the box (root, 0600) with a GitHub token that may read ghcr.io/marola-dev/marola-app (a private package). It reaches the unit with LoadCredential. Null: pull with no login (a public package).";
      };
      registryUser = mkOption {
        type = types.str;
        default = "h0ffmann";
        description = "The GitHub login that owns tokenFile.";
      };
      calendar = mkOption {
        type = types.str;
        default = "*-*-* 01,07,13,19:00:00 UTC";
        description = "When the boards are built (systemd OnCalendar). Each board covers today and tomorrow.";
      };
      memory = mkOption {
        type = types.str;
        default = "2g";
        description = "The container's memory limit (podman --memory).";
      };
    };
    backup.enable = mkOption {
      type = types.bool;
      default = true;
      description = "A daily copy of marola.db, csrf.key and the studies under /var/backups/marola, kept 14 days.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [{
      assertion = !(bcfg.enable && cfg.boards.mirrorFrom != null);
      message = "piabrota.marolaSite: boards.build and boards.mirrorFrom both write MAROLA_DATA; set one.";
    }];

    users.users.marola = {
      isSystemUser = true;
      group = "marola";
    };
    users.groups.marola = { };

    systemd.services.marola-site = {
      description = "marola.dev: marola-site's Haskell server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      # Never MAROLA_DEV (docs/5-hosting.md, "Variables").
      environment = {
        MAROLA_PORT = toString cfg.port;
        MAROLA_STATIC = "${cfg.package}/share/marola/dist";
        MAROLA_DATA = boards;
        MAROLA_DB = "${state}/marola.db";
        MAROLA_STUDIES = "${state}/studies";
        MAROLA_STUDIES_QUOTA = toString cfg.studiesQuota;
        MAROLA_TILES = tiles;
      } // optionalAttrs (cfg.github.clientId != null) {
        MAROLA_GITHUB_CLIENT_ID = cfg.github.clientId;
        MAROLA_GITHUB_CLIENT_SECRET_FILE = "%d/github-client-secret";
      };
      serviceConfig = {
        ExecStart = "${cfg.package}/bin/marola-server";
        User = "marola";
        Group = "marola";
        # The database, csrf.key and the studies. The boards folder is the mirror's: read-only here.
        StateDirectory = "marola";
        StateDirectoryMode = "0750";
        WorkingDirectory = state;
        MemoryMax = "256M";
        Restart = "on-failure";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        NoNewPrivileges = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
        RestrictNamespaces = true;
        LockPersonality = true;
        SystemCallArchitectures = "native";
      } // optionalAttrs (cfg.github.clientId != null) {
        LoadCredential = "github-client-secret:${cfg.github.clientSecretFile}";
      };
    };

    systemd.services.marola-boards = mkIf (cfg.boards.mirrorFrom != null) {
      description = "Copy marola's boards into MAROLA_DATA";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = utils.escapeSystemdExecArgs [
          (lib.getExe mirror)
          (toString cfg.boards.mirrorFrom)
          boards
          "${cfg.package}/share/marola/dist/data/areas.json"
        ];
        User = "marola";
        Group = "marola";
        StateDirectory = "marola-boards";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };
    systemd.timers.marola-boards = mkIf (cfg.boards.mirrorFrom != null) {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "3h";
        RandomizedDelaySec = "10min";
      };
    };

    virtualisation.podman.enable = mkIf bcfg.enable true;

    systemd.services.marola-boards-build = mkIf bcfg.enable {
      description = "Build marola's boards with the pinned app image";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      # A deploy must not stop a running build and start it again: the start of a oneshot waits for
      # the whole build (up to 45 minutes), and deploy-rs rolls back when its confirmation times out.
      # The new definition applies at the next timer or kick start.
      restartIfChanged = false;
      serviceConfig = {
        Type = "oneshot";
        # "-": a failed build (a pull refused, INEA down) must not leave the unit failed, or a deploy
        # that starts it rolls the whole host back. The journal keeps the exit code, and
        # marola-boards.yml mails the owner when the boards go stale.
        ExecStart = "-" + utils.escapeSystemdExecArgs [
          (lib.getExe builder)
          bcfg.image
          bcfg.registryUser
          bcfg.memory
          "${cfg.package.areas}"
          boards
        ];
        StateDirectory = [ "marola-boards-build" "marola-boards" ];
        RuntimeDirectory = "marola-boards-build";
        RuntimeDirectoryMode = "0700";
        TimeoutStartSec = "45min";
      } // optionalAttrs (bcfg.tokenFile != null) {
        LoadCredential = "ghcr-token:${bcfg.tokenFile}";
      };
    };
    # A deploy that moves the image (or the first deploy with the build on) starts a build at once,
    # without waiting for the next timer run and without holding the switch: --no-block, so a
    # 45-minute build never trips deploy-rs's rollback.
    # As user marola, into the server's state folder. About 220 MB from build.protomaps.com and a few
    # minutes; a pin that Protomaps no longer lists (it keeps about a week of builds) fails here and
    # the old file stays.
    systemd.services.marola-tiles = {
      description = "Cut marola's base map tiles file";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = utils.escapeSystemdExecArgs [
          (lib.getExe tilesBuilder)
          tiles
          tilesStamp
          "${cfg.package.basemapVersion}"
          "${cfg.package.areas}"
          "${cfg.package.basemapExtract}"
        ];
        User = "marola";
        Group = "marola";
        StateDirectory = [ "marola" "marola-tiles" ];
        StateDirectoryMode = "0750";
        TimeoutStartSec = "30min";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };
    # Every deploy that moves the pin or the areas starts it, without holding the switch.
    systemd.services.marola-tiles-kick = {
      description = "Start marola-tiles when the base map pin, the areas or the builder change";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      # The builder too: a fix to it reruns the cut even when the pin and the areas stay.
      restartTriggers = [ tilesStamp tilesBuilder ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${config.systemd.package}/bin/systemctl start --no-block marola-tiles.service";
      };
    };

    systemd.services.marola-boards-build-kick = mkIf bcfg.enable {
      description = "Start a board build when the app image changes";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      restartTriggers = [ bcfg.image ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${config.systemd.package}/bin/systemctl start --no-block marola-boards-build.service";
      };
    };
    systemd.timers.marola-boards-build = mkIf bcfg.enable {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = bcfg.calendar;
        Persistent = true;
        RandomizedDelaySec = "10min";
      };
    };

    # Database first, studies second: a file without a row is harmless, a row without a file is not
    # (docs/5-hosting.md, "The studies and their backup").
    systemd.services.marola-backup = mkIf cfg.backup.enable {
      description = "Back up marola's database, csrf.key and studies";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = utils.escapeSystemdExecArgs [ (lib.getExe backup) state ];
      };
    };
    systemd.timers.marola-backup = mkIf cfg.backup.enable {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "30min";
      };
    };

    services.nginx = {
      enable = true;
      recommendedTlsSettings = true;
      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      serverTokens = false;
      virtualHosts = lib.genAttrs ([ cfg.domain ] ++ cfg.aliases)
        (_: {
          forceSSL = true;
          enableACME = true;
          # HSTS once, from nginx: it hides the server's copy and covers nginx's own error pages.
          # The server refuses more than 1 MB itself; only the upload location below is larger.
          extraConfig = ''
            proxy_hide_header Strict-Transport-Security;
            add_header Strict-Transport-Security "max-age=63072000; includeSubDomains" always;
            client_max_body_size 1m;
          '';
          locations = {
            # The study upload, by the API and the web form: a 20 MB file and the form fields,
            # streamed to the server, not buffered to disk by nginx.
            "~ ^(/en)?/submit$|^/api/v1/studies$" = {
              proxyPass = upstream;
              recommendedProxySettings = false;
              extraConfig = ''
                client_max_body_size 21m;
                proxy_request_buffering off;
              '' + proxyHeaders;
            };
            "/" = {
              proxyPass = upstream;
              recommendedProxySettings = false;
              extraConfig = proxyHeaders;
            };
          };
        })
      // lib.genAttrs cfg.redirects (_: {
        forceSSL = true;
        enableACME = true;
        globalRedirect = cfg.domain;
      });
    };

    security.acme = {
      acceptTerms = true;
      defaults.email = config.piabrota.loco.acmeEmail;
    };

    networking.firewall.allowedTCPPorts = [ 80 443 ];
  };
}
