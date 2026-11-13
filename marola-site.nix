# marola.dev: marola-site's Haskell server (marola-site/default.nix, a pinned commit), behind nginx
# with Let's Encrypt. The server listens on 127.0.0.1 only; the unit and the nginx settings follow
# that repository's docs/5-hosting.md, which is the contract. On piabrota2. DNS of marola.dev is on
# Cloudflare, not Porkbun, and the cutover from the Cloudflare Worker is docs/MAROLA-SITE.md.
{ config, lib, pkgs, ... }:
let
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
  mirror = pkgs.writeShellApplication {
    name = "marola-boards-mirror";
    runtimeInputs = [ pkgs.curl pkgs.jq pkgs.coreutils ];
    text = ''
      src=${lib.escapeShellArg (toString cfg.boards.mirrorFrom)}
      out=${boards}
      for area in $(jq -r '.areas[].id' ${cfg.package}/share/marola/dist/data/areas.json); do
        tmp=$(mktemp -d "$out/.incoming.XXXXXX")
        if ! curl -fsS --max-time 30 "$src/$area/latest.json" -o "$tmp/latest.json"; then
          echo "marola-boards: no latest.json for $area" >&2
          rm -rf "$tmp"
          continue
        fi
        ok=1
        for f in $(jq -r '.days[].file' "$tmp/latest.json"); do
          # A file name from the network: only <date>.json, never a path.
          if ! [[ $f =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\.json$ ]]; then
            echo "marola-boards: $area: refused file name $f" >&2
            ok=0
            break
          fi
          curl -fsS --max-time 60 "$src/$area/$f" -o "$tmp/$f" || { ok=0; break; }
        done
        if [ "$ok" = 1 ]; then
          chmod 0755 "$tmp"
          rm -rf "$out/$area.old"
          if [ -d "$out/$area" ]; then mv "$out/$area" "$out/$area.old"; fi
          mv "$tmp" "$out/$area"
          rm -rf "$out/$area.old"
          echo "marola-boards: $area updated" >&2
        else
          echo "marola-boards: $area kept as it was" >&2
          rm -rf "$tmp"
        fi
      done
    '';
  };
  bcfg = cfg.boards.build;
  # The boards as marola-site's site.yml builds them, here instead of on the self-hosted runner:
  # the app image marola-site pins, `--site` over its areas.json, no LLM. piabrota2 is in Brazil
  # (LACNIC: BR), and INEA and INEMA answer only Brazilian addresses. The beach lists stay in the
  # work folder, so Overpass is asked only for an area with none.
  builder = pkgs.writeShellApplication {
    name = "marola-boards-build";
    runtimeInputs = [ config.virtualisation.podman.package pkgs.coreutils pkgs.findutils ];
    text = ''
      image=${lib.escapeShellArg bcfg.image}
      work=/var/lib/marola-boards-build
      out=${boards}
      install -d -o marola -g marola "$work/site" "$work/site/beaches"
      install -m 0644 -o marola -g marola ${cfg.package.areas} "$work/site/areas.json"
      rm -rf "$work/site/dist"
      install -d -o marola -g marola "$work/site/dist"
      if ! podman image exists "$image"; then
        if [ -n "''${CREDENTIALS_DIRECTORY:-}" ] && [ -f "$CREDENTIALS_DIRECTORY/ghcr-token" ]; then
          podman login --authfile "$RUNTIME_DIRECTORY/auth.json" -u ${lib.escapeShellArg bcfg.registryUser} \
            --password-stdin ghcr.io < "$CREDENTIALS_DIRECTORY/ghcr-token"
          podman pull --authfile "$RUNTIME_DIRECTORY/auth.json" "$image"
          rm -f "$RUNTIME_DIRECTORY/auth.json"
        else
          podman pull "$image"
        fi
      fi
      # Two tries, as marola-site's site.yml does: INEA, INEMA and Overpass time out now and then.
      # A failed run still keeps the areas it wrote before it failed, so the copy below always runs.
      status=1
      for attempt in 1 2; do
        if podman run --rm --memory ${bcfg.memory} --user "$(id -u marola):$(id -g marola)" -e HOME=/tmp \
          -v "$work/site:/work/site" -w /work "$image" \
          --site --areas site/areas.json --site-out site/dist; then
          status=0
          break
        fi
        echo "marola-boards: build attempt $attempt failed" >&2
        [ "$attempt" -eq 2 ] || sleep 60
      done
      # Only what the build wrote, area by area; an area it did not write keeps its old boards.
      for dir in "$work/site/dist/data"/*/; do
        area=$(basename "$dir")
        [ -f "$dir/latest.json" ] || continue
        tmp=$(mktemp -d "$out/.incoming.XXXXXX")
        cp -r "$dir". "$tmp/"
        chown -R marola:marola "$tmp"
        chmod 0755 "$tmp"
        rm -rf "$out/$area.old"
        if [ -d "$out/$area" ]; then mv "$out/$area" "$out/$area.old"; fi
        mv "$tmp" "$out/$area"
        rm -rf "$out/$area.old"
        echo "marola-boards: $area built" >&2
      done
      if [ -f "$work/site/dist/data/areas.json" ]; then
        install -m 0644 -o marola -g marola "$work/site/dist/data/areas.json" "$out/areas.json"
      fi
      # Old image versions, after a pin moves.
      podman image prune -f >/dev/null || true
      exit "$status"
    '';
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
    redirects = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "www.marola.dev" "marola.piabrota.art" ];
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
        ExecStart = lib.getExe mirror;
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
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe builder;
        StateDirectory = [ "marola-boards-build" "marola-boards" ];
        RuntimeDirectory = "marola-boards-build";
        RuntimeDirectoryMode = "0700";
        TimeoutStartSec = "45min";
      } // optionalAttrs (bcfg.tokenFile != null) {
        LoadCredential = "ghcr-token:${bcfg.tokenFile}";
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
      path = [ pkgs.sqlite pkgs.rsync pkgs.coreutils pkgs.findutils ];
      script = ''
        set -euo pipefail
        dest=/var/backups/marola
        install -d -m 0700 "$dest" "$dest/studies"
        if [ -f ${state}/marola.db ]; then
          sqlite3 ${state}/marola.db ".backup '$dest/marola-$(date +%F).db'"
          chmod 0600 "$dest/marola-$(date +%F).db"
        fi
        if [ -f ${state}/csrf.key ]; then install -m 0600 ${state}/csrf.key "$dest/csrf.key"; fi
        if [ -d ${state}/studies ]; then rsync -a --exclude .incoming ${state}/studies/ "$dest/studies/"; fi
        find "$dest" -maxdepth 1 -name 'marola-*.db' -mtime +14 -delete
      '';
      serviceConfig.Type = "oneshot";
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
      virtualHosts = {
        ${cfg.domain} = {
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
        };
      } // lib.genAttrs cfg.redirects (_: {
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
