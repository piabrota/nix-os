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
# Without the key file the unit does nothing, and Hermes acts as piabrota-hermes on these repos.
{ config, lib, pkgs, ... }:
let
  cfg = config.piabrota.openrig;
  inherit (cfg) marola;
  owner = "marola-dev";
  names = map (lib.removePrefix "${owner}/") marola.repos;
  keyFile = "/var/lib/hermes-secrets/marola-pr-bot.env";
  tokens = "/run/hermes-github";
  seatTokens = "/run/openrig-github";
  home = "/var/lib/hermes";

  # What Hermes may do as marola-pr-bot: propose and read. The first two arguments decide, so a
  # global flag before the subcommand is refused too. Nothing that merges, reviews, closes or reaches
  # the API, the repository settings, the workflows or the secrets.
  marolaGh = pkgs.writeShellApplication {
    name = "marola-gh";
    runtimeInputs = [ pkgs.gh ];
    text = ''
      case "''${1:-} ''${2:-}" in
        "pr create"|"pr view"|"pr list"|"pr diff"|"pr checks"|"pr status"|"pr comment"|"pr edit") ;;
        "issue view"|"issue list"|"issue comment") ;;
        *) echo "marola-gh: $* is not allowed (humans merge and review)" >&2; exit 2 ;;
      esac
      if [ ! -r ${tokens}/marola-pr-bot ]; then
        echo "marola-gh: no marola-pr-bot token (is marola-bot-token running?)" >&2
        exit 1
      fi
      GH_TOKEN=$(cat ${tokens}/marola-pr-bot)
      export GH_TOKEN
      exec gh "$@"
    '';
  };
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
      path = with pkgs; [ coreutils curl gnused jq openssl ];
      script = ''
        set -u
        umask 077
        # GH_APP_ID and GH_APP_PRIVATE_KEY_B64 (the .pem, base64 on one line).
        GH_APP_ID=$(sed -n 's/^GH_APP_ID=//p' "$CREDENTIALS_DIRECTORY/app")
        key=$(mktemp)
        trap 'rm -f "$key"' EXIT
        sed -n 's/^GH_APP_PRIVATE_KEY_B64=//p' "$CREDENTIALS_DIRECTORY/app" | base64 -d >"$key"
        b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
        now=$(date +%s)
        header=$(printf '{"alg":"RS256","typ":"JWT"}' | b64url)
        payload=$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' $((now - 60)) $((now + 540)) "$GH_APP_ID" | b64url)
        jwt="$header.$payload.$(printf '%s.%s' "$header" "$payload" | openssl dgst -sha256 -sign "$key" | b64url)"
        api() { curl -fsS --max-time 20 -H "Accept: application/vnd.github+json" "$@"; }
        # put FILE GROUP TOKEN: atomic, root:GROUP, 0640.
        put() {
          printf '%s' "$3" >"$1.new"
          chown "root:$2" "$1.new"
          chmod 0640 "$1.new"
          mv "$1.new" "$1"
        }
        drop_all() {
          rm -f ${tokens}/marola-pr-bot ${lib.concatMapStringsSep " " (n: "${seatTokens}/${owner}--${n}") names}
        }

        if ! installations=$(api -H "Authorization: Bearer $jwt" https://api.github.com/app/installations); then
          echo "GitHub refused the App's JWT: check GH_APP_ID and the key"
          exit 0
        fi
        id=$(jq -r --arg o ${owner} '.[] | select(.account.login == $o) | .id' <<<"$installations")
        if [ -z "$id" ]; then
          drop_all
          echo "${owner}: marola-pr-bot is not installed there"
          exit 0
        fi
        mint() {
          api -X POST -H "Authorization: Bearer $jwt" -d "$1" \
            "https://api.github.com/app/installations/$id/access_tokens" | jq -er .token
        }

        # The operator token, for Hermes: one request for all the repos.
        body=$(jq -cn --args '{repositories: $ARGS.positional, permissions: {contents: "write", pull_requests: "write", issues: "write"}}' ${lib.escapeShellArgs names})
        if optoken=$(mint "$body"); then
          put ${tokens}/marola-pr-bot hermes "$optoken"
          echo "${owner}: operator token for one hour"
        else
          rm -f ${tokens}/marola-pr-bot
          echo "${owner}: GitHub refused the operator token"
        fi

        # Read-only tokens for the seats: contents read, on one repository each. The seats run
        # without approval prompts, so their token can do nothing but clone and fetch.
        for repo in ${lib.escapeShellArgs names}; do
          body=$(jq -cn --arg r "$repo" '{repositories: [$r], permissions: {contents: "read"}}')
          if token=$(mint "$body"); then
            put "${seatTokens}/${owner}--$repo" openrig "$token"
            echo "${owner}/$repo: read-only token for the seats, for one hour"
          else
            rm -f "${seatTokens}/${owner}--$repo"
            echo "${owner}/$repo: no read-only token for the seats"
          fi
        done
        [ -n "''${optoken:-}" ] || exit 0

        # Who Hermes commits as on these repos: the App's bot user, as GitHub shows it.
        slug=$(api -H "Authorization: Bearer $jwt" https://api.github.com/app | jq -r .slug)
        botid=$(api -H "Authorization: token $optoken" "https://api.github.com/users/$slug%5Bbot%5D" | jq -r .id)
        case "$botid" in
          *[!0-9]*|"") echo "${owner}: no bot user id, the identity file stays as it is"; exit 0 ;;
        esac
        cat >${home}/.gitconfig-marola-bot.new <<EOF
        [user]
          name = ''${slug}[bot]
          email = $botid+''${slug}[bot]@users.noreply.github.com
        EOF
        chown hermes:hermes ${home}/.gitconfig-marola-bot.new
        chmod 0600 ${home}/.gitconfig-marola-bot.new
        mv ${home}/.gitconfig-marola-bot.new ${home}/.gitconfig-marola-bot
      '';
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
