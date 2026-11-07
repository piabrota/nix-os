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
      default = pkgs.callPackage ./site { inherit (cfg.analytics) measurementId; inherit (cfg) hermes; };
      defaultText = lib.literalExpression "pkgs.callPackage ./site { inherit (cfg.analytics) measurementId; inherit (cfg) hermes; }, the prerendered pages";
      description = "The directory nginx serves. Read-only: the store.";
    };
    skills = mkOption {
      type = types.nullOr types.path;
      # Gleam and erlang run on the builder; the box gets only the pages (skills-site/default.nix).
      default = pkgs.callPackage ./skills-site { };
      defaultText = lib.literalExpression "pkgs.callPackage ./skills-site { }, the prerendered skills website";
      description = "The skills website, served at /skills/. Read-only: the store. null: no /skills page.";
    };
    figures = mkOption {
      type = types.nullOr types.path;
      # Archify, node and jq run on the builder; the box gets only the pages (figures-site/default.nix).
      default = pkgs.callPackage ./figures-site { };
      defaultText = lib.literalExpression "pkgs.callPackage ./figures-site { }, the figures as interactive pages";
      description = "The figures as interactive pages, served at /figures/. Read-only: the store. null: no /figures page.";
    };
    hermes = mkOption {
      type = types.nullOr types.attrs;
      internal = true;
      # The /hermes page: hermes.nix's settings as YAML, from this system's own evaluation.
      default =
        if config.services ? hermes-agent && config.services.hermes-agent.enable then
          import ./site/hermes.nix
            {
              inherit lib;
              cfg = config.services.hermes-agent;
              unit = config.systemd.services.hermes-agent.serviceConfig;
              lock = (lib.importJSON ./flake.lock).nodes.hermes-agent.locked;
            }
        else null;
      defaultText = lib.literalMD "the facts of `site/hermes.nix`, when Hermes is on";
      description = "What the /hermes page shows. null: no /hermes page.";
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
            # The icon (favicon.nix), the redirects and the sub-sites.
            locations = config.piabrota.favicon.locations // mapAttrs'
              (path: url: nameValuePair "= ${path}" { return = "302 ${url}"; })
              cfg.redirects
              // lib.optionalAttrs (cfg.skills != null) {
              # The pages use relative links, so the slash matters.
              "= /skills".return = "301 /skills/";
              "/skills/".alias = "${cfg.skills}/";
            }
              // lib.optionalAttrs (cfg.figures != null) {
              # The pages use relative links, so the slash matters.
              "= /figures".return = "301 /figures/";
              "/figures/".alias = "${cfg.figures}/";
            };
          };
        }
        (genAttrs cfg.redirectFrom (_: tls // {
          enableACME = true;
          globalRedirect = cfg.domain;
        }))
      ];
    };

    security.acme = {
      acceptTerms = true;
      defaults.email = config.piabrota.loco.acmeEmail;
    };

    networking.firewall.allowedTCPPorts = [ 80 443 ];
  };
}
