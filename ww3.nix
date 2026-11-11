# ww3.piabrota.art: the website of the WW3 GPU Lab (h0ffmann/ww3-gpu), the front page and the
# lineage page prerendered from Gleam by ww3-site/ at a pinned ww3-gpu commit. Static files served by
# nginx with Let's Encrypt on their own name, HTTPS only. On piabrota2 (hosts/piabrota2), like proof.
# The name must point at the box before this is on, or the ACME order fails on the deploy and
# deploy-rs rolls the switch back (docs/SITE.md, "DNS on Porkbun").
{ config, lib, pkgs, ... }:
let
  inherit (lib) mkEnableOption mkIf mkOption types;
  cfg = config.piabrota.ww3;
in
{
  options.piabrota.ww3 = {
    enable = mkEnableOption "ww3.piabrota.art, the website of h0ffmann/ww3-gpu";
    domain = mkOption {
      type = types.str;
      default = "ww3.piabrota.art";
      description = "The name nginx serves the ww3-gpu website on. Its DNS A record must point at the box.";
    };
    root = mkOption {
      type = types.path;
      # Gleam and node run on the builder; the box gets only the pages.
      default = pkgs.callPackage ./ww3-site { };
      defaultText = lib.literalExpression "pkgs.callPackage ./ww3-site { }, the prerendered pages";
      description = "The directory nginx serves on `domain`. Read-only: the store.";
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
        # The site names its own icon (ww3-site/static/favicon.svg), as the room does, so the eye's
        # locations of favicon.nix are not added here.
        locations = {
          # A new pin is a new store path, and the pages keep their names: ask for them again.
          "/".extraConfig = ''
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
