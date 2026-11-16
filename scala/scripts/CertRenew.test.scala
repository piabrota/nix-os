package piabrota.scripts

import piabrota.lib.TestKit

/** cert-renew with a fixture /var/lib/acme, a stub systemctl and a stub openssl that reads a
  * fixture "certificate" (its issuer and its end, in epoch seconds). The stub systemctl "orders" a
  * certificate by writing a good one in its place, unless the name is in FAIL_ORDER.
  */
class CertRenewTest extends munit.FunSuite:
  private val work = os.temp.dir(prefix = "certs")
  private val acme = work / "acme"
  private val log = work / "log"

  private val openssl = """#!/bin/sh
# openssl x509 -noout (-issuer | -checkend N | -issuer -enddate) -in FILE
eval "file=\${$#}"
case "$3" in
  -checkend) end=$(sed -n 's/^end=//p' "$file"); [ "$end" -gt $(( $(date +%s) + $4 )) ] ;;
  -issuer) sed -n 's/^issuer=/issuer=/p' "$file"; [ "$4" = -enddate ] && sed -n 's/^end=/notAfter=/p' "$file"; exit 0 ;;
esac
"""
  private val systemctl = s"""#!/bin/sh
echo "$$*" >> "$log"
case $$1 in
  cat) case $$2 in acme-order-renew-*.service) n=$${2#acme-order-renew-}; [ -d "$acme/$${n%.service}" ] ;; *) exit 1 ;; esac ;;
  reset-failed) exit 0 ;;
  start)
    n=$${2#acme-order-renew-}; n=$${n%.service}
    case " $${FAIL_ORDER:-} " in *" $$n "*) exit 1 ;; esac
    printf 'issuer=CN=YE2\\nend=%s\\n' $$(( $$(date +%s) + 90 * 86400 )) > "$acme/$$n/cert.pem" ;;
esac
"""
  private val fakes = TestKit.fakes("openssl" -> openssl, "systemctl" -> systemctl,
    "id" -> "#!/bin/sh\necho \"${STUB_UID:-0}\"\n")

  /** A certificate whose issuer is `issuer` and that ends in `days` days. */
  private def cert(name: String, issuer: String, days: Int): Unit =
    val end = java.time.Instant.now().getEpochSecond + days * 86400L
    os.write.over(acme / name / "cert.pem", s"issuer=CN=$issuer\nend=$end\n", createFolders = true)

  private def run(args: String*)(env: (String, String)*): (Int, String) =
    os.write.over(log, "")
    val r = TestKit.piabrota("cert-renew" +: args, env = Map("ACME_DIR" -> acme.toString) ++ env, fakes = Some(fakes))
    (r.exitCode, r.out.text() + r.err.text())
  private def starts = os.read.lines(log).filter(_.startsWith("start ")).toList
  private def count(out: String, regex: String) = out.linesIterator.count(l => s"$regex.*".r.matches(l))

  override def beforeEach(context: BeforeEach): Unit =
    os.remove.all(acme)
    cert("good.example", "YE1", 80)
    cert("stand-in.example", "minica root ca 093f63", 700)
    cert("old.example", "YE1", 5)
    os.makeDir.all(acme / "acme-challenge")
    os.makeDir.all(acme / ".lego")

  test("--dry-run plans the two bad ones and starts nothing, as any user"):
    val (code, out) = run("--dry-run")("STUB_UID" -> "1000")
    assertEquals(code, 0, out)
    assertEquals(starts, Nil)
    assertEquals(count(out, """^plan  stand-in\.example \(self-signed \(minica\)\)"""), 1, out)
    assertEquals(count(out, """^plan  old\.example \(expires within 14 days\)"""), 1, out)
    assertEquals(count(out, "^ok    good\\.example"), 1, out)
    assert(!out.contains("acme-challenge") && !out.contains(".lego"), out)

  test("a bad argument is refused"):
    assertEquals(run("../etc")()._1, 2)
    assertEquals(run("--force")()._1, 2)

  test("all: the two bad ones are ordered and fixed"):
    val (code, out) = run("all")()
    assertEquals(code, 0, out)
    assertEquals(starts.size, 2)
    assert(!starts.contains("start acme-order-renew-good.example.service"))
    assertEquals(count(out, "^ok    stand-in\\.example: issuer=.*YE2"), 1, out)

  test("a name given is ordered even when it looks fine"):
    val (code, out) = run("good.example")()
    assertEquals(code, 0, out)
    assertEquals(starts.size, 1)

  test("an order that fails leaves exit 1 and says what to check"):
    val (code, out) = run("stand-in.example")("FAIL_ORDER" -> "stand-in.example")
    assertEquals(code, 1, out)
    assertEquals(count(out, """^FAIL  stand-in\.example: still self-signed \(minica\); check its DNS record"""), 1, out)
    assert(out.contains("journalctl -u acme-order-renew-stand-in.example.service"), out)

  test("a name this box does not serve is skipped"):
    val (code, out) = run("nope.example")()
    assertEquals(code, 0, out)
    assertEquals(count(out, "^skip  nope\\.example"), 1, out)

  test("a real run needs root"):
    val (code, out) = run("all")("STUB_UID" -> "1000")
    assertEquals(code, 2, out)
    assertEquals(starts, Nil)
