package piabrota.scripts

import java.net.{Inet4Address, InetAddress, UnknownHostException}
import piabrota.lib.{Sh, env}

/** `piabrota cert-check`: the HTTPS certificate of every live name in scripts/domains.txt, from
  * outside, as a browser sees it. Run by `just certs` and certs.yml; `--coverage` by ci.yml.
  */
object CertCheck:
  val usage: String =
    """The HTTPS certificate of every live name in scripts/domains.txt, from outside, as a browser
      |sees it: the TLS handshake must pass the system's CA store with no warning (a public CA, the right
      |name, not expired) and the certificate must have more than CERT_MIN_DAYS days left (default 14).
      |Prints a Markdown table (for a run summary) and exits 1 when a name fails. Read-only; needs
      |openssl (s_client for the handshake, x509 to read the certificate).
      |
      |  piabrota cert-check               check every live name     (just certs)
      |  piabrota cert-check NAME...       check only these names
      |  piabrota cert-check --coverage    no network: fail when a *.nix file names a
      |                                    piabrota.art name that domains.txt does not list (CI)""".stripMargin

  private val name = "([a-z0-9-]+\\.)?piabrota\\.art".r

  def run(args: List[String]): Int =
    val root = piabrota.lib.Repo.root()
    val config = CertCheckConfig(root, env("DOMAINS_FILE").map(os.Path(_, os.pwd)).getOrElse(root / os.RelPath(Domain.file)))
    val domains = Domain.parse(os.read(config.domains))
    args match
      case ("-h" | "--help") :: _ => println(usage); 0
      case "--coverage" :: _      => coverage(domains.map(_.name).toSet, config.root)
      case names                  =>
        table(domains, names, sys.env.getOrElse("CERT_MIN_DAYS", Acme.defaultMinDays.toString).toInt)

  def coverage(listed: Set[String], root: os.Path): Int =
    val files = Sh.out("git", "-C", root.toString, "ls-files", "*.nix").split("\\s+").filter(_.nonEmpty)
    val missing = missingNames(files.toList.map(f => readLossy(root / os.RelPath(f))), listed)
    missing.foreach(n => System.err.println(s"not in ${Domain.file}: $n"))
    if missing.isEmpty then println(s"every piabrota.art name of the *.nix files is in ${Domain.file}")
    if missing.isEmpty then 0 else 1

  /** The piabrota.art names the texts hold that `listed` does not, sorted. */
  def missingNames(texts: List[String], listed: Set[String]): List[String] =
    texts.flatMap(name.findAllIn(_)).distinct.sorted.filterNot(listed)

  private def readLossy(p: os.Path): String = new String(os.read.bytes(p), "UTF-8")

  private def table(domains: List[Domain], args: List[String], minDays: Int): Int =
    val hosts = domains.map(d => d.name -> d.host).toMap
    val names = if args.nonEmpty then args else domains.filter(_.live).map(_.name)
    CertRow.header.foreach(println)
    val failed = names.count { n =>
      val (issued, verdict) = check(n, minDays)
      println(CertRow(n, hosts.get(n).filter(_.nonEmpty).getOrElse("?"), address(n), issued, verdict).render)
      verdict != CertVerdict.Ok
    }
    println()
    if failed == 0 then
      println(s"All ${names.length} names have a valid certificate with more than $minDays days left.")
    else
      println(s"$failed of ${names.length} names failed. A self-signed (minica) issuer means the ACME order failed: " +
        "see docs/SITE.md, \"Certificates\".")
    if failed == 0 then 0 else 1

  private def address(n: String): Option[String] =
    try InetAddress.getAllByName(n).collect { case a: Inet4Address => a.getHostAddress }.lastOption
    catch case _: UnknownHostException => None

  /** The issuer and end of one name's certificate, and whether a browser takes it. */
  def check(n: String, minDays: Int): (Issued, CertVerdict) =
    handshake(n) match
      case None => (Issued.none, CertVerdict.NoTls)
      case Some(shake) =>
        val issued = describe(shake.pem)
        if !shake.verified then (issued, CertVerdict.BrowserWarning(shake.verify))
        else if Sh.call("openssl", "x509", "-noout", "-checkend", (minDays * 86400L).toString)(using
            Sh.Opts(stdin = shake.pem)).exitCode != 0 then (issued, CertVerdict.ExpiresSoon(minDays))
        else (issued, CertVerdict.Ok)

  /** What the server sends, or None when no TLS answers within 15 s. */
  private def handshake(n: String): Option[Handshake] =
    val p = os.proc("openssl", "s_client", "-connect", s"$n:443", "-servername", n, "-verify_hostname", n)
      .spawn(stdin = "", stdout = os.Pipe, stderr = os.Pipe)
    if !p.waitFor(15000) then
      p.destroy()
      None
    else Handshake.parse(p.stdout.text())

  private def describe(pem: String): Issued =
    Sh.outOpt("openssl", "x509", "-noout", "-issuer", "-enddate")(using Sh.Opts(stdin = pem))
      .fold(Issued.none)(Issued.parse)
