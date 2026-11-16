# The GitHub App marola-pr-bot (MIP-0086 of marola-dev/marola) for the two marola repositories of the
# rig piabrota-dev (piabrota.openrig.marola, docs/OPENRIG.md). Same approach as hermes-github.nix: the
# App's private key stays root-only on the box (/var/lib/hermes-secrets/marola-pr-bot.env, same
# format as github-app.env), and a root unit turns it, every 45 minutes, into tokens that last one
# hour:
#   - one operator token for Hermes: contents, pull requests and issues (write) on the repos only;
#   - one read-only token per repo for the seats, which never push (openrig.nix, marolaClone);
#   - the bot's git identity, for hermes-github.nix's includeIf block.
# `marola-gh` is the one way Hermes uses that token: it lets through only the commands that propose.
# The other App of MIP-0086, the one that merges, is not used here: humans merge. No `workflows`
# permission either: GitHub then refuses a push that changes .github/workflows.
# Without the key file the unit does nothing: git gets no password for these repos (the credential
# helper of hermes-github.nix fails closed), and only `gh` still acts as piabrota-hermes there.
{ config, lib, pkgs, ... }:
let
  cfg = config.piabrota.openrig;
  scripts = pkgs.callPackage ./scala { };
  inherit (cfg) marola;
  owner = "marola-dev";
  names = map (lib.removePrefix "${owner}/") marola.repos;
  keyFile = "/var/lib/hermes-secrets/marola-pr-bot.env";
  tokens = "/run/hermes-github";
  seatTokens = "/run/openrig-github";
  home = "/var/lib/hermes";

  # What Hermes may do as marola-pr-bot: propose and read. The first two arguments decide, so a
  # global flag before the subcommand is refused too. Nothing that merges, reviews, closes or reaches
  # the API, the repository settings, the workflows or the secrets (`piabrota marola-gh`, scala/scripts).
  marolaGh = scripts.command {
    name = "marola-gh";
    runtimeInputs = [ pkgs.gh ];
  };
  # The settings of `piabrota marola-bot-token` (scala/scripts/GithubTokens.scala).
  tokenConfig = pkgs.writeText "marola-bot-token.json" (builtins.toJSON {
    inherit owner names tokens seatTokens home;
  });
in
{
  config = lib.mkIf (cfg.enable && marola.enable) {
    services.hermes-agent.extraPackages = [ marolaGh ];

    systemd.services.marola-bot-token = {
      description = "GitHub App tokens of marola-pr-bot for Hermes and the OpenRig seats";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      unitConfig.ConditionPathExists = keyFile;
      path = with pkgs; [ coreutils curl openssl ];
      script = "${lib.getExe (scripts.command { name = "marola-bot-token"; })} ${tokenConfig}";
      serviceConfig = {
        Type = "oneshot";
        LoadCredential = [ "app:${keyFile}" ];
        ReadWritePaths = [ tokens seatTokens home ];
        CapabilityBoundingSet = [ "CAP_CHOWN" "CAP_DAC_OVERRIDE" "CAP_FOWNER" ];
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
        SystemCallArchitectures = "native";
      };
    };

    # The tokens last an hour: mint new ones well before.
    systemd.timers.marola-bot-token = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "1min";
        OnUnitActiveSec = "45min";
      };
    };
  };
}
