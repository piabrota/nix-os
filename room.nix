# The room (piabrota/room, built by room-site/): static files served by nginx with Let's Encrypt
# on its own name, HTTPS only. On piabrota2 (hosts/piabrota2) at room.piabrota.art; it is not a
# path of www.piabrota.art, because that name points at piabrota.
# The name must point at the box before this is on, or the ACME order fails on the deploy and
# deploy-rs rolls the switch back (docs/SITE.md, "DNS on Porkbun").
# Beside the files, the radio's live listeners count (room-site/listeners.nix) listens on
# localhost only, and nginx passes /live/ on the same name to it, unbuffered.
# grid.piabrota.art (`grid`) is the same room, opened on its ▲ grid view (the shot `grid`, key 0):
# the room has no address for a shot, so this copy of index.html calls the room's own
# window.__room.rig.go('grid') once the room has loaded. It must point at the box too.
{ config, lib, pkgs, ... }:
let
  inherit (lib) mkEnableOption mkIf mkOption types;
  cfg = config.piabrota.room;

  # The room's files, with one script more in index.html: it waits for the HIFI room (main.js
  # loads app.js, which sets window.__room last) and lands the camera on the chart, which opens the
  # map. LOFI has no room, so it gives up after 30 s and the LOFI page stays.
  gridRoot = pkgs.runCommand "piabrota-room-grid" { allowedReferences = [ ]; } ''
    cp -R ${cfg.root} $out
    chmod -R u+w $out
    grep -q '</body>' $out/index.html
    substituteInPlace $out/index.html --replace-fail '</body>' \
      "<script>(function g(n){var r=window.__room;if(r&&r.rig){r.rig.go('grid',true)}else if(n<300){setTimeout(function(){g(n+1)},100)}})(0)</script></body>"
  '';

  # The room's locations, the same on both names.
  locations = config.piabrota.favicon.locations // {
    # Vite puts a content hash in every file name under assets/, so they never change.
    "/assets/".extraConfig = ''
      add_header Cache-Control "public, max-age=31536000, immutable";
    '';
    # The page itself is always asked for again, so a new build shows at once.
    "= /index.html".extraConfig = ''
      add_header Cache-Control "no-cache";
    '';
    # The listeners count: server-sent events, so no buffering and a long read. The
    # counter sends a comment every 25 s, well inside the timeout.
    "/live/" = {
      proxyPass = "http://127.0.0.1:${toString cfg.listeners.port}";
      recommendedProxySettings = true;
      extraConfig = ''
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 1h;
        proxy_send_timeout 1h;
      '';
    };
  };
in
{
  options.piabrota.room = {
    enable = mkEnableOption "the room, piabrota/room's static site";
    domain = mkOption {
      type = types.str;
      default = "room.piabrota.art";
      description = "The name nginx serves the room on. Its DNS A record must point at the box.";
    };
    root = mkOption {
      type = types.path;
      # npm and vite run on the builder; the box gets only dist/ (room-site/default.nix).
      default = pkgs.callPackage ./room-site { };
      defaultText = lib.literalExpression "pkgs.callPackage ./room-site { }, the room's dist/";
      description = "The directory nginx serves. Read-only: the store.";
    };

    grid = {
      enable = mkEnableOption "the room on a second name, opened on its ▲ grid view";
      domain = mkOption {
        type = types.str;
        default = "grid.piabrota.art";
        description = "The name of the grid view. Its DNS A record must point at the box.";
      };
    };

    listeners = {
      package = mkOption {
        type = types.package;
        default = pkgs.callPackage ./room-site/listeners.nix { };
        defaultText = lib.literalExpression "pkgs.callPackage ./room-site/listeners.nix { }";
        description = "The listeners counter, from the same commit of piabrota/room as the site.";
      };
      port = mkOption {
        type = types.port;
        default = 8787;
        description = "The port the counter listens on, on 127.0.0.1 only. nginx passes /live/ to it.";
      };
      max = mkOption {
        type = types.ints.positive;
        # Each listener holds two of nginx's connections (the visitor's and the one to the
        # counter), and a worker has 512 by default; 500 keeps the rest of the box answering.
        default = 500;
        description = "The most listeners counted at once; past it the counter answers 503.";
      };
    };
  };

  config = mkIf cfg.enable {
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
          inherit (cfg) root;
          # favicon.nix replaces the room's own /favicon.svg, the same eye, with the shared file.
          inherit locations;
        };
      } // lib.optionalAttrs cfg.grid.enable {
        ${cfg.grid.domain} = {
          forceSSL = true;
          enableACME = true;
          root = gridRoot;
          inherit locations;
        };
      };
    };

    systemd.services.room-listeners = {
      description = "piabrota RADIO's live listeners count";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      environment = {
        HOST = "127.0.0.1";
        PORT = toString cfg.listeners.port;
        MAX = toString cfg.listeners.max;
      };
      serviceConfig = {
        ExecStart = lib.getExe cfg.listeners.package;
        Restart = "always";
        RestartSec = 5;
        DynamicUser = true;
        MemoryMax = "256M";
        TasksMax = 64;
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
        RestrictNamespaces = true;
        LockPersonality = true;
        CapabilityBoundingSet = "";
        SystemCallArchitectures = "native";
      };
    };

    security.acme = {
      acceptTerms = true;
      defaults.email = config.piabrota.loco.acmeEmail;
    };

    networking.firewall.allowedTCPPorts = [ 80 443 ];
  };
}
