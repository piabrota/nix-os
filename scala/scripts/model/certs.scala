package piabrota.scripts

// The certificates of the boxes: scripts/domains.txt, what a browser sees, and the ACME orders.

/** A line of scripts/domains.txt: a name and the host its DNS record points at, or `off`. */
final case class Domain(name: String, host: String):
  def live: Boolean = host != Domain.off

object Domain:
  /** The host of a name that serves nothing yet. */
  val off = "off"
  val file = "scripts/domains.txt"

  /** The lines that are not comments; a name with no host has "". */
  def parse(text: String): List[Domain] =
    text.linesIterator.map(_.trim.split("\\s+").filter(_.nonEmpty)).collect {
      case cells if cells.nonEmpty && !cells(0).startsWith("#") => Domain(cells(0), cells.lift(1).getOrElse(""))
    }.toList

/** cert-check's settings: the checkout and domains.txt (DOMAINS_FILE). */
final case class CertCheckConfig(root: os.Path, domains: os.Path)

/** The issuer CN and notAfter of a certificate; "" when openssl could not read them. */
final case class Issued(issuer: String, ends: String)

object Issued:
  val none: Issued = Issued("", "")

  /** From `openssl x509 -noout -issuer -enddate`. */
  def parse(out: String): Issued =
    Issued("CN *= *([^,\\n]+)".r.findFirstMatchIn(out).map(_.group(1).strip()).getOrElse(""),
      "notAfter=(.*)".r.findFirstMatchIn(out).map(_.group(1).strip()).getOrElse(""))

/** What `openssl s_client` got from a name: the CA store's verdict and the server's certificate. */
final case class Handshake(verify: String, pem: String):
  def verified: Boolean = verify == Handshake.verifiedOk

object Handshake:
  val verifiedOk = "ok"

  /** None when the output holds no certificate. */
  def parse(out: String): Option[Handshake] =
    val pem = "(?s)-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----".r.findFirstIn(out)
    val verify = "Verify return code: \\d+ \\(([^)]*)\\)".r.findFirstMatchIn(out).map(_.group(1))
    pem.map(cert => Handshake(verify.getOrElse("no verify result"), cert + "\n"))

/** Whether a browser takes a name's certificate. */
enum CertVerdict:
  case Ok
  case NoTls
  case BrowserWarning(verify: String)
  case ExpiresSoon(minDays: Int)

  def render: String = this match
    case Ok                     => "ok"
    case NoTls                  => "no TLS answer (DNS on the wrong host, or nginx refused the name)"
    case BrowserWarning(verify) => s"browser warning: ${verify.replace("|", "/").take(120)}"
    case ExpiresSoon(minDays)   => s"expires in less than $minDays days"

  def mark: String = if this == Ok then "ok" else s"**FAIL** $render"

/** One row of cert-check's table. */
final case class CertRow(name: String, host: String, address: Option[String], issued: Issued, verdict: CertVerdict):
  def render: String =
    def orDash(s: String) = if s.isEmpty then "–" else s
    s"| $name | $host | ${address.getOrElse("no A record")} | ${orDash(issued.issuer)} | ${orDash(issued.ends)} | ${verdict.mark} |"

object CertRow:
  val header: List[String] = List("| Name | Host | Address | Issuer | Expires | Result |", "|---|---|---|---|---|---|")

/** The state of a certificate in /var/lib/acme, as cert-renew sees it. */
enum CertState:
  case Ok
  case NoFile
  case SelfSigned
  case ExpiresWithin(days: Int)

  def render: String = this match
    case Ok                  => "ok"
    case NoFile              => "no certificate file"
    case SelfSigned          => "self-signed (minica)"
    case ExpiresWithin(days) => s"expires within $days days"

/** cert-renew's settings: /var/lib/acme (ACME_DIR), CERT_MIN_DAYS, --dry-run, and the names given. */
final case class CertRenewConfig(acme: os.Path, minDays: Int, dry: Boolean, named: List[String]):
  def cert(name: String): os.Path = acme / name / Acme.certFile

/** NixOS's ACME units and files. */
object Acme:
  val dir = "/var/lib/acme"
  val certFile = "cert.pem"
  /** The issuer of NixOS's self-signed stand-in, left when an order failed. */
  val standIn = "minica"
  val defaultMinDays = 14

  def orderUnit(name: String): String = s"acme-order-renew-$name.service"
