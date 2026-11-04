# `operator`: the observer account plus a short list of actions, so a coding agent's session (Claude
# Code on the owner's computer, `ssh piabrota-operator`) can look at a host and do the small things
# the owner asks for without root. Key only (keys/operator.pub; the private half stays on the
# owner's computer), no password, not in wheel, not a Nix trusted user. It reads every unit's log
# (systemd-journal), and through sudo it may run exactly these, and nothing else:
#
#   sudo systemctl restart <unit>.service   the long-running units this host has (`restart` below)
#   sudo systemctl start <unit>.service     the oneshots this host has (`start` below)
#   sudo -u hermes op-hermes <command>       a fixed set of `hermes` commands (only with Hermes)
#   sudo -u hermes op-peek <path> [lines]    a file or directory under HERMES_HOME (only with Hermes)
#
# `op-help` on the box prints the list for the host it runs on. Each list is filtered to the units
# the host defines, so one module serves every host. It is not in the `hermes` group on purpose:
# upstream's module makes Hermes's .env (the Claude token, the chat tokens) readable by that group.
# op-peek refuses .env, auth files and anything named like a secret, key or token. Deploying,
# editing configuration and reading /var/lib/*-secrets stay out of reach: the fix still goes in a PR.
{ config, lib, pkgs, ... }:
let
  keys = lib.filter (k: k != "" && !lib.hasPrefix "#" k)
    (lib.splitString "\n" (builtins.readFile ./keys/operator.pub));

  has = unit: config.systemd.services ? ${unit};
  locoApps = lib.attrNames config.piabrota.loco.apps;

  # Long-running units: a restart is the usual cure, and systemd brings them back the same way.
  restart = lib.filter has ([ "hermes-agent" "hermes-backend" "nginx" "pgx" ]
    ++ map (n: "loco-${n}") locoApps);
  # Oneshots that already run on a timer: starting one only runs it sooner.
  start = lib.filter has ([ "nix-gc" "nix-optimise" "hermes-github-token" ]
    ++ map (n: "loco-${n}-backup") locoApps);

  hermes = config.services ? hermes-agent && config.services.hermes-agent.enable;
  hermesHome = "${config.services.hermes-agent.stateDir}/.hermes";

  # Runs as the hermes user (sudo -u hermes). The argv is checked here, so sudo allows any.
  opHermes = pkgs.writeShellApplication {
    name = "op-hermes";
    # The `hermes` that addToSystemPackages installs: the package with its extras, as admins run it.
    text = ''
      hermes() { /run/current-system/sw/bin/hermes "$@"; }
      export HERMES_HOME=${hermesHome}
      export HOME=${config.services.hermes-agent.stateDir}/home
      id='^[A-Za-z0-9_.-]+$'
      case "$*" in
        status | doctor | insights | logs | "cron list" | "cron status" | "sessions list" | "sessions stats")
          hermes "$@"; exit ;;
      esac
      if [ "$#" -eq 3 ] && [ "$1" = cron ] && [[ "$3" =~ $id ]]; then
        case "$2" in run | pause | resume) hermes "$@"; exit ;; esac
      fi
      echo "op-hermes: not allowed: hermes $*" >&2
      echo "allowed: status, doctor, insights, logs, cron list, cron status, sessions list," >&2
      echo "         sessions stats, cron run|pause|resume <job-id>" >&2
      exit 64
    '';
  };

  # Runs as the hermes user. Reads only under HERMES_HOME, after symlinks are resolved.
  opPeek = pkgs.writeShellApplication {
    name = "op-peek";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      root=${hermesHome}
      if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
        echo "usage: op-peek <path under $root> [lines, default 200]" >&2; exit 64
      fi
      lines=''${2:-200}
      [[ "$lines" =~ ^[0-9]{1,5}$ ]] || { echo "op-peek: lines must be a number" >&2; exit 64; }
      case "$1" in /*) p=$1 ;; *) p=$root/$1 ;; esac
      p=$(realpath -e -- "$p") || exit 66
      case "$p" in "$root" | "$root"/*) ;; *) echo "op-peek: outside $root" >&2; exit 77 ;; esac
      secret='/(\.env[^/]*|auth[^/]*|[^/]*(secret|token|credential|password|\.key|\.pem)[^/]*)(/|$)'
      shopt -s nocasematch
      if [[ "$p" =~ $secret ]]; then
        echo "op-peek: refused, looks like a secret: $p" >&2; exit 77
      fi
      if [ -d "$p" ]; then ls -la -- "$p"; else tail -n "$lines" -- "$p"; fi
    '';
  };

  help = pkgs.writeText "op-help.txt" (lib.concatLines ([
    "operator on ${config.networking.hostName}: journalctl for logs, and through sudo only:"
  ]
  ++ map (u: "  sudo systemctl restart ${u}.service") restart
  ++ map (u: "  sudo systemctl start ${u}.service") start
  ++ lib.optionals hermes [
    "  sudo -u hermes op-hermes <status|doctor|insights|logs|cron list|cron status|sessions list|sessions stats>"
    "  sudo -u hermes op-hermes cron <run|pause|resume> <job-id>"
    "  sudo -u hermes op-peek <path under ${hermesHome}> [lines]"
  ]));
  opHelp = pkgs.writeShellScriptBin "op-help" "exec ${pkgs.coreutils}/bin/cat ${help}";

  systemctl = "/run/current-system/sw/bin/systemctl";
  nopasswd = command: { inherit command; options = [ "NOPASSWD" ]; };
in
{
  users.users.operator = {
    isNormalUser = true;
    description = "Agent access, read and a short list of actions";
    extraGroups = [ "systemd-journal" ];
    openssh.authorizedKeys.keys = keys;
  };

  environment.systemPackages = [ opHelp ] ++ lib.optionals hermes [ opHermes opPeek ];

  security.sudo.extraRules = [
    {
      users = [ "operator" ];
      runAs = "root";
      commands = map (u: nopasswd "${systemctl} restart ${u}.service") restart
        ++ map (u: nopasswd "${systemctl} start ${u}.service") start;
    }
  ] ++ lib.optional hermes {
    users = [ "operator" ];
    runAs = config.services.hermes-agent.user;
    commands = [
      (nopasswd "/run/current-system/sw/bin/op-hermes")
      (nopasswd "/run/current-system/sw/bin/op-peek")
    ];
  };
}
