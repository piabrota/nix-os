# The room (piabrota/room, built by room-site/): static files served by nginx with Let's Encrypt
# on its own name, HTTPS only. On piabrota2 (hosts/piabrota2) at room.piabrota.art; it is not a
# path of www.piabrota.art, because that name points at piabrota.
# The name must point at the box before this is on, or the ACME order fails on the deploy and
# deploy-rs rolls the switch back (docs/SITE.md, "DNS on Porkbun").
# Beside the files, the radio's live listeners count (room-site/listeners.nix) listens on
# localhost only, and nginx passes /live/ on the same name to it, unbuffered.
{ config, lib, pkgs, ... }:
let
  inherit (lib) mkEnableOption mkIf mkOption types;
  cfg = config.piabrota.room;
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
      virtualHosts.${cfg.domain} = {
        forceSSL = true;
        enableACME = true;
        inherit (cfg) root;
        locations = {
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
