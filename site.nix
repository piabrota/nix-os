# A static site: the files in site/, served by nginx with Let's Encrypt on www.piabrota.art, over
# HTTP and HTTPS. piabrota.art answers with a redirect to https://www, keeping the path.
# Every name here must point at the box before the site is turned on, or the ACME order fails on
# the deploy and deploy-rs rolls the switch back. See docs/SITE.md.
{ config, lib, pkgs, ... }:
let
  inherit (lib) mkEnableOption mkIf mkMerge mkOption types mapAttrs' nameValuePair genAttrs;
  cfg = config.piabrota.site;
  # addSSL serves the same files on HTTP and HTTPS; forceSSL answers HTTP with a redirect.
  tls = if cfg.httpsOnly then { forceSSL = true; } else { addSSL = true; };
in
{
  options.piabrota.site = {
    enable = mkEnableOption "the static site in site/";
    domain = mkOption {
      type = types.str;
      default = "www.piabrota.art";
      description = "The name nginx serves the site on. Its DNS A record must point at the box.";
    };
    redirectFrom = mkOption {
      type = types.listOf types.str;
      default = [ "piabrota.art" ];
      description = "Names that answer with a 301 to `domain` (HTTPS), same path. Each needs its own DNS record; ACME checks them all.";
    };
    httpsOnly = mkOption {
      type = types.bool;
      default = false;
      description = "Redirect HTTP to HTTPS. Off: the site is served on both.";
    };
    root = mkOption {
      type = types.path;
      # Gleam runs on the builder; the box gets only the pages, static/ and mu.svg (site/default.nix).
      default = pkgs.callPackage ./site { inherit (cfg.analytics) measurementId; };
      defaultText = lib.literalExpression "pkgs.callPackage ./site { inherit (cfg.analytics) measurementId; }, the prerendered pages";
      description = "The directory nginx serves. Read-only: the store.";
    };
    analytics.measurementId = mkOption {
      type = types.strMatching "(G-[A-Z0-9]+)?";
      default = "";
      example = "G-XXXXXXXXXX";
      description = "Google Analytics 4 measurement ID. Empty: no analytics, and the pages load no script. Set: every page loads Google's tag (gtag.js). It is public: it ends up in every page's source.";
    };
    redirects = mkOption {
      type = types.attrsOf types.str;
      # The README has linked piabrota.art/nixos since Porkbun forwarded it; keep the link working.
      default = { "/nixos" = "https://github.com/piabrota/nix-os"; };
      description = "Exact paths that answer with a 302 to a URL.";
    };
    redirect302 = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = { "hffmnn.piabrota.art" = "https://h0ffmann.github.io/h0ffmann/"; };
      description = "Names that answer with a 302 to a URL, each on a virtual host of its own. Each name needs its own DNS A record and its own certificate: it must point at the box before the deploy, or the ACME order fails and deploy-rs rolls the switch back.";
    };
  };

  config = mkIf cfg.enable {
    services.nginx = {
      enable = true;
      recommendedTlsSettings = true;
      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      serverTokens = false;
      virtualHosts = mkMerge [
        {
          ${cfg.domain} = tls // {
            enableACME = true;
            inherit (cfg) root;
            locations = mapAttrs'
              (path: url: nameValuePair "= ${path}" { return = "302 ${url}"; })
              cfg.redirects;
          };
        }
        (genAttrs cfg.redirectFrom (_: tls // {
          enableACME = true;
          globalRedirect = cfg.domain;
        }))
        # `redirect302` names answer with a 302 to their URL, on a virtual host of their own, with
        # a certificate of their own: each name must point at the box before the deploy.
        (mapAttrs'
          (name: url: nameValuePair name (tls // {
            enableACME = true;
            locations."/".return = "302 ${url}";
          }))
          cfg.redirect302)
      ];
    };

    security.acme = {
      acceptTerms = true;
      defaults.email = config.piabrota.loco.acmeEmail;
    };

    networking.firewall.allowedTCPPorts = [ 80 443 ];
  };
}
