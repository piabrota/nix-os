package piabrota.scripts

import piabrota.lib.Sh

/** `piabrota specs`: the machine's specs, read from /proc and a few coreutils. It never fails. */
object Specs:
  def run(@annotation.unused args: List[String]): Int =
    osRelease().foreach(row("os", _))
    Sh.outOpt("nixos-version").foreach(row("nixos", _))
    row("kernel", Sh.out("uname", "-srm"))
    row("hostname", Sh.out("uname", "-n"))
    cpu().foreach(row("cpu", _))
    memory().foreach(println)
    disks().foreach(println)
    uptime().foreach(row("uptime", _))
    readable("/proc/loadavg").foreach(text => row("load", text.split(' ').take(3).mkString(" ")))
    generation().foreach(println)
    0

  private def row(key: String, value: String): Unit = println(f"$key%-12s $value")

  private def readable(path: String): Option[String] =
    val p = os.Path(path)
    Option.when(os.isFile(p) && p.toIO.canRead)(os.read(p))

  /** PRETTY_NAME, else NAME, of /etc/os-release. */
  private def osRelease(): Option[String] =
    readable("/etc/os-release").map { text =>
      val fields = text.linesIterator.flatMap { line =>
        line.split("=", 2) match
          case Array(k, v) => Some(k.trim -> v.trim.stripPrefix("\"").stripSuffix("\""))
          case _           => None
      }.toMap
      fields.get("PRETTY_NAME").filter(_.nonEmpty).orElse(fields.get("NAME")).getOrElse("")
    }

  private def cpu(): Option[String] =
    readable("/proc/cpuinfo").map { text =>
      val lines = text.linesIterator.toList
      val model = lines.collectFirst {
        case l if l.startsWith("model name") => l.dropWhile(_ != ':').drop(1).trim
      }.filter(_.nonEmpty).getOrElse("unknown")
      s"$model (${lines.count(_.startsWith("processor"))} vCPU)"
    }

  private def memory(): List[String] =
    readable("/proc/meminfo").toList.flatMap { text =>
      val kib = text.linesIterator.flatMap { line =>
        line.split("\\s+") match
          case Array(key, value, _*) => value.toLongOption.map(key.stripSuffix(":") -> _)
          case _                     => None
      }.toMap.withDefaultValue(0L)
      def gib(key: String) = kib(key) / 1048576.0
      List(
        f"${"ram"}%-12s ${gib("MemTotal")}%.1f GiB total, ${gib("MemAvailable")}%.1f GiB available",
        f"${"swap"}%-12s ${gib("SwapTotal")}%.1f GiB total, ${gib("SwapTotal") - gib("SwapFree")}%.1f GiB used",
      )
    }

  /** One line per file system of /, /nix and /boot; a second mount point on the same device is left out. */
  private def disks(): List[String] =
    val lines = for
      path <- List("/", "/nix", "/boot") if os.isDir(os.Path(path))
      df <- Sh.outOpt("df", "-hP", path).toList
      fields <- df.linesIterator.drop(1).take(1).map(_.split("\\s+")).toList
      if fields.length >= 6
    yield f"${"disk " + path}%-12s ${fields(2)} used of ${fields(1)} (${fields(4)}), ${fields(3)} free, on ${fields(0)}"
    lines.distinctBy(_.split(' ').last)

  private def uptime(): Option[String] =
    readable("/proc/uptime").flatMap(_.split(' ').headOption).flatMap(_.toDoubleOption).map { s =>
      val t = s.toLong
      s"${t / 86400}d ${t % 86400 / 3600}h ${t % 3600 / 60}m"
    }

  private def generation(): List[String] =
    val system = os.Path(BoxPaths.systemProfile)
    if !os.isLink(system) then Nil
    else
      val gen = os.readLink(system).toString.stripPrefix("system-").stripSuffix("-link")
      val kept = os.list(system / os.up).count(p => p.last.matches("system-[0-9]+-link") && os.exists(p))
      val current = os.Path(BoxPaths.currentSystem).toIO.getCanonicalPath
      val booted = scala.util.Try(os.Path(BoxPaths.bootedSystem).toIO.getCanonicalPath).getOrElse("")
      List(f"${"generation"}%-12s $gen (of $kept kept)", f"${"system"}%-12s $current") ++
        Option.when(booted != current)(f"${"booted"}%-12s $booted (reboot to boot the current one)")
