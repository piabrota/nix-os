package piabrota.scripts

import piabrota.lib.{Sh, die, env, warn}
import Util.step

/** The units of marola-site.nix that fill /var/lib/marola-boards and the base map's tiles. Every
  * area is replaced whole: its new folder is written beside the live one and renamed over it, so a
  * reader never sees half a board. Messages go to stderr, as the scripts these replace wrote them.
  */
object MarolaBoards:
  /** A new folder for an area, beside the boards: mode 0700 until it is complete. */
  private def incoming(out: os.Path): os.Path = os.temp.dir(dir = out, prefix = ".incoming.", deleteOnExit = false)

  /** Puts `tmp` in the place of `out/area`, with mode 0755. */
  private def swap(tmp: os.Path, out: os.Path, area: String): Unit =
    os.perms.set(tmp, "rwxr-xr-x")
    os.remove.all(out / s"$area.old")
    if os.isDir(out / area) then os.move(out / area, out / s"$area.old")
    os.move(tmp, out / area)
    os.remove.all(out / s"$area.old")

  /** `piabrota marola-boards-mirror SOURCE OUT AREAS_JSON`: copies each area's boards from another
    * marola site (SOURCE/<area>/latest.json and the day files it names) into OUT. An area that
    * fails keeps the boards it had.
    */
  def mirror(args: List[String]): Int = args match
    case List(src, outDir, areasJson) =>
      val out = os.Path(outDir, os.pwd)
      for area <- Boards.areas(os.read(os.Path(areasJson, os.pwd))) do
        val tmp = incoming(out)
        if Sh.run("curl", "-fsS", "--max-time", "30", s"$src/$area/${Boards.latestFile}", "-o", tmp / Boards.latestFile) != 0 then
          warn(s"marola-boards: no latest.json for $area")
          os.remove.all(tmp)
        else
          val ok = Boards.days(os.read(tmp / Boards.latestFile)).forall { f =>
            if !Boards.isDayFile(f) then
              warn(s"marola-boards: $area: refused file name $f")
              false
            else Sh.run("curl", "-fsS", "--max-time", "60", s"$src/$area/$f", "-o", tmp / f) == 0
          }
          if ok then
            swap(tmp, out, area)
            warn(s"marola-boards: $area updated")
          else
            warn(s"marola-boards: $area kept as it was")
            os.remove.all(tmp)
      0
    case _ => die("usage: piabrota marola-boards-mirror SOURCE OUT AREAS_JSON", 2)

  /** `piabrota marola-tiles TILES STAMP BASEMAP_VERSION AREAS BASEMAP_EXTRACT`: cuts the base map's
    * tiles file TILES/marola.pmtiles with marola-site's basemap_extract.sh, for the Protomaps build
    * BASEMAP_VERSION pins and the areas of AREAS. STAMP is the hash of the two: a deploy that
    * changes neither leaves the file alone.
    */
  def tiles(args: List[String]): Int = args match
    case List(tilesDir, stamp, basemapVersion, areas, extract) =>
      val tiles = os.Path(tilesDir, os.pwd)
      val (live, fresh) = (tiles / MarolaPaths.tiles, tiles / MarolaPaths.newTiles)
      val work = MarolaPaths.tilesWork
      val current = scala.util.Try(os.read(tiles / MarolaPaths.stamp).stripTrailing()).getOrElse("")
      if os.isFile(live) && os.size(live) > 0 && current == stamp then
        warn("marola-tiles: marola.pmtiles is current")
      else
        step("install", "-d", "-m", "0750", tiles)
        step("install", "-d", work / "site")
        step("install", "-m", "0644", basemapVersion, work / "site" / "basemap.version")
        step("install", "-m", "0644", areas, work / "site" / Boards.areasFile)
        // Write beside the live file, then rename: a reader never sees half a file.
        val code = os.proc("bash", extract, fresh).call(env = Map("BASEMAP_ROOT" -> work.toString),
          stdin = os.Inherit, stdout = os.Inherit, stderr = os.Inherit, check = false).exitCode
        if code != 0 then die("", code)
        os.perms.set(fresh, "rw-r--r--")
        os.remove(tiles / s"${MarolaPaths.tiles}.new")
        os.move(fresh, live, replaceExisting = true)
        os.write.over(tiles / MarolaPaths.stamp, stamp + "\n")
        os.remove.all(work / ".tmp")
      0
    case _ => die("usage: piabrota marola-tiles TILES STAMP BASEMAP_VERSION AREAS BASEMAP_EXTRACT", 2)

  /** `piabrota marola-boards-build IMAGE REGISTRY_USER MEMORY AREAS OUT`: builds the boards as
    * marola-site's site.yml does, with its app image IMAGE (pulled with the credential ghcr-token
    * when the unit has one), `--site` over AREAS, no LLM, then copies area by area what the build
    * wrote into OUT. Two tries: INEA, INEMA and Overpass time out now and then. A failed run keeps
    * the areas it wrote before it failed, so the copy always runs; the exit code is the build's.
    */
  def build(args: List[String]): Int = args match
    case List(image, registryUser, memory, areas, outDir) =>
      val config = BoardsBuildConfig(env(EnvNames.credentialsDirectory).map(os.Path(_)),
        env("RUNTIME_DIRECTORY").map(os.Path(_)))
      val out = os.Path(outDir, os.pwd)
      val site = MarolaPaths.boardsBuild / "site"
      val owner = Seq("-o", Owner.marola.user, "-g", Owner.marola.group)
      step(Seq("install", "-d") ++ owner ++ Seq(site.toString, (site / "beaches").toString))
      step(Seq("install", "-m", "0644") ++ owner ++ Seq(areas, (site / Boards.areasFile).toString))
      os.remove.all(site / "dist")
      step(Seq("install", "-d") ++ owner :+ (site / "dist").toString)
      if !Sh.ok("podman", "image", "exists", image) then pull(config, image, registryUser)

      val user = s"${Sh.out("id", "-u", Owner.marola.user)}:${Sh.out("id", "-g", Owner.marola.group)}"
      val built = (1 to 2).exists { attempt =>
        val ok = Util.run("podman", "run", "--rm", "--memory", memory, "--user", user, "-e", "HOME=/tmp",
          "-v", s"$site:/work/site", "-w", "/work", image, "--site", "--areas", s"site/${Boards.areasFile}",
          "--site-out", "site/dist") == 0
        if !ok then
          warn(s"marola-boards: build attempt $attempt failed")
          if attempt < 2 then Thread.sleep(60000)
        ok
      }
      // Only what the build wrote, area by area; an area it did not write keeps its old boards.
      val data = site / "dist" / "data"
      val written = if os.isDir(data) then os.list(data).filter(d => os.isDir(d) && !d.last.startsWith(".")) else Nil
      for dir <- written if os.isFile(dir / Boards.latestFile) do
        val tmp = incoming(out)
        step("cp", "-r", s"$dir/.", s"$tmp/")
        step("chown", "-R", Owner.marola.render, tmp)
        swap(tmp, out, dir.last)
        warn(s"marola-boards: ${dir.last} built")
      if os.isFile(data / Boards.areasFile) then
        step(Seq("install", "-m", "0644") ++ owner ++ Seq((data / Boards.areasFile).toString, (out / Boards.areasFile).toString))
      // Old image versions, after a pin moves.
      Sh.ok("podman", "image", "prune", "-f")
      if built then 0 else 1
    case _ => die("usage: piabrota marola-boards-build IMAGE REGISTRY_USER MEMORY AREAS OUT", 2)

  private def pull(config: BoardsBuildConfig, image: String, registryUser: String): Unit =
    config.ghcrToken match
      case Some(file) =>
        val auth = config.runtime.getOrElse(die("RUNTIME_DIRECTORY is not set", 1)) / "auth.json"
        System.out.flush()
        val login = os.proc("podman", "login", "--authfile", auth, "-u", registryUser, "--password-stdin", MarolaPaths.registry)
          .call(stdin = file, stdout = os.Inherit, stderr = os.Inherit, check = false).exitCode
        if login != 0 then die("", login)
        step("podman", "pull", "--authfile", auth, image)
        os.remove(auth)
      case None => step("podman", "pull", image)
