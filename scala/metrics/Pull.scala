package piabrota.metrics

import java.io.IOException
import java.nio.charset.StandardCharsets.ISO_8859_1
import java.nio.file.Files

import piabrota.lib.{warn, Sh}

/** `piabrota metrics-pull`: fetch another host's metrics file (piabrota, on KVM 1) and keep it as
  * OUT_DIR/<name>.json. A timer runs it on piabrota2 (metrics.nix). A failed fetch, a body that is
  * not this host's JSON object, or a body over 64 KB leaves the old file, so the page shows the
  * host going stale and then offline. Exit 0 either way: a host that is down is a state of the
  * page, not a failed unit.
  *
  * Environment ([[PullConfig]]):
  *   METRICS_PULL_URL   the address of the file (required)
  *   METRICS_PULL_NAME  the host's name, as in its "host" key (required)
  *   OUT_DIR            where <name>.json goes (default /run/metrics-web)
  */
object Pull:
  private val MaxBytes = "65536"

  def run(args: List[String]): Int =
    val config = PullConfig.fromEnv()
    Host.umask022()
    val (url, name, out) = (config.url, config.name, config.outFile)
    val tmp = Host.temp(out)
    Host.cleaning(tmp) {
      // -4: the other host allows this host's IPv4 address only.
      val fetched =
        try Sh.ok("curl", "-4", "-sf", "--max-time", "5", "--max-filesize", MaxBytes, "-o", tmp, url)
        catch case _: IOException => false
      if !fetched then warn(s"pull: fetch of $url failed; the old file stays")
      else
        val body = bytes(tmp)
        if !HostName.claims(String(body.getOrElse(Array.emptyByteArray), ISO_8859_1), name) then
          warn(s"pull: $url did not return the file of $name; the old file stays")
        else if !bytes(out).exists(_.sameElements(body.get)) then Host.move(tmp, out)
    }
    0

  private def bytes(file: String): Option[Array[Byte]] =
    try Some(Files.readAllBytes(Host.path(file)))
    catch case _: IOException => None
