# piabrota-dot: a bot, with no model, that once a day (14:00 America/Sao_Paulo) looks for a new
# release of Hermes Agent and of OpenRig and opens, or refreshes, one pull request for each on
# piabrota/nix-os, as its own GitHub App (piabrota-dot[bot]). Two stages, and Hermes reaches neither:
#   piabrota-dot-token  root, every 45 minutes: turns the App's key (root-only) into a one-hour token
#                       for ONE repository, in /run/piabrota-dot/token, readable by the bot only.
#   piabrota-dot        the user piabrota-dot, once a day: piabrota-dot/run.sh, with that token.
# The result is /var/lib/piabrota-dot/last-run.txt; a Hermes cron job at 14:15 only delivers it
# (hermes/scripts/piabrota-dot-report.sh). Without the key file both units do nothing. Off by
# default. See docs/PIABROTA-DOT.md.
{ config, lib, pkgs, ... }:
let
  inherit (lib) mkEnableOption mkIf mkOption types;
  cfg = config.piabrota.dot;
  user = "piabrota-dot";
  state = "/var/lib/piabrota-dot";
  run = "/run/piabrota-dot";
  token = "${run}/token";

  scripts = pkgs.runCommand "piabrota-dot-scripts" { } ''
    install -Dm755 ${./piabrota-dot/run.sh} $out/run.sh
    install -Dm755 ${./piabrota-dot/git-credential.sh} $out/git-credential.sh
    install -Dm755 ${./piabrota-dot/mint-token.sh} $out/mint-token.sh
  '';

  # No awk and no perl on a bare PATH: list what run.sh calls. The evaluation (nix eval, no build)
  # of both hosts is why nix is here.
  runPath = with pkgs; [ coreutils findutils gawk gh git gnugrep gnused jq config.nix.package util-linux ];

  # The one program that the unit runs. `sudo -u piabrota-dot piabrota-dot --dry-run` runs the same
  # code by hand (without the unit's sandbox; docs/PIABROTA-DOT.md).
  runner = pkgs.writeShellScriptBin "piabrota-dot" ''
    export PATH=${lib.makeBinPath runPath}
    export HOME=${state} XDG_CACHE_HOME=${state}/.cache TZ=America/Sao_Paulo
    export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
    export DOT_STATE=${state} DOT_TOKEN_FILE=${token} DOT_REPO=${cfg.repo}
    export DOT_MERGE_HERMES=${lib.boolToString cfg.merge.hermes} DOT_MERGE_OPENRIG=${lib.boolToString cfg.merge.openrig}
    exec ${scripts}/run.sh "$@"
  '';

  mergeDescription = what: ''
    Let the bot merge ITS OWN open pull request for ${what}. Off by default; turning it on is a
    decision of the owner. A merge to main is a deploy.
  '' + lib.optionalString (what == "OpenRig") ''
    An OpenRig merge makes the daemon run new database migrations at its first start. They only go
    forward and nothing here undoes them. It also restarts the `openrig` unit and ends every live seat.
  '' + lib.optionalString (what == "Hermes Agent") ''
    A Hermes merge restarts `hermes-agent` and `hermes-backend`, and ends the agent's own runs.
  '' + ''
    The bot merges only when its own gate holds: the author is piabrota-dot[bot], the pull request is
    not a draft, its head is the commit the bot pushed, the diff touches only the pin files, and every
    check run and status on the head is finished and green (no check at all is not green). It merges
    with the squash method, once; if the repository's ruleset refuses, it records that and stops. The
    ruleset, which the owner sets in GitHub, is the real gate: this code does not bypass it and the
    App has no right to change it.
  '';
in
{
  options.piabrota.dot = {
    enable = mkEnableOption "piabrota-dot, the daily check for new Hermes and OpenRig releases (docs/PIABROTA-DOT.md)";
    repo = mkOption {
      type = types.strMatching "[A-Za-z0-9._-]+/[A-Za-z0-9._-]+";
      default = "piabrota/nix-os";
      description = "The repository whose pin files the bot bumps, and the only one its token reaches (owner/name).";
    };
    schedule = mkOption {
      type = types.str;
      default = "*-*-* 14:00:00 America/Sao_Paulo";
      description = "systemd OnCalendar of the daily run; a time zone name is part of it.";
    };
    keyFile = mkOption {
      type = types.str;
      default = "/var/lib/piabrota-secrets/piabrota-dot.env";
      description = ''
        Root-only file on the box with the App's key, in the format of hermes-github.nix: the lines
        `GH_APP_ID=<App ID>` and `GH_APP_PRIVATE_KEY_B64=<the .pem in base64, on one line>`. Without
        it both units do nothing and do not fail. Never in the store.
      '';
    };
    merge.hermes = mkOption {
      type = types.bool;
      default = false;
      description = mergeDescription "Hermes Agent";
    };
    merge.openrig = mkOption {
      type = types.bool;
      default = false;
      description = mergeDescription "OpenRig";
    };
  };

  config = mkIf cfg.enable {
    users.users.${user} = {
      isSystemUser = true;
      group = user;
      home = state;
      shell = "${pkgs.shadow}/bin/nologin";
      description = "piabrota-dot, the release bot";
    };
    users.groups.${user} = { };

    environment.systemPackages = [ runner ];

    # The token's folder: only root and the bot's group reach it. The hermes user is in neither.
    systemd.tmpfiles.rules = [ "d ${run} 0750 root ${user} -" ];

    systemd.services.piabrota-dot-token = {
      description = "GitHub App token for piabrota-dot";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      unitConfig.ConditionPathExists = cfg.keyFile;
      path = with pkgs; [ coreutils curl gnused jq openssl ];
      environment = {
        DOT_REPO = cfg.repo;
        DOT_TOKEN_FILE = token;
        DOT_TOKEN_USER = user;
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${scripts}/mint-token.sh";
        LoadCredential = [ "app:${cfg.keyFile}" ];
        ReadWritePaths = [ run ];
        CapabilityBoundingSet = [ "CAP_CHOWN" ];
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
        RestrictNamespaces = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        SystemCallArchitectures = "native";
      };
    };

    # The token lasts an hour: mint a new one well before.
    systemd.timers.piabrota-dot-token = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "1min";
        OnUnitActiveSec = "45min";
      };
    };

    systemd.services.piabrota-dot = {
      description = "piabrota-dot: new releases of Hermes Agent and OpenRig";
      after = [ "network-online.target" "piabrota-dot-token.service" ];
      wants = [ "network-online.target" "piabrota-dot-token.service" ];
      unitConfig.ConditionPathExists = cfg.keyFile;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe runner;
        User = user;
        Group = user;
        # 0751: Hermes's report script reads last-run.txt (0644) by its exact name and cannot list the folder.
        StateDirectory = "piabrota-dot";
        StateDirectoryMode = "0751";
        WorkingDirectory = state;
        UMask = "0077";
        TimeoutStartSec = "30min";
        MemoryMax = "3G"; # the two evaluations peak at about 0.95 GB (docs/PIABROTA-DOT.md)
        CPUWeight = 20;
        Nice = 10;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ReadWritePaths = [ state ];
        CapabilityBoundingSet = "";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
        RestrictNamespaces = true;
        RestrictSUIDSGID = true;
        RestrictRealtime = true;
        LockPersonality = true;
        SystemCallArchitectures = "native";
      };
    };

    systemd.timers.piabrota-dot = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.schedule;
        Persistent = true;
        RandomizedDelaySec = "2min";
      };
    };
  };
}
