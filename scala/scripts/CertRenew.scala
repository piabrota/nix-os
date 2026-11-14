package piabrota.scripts

import piabrota.lib.{Sh, env}

/** `piabrota cert-renew [all|NAME...] [--dry-run]`: orders again the certificates of this box that a
  * browser would refuse: NixOS's self-signed stand-in (issuer minica, left when an order failed) or
  * one that expires within CERT_MIN_DAYS days (default 14). For the OWNER only: an agent never runs
  * it. Run as root on the box (`just remote-cert-renew`, `just certs-fix`).
  *
  * all (the default): every certificate in /var/lib/acme that needs it. NAME: that certificate,
  * even when it looks fine. --dry-run: print the plan and change nothing. It starts
  * acme-order-renew-<name>.service only, never another unit, and waits for it. The DNS record of the
  * name must point at this box first (scripts/domains.txt, docs/SITE.md, "Certificates"), or Let's
  * Encrypt fails the order again.
  * Exit 0: every certificate is fine. 1: one is still self-signed or near its end. 2: usage, or no
  * root for a real run. For tests only: ACME_DIR (default /var/lib/acme).
  */
object CertRenew:
  private val usage = "usage: piabrota cert-renew [all|NAME...] [--dry-run]"
  private val validName = "[a-z0-9.-]+".r
  private val dryRun = "--dry-run"

  def run(args: List[String]): Int =
    val config = CertRenewConfig(
      acme = os.Path(env("ACME_DIR").getOrElse(Acme.dir), os.pwd),
      minDays = env("CERT_MIN_DAYS").flatMap(_.toIntOption).getOrElse(Acme.defaultMinDays),
      dry = args.contains(dryRun),
      named = args.filterNot(a => a == dryRun || a == "all"))
    if config.named.exists(a => a.startsWith("-") || !validName.matches(a)) then
      System.err.println(usage)
      2
    else if !config.dry && !Util.isRoot() then
      System.err.println("cert-renew: run it as root (sudo), or with --dry-run")
      2
    else
      val forced = config.named.nonEmpty
      val names =
        if forced then config.named
        else if !os.isDir(config.acme) then Nil
        else os.list(config.acme).filter(d => os.isDir(d) && !d.last.startsWith(".") && os.isFile(d / Acme.certFile))
          .map(_.last).toList
      val results = names.map(renew(config, _, forced))
      if results.contains(false) then 1 else 0

  /** Why a browser would refuse the certificate, if it would. */
  def state(config: CertRenewConfig, name: String): CertState =
    val cert = config.cert(name)
    if !os.isFile(cert) then CertState.NoFile
    else if Sh.outOpt("openssl", "x509", "-noout", "-issuer", "-in", cert).exists(_.toLowerCase.contains(Acme.standIn)) then
      CertState.SelfSigned
    else if !Sh.ok("openssl", "x509", "-noout", "-checkend", (config.minDays * 86400).toString, "-in", cert) then
      CertState.ExpiresWithin(config.minDays)
    else CertState.Ok

  /** One certificate; false if it is still refused after its order. */
  private def renew(config: CertRenewConfig, name: String, forced: Boolean): Boolean =
    val unit = Acme.orderUnit(name)
    val before = state(config, name)
    if !Sh.ok("systemctl", "cat", unit) then
      println(s"skip  $name: this box has no $unit"); true
    else if before == CertState.Ok && !forced then
      println(s"ok    $name"); true
    else if config.dry then
      println(s"plan  $name (${before.render}): systemctl start $unit"); true
    else
      println(s"order $name (${before.render}) ...")
      Sh.ok("systemctl", "reset-failed", unit)
      if Util.run("systemctl", "start", unit) != 0 then
        println(s"      the order failed: journalctl -u $unit -n 30")
      val after = state(config, name)
      if after == CertState.Ok then
        val info = Sh.outOpt("openssl", "x509", "-noout", "-issuer", "-enddate", "-in", config.cert(name)).getOrElse("")
        println(s"ok    $name: ${info.linesIterator.map(_ + " ").mkString}")
        true
      else
        println(s"FAIL  $name: still ${after.render}; check its DNS record (dig +short A $name)")
        false
