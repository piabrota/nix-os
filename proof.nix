# proof.piabrota.art: every HTML page of h0ffmann/proof and piabrota/pirsig, with an index of them
# (proof-site/), static files served by nginx with Let's Encrypt on their own name, HTTPS only. On
# piabrota2 (hosts/piabrota2), like the room: www.piabrota.art points at piabrota.
# The name must point at the box before this is on, or the ACME order fails on the deploy and
# deploy-rs rolls the switch back (docs/SITE.md, "DNS on Porkbun").
{ config, lib, pkgs, ... }:
let
  inherit (lib) mkEnableOption mkIf mkOption types;
  cfg = config.piabrota.proof;
in
{
  options.piabrota.proof = {
    enable = mkEnableOption "proof.piabrota.art, the HTML pages of h0ffmann/proof and piabrota/pirsig";
    domain = mkOption {
      type = types.str;
      default = "proof.piabrota.art";
      description = "The name nginx serves the pages on. Its DNS A record must point at the box.";
    };
    root = mkOption {
      type = types.path;
      # TeX Live, ffmpeg, node and archify run on the builder; the box gets only the files.
      default = pkgs.callPackage ./proof-site { };
      defaultText = lib.literalExpression "pkgs.callPackage ./proof-site { }, the pages and their index";
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
        locations = config.piabrota.favicon.locations // {
          # A new pin is a new store path, and the pages keep their names: ask for them again.
          "/".extraConfig = ''
            add_header Cache-Control "no-cache";
          '';
          # The archify pages open dark, whatever the reader's setting (the owner, 2026-11-09):
          # without ?theme=dark in the address, which archify reads first, nginx sends the visitor
          # there. proof-site/default.nix fails if an archify page is outside these folders.
          # The page's name is captured from a closed set of characters: $uri could carry a
          # newline into the Location header (gixy's http_splitting).
          "~ ^/(?<page>(proof/docs/diagrams/(en|pt-BR)|pirsig/figures)/[A-Za-z0-9._-]+\\.html)$".extraConfig = ''
            if ($arg_theme != "dark") {
              return 302 "/$page?theme=dark";
            }
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
