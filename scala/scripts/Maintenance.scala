package piabrota.scripts

import piabrota.lib.{Sh, die, warn}

/** Units that look after the box itself. */
object Maintenance:
  /** `piabrota acme-retry NAME` (acme-retry.nix, acme-retry@NAME.service): starts the failed
    * certificate order acme-order-renew-NAME.service again in 20 minutes, through a transient timer.
    * Past the unit's StartLimitBurst the start is refused anyway, so the name is left to its daily
    * timer.
    */
  def acmeRetry(args: List[String]): Int = args match
    case List(name) =>
      val unit = Acme.orderUnit(name)
      if Sh.outOpt("systemctl", "show", "-P", "Result", unit).contains("start-limit-hit") then 0
      else
        val systemctl = Sh.which("systemctl").map(_.toString).getOrElse("systemctl")
        Util.exec(Exec(List("systemd-run", "--collect", "--on-active=20min", s"--unit=acme-retry-later-$name",
          systemctl, "start", "--no-block", unit)))
    case _ => die("usage: piabrota acme-retry NAME", 2)

  /** `piabrota kubesolo-purge` (kubesolo-purge.nix): deletes what KubeSolo left on the box: the
    * pods and their shims, the mounts (deepest first, lazily), the state, the pod network and its
    * firewall rules. The steps of the old docs/KUBESOLO.md, "Cleaning what is left". Every step may
    * fail and the next one still runs; it always exits 0.
    */
  def kubesoloPurge(@annotation.unused args: List[String]): Int =
    // A program that is missing is one more step that failed.
    def step(cmd: String*): Unit =
      try Util.run(cmd)
      catch case e: java.io.IOException => warn(s"${cmd.head}: ${e.getMessage}")
    def quiet(cmd: String*): Unit =
      try Sh.ok(cmd)
      catch case _: java.io.IOException => ()
    // 1. The pods, then the containerd shims that outlived the unit.
    step("systemctl", "stop", "kubepods.slice")
    step("pkill", "-f", "containerd-shim-runc-v2")
    // 2. What containerd and the kubelet mounted, deepest first, then the state. --one-file-system
    //    keeps rm out of anything still mounted.
    val mounts = Sh.outOpt("findmnt", "-rn", "-o", "TARGET").getOrElse("").linesIterator
      .filter(m => "^(/var/lib/kubesolo|/run/containerd|/run/netns/cni-).*".r.matches(m)).toList
    mounts.sorted.reverse.foreach(m => step("umount", "-l", m))
    step("rm", "-rf", "--one-file-system", "/var/lib/kubesolo", "/var/lib/kubesolo-secrets",
      "/run/kubesolo-admin", "/etc/cni/net.d/10-bridge.conflist")
    quiet("rmdir", "/etc/cni/net.d", "/etc/cni")
    // 3. The pod network: the bridge, the veths, kube-proxy's and the CNI's rules, forwarding.
    quiet("ip", "link", "delete", "cni0")
    val veths = "veth[^@:]*".r.findAllIn(Sh.outOpt("ip", "-o", "link", "show").getOrElse("")).toList
    veths.foreach(v => step("ip", "link", "delete", v))
    val kube = ".*(KUBE-|CNI-).*".r
    for t <- List("iptables", "ip6tables") do
      val rules = Sh.outOpt(s"$t-save").getOrElse("")
      if rules.linesIterator.exists(kube.matches) then
        val kept = rules.linesIterator.filterNot(kube.matches).map(_ + "\n").mkString
        try os.proc(s"$t-restore").call(stdin = kept, stdout = os.Inherit, stderr = os.Inherit, check = false)
        catch case e: java.io.IOException => warn(s"$t-restore: ${e.getMessage}")
    for line <- Sh.outOpt("nft", "list", "tables").getOrElse("").linesIterator if line.toLowerCase.contains("kube") do
      line.trim.split("\\s+") match
        case Array(_, family, name, _*) => step("nft", "delete", "table", family, name)
        case _                          => ()
    step("sysctl", "-q", "-w", "net.ipv4.ip_forward=0")
    quiet("modprobe", "-r", "br_netfilter")
    println("KubeSolo's state, mounts and network are gone")
    0
