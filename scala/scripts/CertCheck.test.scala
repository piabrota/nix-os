package piabrota.scripts

import piabrota.lib.TestKit

/** The offline half of cert-check: domains.txt and the coverage of the *.nix files. */
class CertCheckTest extends munit.FunSuite:
  test("entries"):
    val d = Domain.parse("# a comment\n\na.piabrota.art  piabrota2\nb.piabrota.art off\nc.piabrota.art\n")
    assertEquals(d, List(Domain("a.piabrota.art", "piabrota2"), Domain("b.piabrota.art", "off"), Domain("c.piabrota.art", "")))
    assertEquals(d.filter(_.live).map(_.name), List("a.piabrota.art", "c.piabrota.art"))

  test("the names the *.nix files hold that domains.txt lacks"):
    assertEquals(CertCheck.missingNames(List("a.piabrota.art b.piabrota.art", "https://piabrota.art/ a.piabrota.art"),
      Set("piabrota.art")), List("a.piabrota.art", "b.piabrota.art"))

  test("the handshake, the issuer and the verdict"):
    val shake = Handshake.parse("CONNECTED\n-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----\nVerify return code: 18 (self signed)\n")
    assertEquals(shake, Some(Handshake("self signed", "-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----\n")))
    assertEquals(Handshake.parse("CONNECTED\n"), None)
    assertEquals(Issued.parse("issuer=C=US, O=Let's Encrypt, CN=R11\nnotAfter=Mar  1 12:00:00 2027 GMT\n"),
      Issued("R11", "Mar  1 12:00:00 2027 GMT"))
    assertEquals(CertVerdict.BrowserWarning("a|b").mark, "**FAIL** browser warning: a/b")
    assertEquals(CertRow("n", "h", None, Issued.none, CertVerdict.Ok).render, "| n | h | no A record | – | – | ok |")

  def repo(): os.Path =
    val root = os.temp.dir(prefix = "certs")
    os.proc("git", "init", "-q").call(cwd = root)
    os.write(root / "a.nix", "{ x = \"new.piabrota.art\"; y = \"https://piabrota.art/\"; }\n")
    os.write(root / "b.txt", "other.piabrota.art\n")
    os.proc("git", "add", ".").call(cwd = root)
    root

  test("coverage"):
    val root = repo()
    val missing = TestKit.piabrota(Seq("cert-check", "--coverage"), cwd = root,
      env = Map("DOMAINS_FILE" -> os.temp("piabrota.art piabrota\n").toString))
    assertEquals(missing.exitCode, 1)
    assertEquals(missing.err.text(), "not in scripts/domains.txt: new.piabrota.art\n")
    os.write(root / "scripts" / "domains.txt", "piabrota.art piabrota\nnew.piabrota.art off\n", createFolders = true)
    val listed = TestKit.piabrota(Seq("cert-check", "--coverage"), cwd = root / "scripts")
    assertEquals(listed.exitCode, 0, listed.err.text())
    assertEquals(listed.out.text(), "every piabrota.art name of the *.nix files is in scripts/domains.txt\n")

  val openssl = """#!/bin/sh
                  |case "$1 $3" in
                  |  "s_client none.invalid:443") exit 1 ;;
                  |  "s_client good.invalid:443") code="0 (ok)" ;;
                  |  "s_client warn.invalid:443") code="18 (self-signed certificate)" ;;
                  |  "s_client old.invalid:443") printf -- '-----BEGIN CERTIFICATE-----\nOLD\n-----END CERTIFICATE-----\nVerify return code: 0 (ok)\n'; exit 0 ;;
                  |  x509*)
                  |    case "$*" in *-checkend*) grep -q MIIB; exit $? ;; esac
                  |    cat >/dev/null
                  |    echo "issuer=C=US, O=Let's Encrypt, CN=R11"
                  |    echo "notAfter=Mar  1 12:00:00 2027 GMT"
                  |    exit 0 ;;
                  |esac
                  |printf 'CONNECTED\n-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----\nVerify return code: %s\n' "$code"
                  |""".stripMargin

  test("the table, with openssl standing in for the handshake"):
    val domains = os.temp("good.invalid piabrota2\nwarn.invalid piabrota\nnone.invalid piabrota\noff.invalid off\n")
    val r = TestKit.piabrota(Seq("cert-check"), env = Map("DOMAINS_FILE" -> domains.toString),
      cwd = os.temp.dir(), fakes = Some(TestKit.fakes("openssl" -> openssl)))
    assertEquals(r.exitCode, 1)
    assertEquals(r.out.text(),
      """|| Name | Host | Address | Issuer | Expires | Result |
        ||---|---|---|---|---|---|
        || good.invalid | piabrota2 | no A record | R11 | Mar  1 12:00:00 2027 GMT | ok |
        || warn.invalid | piabrota | no A record | R11 | Mar  1 12:00:00 2027 GMT | **FAIL** browser warning: self-signed certificate |
        || none.invalid | piabrota | no A record | – | – | **FAIL** no TLS answer (DNS on the wrong host, or nginx refused the name) |
        |
        |2 of 3 names failed. A self-signed (minica) issuer means the ACME order failed: see docs/SITE.md, "Certificates".
        |""".stripMargin)

  test("one name that passes"):
    val r = TestKit.piabrota(Seq("cert-check", "good.invalid"), cwd = os.temp.dir(),
      env = Map("DOMAINS_FILE" -> os.temp("").toString), fakes = Some(TestKit.fakes("openssl" -> openssl)))
    assertEquals(r.exitCode, 0)
    assert(r.out.text().contains("| good.invalid | ? | no A record | R11 |"), r.out.text())
    assert(r.out.text().endsWith("All 1 names have a valid certificate with more than 14 days left.\n"), r.out.text())

  test("a certificate that expires soon"):
    val r = TestKit.piabrota(Seq("cert-check", "old.invalid"), cwd = os.temp.dir(),
      env = Map("DOMAINS_FILE" -> os.temp("").toString, "CERT_MIN_DAYS" -> "30"),
      fakes = Some(TestKit.fakes("openssl" -> openssl)))
    assertEquals(r.exitCode, 1)
    assert(r.out.text().contains("| R11 | Mar  1 12:00:00 2027 GMT | **FAIL** expires in less than 30 days |"), r.out.text())
