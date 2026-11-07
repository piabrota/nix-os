#!/bin/sh
# Mint one installation token of the piabrota-dot GitHub App, for ONE repository, and write it to
# DOT_TOKEN_FILE (0400, owned by DOT_TOKEN_USER). The token lasts one hour; a timer runs this every
# 45 minutes. Run as root by the unit piabrota-dot-token (piabrota-dot.nix); the App's key arrives as
# the systemd credential "app", never in this script's environment.
#
# The JWT and API steps copy hermes-github.nix (the unit hermes-github-token), which is Nix-inline and
# tied to Hermes's accounts, so they are repeated here. The key file has the same two lines as that
# unit's file: GH_APP_ID and GH_APP_PRIVATE_KEY_B64 (the .pem, base64 on one line).
#
# Environment: CREDENTIALS_DIRECTORY (systemd), DOT_REPO (owner/name), DOT_TOKEN_FILE,
# DOT_TOKEN_USER, DOT_API (default https://api.github.com).
set -eu
umask 077

app=$CREDENTIALS_DIRECTORY/app
repo=${DOT_REPO:?}
file=${DOT_TOKEN_FILE:?}
user=${DOT_TOKEN_USER:?}
api_url=${DOT_API:-https://api.github.com}
name=${repo#*/}

app_id=$(sed -n 's/^GH_APP_ID=//p' "$app")
[ -n "$app_id" ] || { echo "the key file has no GH_APP_ID line"; exit 1; }
key=$(mktemp)
trap 'rm -f "$key"' EXIT
sed -n 's/^GH_APP_PRIVATE_KEY_B64=//p' "$app" | base64 -d >"$key"

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
now=$(date +%s)
header=$(printf '{"alg":"RS256","typ":"JWT"}' | b64url)
payload=$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' $((now - 60)) $((now + 540)) "$app_id" | b64url)
jwt="$header.$payload.$(printf '%s.%s' "$header" "$payload" | openssl dgst -sha256 -sign "$key" | b64url)"
call() { curl -fsS --max-time 20 -H "Accept: application/vnd.github+json" -H "Authorization: Bearer $jwt" "$@"; }

# The installation on this repository. A 404 means the App is not installed there.
if ! id=$(call "$api_url/repos/$repo/installation" | jq -er .id); then
  echo "GitHub gave no installation of the App on $repo: check GH_APP_ID, the key and the install"
  exit 1
fi

# Least rights: no workflows, no administration. metadata is read-only and always present.
body=$(jq -cn --arg r "$name" \
  '{repositories: [$r], permissions: {contents: "write", pull_requests: "write", issues: "write", metadata: "read"}}')
if ! token=$(call -X POST -d "$body" "$api_url/app/installations/$id/access_tokens" | jq -er .token); then
  echo "GitHub refused a token for $repo"
  exit 1
fi

printf '%s' "$token" >"$file.new"
chmod 0400 "$file.new"
chown "$user" "$file.new"
mv "$file.new" "$file"
echo "$repo: token for one hour"
