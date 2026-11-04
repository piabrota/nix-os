# Hermes's own web dashboard (`hermes dashboard`, from the package hermes.nix installs) at
# https://hermes.piabrota.art, for the owner only. See docs/HERMES.md, "The web dashboard".
#
# The backend binds to loopback, so upstream's auth gate stays off and the backend accepts only
# loopback peers. nginx is the gate: TLS from Let's Encrypt and HTTP basic auth against a bcrypt
# file on the box, outside the store. Upstream's own username/password provider is "for a trusted
# network only", so it is not the gate here.
# The DNS record must point at the box before this is on, or the ACME order fails on the deploy.
{ config, lib, ... }:
let
  inherit (lib) mkEnableOption mkIf mkOption types;
  cfg = config.piabrota.hermesWeb;
  hermes = config.services.hermes-agent;
  backend = "127.0.0.1:${toString hermes.backend.port}";
  # A page on another site cannot use the owner's basic-auth session to write: any Origin but the
  # dashboard's own is refused before the backend sees it.
  origin = "https://${cfg.domain}";
  # The Documentation tab frames this address and its button opens it (web/src/pages/DocsPage.tsx
  # upstream). The address is a literal in the built bundle, so nginx swaps it on the way;
  # checks.hermes-docs-url fails when an upstream bump renames it.
  upstreamDocs = "https://hermes-agent.nousresearch.com/docs/";
  docsPath = "/piabrota-docs/";
in
{
  options.piabrota.hermesWeb = {
    enable = mkEnableOption "Hermes's web dashboard behind nginx, TLS and basic auth";
    domain = mkOption {
      type = types.str;
      default = "hermes.piabrota.art";
      description = "The name nginx serves the dashboard on. Its DNS A record must point at the box.";
    };
    htpasswdFile = mkOption {
      # A string, not a path: a path literal copies the file into the world-readable store.
      type = types.str;
      default = "/var/lib/hermes-web-secrets/htpasswd";
      description = ''
        The basic-auth users, one `name:bcrypt-hash` line each (`htpasswd -B`), written by hand on
        the box: mode 0640, owner root, group nginx. Without it every request gets a 500, so the
        dashboard stays closed until the file exists.
      '';
    };
    docs = mkOption {
      type = types.path;
      default = ./hermes-web/docs;
      description = ''
        A directory with an index.html that the Documentation tab shows in place of upstream's
        docs, served at ${docsPath} behind the same basic auth.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [{
      assertion = hermes.enable;
      message = "piabrota.hermesWeb needs services.hermes-agent (hermes.nix) on the same host.";
    }];

    # The unit hermes-backend, from the upstream module: the same user, package and HERMES_HOME as
    # the gateway, a separate process. Loopback only: the firewall never opens its port.
    services.hermes-agent.backend = {
      mode = "dashboard";
      host = "127.0.0.1";
    };
    # A cap of its own, so a runaway Chat tab (it runs an agent in this unit) cannot take the box.
    systemd.services.hermes-backend.serviceConfig.MemoryMax = lib.mkDefault "2G";

    systemd.tmpfiles.rules = [ "d /var/lib/hermes-web-secrets 0750 root nginx -" ];

    services.nginx = {
      enable = true;
      recommendedTlsSettings = true;
      serverTokens = false;
      # Slows a password guesser; the dashboard's page loads stay within the burst.
      appendHttpConfig = ''
        limit_req_zone $binary_remote_addr zone=hermes_web:1m rate=10r/s;
        map $http_origin $hermes_web_foreign_origin {
          default 1;
          "" 0;
          "${origin}" 0;
        }
      '';
      virtualHosts.${cfg.domain} = {
        forceSSL = true;
        enableACME = true;
        basicAuthFile = cfg.htpasswdFile;
        extraConfig = ''
          limit_req zone=hermes_web burst=60 nodelay;
          limit_req_status 429;
          # SAMEORIGIN, not DENY: the Documentation tab frames ${docsPath}.
          add_header X-Frame-Options SAMEORIGIN always;
          add_header Referrer-Policy no-referrer always;
          add_header X-Content-Type-Options nosniff always;
          add_header Strict-Transport-Security "max-age=31536000" always;
          if ($hermes_web_foreign_origin) { return 403; }
        '';
        locations = {
          "/" = {
            proxyPass = "http://${backend}";
            proxyWebsockets = true;
            # loco.nix turns these on for every location; they would send the public Host and an
            # X-Forwarded-For, which the backend refuses.
            recommendedProxySettings = false;
            # The backend refuses a Host or a WebSocket Origin that is not its loopback address
            # (DNS-rebinding guard), and with no X-Forwarded-For it sees nginx as a loopback peer.
            # The Origin was checked above.
            extraConfig = ''
              proxy_set_header Host ${backend};
              proxy_set_header Origin "";
              proxy_set_header X-Forwarded-For "";
              proxy_set_header Authorization "";
              # sub_filter needs the body uncompressed.
              proxy_set_header Accept-Encoding "";
              sub_filter_types application/javascript text/javascript;
              sub_filter_once off;
              sub_filter '"${upstreamDocs}"' '"${docsPath}"';
              proxy_read_timeout 1h;
              proxy_send_timeout 1h;
              client_max_body_size 32m;
            '';
          };
          # Never show a secret's value in the browser: the token and the bot tokens stay on the
          # box. Edits to .env are refused too, since activation writes it from the env file on
          # every deploy (hermes.nix).
          "= /api/env/reveal".return = "403";
          ${docsPath} = {
            alias = "${cfg.docs}/";
            index = "index.html";
          };
          "/api/env" = {
            proxyPass = "http://${backend}";
            recommendedProxySettings = false;
            extraConfig = ''
              limit_except GET { deny all; }
              proxy_set_header Host ${backend};
              proxy_set_header Origin "";
              proxy_set_header X-Forwarded-For "";
              proxy_set_header Authorization "";
            '';
          };
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
