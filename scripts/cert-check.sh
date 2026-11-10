#!/bin/sh
# The HTTPS certificate of every live name in scripts/domains.txt, from outside, as a browser
# sees it: curl must connect with no warning (a public CA, the right name, not expired) and the
# certificate must have more than CERT_MIN_DAYS days left (default 14). Prints a Markdown table
# (for a run summary) and exits 1 when a name fails. Read-only; needs curl and openssl.
#
#   scripts/cert-check.sh               check every live name
#   scripts/cert-check.sh NAME...       check only these names
#   scripts/cert-check.sh --coverage    no network: fail when a *.nix file names a piabrota.art
#                                       name that domains.txt does not list (CI runs this)
set -u
here=$(cd "$(dirname "$0")" && pwd)
list=${DOMAINS_FILE:-$here/domains.txt}
min_days=${CERT_MIN_DAYS:-14}

names() { # the names of domains.txt; with "live", only those whose host is not "off"
  awk -v live="${1:-}" '!/^[[:space:]]*(#|$)/ && (live == "" || $2 != "off") { print $1 }' "$list"
}

if [ "${1:-}" = --coverage ]; then
  cd "$here/.." || exit 2
  missing=0
  for n in $(git ls-files '*.nix' | xargs grep -ohE '([a-z0-9-]+\.)?piabrota\.art' | sort -u); do
    if ! names | grep -qxF "$n"; then
      echo "not in scripts/domains.txt: $n" >&2
      missing=1
    fi
  done
  [ "$missing" = 0 ] && echo "every piabrota.art name of the *.nix files is in scripts/domains.txt"
  exit "$missing"
fi

# The names have no space or glob character, so word splitting is what is wanted here.
# shellcheck disable=SC2046
[ $# -gt 0 ] || set -- $(names live)

failed=0
echo "| Name | Host | Address | Issuer | Expires | Result |"
echo "|---|---|---|---|---|---|"
for n in "$@"; do
  host=$(awk -v n="$n" '$1 == n { print $2 }' "$list")
  addr=$( (dig +short A "$n" 2>/dev/null || getent hosts "$n" 2>/dev/null | awk '{print $1}') | tail -n 1)
  cert=$(openssl s_client -connect "$n:443" -servername "$n" </dev/null 2>/dev/null | openssl x509 2>/dev/null)
  issuer=$(printf '%s\n' "$cert" | openssl x509 -noout -issuer 2>/dev/null | sed 's/^issuer= *//; s/.*CN *= *//')
  ends=$(printf '%s\n' "$cert" | openssl x509 -noout -enddate 2>/dev/null | sed 's/^notAfter=//')
  err=$(curl -sS -o /dev/null --max-time 15 "https://$n/" 2>&1)
  rc=$?
  if [ -z "$cert" ]; then
    result="no TLS answer (DNS on the wrong host, or nginx refused the name)"
  elif [ "$rc" != 0 ]; then
    result="browser warning: $(printf "%s\n" "$err" | head -n 1 | sed 's/^curl: ([0-9]*) //' | tr '|' '/' | cut -c1-120)"
  elif ! printf '%s\n' "$cert" | openssl x509 -noout -checkend $((min_days * 86400)) >/dev/null 2>&1; then
    result="expires in less than $min_days days"
  else
    result=ok
  fi
  [ "$result" = ok ] || failed=$((failed + 1))
  [ "$result" = ok ] && mark="ok" || mark="**FAIL** $result"
  echo "| $n | ${host:-?} | ${addr:-no A record} | ${issuer:-–} | ${ends:-–} | $mark |"
done
echo
if [ "$failed" = 0 ]; then
  echo "All $# names have a valid certificate with more than $min_days days left."
else
  echo "$failed of $# names failed. A self-signed (minica) issuer means the ACME order failed: see docs/SITE.md, \"Certificates\"."
fi
[ "$failed" = 0 ]
