# proof.piabrota.art: every HTML page of h0ffmann/proof, with an index (proof-site/), and
# pirsig.piabrota.art: the video notes and archify figures of piabrota/pirsig, with an index
# (proof-site/pirsig.nix). Static files served by nginx with Let's Encrypt on their own names, HTTPS
# only. On piabrota2 (hosts/piabrota2), like the room: www.piabrota.art points at piabrota.
# Both names must point at the box before this is on, or the ACME order fails on the deploy and
# deploy-rs rolls the switch back (docs/SITE.md, "DNS on Porkbun").
{ config, lib, pkgs, ... }:
let
  inherit (lib) mkEnableOption mkIf mkOption types;
  cfg = config.piabrota.proof;

  # One vhost. `darkPages` is the path, in a regex, of the folders of its archify pages.
  vhost = root: darkPages: {
    forceSSL = true;
    enableACME = true;
    inherit root;
    locations = config.piabrota.favicon.locations // {
      # A new pin is a new store path, and the pages keep their names: ask for them again.
      "/".extraConfig = ''
        add_header Cache-Control "no-cache";
      '';
      # The archify pages open dark, whatever the reader's setting (the owner, 2026-11-09):
      # without ?theme=dark in the address, which archify reads first, nginx sends the visitor
      # there. proof-site/*.nix fail if an archify page is outside these folders.
      # The page's name is captured from a closed set of characters: $uri could carry a
      # newline into the Location header (gixy's http_splitting).
      "~ ^/(?<page>${darkPages}/[A-Za-z0-9._-]+\\.html)$".extraConfig = ''
        if ($arg_theme != "dark") {
          return 302 "/$page?theme=dark";
        }
        add_header Cache-Control "no-cache";
      '';
    };
  };
in
{
  options.piabrota.proof = {
    enable = mkEnableOption "proof.piabrota.art, the HTML pages of h0ffmann/proof, and pirsig.piabrota.art, those of piabrota/pirsig";
    domain = mkOption {
      type = types.str;
      default = "proof.piabrota.art";
      description = "The name nginx serves the pages of h0ffmann/proof on. Its DNS A record must point at the box.";
    };
    root = mkOption {
      type = types.path;
      # TeX Live, node and jq run on the builder; the box gets only the files.
      default = pkgs.callPackage ./proof-site { };
      defaultText = lib.literalExpression "pkgs.callPackage ./proof-site { }, the pages and their index";
      description = "The directory nginx serves on `domain`. Read-only: the store.";
    };
    pirsig.domain = mkOption {
      type = types.str;
      default = "pirsig.piabrota.art";
      description = "The name nginx serves the pages of piabrota/pirsig on. Its DNS A record must point at the box.";
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
        ${cfg.domain} = vhost cfg.root "proof/docs/diagrams/(en|pt-BR)";
        # ffmpeg, node and archify run on the builder; the box gets only the files.
        ${cfg.pirsig.domain} = vhost (pkgs.callPackage ./proof-site/pirsig.nix { }) "figures";
      };
    };

    security.acme = {
      acceptTerms = true;
      defaults.email = config.piabrota.loco.acmeEmail;
    };

    networking.firewall.allowedTCPPorts = [ 80 443 ];
  };
}
