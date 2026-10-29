# Light command-line tools and defaults, chosen from gvolpe/nix-config
# (home/modules/software.nix, home/shared/programs.nix, system/configuration.nix) for a
# small VPS: no GUI, nothing that pulls a large runtime. See AGENTS.md, "Resource budget".
{ pkgs, ... }:
let
  # gvolpe/nix-config home/scripts/show-zombie-parents.nix
  show-zombie-parents = pkgs.writeShellScriptBin "show-zombie-parents" ''
    ps -A -ostat,ppid | grep -e '[zZ]' | awk '{ print $2 }' | uniq | xargs -r ps -p
  '';
in
{
  environment.systemPackages = with pkgs; [
    bat # cat with syntax highlighting
    dix # store-path diff, used by the activation report below
    duf # disk usage/free
    eza # ls
    fd # find
    jq # JSON
    ncdu # interactive du
    psmisc # killall, pstree, fuser
    ripgrep # grep
    socat # socket relay
    systemctl-tui # systemd units and their logs
    tree
    unzip
    zip
    show-zombie-parents
  ];

  programs = {
    fzf = {
      keybindings = true;
      fuzzyCompletion = true;
    };
    zoxide.enable = true;

    htop = {
      enable = true;
      settings = {
        sort_direction = true;
        sort_key = "PERCENT_CPU";
      };
    };

    tmux = {
      enable = true;
      # utempter is a setuid wrapper built from source with a musl gcc (~290 MiB to fetch).
      withUtempter = false;
      aggressiveResize = true;
      baseIndex = 1;
      escapeTime = 0;
      keyMode = "vi";
      terminal = "screen-256color";
      extraConfig = ''
        set -g renumber-windows on
        setw -g monitor-activity off
        set -g visual-activity off
      '';
    };

    # System-wide /etc/gitconfig: no identity here, each user sets their own.
    git = {
      enable = true;
      config = {
        init.defaultBranch = "main";
        merge.conflictStyle = "diff3";
        pull.rebase = false;
        push.autoSetupRemote = true;
        alias = {
          st = "status";
          co = "checkout";
          cob = "checkout -b";
          br = "branch";
          dc = "diff --cached";
          amend = "commit --amend -m";
          ls = "log --pretty=format:'%C(yellow)%h%Cred%d %Creset%s%Cblue [%cn]' --decorate";
        };
      };
    };

    # command-not-found needs a channel's programs.sqlite; nix-index would need its database.
    command-not-found.enable = false;
  };

  # gvolpe/nix-config system/configuration.nix: print what changed on every switch.
  system.activationScripts.diff = ''
    if [[ -e /run/current-system ]]; then
      echo "--- system diff ---"
      ${pkgs.dix}/bin/dix /run/current-system "$systemConfig" || true
    fi
  '';

  # Not from gvolpe: limits for a small disk and little RAM.
  # nixos + doc: ~95 MiB of closure (the manuals, options.json, a nixpkgs source copy).
  documentation = {
    nixos.enable = false;
    doc.enable = false;
    man.cache.enable = false;
  };
  services.journald.extraConfig = ''
    SystemMaxUse=200M
    MaxRetentionSec=1month
  '';
  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };
}
