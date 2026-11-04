#!/bin/sh
# paperclip-hermes-key [--show]: gives Hermes an API server key, so Paperclip's hermes_gateway
# adapter has something to call. Run it with sudo on the box. It appends API_SERVER_KEY to Hermes's
# secrets file once and never changes an existing line. It prints the key only with --show.
set -eu

file=${HERMES_ENV_FILE:-/var/lib/hermes-secrets/hermes.env}
show=0
if [ "$#" -gt 1 ]; then
  echo "usage: paperclip-hermes-key [--show]" >&2
  exit 2
fi
case ${1:-} in
  '') ;;
  --show) show=1 ;;
  *)
    echo "usage: paperclip-hermes-key [--show]" >&2
    exit 2
    ;;
esac

status=0
grep -q '^API_SERVER_KEY=' "$file" 2>/dev/null || status=$?
case $status in
  0) echo "API_SERVER_KEY is already set" ;;
  1)
    umask 077
    key=$(openssl rand -hex 32)
    lead=0
    if [ -s "$file" ] && [ "$(tail -c 1 "$file" | wc -l)" -eq 0 ]; then lead=1; fi
    {
      if [ "$lead" -eq 1 ]; then echo; fi
      echo "API_SERVER_KEY=$key"
    } 2>/dev/null >>"$file" || {
      echo "paperclip-hermes-key: cannot write $file" >&2
      exit 2
    }
    echo "API_SERVER_KEY added to $file"
    ;;
  *)
    echo "paperclip-hermes-key: cannot read $file" >&2
    exit 2
    ;;
esac

if [ "$show" -eq 1 ]; then
  grep '^API_SERVER_KEY=' "$file" | tail -n 1 | cut -d= -f2-
fi

cat <<'EOF'

Next:
1. sudo /run/current-system/bin/switch-to-configuration switch
   (the activation copies the secrets file into Hermes's .env)
2. sudo systemctl reload hermes-agent
3. In the Paperclip UI, set the agent's adapter to hermes_gateway, the base URL to
   http://127.0.0.1:8642, and paste the key. To read it: sudo paperclip-hermes-key --show
EOF
