# OpenRig (github.com/mvschwarz/openrig, Apache-2.0), a control plane for teams of AI coding agents
# ("seats", each in a tmux pane), as the unit `openrig` on piabrota2. Hermes operates it with the
# `rig` command and the skill hermes-rig. See docs/OPENRIG.md.
#
# The daemon (openrig/package.nix) runs in the foreground on 127.0.0.1 only: no firewall port and no
# ACME of its own. It serves the web UI of the package on that loopback port (`ui.enabled`).
# `piabrota.openrig.web` adds an nginx vhost with TLS and basic auth in front of it; the option is off by
# default. Its tmux server and every seat run inside this unit's cgroup, so
# MemoryMax is one budget for all of them, and a restart of the unit ends them all. The seats run
# `omp` from omp/wrapper.nix. With piabrota.openrig.waveForecaster.enable the seats of the port rig
# run Claude Code (`claude`, unfree: unfree.nix) and Codex is not installed. The specs of the first
# rig are in openrig/specs, installed at /etc/openrig/specs. Nothing starts a rig: a human or Hermes
# runs `rig up`. With piabrota.openrig.marola.enable the same two seats of piabrota-dev also work on
# the two marola repositories, with read tokens of marola-pr-bot (marola-bot.nix, docs/OPENRIG.md).
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

  # The rigs of wave-forecaster-dev (openrig/specs/rigs/wave-forecaster-dev*): seats that port
  # WAVEWATCH III to Rust in h0ffmann/chaceon, a private repository. docs/OPENRIG.md,
  # "wave-forecaster-dev".
  wf = cfg.waveForecaster;
  # The rig wave-forecaster-thesis (thesis/, docs/THESIS.md): seats that write a UFRJ final project in
  # independent sections with the `thesis` toolkit, pandoc and TeX. Claude Code seats, like the port rig.
  th = cfg.thesis;
  thesisPkg = pkgs.callPackage ./thesis/default.nix { };
  # `claude` and its deny rules serve every rig that runs Claude Code seats.
  claudeSeats = wf.enable || th.enable || (marola.enable && marola.claude.enable);
  # marola-front and marola-back on the rig piabrota-dev (docs/OPENRIG.md, "marola-front and marola-back").
  inherit (cfg) marola;
  # One read-only token per repository of cfg.githubRead, written by hermes-github.nix.
  seatTokens = "/run/openrig-github";
  # Where a seat leaves a git bundle for Hermes. Not under /var/lib/openrig: Hermes may not read
  # the daemon's state, and its deny list blocks that path.
  outbox = "/var/lib/rig-outbox";
  wfFolders = [ "openrig/work/wave-forecaster-dev" ]
    ++ map (seat: "openrig/work/wave-forecaster-dev/${seat}") [ "porter" "auditor" "integrator" ];
  # The rig piabrota-dev-claude (setup B of the comparison, docs/OPENRIG.md): one folder per seat.
  marolaClaudeFolders = [ "openrig/work/piabrota-dev-claude" ]
    ++ map (seat: "openrig/work/piabrota-dev-claude/${seat}") [ "builder" "reviewer" ];
  thFolders = [ "openrig/work/wave-forecaster-thesis" "openrig/work/wave-forecaster-thesis/projects" "openrig/work/wave-forecaster-thesis/out" ]
    ++ map (seat: "openrig/work/wave-forecaster-thesis/${seat}") [ "editor" "writer-a" "writer-b" "writer-c" "librarian" "reviewer" ];

  # git credential helper of the seats: the read-only token of the repository, from the path git
  # hands over (credential.useHttpPath). Nothing for another repository: git then goes on with no
  # password, which is enough for a public one. A clone names it by its profile path, not its store
  # path: nix.gc deletes an old store path 14 days after a deploy that changes the helper.
  seatCredential = pkgs.writeShellScriptBin "openrig-git-credential" ''
    [ "''${1:-}" = get ] || exit 0
    path=
    while IFS='=' read -r key value; do
      [ -z "$key" ] && break
      [ "$key" = path ] && path=$value
    done
    path=''${path%.git}
    file=${seatTokens}/''${path%%/*}--''${path#*/}
    [ -n "$path" ] && [ -r "$file" ] || exit 0
    echo username=x-access-token
    echo "password=$(cat "$file")"
  '';

  # A seat's clone of chaceon: the credential helper stays in the clone's own config, so a later
  # fetch works, also after a deploy. WW3/ is public (metocean/WW3) and pinned by the superproject.
  chaceonClone = pkgs.writeShellApplication {
    name = "chaceon-clone";
    runtimeInputs = [ pkgs.git ];
    text = ''
      dir=''${1:-chaceon}
      git clone --filter=blob:none \
        --config credential.helper=/etc/profiles/per-user/openrig/bin/openrig-git-credential --config credential.useHttpPath=true \
        https://github.com/h0ffmann/chaceon.git "$dir"
      git -C "$dir" submodule update --init --depth 1 WW3 || git -C "$dir" submodule update --init WW3
    '';
  };

  # A seat's clone of a marola repository (marola.repos): the pattern of chaceonClone. The token
  # comes from seatCredential, which reads the file of marola-bot.nix; with no file git goes on
  # with no password, which is enough for a public repository. Any other name is refused.
  marolaClone = pkgs.writeShellApplication {
    name = "marola-clone";
    runtimeInputs = [ pkgs.git ];
    text = ''
      [ $# -ge 1 ] || { echo "usage: marola-clone <marola-front|marola-back|owner/name> [dir]" >&2; exit 2; }
      name=''${1#marola-dev/}
      case "$name" in
        ${lib.concatMapStringsSep "|" (r: lib.escapeShellArg (lib.removePrefix "marola-dev/" r)) marola.repos}) ;;
        *) echo "marola-clone: $1 is not one of: ${toString marola.repos}" >&2; exit 2 ;;
      esac
      dir=''${2:-$name}
      git clone --filter=blob:none \
        --config credential.helper=/etc/profiles/per-user/openrig/bin/openrig-git-credential --config credential.useHttpPath=true \
        "https://github.com/marola-dev/$name.git" "$dir"
    '';
  };

  # The `claude` of a Claude seat (the port rig, docs/RUNTIMES.md). The unit gives every seat
  # ANTHROPIC_API_KEY for the omp seats, and OpenRig lists that name among those that Claude Code
  # ranks above CLAUDE_CODE_OAUTH_TOKEN (claude-credential-precedence.ts, v0.7.7): Claude would send
  # the subscription token as an API key and fail. OpenRig's own way out, `claude_token` in the spec,
  # reads the token with /bin/cat (claude-seat-token.ts), which NixOS does not have. So this wrapper
  # does what omp's does: the sk-ant-oat token moves from ANTHROPIC_API_KEY to CLAUDE_CODE_OAUTH_TOKEN,
  # and what outranks it goes, for Claude's process only. Anything else in that variable (an API key)
  # is dropped and never passed on, so Claude cannot bill an API key by accident. choom: as omp's.
  seatClaude = pkgs.writeShellApplication {
    name = "claude";
    text = ''
      unset ANTHROPIC_AUTH_TOKEN CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX CLAUDE_CODE_USE_FOUNDRY
      case "''${ANTHROPIC_API_KEY:-}" in
        sk-ant-oat*) export CLAUDE_CODE_OAUTH_TOKEN="''${CLAUDE_CODE_OAUTH_TOKEN:-$ANTHROPIC_API_KEY}" ;;
      esac
      unset ANTHROPIC_API_KEY
      exec ${pkgs.util-linux}/bin/choom -n 500 -- ${lib.getExe pkgs.claude-code} "$@"
    '';
  };

  # The deny rules of a Claude seat, from the rules of an omp seat. Every `match` of `bash.patterns` in
  # hermes/omp.yml becomes a `Bash(...)` rule as written (both are globs over the whole command), and
  # its `restrictedFolders` become `Read(...)` rules. Keep the two in step. A bypass seat still honours
  # deny rules, but they are no sandbox: a program that the seat starts can read what a rule names. The
  # hard layer is the unit's sandbox (ProtectSystem, the user `openrig`, no access to Hermes's files).
  ompBashDeny = [
    "git push*"
    "git remote*"
    "git config --global*"
    "gh"
    "gh *"
    "*hermes-secrets*"
    "*.hermes/*"
    "*/.env*"
    "*auth.json*"
    "*/proc/*/environ*"
    "*/proc/self/*"
    "*.ssh/*"
    "env"
    "printenv*"
    "export -p"
    "set"
    "sudo *"
    "doas *"
    "su *"
    "systemctl *"
    "nixos-rebuild*"
    "nix-env*"
    "nix profile*"
    "curl *"
    "wget *"
    "npm *"
    "npx *"
    "pnpm *"
    "yarn *"
    "bun add*"
    "bun install*"
    "bunx *"
    "pip *"
    "pip3 *"
    "uv *"
    "uvx *"
    "cargo install*"
    "go install*"
    "gem *"
    "omp *"
    "hermes *"
    "rig setup*"
    "rig daemon *"
    "rig start*"
    "rig host *"
    "rig auth *"
    "rig provider switch*"
    "rig mcp *"
    "rig slack *"
    "rig gateway *"
    "rig destroy*"
  ];
  # What only a Claude seat needs. A seat runs `git -C chaceon ...`, which `git push*` does not match.
  # Its own token is in its environment, and `claude` would start another agent. A seat may not change
  # its own permission policy (hermes/dangerous-patterns.yaml, OPENRIG).
  claudeBashDeny = [
    "git -C * push"
    "git -C * push *"
    "*CLAUDE_CODE_OAUTH_TOKEN*"
    "*openrig-secrets*"
    "claude *"
    "rig seat set-permissions*"
    "rig policy apply*"
  ];
  # Absolute paths in a Read rule start with `//`; one `/` is the root of the project. The first form is
  # the documented one, and the second covers a Claude Code that reads a single `/` as absolute.
  secretFolders = [
    "/var/lib/hermes-secrets"
    secretsDir
    "/var/lib/hermes/.hermes"
    "/var/lib/hermes/.ssh"
    "/var/lib/hermes/.config/gh"
    "/proc/self"
  ];
  claudeManagedSettings = {
    # Only these rules apply: a rule of a cloned repository (chaceon/.claude/settings.json) cannot
    # loosen them. disableBypassPermissionsMode stays unset: the rig's builtin:yolo needs bypass mode.
    allowManagedPermissionRulesOnly = true;
    permissions.deny =
      map (m: "Bash(${m})") (ompBashDeny ++ claudeBashDeny)
      ++ lib.concatMap (d: [ "Read(/${d}/**)" "Read(${d}/**)" ]) secretFolders
      ++ [ "Read(//proc/*/environ)" "Read(**/.env*)" "Read(**/auth.json)" "Read(~/.ssh/**)" ];
  };

  # What a chaceon seat runs: `just check` (rustup's toolchain, gcc as the linker of build
  # scripts) and `just lint-sh`. Claude Code is in claudeTools. No Docker, no Vulkan, no CUDA:
  # those gates stay with the owner.
  # Shared by the chaceon rigs and the marola repositories; marolaClone is the marola one.
  rustTools = [ pkgs.rustup pkgs.gcc pkgs.just pkgs.shellcheck seatCredential ];
  wfTools = rustTools ++ [ chaceonClone ];
  marolaTools = rustTools ++ [ marolaClone ];
  claudeTools = [ seatClaude ];
  thTools = [ thesisPkg ];
in
{
  # The one unfree package, by name: the `claude` of the port rig's seats (docs/RUNTIMES.md). Here and
  # not in the host, so that a host which turns waveForecaster on can evaluate it.
  imports = [ ./unfree.nix ./marola-bot.nix ];

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
    githubRead = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "h0ffmann/chaceon" ];
      description = ''
        Repositories (`owner/name`) that the seats may read. hermes-github.nix mints a token for
        each, with `contents: read` on that repository only, from Hermes's GitHub App, and writes
        it to ${seatTokens}, readable by the openrig user. The App must be installed on the
        repository.
      '';
    };
    waveForecaster.enable = mkEnableOption ''
      the rigs of wave-forecaster-dev: Rust tools in the seats' profile, a folder per seat, the
      outbox for Hermes and a read-only token for h0ffmann/chaceon (docs/OPENRIG.md)'';
    marola = {
      enable = mkEnableOption ''
        marola-front and marola-back on the rig piabrota-dev: the seats' Rust tools and `marola-clone`,
        the outbox for Hermes and read-only tokens of marola-pr-bot (marola-bot.nix). Hermes pushes
        and opens the pull requests of these two repositories as marola-pr-bot (docs/OPENRIG.md)'';
      repos = mkOption {
        type = types.listOf types.str;
        default = [ "marola-dev/marola-front" "marola-dev/marola-back" ];
        description = ''
          The marola repositories (`marola-dev/<name>`) that the seats may read and that Hermes may
          push to as marola-pr-bot. marola-bot.nix mints their tokens, so they do not go in `githubRead`.
        '';
      };
      claude.enable = mkEnableOption ''
        the Claude Code setup B of marola-front and marola-back, the rig piabrota-dev-claude: adds
        `claude`, `managed-settings.json` and the two seat folders. It costs about 280 MiB of closure
        (docs/RUNTIMES.md). Needs marola.enable'';
    };
    thesis.enable = mkEnableOption ''
      the rig wave-forecaster-thesis: the `thesis` toolkit with pandoc and a small TeX set in the seats'
      profile, a folder per seat, the outbox for Hermes and Claude Code seats (docs/THESIS.md)'';
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
    assertions = [
      {
        assertion = config.services.hermes-agent.enable;
        message = "piabrota.openrig needs services.hermes-agent (hermes.nix) on the same host: Hermes operates it, and the seats use Hermes's Claude subscription token.";
      }
      {
        assertion = !marola.enable || (marola.repos != [ ] && lib.all (lib.hasPrefix "marola-dev/") marola.repos);
        message = "piabrota.openrig.marola.repos needs at least one entry, and every entry must start with marola-dev/: marola-pr-bot has one installation, and one installation belongs to one owner.";
      }
      {
        assertion = !marola.claude.enable || marola.enable;
        message = "piabrota.openrig.marola.claude.enable needs piabrota.openrig.marola.enable: the rig piabrota-dev-claude uses the same agents, tokens and outbox.";
      }
    ];

    users.users.openrig = {
      isSystemUser = true;
      group = "openrig";
      inherit home;
      # OpenRig starts a pane shell with a clean environment, so the unit's `path` does not reach
      # it. NixOS builds the pane's PATH from the per-user profile of $USER (the RigSpec `env:` sets
      # USER, see openrig/specs/rigs/piabrota-dev/rig.yaml).
      packages = lib.unique (seatTools ++ lib.optionals wf.enable wfTools ++ lib.optionals marola.enable marolaTools ++ lib.optionals claudeSeats claudeTools ++ lib.optionals th.enable thTools);
    };
    users.groups.openrig = { };

    # Only the openrig user reads this directory. The token file in it is made by the unit.
    systemd.tmpfiles.rules = [ "d ${secretsDir} 0700 openrig openrig -" ]
      ++ lib.optionals (cfg.githubRead != [ ] || marola.enable) [ "d ${seatTokens} 0750 root openrig -" ]
      # The outbox: the seats write, Hermes (group hermes) reads. The default ACL gives the group
      # read access to new files in spite of the unit's UMask. Bundles older than 14 days go.
      ++ lib.optionals (claudeSeats || marola.enable) [ "d ${outbox} 0750 openrig hermes -" ]
      ++ lib.optionals wf.enable [
      "d ${outbox}/wave-forecaster-dev 0750 openrig hermes 14d"
      "a+ ${outbox}/wave-forecaster-dev - - - - default:group::r-X"
    ]
      ++ lib.optionals th.enable [
      "d ${outbox}/wave-forecaster-thesis 0750 openrig hermes 14d"
      "a+ ${outbox}/wave-forecaster-thesis - - - - default:group::r-X"
    ]
      ++ lib.optionals marola.enable [
      "d ${outbox}/marola 0750 openrig hermes 14d"
      "a+ ${outbox}/marola - - - - default:group::r-X"
    ];

    piabrota.openrig.githubRead = lib.optionals wf.enable [ "h0ffmann/chaceon" ];

    # Hermes runs `rig` through this wrapper.
    services.hermes-agent.extraPackages = [ rigCli ];

    # The specs of openrig/specs, read-only: rig up /etc/openrig/specs/rigs/piabrota-dev/rig.yaml
    environment.etc."openrig/specs".source = ./openrig/specs;

    # The rules of a Claude seat (the port rig, the thesis rig and piabrota-dev-claude: waveForecaster, thesis or marola.claude on): Claude Code reads this file
    # first, and no setting of a cloned repository can override it.
    environment.etc."claude-code/managed-settings.json" = mkIf claudeSeats {
      text = builtins.toJSON claudeManagedSettings;
    };

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
        # Seats run without approval prompts: the owner's decision (PR 124). The rig's
        # `permission_policy: builtin:yolo` (openrig/specs/rigs/piabrota-dev/rig.yaml) does that. This
        # variable alone does not: a rig with no policy gets the floor, and a policy wins over it. The
        # reasons are in hermes/skills/hermes-omp/references/openrig-seats.md. The deny rules of
        # hermes/omp.yml stay the guard of the omp seats, and /etc/claude-code/managed-settings.json
        # the guard of the Claude seats. No kernel rig: OpenRig's own agent seats are not wanted here.
        OPENRIG_YOLO = "1";
        OPENRIG_NO_KERNEL = "1";
        # The daemon setting recovery.provider_auth_env_allowlist. It names the variable only, never a
        # value. The value stays in the unit's root-only EnvironmentFile. A seat whose model is
        # `anthropic/<id>` then gets the key (the double opt-in of OpenRig). Other variables stay out.
        # A Claude seat gets it too, as every seat does: its `claude` (seatClaude) moves it to
        # CLAUDE_CODE_OAUTH_TOKEN and drops it from Claude's own environment.
        OPENRIG_RECOVERY_PROVIDER_AUTH_ENV_ALLOWLIST = "ANTHROPIC_API_KEY";
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
      # The tools of the chaceon rigs are in this path too, so that a Claude seat that OpenRig starts
      # with a clean environment (a permission mode set by `rig seat set-permissions`) finds `claude`.
      path = lib.unique (seatTools ++ lib.optionals wf.enable wfTools ++ lib.optionals marola.enable marolaTools ++ lib.optionals claudeSeats claudeTools ++ lib.optionals th.enable thTools);
      serviceConfig = {
        ExecStart = "${lib.getExe pkg.nodejs} ${pkg}/${pkg.daemon}/dist/index.js";
        # `-` lets the daemon start if this step fails: the token is only for the seats. systemd
        # reads the EnvironmentFile after this step. The daemon holds the key in its environment;
        # the runner passes it on to each seat.
        ExecStartPre = [ "-+${claudeToken}" ];
        EnvironmentFile = "-${tokenFile}";
        User = "openrig";
        Group = "openrig";
        StateDirectory = [ "openrig" "openrig/work" ] ++ lib.optionals wf.enable wfFolders ++ lib.optionals (marola.enable && marola.claude.enable) marolaClaudeFolders ++ lib.optionals th.enable thFolders;
        StateDirectoryMode = "0700";
        RuntimeDirectory = "openrig";
        RuntimeDirectoryMode = "0700";
        WorkingDirectory = work;
        ReadWritePaths = lib.optionals wf.enable [ outbox ] ++ lib.optionals th.enable [ "${outbox}/wave-forecaster-thesis" ] ++ lib.optionals marola.enable [ "${outbox}/marola" ];
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
