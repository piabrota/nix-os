package piabrota.scripts

import piabrota.lib.Sh

/** `piabrota freeze [--by-size] [system]`: like `pip freeze`, for the running NixOS system. Every
  * package in its closure as name==version with its size, sorted by name (or by size, largest
  * first). Store paths with no version (config files, units, scripts) are not listed but count in
  * the total on the last line. Run on the box (`ssh box piabrota freeze`); the default system is
  * /run/current-system.
  */
object Freeze:
  def run(args: List[String]): Int =
    val chosen = FreezeArgs.parse(args)
    val r = Sh.call("nix", "--extra-experimental-features", "nix-command", "path-info", "--recursive",
      "--size", chosen.system)
    System.err.print(r.err.text())
    report(r.out.text(), chosen.bySize).foreach(println)
    0

  /** The lines of the report, from the output of `nix path-info --recursive --size`. */
  def report(pathInfo: String, bySize: Boolean): List[String] =
    val rows = pathInfo.linesIterator.map(_.trim.split("\\s+")).filter(_.head.nonEmpty).toList
    val sizes = rows.map(f => f.lift(1).flatMap(_.toLongOption).getOrElse(0L))
    val packages = rows.zip(sizes).flatMap((f, bytes) => nameVersion(f(0)).map(FreezePkg(_, bytes)))
    // sort(1) with LC_ALL=C: by the key (-k2,2f or -k3,3nr), then by the whole line.
    val line = (p: FreezePkg) => s"${p.name}\t${p.bytes}"
    val sorted =
      if bySize then packages.sortWith((a, b) => if a.bytes != b.bytes then a.bytes > b.bytes else line(a) < line(b))
      else packages.sortWith { (a, b) =>
        val (ka, kb) = (a.name.toUpperCase, b.name.toUpperCase)
        if ka != kb then ka < kb else line(a) < line(b)
      }
    sorted.map(p => f"${p.name}%-56s ${human(p.bytes)}%12s") :+
      s"# ${packages.size} packages, ${rows.size} store paths, ${human(sizes.sum)}"

  /** `bash-interactive==5.3p9` from `/nix/store/<hash>-bash-interactive-5.3p9`: the version starts
    * at the first "-<digit>", as in nixpkgs names. None for a path with no version.
    */
  def nameVersion(path: String): Option[String] =
    val n = path.replaceFirst("^/nix/store/[^-]*-", "")
    "-[0-9]".r.findFirstMatchIn(n).map(m => s"${n.take(m.start)}==${n.drop(m.start + 1)}")

  def human(b: Long): String =
    if b >= 1073741824L then f"${b / 1073741824.0}%.2f GiB"
    else if b >= 1048576L then f"${b / 1048576.0}%.1f MiB"
    else if b >= 1024L then f"${b / 1024.0}%.1f KiB"
    else s"$b B"
