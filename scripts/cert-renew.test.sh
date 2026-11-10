#!/bin/sh
# Tests of scripts/cert-renew.sh with a fixture /var/lib/acme and a stub systemctl (offline; needs
# openssl). The stub "orders" a certificate by writing a good one in its place, unless the name is
# in FAIL_ORDER. `sh scripts/cert-renew.test.sh` or `just cert-renew-test`.
set -u
here=$(cd "$(dirname "$0")" && pwd)
renew="$here/cert-renew.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
acme="$work/acme" bin="$work/bin" log="$work/log"
mkdir -p "$acme" "$bin"

checks=0 failed=0
check() { # description, got, want
  checks=$((checks + 1))
  if [ "$2" != "$3" ]; then failed=$((failed + 1)); printf 'FAIL %s: got [%s], want [%s]\n' "$1" "$2" "$3"; fi
}

# cert NAME ISSUER_CN DAYS: a self-signed certificate whose subject and issuer is ISSUER_CN.
cert() {
  mkdir -p "$acme/$1"
  openssl req -x509 -newkey rsa:2048 -nodes -keyout "$acme/$1/key.pem" -out "$acme/$1/cert.pem" \
    -subj "/CN=$2" -days "$3" >/dev/null 2>&1
}
cat > "$bin/systemctl" <<EOF
#!/bin/sh
echo "\$*" >> "$log"
case \$1 in
  cat) case \$2 in acme-order-renew-*.service) n=\${2#acme-order-renew-}; [ -d "$acme/\${n%.service}" ] ;; *) exit 1 ;; esac ;;
  reset-failed) exit 0 ;;
  start)
    n=\${2#acme-order-renew-}; n=\${n%.service}
    case " \${FAIL_ORDER:-} " in *" \$n "*) exit 1 ;; esac
    openssl req -x509 -newkey rsa:2048 -nodes -keyout "$acme/\$n/key.pem" -out "$acme/\$n/cert.pem" -subj "/CN=YE2" -days 90 >/dev/null 2>&1 ;;
esac
EOF
chmod +x "$bin/systemctl"
run() { : > "$log"; PATH="$bin:$PATH" ACME_DIR="$acme" sh "$renew" "$@" > "$work/out" 2>&1; echo $?; }
starts() { grep -c '^start ' "$log"; }

cert good.example YE1 80
cert stand-in.example "minica root ca 093f63" 700
cert old.example YE1 5
mkdir -p "$acme/acme-challenge" "$acme/.lego"

echo "# --dry-run plans the two bad ones and starts nothing"
check "dry-run exit" "$(run --dry-run)" 0
check "dry-run starts nothing" "$(starts)" 0
check "dry-run plans the stand-in" "$(grep -c '^plan  stand-in.example (self-signed (minica))' "$work/out")" 1
check "dry-run plans the old one" "$(grep -c '^plan  old.example (expires within 14 days)' "$work/out")" 1
check "dry-run leaves the good one" "$(grep -c '^ok    good.example' "$work/out")" 1
check "folders with no cert.pem are not certificates" "$(grep -c 'acme-challenge\|\.lego' "$work/out")" 0

echo "# a bad argument"
check "a name with a slash is refused" "$(run ../etc)" 2
check "an option it does not know is refused" "$(run --force)" 2

echo "# all: the two bad ones are ordered and fixed (the stub runs as any user, so root is faked)"
mkdir -p "$work/idbin"; printf '#!/bin/sh\necho 0\n' > "$work/idbin/id"; chmod +x "$work/idbin/id"
bin_save=$bin; bin="$work/idbin:$bin"
check "all exit" "$(run all)" 0
check "two orders" "$(starts)" 2
check "the good one is not ordered" "$(grep -c 'start acme-order-renew-good.example' "$log")" 0
check "the stand-in is ok after" "$(grep -c '^ok    stand-in.example: issuer=.*YE2' "$work/out")" 1

echo "# a name given is ordered even when it looks fine"
check "named exit" "$(run good.example)" 0
check "one order" "$(starts)" 1

echo "# an order that fails leaves exit 1 and says what to check"
cert stand-in.example "minica root ca 093f63" 700
check "failed order exit" "$(export FAIL_ORDER=stand-in.example; run stand-in.example)" 1
check "it points at DNS" "$(grep -c '^FAIL  stand-in.example: still self-signed (minica); check its DNS record' "$work/out")" 1
check "it gives the journal command" "$(grep -c 'journalctl -u acme-order-renew-stand-in.example.service' "$work/out")" 1

echo "# a name this box does not serve is skipped"
check "unknown name exit" "$(run nope.example)" 0
check "unknown name skipped" "$(grep -c '^skip  nope.example' "$work/out")" 1
bin=$bin_save

echo "# a real run needs root"
if [ "$(id -u)" != 0 ]; then check "no root exit" "$(run all)" 2; fi

printf '%s checks, %s failed\n' "$checks" "$failed"
[ "$failed" = 0 ]
