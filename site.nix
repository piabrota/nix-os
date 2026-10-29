# A static site on the apex domain: the files in site/, served by nginx with Let's Encrypt.
# Off by default. piabrota.art (and www) must point at the box before it is turned on, or the
# ACME order fails on the deploy and deploy-rs rolls the switch back. See docs/SITE.md.
{ config, lib, ... }:
let
  inherit (lib) mkEnableOption mkIf mkOption types mapAttrs' nameValuePair;
  cfg = config.piabrota.site;
in
{
  options.piabrota.site = {
    enable = mkEnableOption "the static site in site/";
    domain = mkOption {
      type = types.str;
      default = "piabrota.art";
      description = "The name nginx serves the site on. Its DNS A record must point at the box.";
    };
    aliases = mkOption {
      type = types.listOf types.str;
      default = [ "www.piabrota.art" ];
      description = "More names for the same site; each needs its own DNS record, ACME checks them all.";
    };
    root = mkOption {
      type = types.path;
      default = lib.fileset.toSource {
        root = ./site;
        fileset = ./site;
      };
      defaultText = lib.literalExpression "./site, copied into the store";
      description = "The directory nginx serves. Read-only: the store.";
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
      virtualHosts.${cfg.domain} = {
        serverAliases = cfg.aliases;
        enableACME = true;
        forceSSL = true;
        inherit (cfg) root;
        locations = mapAttrs'
          (path: url: nameValuePair "= ${path}" { return = "302 ${url}"; })
          cfg.redirects;
      };
    };

    security.acme = {
      acceptTerms = true;
      defaults.email = config.piabrota.loco.acmeEmail;
    };

    networking.firewall.allowedTCPPorts = [ 80 443 ];
  };
}
