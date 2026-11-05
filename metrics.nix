# Live metrics with Beszel (github.com/henrygd/beszel): a hub with a web UI and one agent on each
# host. The hub runs on piabrota2 at metrics.piabrota.art; the agent runs on both hosts and dials
# out to the hub over a WebSocket, so piabrota opens no port. docs/METRICS.md says what it is,
# shows and costs, and how to set it up.
#
# Everything is off by default. The hub's name must point at its host before `hub.enable` is on,
# or the ACME order fails on the deploy and deploy-rs rolls the switch back (docs/SITE.md, "DNS on
# Porkbun"). The agent's KEY and TOKEN come from the hub's UI and live only in an environment file
# on the box (`agent.environmentFile`), never here and never in the store.
{ config, lib, pkgs, ... }:
let
  inherit (lib) mkEnableOption mkIf mkMerge mkOption types;
  cfg = config.piabrota.metrics;
  hubPort = config.services.beszel.hub.port;
  hubAddress = "http://127.0.0.1:${toString hubPort}";
  # PocketBase's password login. nginx lets one address try it ten times a minute.
  loginPath = "~ ^/api/collections/[^/]+/(auth-with-password|request-otp|auth-with-otp)$";
  headers = ''
    add_header X-Frame-Options DENY always;
    add_header Referrer-Policy no-referrer always;
    add_header X-Content-Type-Options nosniff always;
    add_header Strict-Transport-Security "max-age=31536000" always;
  '';
  # No basic auth: the agent on the other host dials this name too. The hub has its own login,
  # and an agent has its token. The agent's path is /api/beszel/agent-connect (a WebSocket); the
  # UI's live updates are server-sent events on /api/realtime, which need no buffering.
  proxy = {
    proxyPass = hubAddress;
    proxyWebsockets = true;
    extraConfig = ''
      proxy_buffering off;
      proxy_read_timeout 1h;
      proxy_send_timeout 1h;
    '';
    recommendedProxySettings = true;
  };
in
{
  options.piabrota.metrics = {
    package = mkOption {
      type = types.package;
      # One source for the hub and the agent, so the two always have the same version.
      default = pkgs.callPackage ./beszel/package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ./beszel/package.nix { }";
      description = "Beszel, pinned in beszel/package.nix. Both units use it.";
    };

    hub = {
      enable = mkEnableOption "the Beszel hub behind nginx and TLS";
      domain = mkOption {
        type = types.str;
        example = "metrics.piabrota.art";
        description = "The name nginx serves the hub on. Its DNS A record must point at the box.";
      };
    };

    agent = {
      enable = mkEnableOption "the Beszel agent, which dials out to the hub";
      hubUrl = mkOption {
        type = types.str;
        example = "https://metrics.piabrota.art";
        description = "The hub's address, with no path.";
      };
      environmentFile = mkOption {
        type = types.path;
        default = "/var/lib/beszel-secrets/agent.env";
        description = ''
          Holds `KEY` (the hub's public key) and `TOKEN`, from the hub's UI. Written by hand on the
          box. systemd reads it as root, so root-only mode 0600 is enough. Without it the unit does
          not start and does not fail.
        '';
      };
    };
  };

  config = mkMerge [
    (mkIf (cfg.hub.enable || cfg.agent.enable) {
      systemd.tmpfiles.rules = [ "d /var/lib/beszel-secrets 0750 root root -" ];
    })

    (mkIf cfg.hub.enable {
      services.beszel.hub = {
        enable = true;
        inherit (cfg) package;
        # Loopback only: nginx is the way in.
        host = "127.0.0.1";
        environment = {
          APP_URL = "https://${cfg.hub.domain}";
        };
      };

      systemd.services.beszel-hub.serviceConfig = {
        MemoryMax = "256M";
        CPUWeight = 20;
        # Optional: USER_EMAIL and USER_PASSWORD make the first admin when the data is new, so
        # nobody can take that account first (docs/METRICS.md). The `-` lets the unit start without it.
        EnvironmentFile = "-/var/lib/beszel-secrets/hub.env";
        # The module of this nixpkgs runs `beszel-hub history-sync`, a command 0.21 no longer has
        # ("unknown command"): the hub would never start. It is `migrate history-sync` now (as in
        # newer nixpkgs). mkForce, or the list would add to the module's own.
        ExecStartPre = lib.mkForce [
          "${cfg.package}/bin/beszel-hub migrate up"
          "${cfg.package}/bin/beszel-hub migrate history-sync"
        ];
      };

      services.nginx = {
        enable = true;
        recommendedTlsSettings = true;
        serverTokens = false;
        appendHttpConfig = ''
          limit_req_zone $binary_remote_addr zone=beszel_login:1m rate=10r/m;
        '';
        virtualHosts.${cfg.hub.domain} = {
          forceSSL = true;
          enableACME = true;
          extraConfig = headers;
          locations = {
            "/" = proxy;
            ${loginPath} = proxy // {
              extraConfig = proxy.extraConfig + ''
                limit_req zone=beszel_login burst=5 nodelay;
                limit_req_status 429;
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
    })

    (mkIf cfg.agent.enable {
      services.beszel.agent = {
        enable = true;
        inherit (cfg) package;
        inherit (cfg.agent) environmentFile;
        environment = {
          HUB_URL = cfg.agent.hubUrl;
          # The agent only dials out: no SSH listener, so no port is bound (agent/server.go).
          DISABLE_SSH = "true";
          # No GPU here, and the agent has no right to read the journal.
          SKIP_GPU = "true";
          SKIP_SYSTEMD_LOGS = "true";
        };
      };

      systemd.services.beszel-agent = {
        # Without the file the unit is skipped, not failed, so a deploy before the first setup
        # does not roll back. After writing the file: `sudo systemctl restart beszel-agent`.
        unitConfig.ConditionPathExists = cfg.agent.environmentFile;
        serviceConfig = {
          MemoryMax = lib.mkDefault "64M";
          CPUWeight = 20;
        };
      };
    })
  ];
}
