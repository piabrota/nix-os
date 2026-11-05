# OpenRig (github.com/mvschwarz/openrig, Apache-2.0), a control plane for teams of AI coding agents
# ("seats", each in a tmux pane), as the unit `openrig` on piabrota2. Hermes operates it with the
# `rig` command and the skill hermes-rig. See docs/OPENRIG.md.
#
# The daemon (openrig/package.nix) runs in the foreground on 127.0.0.1 only: no firewall port and no
# ACME of its own. It serves the web UI of the package on that loopback port (`ui.enabled`).
# `piabrota.openrig.web` adds an nginx vhost with TLS and basic auth in front of it; the option is off by
# default. Its tmux server and every seat run inside this unit's cgroup, so
# MemoryMax is one budget for all of them, and a restart of the unit ends them all. The seats run
# `omp` from omp/wrapper.nix; `claude` is unfree and Codex is not installed. The specs of the first rig
# are in openrig/specs, installed at /etc/openrig/specs. Nothing starts a rig: a human or Hermes
# runs `rig up`.
{ config, lib, pkgs, ... }:
let
  inherit (lib) mkEnableOption mkIf mkOption types;
  cfg = config.piabrota.openrig;
  pkg = cfg.package;
  home = "/var/lib/openrig";
  work = "${home}/work";
  url = "http://127.0.0.1:${toString cfg.port}";
  backend = "127.0.0.1:${toString cfg.port}";
  origin = "https://${cfg.web.domain}";
  secretsDir = "/var/lib/openrig-secrets";
  tokenFile = "${secretsDir}/.env";

  # Hermes's `rig`: the real CLI aimed at the daemon by URL. With OPENRIG_URL the CLI reads no file
  # of the daemon's state, so the hermes user needs no access to /var/lib/openrig. (The CLI keeps
  # its own small state in the caller's home.) The deny list in hermes/dangerous-patterns.yaml
  # holds back the commands Hermes must not run.
  rigCli = pkgs.writeShellApplication {
    name = "rig";
    text = ''
      export OPENRIG_URL=${url}
      exec ${lib.getExe' pkg "rig"} "$@"
    '';
  };

  # The `omp` of the seats: the one wrapper of omp/wrapper.nix, with no time ceiling (a seat lives
  # as long as its rig) and the seat rules appended. What a seat needs from this unit, and why, is
  # in hermes/skills/hermes-omp/references/openrig-seats.md.
  seatOmp = pkgs.callPackage ./omp/wrapper.nix {
    ceiling = null;
    appendSystemPrompt = ./hermes/omp-seat-append-system.md;
  };

  # Runs as root (the `+` of ExecStartPre) at each start: copies the one line CLAUDE_CODE_OAUTH_TOKEN
  # of Hermes's secrets file, and nothing else, under the name ANTHROPIC_API_KEY, to a file that
  # only the openrig user reads. The unit takes it as its EnvironmentFile. The step prints nothing
  # and never runs with `set -x`: grep, tail and sed write to the file, and grep's errors go to
  # /dev/null. The file is empty when the line or the source is missing.
  claudeToken = pkgs.writeShellScript "openrig-claude-token" ''
    export PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.gnugrep pkgs.gnused ]}
    umask 077
    grep '^CLAUDE_CODE_OAUTH_TOKEN=' /var/lib/hermes-secrets/hermes.env 2>/dev/null | tail -n 1 | sed 's/^CLAUDE_CODE_OAUTH_TOKEN=/ANTHROPIC_API_KEY=/' > ${tokenFile}.new
    chown openrig:openrig ${tokenFile}.new
    chmod 600 ${tokenFile}.new
    mv ${tokenFile}.new ${tokenFile}
  '';

  seatTools = [ pkgs.tmux pkgs.bash pkgs.git pkgs.procps pkgs.lsof pkg pkg.nodejs seatOmp ];
in
{
  options.piabrota.openrig = {
    enable = mkEnableOption "OpenRig, run by Hermes (docs/OPENRIG.md)";
    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ./openrig/package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ./openrig/package.nix { }";
      description = "OpenRig's release, built from source: the rig CLI, the daemon and the TUI.";
    };
    port = mkOption {
      type = types.port;
      default = 7433;
      description = "The daemon's loopback port (upstream's default).";
    };
    memoryMax = mkOption {
      type = types.str;
      default = "2G";
      description = ''
        systemd MemoryMax of the unit: the budget of the daemon, tmux and every seat. MemoryHigh is
        1536M, below it. Two seats fit (docs/OPENRIG.md, "Limits").
      '';
    };
    web = {
      enable = mkEnableOption "the web UI of OpenRig behind nginx, TLS and basic auth (docs/OPENRIG.md, \"The web UI\")";
      domain = mkOption {
        type = types.str;
        example = "rig.piabrota.art";
        description = "The name nginx serves the UI on. Its DNS A record must point at the box before this is on, or the ACME order fails on the deploy.";
      };
      htpasswdFile = mkOption {
        # A string, not a path: a path literal copies the file into the world-readable store.
        type = types.str;
        default = config.piabrota.hermesWeb.htpasswdFile;
        defaultText = lib.literalExpression "config.piabrota.hermesWeb.htpasswdFile";
        description = ''
          The basic-auth users, one `name:bcrypt-hash` line each (`htpasswd -B`). The default is the
          dashboard's file, so the same login opens both. Set a file of its own to give the UI its
          own users: mode 0640, owner root, group nginx, in a directory that exists.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [{
      assertion = config.services.hermes-agent.enable;
      message = "piabrota.openrig needs services.hermes-agent (hermes.nix) on the same host: Hermes operates it, and the seats use Hermes's Claude subscription token.";
    }];

    users.users.openrig = {
      isSystemUser = true;
      group = "openrig";
      inherit home;
      # OpenRig starts a pane shell with a clean environment, so the unit's `path` does not reach
      # it. NixOS builds the pane's PATH from the per-user profile of $USER (the RigSpec `env:` sets
      # USER, see openrig/specs/rigs/piabrota-dev/rig.yaml).
      packages = seatTools;
    };
    users.groups.openrig = { };

    # Only the openrig user reads this directory. The token file in it is made by the unit.
    systemd.tmpfiles.rules = [ "d ${secretsDir} 0700 openrig openrig -" ];

    # Hermes runs `rig` through this wrapper.
    services.hermes-agent.extraPackages = [ rigCli ];

    # The specs of openrig/specs, read-only: rig up /etc/openrig/specs/rigs/piabrota-dev/rig.yaml
    environment.etc."openrig/specs".source = ./openrig/specs;

    # The web vhost. Same gate as hermes-web.nix: TLS from Let's Encrypt and HTTP basic auth against
    # a bcrypt file on the box, outside the store. The UI can type into the seats, which run without
    # approval prompts, so without the file every request gets a 500 and the UI stays closed. The
    # file is the dashboard's by default (hermes-web.nix makes its directory).

    services.nginx = mkIf cfg.web.enable {
      enable = true;
      recommendedTlsSettings = true;
      serverTokens = false;
      # Slows a password guesser; the UI's polling stays within the burst.
      appendHttpConfig = ''
        limit_req_zone $binary_remote_addr zone=openrig_web:1m rate=20r/s;
        map $http_origin $openrig_web_foreign_origin {
          default 1;
          "" 0;
          "${origin}" 0;
        }
      '';
      virtualHosts.${cfg.web.domain} = {
        forceSSL = true;
        enableACME = true;
        basicAuthFile = cfg.web.htpasswdFile;
        extraConfig = ''
          limit_req zone=openrig_web burst=100 nodelay;
          limit_req_status 429;
          add_header X-Frame-Options DENY always;
          add_header Referrer-Policy no-referrer always;
          add_header X-Content-Type-Options nosniff always;
          add_header Strict-Transport-Security "max-age=31536000" always;
          if ($openrig_web_foreign_origin) { return 403; }
        '';
        locations."/" = {
          proxyPass = "http://${backend}";
          proxyWebsockets = true;
          # nginx may turn these on for every location (loco.nix); set only what the daemon needs.
          recommendedProxySettings = false;
          # The daemon accepts the public name through OPENRIG_ALLOWED_HOSTS and the page's Origin
          # through OPENRIG_ALLOWED_ORIGINS (both set below), so Host and Origin pass unchanged. The
          # basic-auth header stays in nginx: the daemon reads `Authorization` as a bearer token.
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header Authorization "";
            proxy_set_header X-Forwarded-For "";
            # The terminal WebSocket and the event streams stay open for hours.
            proxy_buffering off;
            proxy_read_timeout 1h;
            proxy_send_timeout 1h;
            add_header X-Frame-Options DENY always;
            add_header Referrer-Policy no-referrer always;
            add_header X-Content-Type-Options nosniff always;
            add_header Strict-Transport-Security "max-age=31536000" always;
          '';
        };
      };
    };

    security.acme = mkIf cfg.web.enable {
      acceptTerms = true;
      defaults.email = config.piabrota.loco.acmeEmail;
    };

    networking.firewall.allowedTCPPorts = mkIf cfg.web.enable [ 80 443 ];

    systemd.services.openrig = {
      description = "OpenRig, a control plane for AI coding agents";
      documentation = [ "https://github.com/mvschwarz/openrig" ];
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      # The unit must not loop: five failed starts in ten minutes and it stays down.
      startLimitIntervalSec = 600;
      startLimitBurst = 5;
      environment = {
        HOME = home;
        OPENRIG_HOME = "${home}/.openrig";
        OPENRIG_PORT = toString cfg.port;
        # Loopback by name, so a Tailscale interface (none here) would not add a listener.
        OPENRIG_BIND_HOST = "127.0.0.1";
        OPENRIG_URL = url;
        # Seats run without approval prompts and without a kernel rig: the owner's decision (PR 124)
        # and the reasons are in hermes/skills/hermes-omp/references/openrig-seats.md. The deny
        # rules of hermes/omp.yml stay the guard.
        OPENRIG_YOLO = "1";
        OPENRIG_NO_KERNEL = "1";
        # tmux's socket goes here (a private 0700 directory of the unit), not in /tmp.
        TMUX_TMPDIR = "/run/openrig";
        # The system user has no login shell; tmux and the seats need a real one.
        SHELL = "/run/current-system/sw/bin/bash";
        LANG = "C.UTF-8";
        # The daemon serves the web UI of the package on its loopback port (read once at start).
        # The UI can type into the seats: reach it by an SSH tunnel or the vhost of
        # piabrota.openrig.web, never by a public port.
        OPENRIG_UI_ENABLED = "true";
      } // lib.optionalAttrs cfg.web.enable {
        # The /api boundary of the daemon: the Host must be this name, and the page's Origin (the
        # vhost is https, the daemon's own UI origin is http) must be listed. Format: comma lists;
        # an origin entry is scheme://host[:port].
        OPENRIG_ALLOWED_HOSTS = cfg.web.domain;
        OPENRIG_ALLOWED_ORIGINS = origin;
      };
      # What the unit and the seat panes need (the same list serves both, see
      # users.users.openrig.packages). tmux holds the seats. node starts the seats' runner (the
      # daemon types `node ...` in a pane). ps and lsof: the daemon reads the process table. git:
      # the seats work on clones. The NixOS default adds coreutils, findutils, grep, sed and systemd.
      path = seatTools;
      serviceConfig = {
        ExecStart = "${lib.getExe pkg.nodejs} ${pkg}/${pkg.daemon}/dist/index.js";
        # `-` lets the daemon start if this step fails: the token is only for the seats. systemd
        # reads the EnvironmentFile after this step. The daemon holds the key in its environment;
        # the runner passes it on to each seat.
        ExecStartPre = [ "-+${claudeToken}" ];
        EnvironmentFile = "-${tokenFile}";
        User = "openrig";
        Group = "openrig";
        StateDirectory = [ "openrig" "openrig/work" ];
        StateDirectoryMode = "0700";
        RuntimeDirectory = "openrig";
        RuntimeDirectoryMode = "0700";
        WorkingDirectory = work;
        UMask = "0077";
        Restart = "on-failure";
        RestartSec = "10s";
        # The default: SIGTERM to the daemon, tmux and every seat, then SIGKILL. A restart of the
        # unit ends the seats; `rig up <rig> --existing` brings a rig back from its snapshot.
        KillMode = "control-group";
        # An OOM kill takes one seat (choom aims at it), not the daemon and the other seats.
        OOMPolicy = "continue";
        MemoryMax = cfg.memoryMax;
        MemoryHigh = "1536M";
        CPUWeight = 50;
        TasksMax = 2048;
        NoNewPrivileges = true;
        PrivateTmp = true;
        # No PrivateDevices: tmux gives every seat a pseudo terminal, and a test in a user unit
        # showed tmux cannot start a pane with a private /dev.
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        ProtectHostname = true;
        ProtectProc = "invisible";
        CapabilityBoundingSet = "";
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        # AF_NETLINK: Node reads the network addresses over netlink; without it the process fails
        # with EAFNOSUPPORT (it broke Paperclip on 2026-11-04). No MemoryDenyWriteExecute: Node's
        # JIT and omp's runtime need writable and executable memory.
        RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" "AF_NETLINK" ];
        SystemCallArchitectures = "native";
        SystemCallFilter = [ "@system-service" "~@privileged" ];
        SystemCallErrorNumber = "EPERM";
      };
    };
  };
}
