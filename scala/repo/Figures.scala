package piabrota.repo

import piabrota.lib.{Repo, Sh, Sha256, die}

/** The figures of docs/FIGURES.md and the wiki against their sources (the `figure` skill):
  * `piabrota figure-lock` prints figures.lock, the inputs of each figure; `piabrota figure-check`
  * fails on a missing, unshown or stale PNG. Offline; CI runs the check.
  */
object Figures:
  def lock(args: List[String]): Int =
    if args.nonEmpty then die("usage: piabrota figure-lock", 2)
    lockLines(Repo.root()).foreach(l => println(l.render))
    0

  def check(args: List[String]): Int =
    if args.nonEmpty then die("usage: piabrota figure-check", 2)
    val root = Repo.root()
    figures(root).flatMap(problem(root, _)).headOption.orElse(staleLock(root)) match
      case Some(message) => System.err.println(s"figure-check: $message"); 1
      case None          => println("figure-check: ok"); 0

  /** Every source, English first, then the pt-BR mirrors, each set in name order. */
  def figures(root: os.Path): List[Figure] =
    def in(dir: os.SubPath, prefix: String) =
      val path = root / dir
      if !os.isDir(path) then Nil
      else os.list(path).filter(p => os.isFile(p) && p.ext == "json").map(p => Figure(prefix + p.baseName)).sortBy(_.slug).toList
    in(FigurePaths.sources, "") ++ in(FigurePaths.sources / FigurePaths.mirrorDir, FigurePaths.mirrorDir + "/")

  /** The first rule this figure breaks, as the old recipe reported it. */
  def problem(root: os.Path, f: Figure): Option[String] =
    val png = root / f.png
    if !os.isFile(png) || os.size(png) == 0 then Some(s"no PNG for ${f.source}; run just figure")
    else if !os.isFile(root / f.wikiPng) || os.read.bytes(png).toSeq != os.read.bytes(root / f.wikiPng).toSeq then
      Some(s"${f.wikiPng} is not ${f.png}; run just figure")
    else if f.isMirror && !wikiShows(root, f) then Some(s"no wiki page shows img/${f.slug}.png")
    else if !f.isMirror && !os.read(root / FigurePaths.index).contains(f.link) then
      Some(s"${FigurePaths.index} does not show img/${f.slug}.png")
    else None

  def lockLines(root: os.Path): List[LockLine] =
    val pin = Sh.out("git", "ls-files", "-s", FigurePaths.archify.toString)(using Sh.Opts(cwd = root)).split("\\s+")(1)
    val shared = os.read.bytes(root / FigurePaths.look) ++ os.read.bytes(root / FigurePaths.crop)
    figures(root).map { f =>
      LockLine(f.slug, s"${Sha256.hex(os.read.bytes(root / f.source) ++ shared).take(16)}-${pin.take(7)}")
    }

  private def staleLock(root: os.Path): Option[String] =
    val want = lockLines(root).map(_.render).mkString("", "\n", "\n")
    Option.when(!os.isFile(root / FigurePaths.lock) || os.read(root / FigurePaths.lock) != want)(
      "a source, the look or the Archify pin changed since the PNG; run just figure")

  private def wikiShows(root: os.Path, f: Figure): Boolean =
    os.walk(root / FigurePaths.wiki).exists(p => os.isFile(p) && p.ext == "md" && os.read(p).contains(f.link))
