# Live metrics, home-made (docs/METRICS.md): processes, memory and vCPU of each host on one page at
# metrics.piabrota.art. No daemon stays resident:
#   collector  a timer runs metrics/collect.sh every 10 s; it writes /run/metrics-web/<name>.json
#   web        nginx serves metrics/index.html and /data/ from that folder, behind the basic-auth
#              file of the Hermes dashboard
#   publish    (KVM 1) one location on the www vhost serves the host's file to one address
#   pull       (KVM 4) a timer fetches that file and keeps it beside its own
# Everything is off by default. The web name must point at its host before `web.enable` is on, or the
# ACME order fails on the deploy and deploy-rs rolls the switch back (docs/SITE.md).
{ config, lib, pkgs, ... }:
let
  inherit (lib) mkEnableOption mkIf mkMerge mkOption types;
  cfg = config.piabrota.metrics;
  anyOn = cfg.collector.enable || cfg.web.enable || cfg.publish.enable || cfg.pull.enable;
  outDir = "/run/metrics-web";
  stateDir = "/run/metrics-state";

  # The scripts get their shebang patched to a store shell; the tools they call are on the unit's PATH.
  script = name: file: pkgs.runCommand name { } ''
    install -D -m 0755 ${file} $out/bin/${name}
    patchShebangs $out/bin/${name}
  '';
  collect = script "metrics-collect" ./metrics/collect.sh;
  pull = script "metrics-pull" ./metrics/pull.sh;
  page = pkgs.runCommand "metrics-page" { } ''
    install -D -m 0644 ${./metrics/index.html} $out/index.html
  '';

  headers = ''
    add_header X-Frame-Options DENY always;
    add_header Referrer-Policy no-referrer always;
    add_header X-Content-Type-Options nosniff always;
    add_header Strict-Transport-Security "max-age=31536000" always;
  '';

  # What both units share: one fixed user, nothing written but the two folders in /run, no way to
  # gain a right. Not here: ProcSubset=pid, ProtectProc=invisible and PrivateUsers, which hide
  # /proc/stat, other users' processes and their names (docs/METRICS.md, "Hardening").
  sandbox = {
    User = "metrics";
    Group = "metrics";
    UMask = "0022";
    NoNewPrivileges = true;
    CapabilityBoundingSet = "";
    AmbientCapabilities = "";
    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateTmp = true;
    PrivateDevices = true;
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectKernelLogs = true;
    ProtectControlGroups = true;
    ProtectClock = true;
    ProtectHostname = true;
    LockPersonality = true;
    MemoryDenyWriteExecute = true;
    RestrictRealtime = true;
    RestrictSUIDSGID = true;
    RestrictNamespaces = true;
    SystemCallArchitectures = "native";
    SystemCallFilter = [ "@system-service" "~@privileged" "~@resources" ];
    ReadWritePaths = [ outDir stateDir ];
    MemoryMax = "64M";
    TasksMax = 64;
    CPUWeight = 20;
    Nice = 10;
    Type = "oneshot";
    # One start and one finish a run would be 17,000 journal lines a day.
    LogLevelMax = "warning";
  };

  timer = what: {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnActiveSec = "2s";
      OnUnitActiveSec = "${toString cfg.collector.interval}s";
      AccuracySec = "1s";
      Unit = "${what}.service";
    };
  };
in
{
  options.piabrota.metrics = {
    name = mkOption {
      type = types.strMatching "[a-z0-9-]*";
      default = "";
      example = "piabrota2";
      description = ''
        The host's name on the page and in its file: `/run/metrics-web/<name>.json`. Never the
        hostname: piabrota2's is still `nixos` until a reboot. The page reads piabrota and piabrota2.
      '';
    };
    label = mkOption {
      type = types.str;
      default = "";
      example = "piabrota2 (KVM 4)";
      description = "What the page calls the host. Empty: the name.";
    };

    collector = {
      enable = mkEnableOption "the collector timer: metrics/collect.sh writes this host's file";
      interval = mkOption {
        type = types.ints.between 2 300;
        default = 10;
        description = "Seconds between two runs. The page marks a host offline after 30 s without a new file.";
      };
    };

    web = {
      enable = mkEnableOption "the page and its data behind nginx, TLS and basic auth";
      domain = mkOption {
        type = types.str;
        default = "metrics.piabrota.art";
        description = "The name nginx serves the page on. Its DNS A record must point at the box.";
      };
      htpasswdFile = mkOption {
        # A string, not a path: a path literal copies the file into the world-readable store.
        type = types.str;
        default = config.piabrota.hermesWeb.htpasswdFile;
        defaultText = lib.literalExpression "config.piabrota.hermesWeb.htpasswdFile";
        description = ''
          The basic-auth users, one `name:bcrypt-hash` line each. The default is the Hermes
          dashboard's file, so the same login opens both. Without the file every request gets a 500.
        '';
      };
    };

    publish = {
      enable = mkEnableOption "one location on the site's vhost that serves this host's file to the addresses in allowFrom";
      allowFrom = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "187.41.117.18" ];
        description = "IPv4 addresses that may fetch `/_metrics/<name>.json`. Everyone else gets a 403. Not a secret: the file holds no command line.";
      };
    };

    pull = {
      enable = mkEnableOption "the pull timer: metrics/pull.sh fetches another host's published file";
      url = mkOption {
        type = types.str;
        default = "";
        example = "https://www.piabrota.art/_metrics/piabrota.json";
        description = "The address of the other host's file.";
      };
      name = mkOption {
        type = types.strMatching "[a-z0-9-]+";
        default = "piabrota";
        description = "The other host's name: its file is kept as `<name>.json`, and must say `host: <name>`.";
      };
    };
  };

  config = mkMerge [
    (mkIf anyOn {
      users.users.metrics = {
        isSystemUser = true;
        group = "metrics";
      };
      users.groups.metrics = { };
      # In /run: nothing survives a reboot, nothing fills the disk. nginx reads the first folder.
      systemd.tmpfiles.rules = [
        "d ${outDir} 0755 metrics metrics -"
        "d ${stateDir} 0700 metrics metrics -"
      ];
    })

    (mkIf cfg.collector.enable {
      assertions = [{
        assertion = cfg.name != "";
        message = "piabrota.metrics.collector needs piabrota.metrics.name.";
      }];

      systemd.services.metrics-collect = {
        description = "Write this host's metrics file";
        path = [ pkgs.coreutils pkgs.gawk pkgs.glibc.bin ];
        environment = {
          METRICS_NAME = cfg.name;
          METRICS_LABEL = if cfg.label == "" then cfg.name else cfg.label;
          METRICS_INTERVAL = toString cfg.collector.interval;
          OUT_DIR = outDir;
          STATE_DIR = stateDir;
        };
        serviceConfig = sandbox // {
          ExecStart = "${collect}/bin/metrics-collect";
          # Reads /proc and /sys/fs/cgroup only.
          PrivateNetwork = true;
          RestrictAddressFamilies = "AF_UNIX";
        };
      };
      systemd.timers.metrics-collect = timer "metrics-collect";
    })

    (mkIf cfg.pull.enable {
      assertions = [{
        assertion = cfg.pull.url != "";
        message = "piabrota.metrics.pull needs piabrota.metrics.pull.url.";
      }];

      systemd.services.metrics-pull = {
        description = "Fetch ${cfg.pull.name}'s metrics file";
        path = [ pkgs.coreutils pkgs.curl pkgs.gnugrep ];
        environment = {
          METRICS_PULL_URL = cfg.pull.url;
          METRICS_PULL_NAME = cfg.pull.name;
          OUT_DIR = outDir;
        };
        serviceConfig = sandbox // {
          ExecStart = "${pull}/bin/metrics-pull";
          RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
        };
      };
      systemd.timers.metrics-pull = timer "metrics-pull";
    })

    (mkIf cfg.publish.enable {
      assertions = [
        {
          assertion = cfg.name != "" && cfg.publish.allowFrom != [ ];
          message = "piabrota.metrics.publish needs piabrota.metrics.name and at least one address in allowFrom.";
        }
        {
          assertion = config.piabrota.site.enable;
          message = "piabrota.metrics.publish adds a location to the site's vhost: turn piabrota.site on.";
        }
      ];

      # The vhost is declared in site.nix; this adds one location and changes nothing else.
      services.nginx.virtualHosts.${config.piabrota.site.domain}.locations."= /_metrics/${cfg.name}.json" = {
        alias = "${outDir}/${cfg.name}.json";
        extraConfig = ''
          ${lib.concatMapStrings (ip: "allow ${ip};\n") cfg.publish.allowFrom}
          deny all;
          default_type application/json;
          add_header Cache-Control "no-store" always;
          add_header X-Content-Type-Options nosniff always;
        '';
      };
    })

    (mkIf cfg.web.enable {
      services.nginx = {
        enable = true;
        recommendedTlsSettings = true;
        serverTokens = false;
        # Slows a password guesser; a tab polling two files every 5 s stays far below it.
        appendHttpConfig = ''
          limit_req_zone $binary_remote_addr zone=metrics_web:1m rate=10r/s;
        '';
        virtualHosts.${cfg.web.domain} = {
          forceSSL = true;
          enableACME = true;
          basicAuthFile = cfg.web.htpasswdFile;
          root = page;
          extraConfig = ''
            limit_req zone=metrics_web burst=30 nodelay;
            limit_req_status 429;
            ${headers}
          '';
          locations = config.piabrota.favicon.locations // {
            "/data/" = {
              alias = "${outDir}/";
              # add_header in a location drops the server's, so the headers are repeated.
              extraConfig = ''
                add_header Cache-Control "no-store" always;
                ${headers}
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
  ];
}
