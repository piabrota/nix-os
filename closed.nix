# closed.piabrota.art: the website of h0ffmann/closed-source (the book *The god that failed*), built
# by closed-site/ at a pinned commit of that repository. Static files served by nginx with Let's
# Encrypt on their own name, HTTPS only. On piabrota2 (hosts/piabrota2), like wave. GitHub Pages
# still publishes the same site at h0ffmann.github.io/closed-source. The name must point at the box
# before this is on, or the ACME order fails on the deploy (docs/SITE.md, "DNS on Porkbun").
{ config, lib, pkgs, ... }:
let
  inherit (lib) mkEnableOption mkIf mkOption types;
  cfg = config.piabrota.closedSource;
in
{
  options.piabrota.closedSource = {
    enable = mkEnableOption "closed.piabrota.art, the website of h0ffmann/closed-source";
    domain = mkOption {
      type = types.str;
      default = "closed.piabrota.art";
      description = "The name nginx serves the closed-source website on. Its DNS A record must point at the box.";
    };
    root = mkOption {
      type = types.path;
      # Gleam, Erlang, node and pandoc run on the builder; the box gets only the files.
      default = pkgs.callPackage ./closed-site { };
      defaultText = lib.literalExpression "pkgs.callPackage ./closed-site { }, the prerendered site";
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
        # The site names its own icon (icons/favicon.svg), so favicon.nix's locations are not added.
        locations = {
          # A new pin is a new store path, and the files keep their names: ask for them again.
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
