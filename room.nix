# The room (piabrota/room, built by room-site/): static files served by nginx with Let's Encrypt
# on its own name, HTTPS only. On piabrota2 (hosts/piabrota2) at room.piabrota.art; it is not a
# path of www.piabrota.art, because that name points at piabrota.
# The name must point at the box before this is on, or the ACME order fails on the deploy and
# deploy-rs rolls the switch back (docs/SITE.md, "DNS on Porkbun").
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
        };
      };
    };

    security.acme = {
      acceptTerms = true;
      defaults.email = config.piabrota.loco.acmeEmail;
    };

    networking.firewall.allowedTCPPorts = [ 80 443 ];
  };
}
