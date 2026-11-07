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
  # An includeIf block per repository: the bot's identity wins for these repositories only.
  marolaGitconfig = lib.concatMapStrings
    (r: "[includeIf \"hasconfig:remote.*.url:https://github.com/${r}**\"]\n  path = ${home}/.gitconfig-marola-bot\n")
    marola.repos;

  # git credential helper: the token of the repository's owner, from the path git hands over
  # (credential.useHttpPath). Nothing for an owner without an installation: git then fails.
  credentialHelper = pkgs.writeShellScript "hermes-git-credential" ''
    [ "''${1:-}" = get ] || exit 0
    path=
    while IFS='=' read -r key value; do
      [ -z "$key" ] && break
      [ "$key" = path ] && path=$value
    done${lib.optionalString marola.enable ''

      path=''${path%.git}
      case "$path" in
        ${lib.concatMapStringsSep "|" lib.escapeShellArg marola.repos})
          # Fail closed: no token of marola-pr-bot, no password, and never the token of the owner.
          if [ -r "${tokens}/marola-pr-bot" ]; then
            echo username=x-access-token
            echo "password=$(cat "${tokens}/marola-pr-bot")"
          fi
          exit 0 ;;
      esac''}
    owner=''${path%%/*}
    [ -n "$owner" ] && [ -r "${tokens}/$owner" ] || exit 0
    echo username=x-access-token
    echo "password=$(cat "${tokens}/$owner")"
  '';
in
{
  systemd.tmpfiles.rules = [ "d ${tokens} 0750 root hermes -" ];

  systemd.services.hermes-github-token = {
    description = "GitHub App tokens for Hermes";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    unitConfig.ConditionPathExists = "/var/lib/hermes-secrets/github-app.env";
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

      if ! installations=$(api -H "Authorization: Bearer $jwt" https://api.github.com/app/installations); then
        echo "GitHub refused the App's JWT: check GH_APP_ID and the key"
        exit 0
      fi
      first=
      for owner in ${toString owners}; do
        id=$(jq -r --arg o "$owner" '.[] | select(.account.login == $o) | .id' <<<"$installations")
        if [ -z "$id" ]; then
          rm -f "${tokens}/$owner"
          echo "$owner: the App is not installed there"
          continue
        fi
        if token=$(api -X POST -H "Authorization: Bearer $jwt" -d '{"permissions":${permissions}}' \
          "https://api.github.com/app/installations/$id/access_tokens" | jq -er .token); then
          printf '%s' "$token" >"${tokens}/.$owner"
          chown root:hermes "${tokens}/.$owner"
          chmod 0640 "${tokens}/.$owner"
          mv "${tokens}/.$owner" "${tokens}/$owner"
          [ -n "$first" ] || first=$token
          echo "$owner: token for one hour"
        else
          echo "$owner: GitHub refused a token"
        fi
      done
      ${lib.optionalString (seatRepos != [ ]) ''
        # Read-only tokens for the OpenRig seats: contents read, on one repository each. The seats
        # run without approval prompts, so their token can do nothing but clone and fetch.
        for full in ${toString seatRepos}; do
          owner=''${full%%/*}
          repo=''${full#*/}
          file="${seatTokens}/$owner--$repo"
          id=$(jq -r --arg o "$owner" '.[] | select(.account.login == $o) | .id' <<<"$installations")
          body=$(jq -cn --arg r "$repo" '{repositories: [$r], permissions: {contents: "read"}}')
          if [ -n "$id" ] && token=$(api -X POST -H "Authorization: Bearer $jwt" -d "$body" \
            "https://api.github.com/app/installations/$id/access_tokens" | jq -er .token); then
            printf '%s' "$token" >"$file.new"
            chown root:openrig "$file.new"
            chmod 0640 "$file.new"
            mv "$file.new" "$file"
            echo "$full: read-only token for the seats, for one hour"
          else
            rm -f "$file"
            echo "$full: no read-only token for the seats (is the App installed on it?)"
          fi
        done
      ''}
      [ -n "$first" ] || exit 0

      # Who Hermes commits as: the App's bot user, as GitHub shows it.
      slug=$(api -H "Authorization: Bearer $jwt" https://api.github.com/app | jq -r .slug)
      botid=$(api -H "Authorization: token $first" "https://api.github.com/users/$slug%5Bbot%5D" | jq -r .id)
      install -d -o hermes -g hermes -m 0750 ${home}/.config ${home}/.config/gh
      cat >${home}/.gitconfig.new <<EOF
      [user]
        name = ''${slug}[bot]
        email = $botid+''${slug}[bot]@users.noreply.github.com
      [credential "https://github.com"]
        helper = ${credentialHelper}
        useHttpPath = true
      [push]
        default = current
      EOF${lib.optionalString marola.enable ''

        cat >>${home}/.gitconfig.new <<'EOF'
        ${marolaGitconfig}EOF''}
      cat >${home}/.config/gh/hosts.yml.new <<EOF
      github.com:
        oauth_token: $first
        git_protocol: https
        user: ''${slug}[bot]
      EOF
      for f in ${home}/.gitconfig ${home}/.config/gh/hosts.yml; do
        chown hermes:hermes "$f.new"
        chmod 0600 "$f.new"
        mv "$f.new" "$f"
      done
    '';
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
