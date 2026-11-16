# The room (piabrota/room, built by room-site/): static files served by nginx with Let's Encrypt
# on its own name, HTTPS only. On piabrota2 (hosts/piabrota2) at room.piabrota.art; it is not a
# path of www.piabrota.art, because that name points at piabrota.
# The name must point at the box before this is on, or the ACME order fails on the deploy and
# deploy-rs rolls the switch back (docs/SITE.md, "DNS on Porkbun").
# Beside the files, the radio's live listeners count (room-site/listeners.nix) listens on
# localhost only, and nginx passes /live/ on the same name to it, unbuffered. The same server keeps
# the emails visitors leave at the room's door (POST /live/door) in its state directory.
# grid.piabrota.art (`grid`) is the same room and the same files: the room opens on its ▲ grid view
# (the shot `grid`, key 0) by itself when it sees that name (`grid.host` in its src/config.js,
# piabrota/room#28). It must point at the box too.
{ config, lib, pkgs, ... }:
let
  inherit (lib) mkEnableOption mkIf mkOption types;
  cfg = config.piabrota.room;

  # The room's locations, the same on both names.
  locations = config.piabrota.favicon.locations // {
    # Vite puts a content hash in every file name under assets/, so they never change.
    "/assets/".extraConfig = ''
      add_header Cache-Control "public, max-age=31536000, immutable";
    '';
    # The room asks for a file of public/ as path?v=<8 hex of its SHA-256> (piabrota/room#51,
    # src/files.js): with that hash the file never changes; without it, it is asked for again.
    "~ ^/(models|textures|audio|grid)/".extraConfig = ''
      add_header Cache-Control $room_public_cache;
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
        description = "The name of the grid view: the room's `grid.host`. Its DNS A record must point at the box.";
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
      # brotli, and brotli_static: the room's build writes a .br copy beside its files
      # (piabrota/room#51), and nginx sends that copy as it is.
      recommendedBrotliSettings = true;
      recommendedOptimisation = true;
      commonHttpConfig = ''
        map $arg_v $room_public_cache {
          default          "no-cache";
          "~^[0-9a-f]{8}$" "public, max-age=31536000, immutable";
        }
      '';
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
          inherit (cfg) root;
          inherit locations;
        };
      };
    };

    # Beside the count, the room's door (piabrota/room#31): a visitor leaves an email to try its
    # lock, POST /live/door, and the counter appends it, with the time, to door.tsv in its own
    # state directory, readable by root only (/var/lib/private/room-listeners/door.tsv, since the
    # user is dynamic). Nothing else about the visitor is kept.
    systemd.services.room-listeners = {
      description = "piabrota RADIO's live listeners count, and the emails left at the room's door";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      environment = {
        HOST = "127.0.0.1";
        PORT = toString cfg.listeners.port;
        MAX = toString cfg.listeners.max;
        DOOR_FILE = "/var/lib/room-listeners/door.tsv";
      };
      serviceConfig = {
        ExecStart = lib.getExe cfg.listeners.package;
        Restart = "always";
        RestartSec = 5;
        DynamicUser = true;
        StateDirectory = "room-listeners";
        StateDirectoryMode = "0700";
        UMask = "0077";
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
