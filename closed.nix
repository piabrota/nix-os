# closed.piabrota.art: the site of h0ffmann/closed-source (the book *The god that failed*), which
# that repository builds and publishes to GitHub Pages at h0ffmann.github.io/closed-source on each
# push to its main. nginx passes each request to Pages, so the box keeps no copy and builds nothing:
# the PDFs need TeX Live and the content generator Erlang, both too heavy for the closure. On
# piabrota2 (hosts/piabrota2), like wave. The name must point at the box before this is on, or the
# ACME order fails on the deploy (docs/SITE.md, "DNS on Porkbun").
{ config, lib, ... }:
let
  inherit (lib) mkEnableOption mkIf mkOption types;
  cfg = config.piabrota.closedSource;
in
{
  options.piabrota.closedSource = {
    enable = mkEnableOption "closed.piabrota.art, the site of h0ffmann/closed-source";
    domain = mkOption {
      type = types.str;
      default = "closed.piabrota.art";
      description = "The name nginx serves the closed-source site on. Its DNS A record must point at the box.";
    };
    upstream = mkOption {
      type = types.str;
      default = "h0ffmann.github.io";
      description = "The GitHub Pages host that publishes the site.";
    };
    path = mkOption {
      type = types.str;
      default = "/closed-source";
      description = "The path of the site on `upstream`, with no slash at the end.";
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
        # The site names its own icon (icons/favicon.svg), so favicon.nix's locations are not added.
        locations."/".extraConfig = ''
          # A name in a variable is resolved when a request comes, not when nginx starts: if DNS
          # does not answer at boot, nginx still starts and the other vhosts of the box stay up.
          resolver 8.8.8.8 1.1.1.1 valid=300s ipv6=off;
          resolver_timeout 5s;
          set $pages ${cfg.upstream};
          proxy_pass https://$pages${cfg.path}$request_uri;
          # Only these headers go to Pages: the visitor's address (X-Forwarded-For) does not.
          proxy_set_header Host $pages;
          proxy_ssl_server_name on;
          proxy_ssl_name $pages;
          proxy_ssl_verify on;
          proxy_ssl_trusted_certificate /etc/ssl/certs/ca-certificates.crt;
          # Pages sends /closed-source to /closed-source/ with its own name in Location.
          proxy_redirect https://${cfg.upstream}${cfg.path}/ /;
          proxy_redirect http://${cfg.upstream}${cfg.path}/ /;
        '';
      };
    };

    security.acme = {
      acceptTerms = true;
      defaults.email = config.piabrota.loco.acmeEmail;
    };

    networking.firewall.allowedTCPPorts = [ 80 443 ];
  };
}
