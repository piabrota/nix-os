#!/bin/sh
# Order again the certificates of this box that a browser would refuse: NixOS's self-signed
# stand-in (issuer minica, left when an order failed) or one that expires within CERT_MIN_DAYS
# days (default 14). For the OWNER only: an agent never runs it. Run it as root on the box:
#   sudo sh scripts/cert-renew.sh [all|NAME...] [--dry-run]       (on the box)
#   just remote-cert-renew [what] [user] [target]                 (from your machine, over SSH)
#   just certs-fix                                                (both hosts, then just certs)
#
# all (the default): every certificate in /var/lib/acme that needs it. NAME: that certificate,
# even when it looks fine. --dry-run: print the plan and change nothing.
# It starts acme-order-renew-<name>.service only, never another unit, and waits for it. The DNS
# record of the name must point at this box first (scripts/domains.txt, docs/SITE.md,
# "Certificates"), or Let's Encrypt fails the order again.
# Exit 0: every certificate is fine. 1: one is still self-signed or near its end. 2: usage, or no
# root for a real run.
# For tests only: ACME_DIR (default /var/lib/acme).
set -u
acme=${ACME_DIR:-/var/lib/acme}
min_days=${CERT_MIN_DAYS:-14}

usage() { printf 'usage: %s [all|NAME...] [--dry-run]\n' "$0" >&2; }

dry=0 names="" forced=0
for a in "$@"; do
  case $a in
    --dry-run) dry=1 ;;
    all) ;;
    -* | *[!a-z0-9.-]* | '') usage; exit 2 ;;
    *) names="$names $a"; forced=1 ;;
  esac
done
if [ "$dry" = 0 ] && [ "$(id -u)" != 0 ]; then
  echo "cert-renew: run it as root (sudo), or with --dry-run" >&2; exit 2
fi
if [ -z "$names" ]; then
  for d in "$acme"/*/; do
    n=$(basename "$d")
    [ -f "$d/cert.pem" ] && names="$names $n"
  done
fi

# state NAME: "ok", or why a browser would refuse the certificate.
state() {
  c="$acme/$1/cert.pem"
  [ -f "$c" ] || { echo "no certificate file"; return; }
  if openssl x509 -noout -issuer -in "$c" 2>/dev/null | grep -qi minica; then echo "self-signed (minica)"; return; fi
  openssl x509 -noout -checkend $((min_days * 86400)) -in "$c" >/dev/null 2>&1 || { echo "expires within $min_days days"; return; }
  echo ok
}

bad=0
for n in $names; do
  unit="acme-order-renew-$n.service"
  if ! systemctl cat "$unit" >/dev/null 2>&1; then
    echo "skip  $n: this box has no $unit"; continue
  fi
  s=$(state "$n")
  if [ "$s" = ok ] && [ "$forced" = 0 ]; then echo "ok    $n"; continue; fi
  if [ "$dry" = 1 ]; then echo "plan  $n ($s): systemctl start $unit"; continue; fi
  echo "order $n ($s) ..."
  systemctl reset-failed "$unit" 2>/dev/null
  if systemctl start "$unit"; then :; else echo "      the order failed: journalctl -u $unit -n 30"; fi
  s=$(state "$n")
  if [ "$s" = ok ]; then echo "ok    $n: $(openssl x509 -noout -issuer -enddate -in "$acme/$n/cert.pem" | tr '\n' ' ')"
  else echo "FAIL  $n: still $s; check its DNS record (dig +short A $n)"; bad=1; fi
done
exit "$bad"
