#!/usr/bin/env python3
"""The HTTPS certificate of every live name in scripts/domains.txt, from outside, as a browser
sees it: the TLS handshake must pass the system's CA store with no warning (a public CA, the right
name, not expired) and the certificate must have more than CERT_MIN_DAYS days left (default 14).
Prints a Markdown table (for a run summary) and exits 1 when a name fails. Read-only; needs no
other program (openssl, when present, names the issuer of a certificate that fails).

  python3 scripts/cert_check.py               check every live name     (just certs)
  python3 scripts/cert_check.py NAME...       check only these names
  python3 scripts/cert_check.py --coverage    no network: fail when a *.nix file names a
                                              piabrota.art name that domains.txt does not list (CI)
"""

import os
import re
import socket
import ssl
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
NAME = re.compile(r"([a-z0-9-]+\.)?piabrota\.art")


def entries(path):
    """(name, host) for each line of domains.txt that is not a comment."""
    rows = []
    for line in Path(path).read_text().splitlines():
        cells = line.split()
        if cells and not cells[0].startswith("#"):
            rows.append((cells[0], cells[1] if len(cells) > 1 else ""))
    return rows


def coverage(listed, root):
    files = subprocess.run(
        ["git", "-C", str(root), "ls-files", "*.nix"], check=True, text=True, stdout=subprocess.PIPE
    ).stdout.split()
    named = sorted({m.group(0) for f in files for m in NAME.finditer((root / f).read_text(errors="replace"))})
    missing = [n for n in named if n not in listed]
    for n in missing:
        print(f"not in scripts/domains.txt: {n}", file=sys.stderr)
    if not missing:
        print("every piabrota.art name of the *.nix files is in scripts/domains.txt")
    return int(bool(missing))


def address(name):
    try:
        return socket.getaddrinfo(name, 443, socket.AF_INET, socket.SOCK_STREAM)[-1][4][0]
    except OSError:
        return ""


def handshake(name, context):
    with (
        socket.create_connection((name, 443), timeout=15) as raw,
        context.wrap_socket(raw, server_hostname=name) as tls,
    ):
        return tls.getpeercert(), tls.getpeercert(binary_form=True)


def describe(der):
    """Issuer CN and notAfter of a certificate the CA store refused, through openssl if present."""
    try:
        out = subprocess.run(
            ["openssl", "x509", "-noout", "-issuer", "-enddate"],
            input=ssl.DER_cert_to_PEM_cert(der),
            text=True,
            stdout=subprocess.PIPE,
            check=True,
        ).stdout
    except (OSError, subprocess.CalledProcessError):
        return "", ""
    issuer = re.search(r"CN *= *([^,\n]+)", out)
    ends = re.search(r"notAfter=(.*)", out)
    return (issuer.group(1).strip() if issuer else ""), (ends.group(1).strip() if ends else "")


def check(name, min_days):
    """(issuer, expires, result) for one name; result is "ok" or why it fails."""
    try:
        cert, _ = handshake(name, ssl.create_default_context())
    except ssl.SSLCertVerificationError as e:
        loose = ssl.create_default_context()
        loose.check_hostname, loose.verify_mode = False, ssl.CERT_NONE
        try:
            _, der = handshake(name, loose)
        except OSError:
            der = None
        issuer, ends = describe(der) if der else ("", "")
        why = (e.verify_message or str(e)).replace("|", "/")[:120]
        return issuer, ends, f"browser warning: {why}"
    except OSError:
        return "", "", "no TLS answer (DNS on the wrong host, or nginx refused the name)"
    issuer = next((v for rdn in cert.get("issuer", ()) for k, v in rdn if k == "commonName"), "")
    ends = cert.get("notAfter", "")
    if ssl.cert_time_to_seconds(ends) - time.time() < min_days * 86400:
        return issuer, ends, f"expires in less than {min_days} days"
    return issuer, ends, "ok"


def main(argv):
    rows = entries(os.environ.get("DOMAINS_FILE", HERE / "domains.txt"))
    if argv[:1] == ["--coverage"]:
        return coverage({n for n, _ in rows}, HERE.parent)
    min_days = int(os.environ.get("CERT_MIN_DAYS", "14"))
    hosts = dict(rows)
    names = argv or [n for n, h in rows if h != "off"]
    failed = 0
    print("| Name | Host | Address | Issuer | Expires | Result |")
    print("|---|---|---|---|---|---|")
    for n in names:
        issuer, ends, result = check(n, min_days)
        mark = "ok" if result == "ok" else f"**FAIL** {result}"
        failed += result != "ok"
        print(
            f"| {n} | {hosts.get(n) or '?'} | {address(n) or 'no A record'} | {issuer or '–'} | {ends or '–'} | {mark} |"
        )
    print()
    if not failed:
        print(f"All {len(names)} names have a valid certificate with more than {min_days} days left.")
    else:
        print(
            f"{failed} of {len(names)} names failed. A self-signed (minica) issuer means the ACME order failed: "
            'see docs/SITE.md, "Certificates".'
        )
    return int(bool(failed))


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
