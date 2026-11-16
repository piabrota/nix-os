# Hermes's write access to GitHub, as its own GitHub App (piabrota-hermes[bot]). The App's private
# key stays root-only on the box (/var/lib/hermes-secrets/github-app.env, never in Hermes's .env).
# A root unit turns it, every 45 minutes, into installation tokens that last one hour, one per
# account the App is installed on, and gives Hermes only those: git takes them through a
# credential helper (by the repository's owner), gh through its own config. Hermes pushes only to
# hermes/* branches and opens pull requests; hermes/dangerous-patterns.yaml blocks merges and every
# other push, and a ruleset on each default branch stops a push to it at GitHub. Humans merge.
# Without the key file the unit does nothing, and Hermes stays read-only. See docs/HERMES.md.
# It also mints the OpenRig seats' read-only tokens, one repository each (openrig.nix, githubRead).
# With piabrota.openrig.marola.enable, git on the two marola repositories uses the token and the
# identity of marola-pr-bot instead (marola-bot.nix); with no such token, git gets no password there.
{ config, lib, pkgs, ... }:
let
  # The accounts whose installations get a token, in order: gh uses the first one that has one.
  owners = [ "piabrota" "marola-dev" "h0ffmann" ];
  # What a token may do: push branches, open and comment on pull requests and issues. Not
  # workflows (GitHub then refuses a push that changes .github/workflows), not administration.
  permissions = ''{"contents":"write","pull_requests":"write","issues":"write"}'';
  tokens = "/run/hermes-github";
  # The repositories the OpenRig seats may read (openrig.nix), and where their tokens go.
  seatRepos = lib.attrByPath [ "piabrota" "openrig" "githubRead" ] [ ] config;
  seatTokens = "/run/openrig-github";
  home = "/var/lib/hermes";
  # The marola repositories of the rig piabrota-dev (openrig.nix, marola-bot.nix); off by default.
  marola = lib.attrByPath [ "piabrota" "openrig" "marola" ] { enable = false; repos = [ ]; } config;
  # Two includeIf blocks per repository, with and without .git: the bot's identity wins for these
  # repositories only. Not `${r}**`, which also matches marola-frontend or marola-backup.
  marolaGitconfig = lib.concatMapStrings
    (url: "[includeIf \"hasconfig:remote.*.url:${url}\"]\n  path = ${home}/.gitconfig-marola-bot\n")
    (lib.concatMap (r: [ "https://github.com/${r}" "https://github.com/${r}.git" ]) marola.repos);

  scripts = pkgs.callPackage ./scala { };
  # git credential helper: the token of the repository's owner, from the path git hands over
  # (credential.useHttpPath). Nothing for an owner without an installation: git then fails. The
  # marola repositories take marola-pr-bot's token, and fail closed (`piabrota hermes-git-credential`).
  credentialHelper = lib.getExe (scripts.command {
    name = "hermes-git-credential";
    env = lib.optionalAttrs marola.enable { HERMES_GIT_MAROLA_REPOS = toString marola.repos; };
  });
  # The settings of `piabrota hermes-github-token` (scala/scripts/GithubTokens.scala).
  tokenConfig = pkgs.writeText "hermes-github-token.json" (builtins.toJSON {
    inherit owners permissions tokens seatRepos seatTokens home;
    helper = credentialHelper;
    marolaGitconfig = lib.optionalString marola.enable marolaGitconfig;
  });
in
{
  systemd.tmpfiles.rules = [ "d ${tokens} 0750 root hermes -" ];

  systemd.services.hermes-github-token = {
    description = "GitHub App tokens for Hermes";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    unitConfig.ConditionPathExists = "/var/lib/hermes-secrets/github-app.env";
    path = with pkgs; [ coreutils curl openssl ];
    script = "${lib.getExe (scripts.command { name = "hermes-github-token"; })} ${tokenConfig}";
    serviceConfig = {
      Type = "oneshot";
      LoadCredential = [ "app:/var/lib/hermes-secrets/github-app.env" ];
      ReadWritePaths = [ tokens home ] ++ lib.optional (seatRepos != [ ]) seatTokens;
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
  systemd.timers.hermes-github-token = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "45min";
    };
  };
}
