package piabrota.hermes

/** What refresh-grid reads from the environment, once, at its start. */
final case class GridConfig(repoDir: os.Path, repo: String, tokenFile: os.Path, gridCmd: String,
    checkCmd: String, gridTimeout: String, checkTimeout: String)

object GridConfig:
  def read(env: String => Option[String]): GridConfig =
    val repoDir = CronEnv.pathVar(env, "REPO_DIR", "/var/lib/hermes/workspace/room-src")
    val nixDevelop = s"nix develop --extra-experimental-features 'nix-command flakes' \"path:$repoDir\" --command"
    GridConfig(
      repoDir = repoDir,
      repo = env("REPO").getOrElse("piabrota/room"),
      tokenFile = CronEnv.pathVar(env, "TOKEN_FILE", GitHub.DefaultTokenFile),
      gridCmd = env("GRID_CMD").getOrElse(s"$nixDevelop just grid"),
      checkCmd = env("CHECK_CMD").getOrElse(s"$nixDevelop node scripts/check.mjs"),
      gridTimeout = env("GRID_TIMEOUT").getOrElse("2400"),
      checkTimeout = env("CHECK_TIMEOUT").getOrElse("600"),
    )

/** The files of public/grid that the job reads or names. */
object GridFiles:
  val Dir = "public/grid"
  val RunJson = "run.json"
  val Mesh = "mesh.bin"
  val Land = "land.json"
  /** Same nodes and same hours: these keep their sizes. */
  val Sized = List("frames.bin", "sst.bin")
  /** A change to one of these comes from the Natural Earth source. */
  val NaturalEarth = Set(Mesh, Land)
  val branches = Branches("hermes/grid-refresh")

  /** The file of a `git status --porcelain` line, relative to public/grid. */
  def changed(porcelain: String): String = porcelain.drop(3).stripPrefix(s"$Dir/")

/** The numbers of run.json that the checks and the PR body need, as jq -r prints them. */
final case class RunJson(hours: Int, first: String, last: String, fetched: String, sstDate: String,
    nodes: String, triangles: String, hasSst: Boolean):
  def sameMesh(other: RunJson): Boolean = nodes == other.nodes && triangles == other.triangles

object RunJson:
  /** run.json, when it is a JSON object. */
  def parse(text: String): Option[RunJson] =
    scala.util.Try(ujson.read(text)).toOption.filter(_.objOpt.isDefined).map(v => RunJson(v))

  def apply(v: ujson.Value): RunJson =
    val hours = v.obj.get("hours").map(lengthOf).getOrElse(0)
    val hourList = v.obj.get("hours").flatMap(_.arrOpt).map(_.toList).getOrElse(Nil)
    RunJson(
      hours = hours,
      first = hourList.headOption.map(raw).getOrElse("null"),
      last = hourList.lastOption.map(raw).getOrElse("null"),
      fetched = v.obj.get("fetched").filter(truthy).map(raw).getOrElse("not stated"),
      sstDate = v.obj.get("sst").flatMap(_.objOpt).flatMap(_.get("date")).filter(truthy).map(raw).getOrElse("none"),
      nodes = v.obj.get("nodes").map(raw).getOrElse("null"),
      triangles = v.obj.get("triangles").map(raw).getOrElse("null"),
      hasSst = v.obj.get("sst").exists(_ != ujson.Null),
    )

  private def truthy(v: ujson.Value) = v != ujson.Null && v != ujson.False

  /** jq's `length`. */
  private def lengthOf(v: ujson.Value): Int = v match
    case a: ujson.Arr => a.value.length
    case o: ujson.Obj => o.value.size
    case ujson.Str(s) => s.codePointCount(0, s.length)
    case _            => 0

  /** A value as `jq -r` prints it. */
  def raw(v: ujson.Value): String = v match
    case ujson.Str(s)                                          => s
    case ujson.Num(n) if n == n.floor && math.abs(n) < 1e17   => n.toLong.toString
    case other                                                 => ujson.write(other, indent = 2)

  /** Why the new run.json must not replace the committed one, if it must not. */
  def refuse(fresh: RunJson, old: RunJson, meshChanged: Boolean): Option[String] =
    // The sea temperature: a missing OSTIA day must not replace a good one.
    if old.hasSst && !fresh.hasSst then Some("the sea temperature is missing (Copernicus Marine)")
    else if fresh.hours != old.hours then Some(s"run.json has ${fresh.hours} hours, the committed one has ${old.hours}")
    else if !meshChanged && !fresh.sameMesh(old) then Some("run.json has other nodes or triangles, but mesh.bin did not change")
    else None

/** The size of one file of public/grid in the committed tree and in the new one. */
final case class Sizes(file: String, before: Option[Long], after: Option[Long]):
  /** A file that the commit has must keep its size. */
  def refuse: Option[String] = before.flatMap { b =>
    after match
      case None                => Some(s"$file is missing")
      case Some(a) if a != b   => Some(s"$file has $a bytes, the committed one has $b")
      case _                   => None
  }

  /** The line of the PR body for this file. */
  def describe: String =
    def bytes(n: Option[Long]) = n.fold("no file")(n => s"$n bytes")
    val note = if GridFiles.NaturalEarth(file) then " **changed: check the Natural Earth source**" else ""
    s"- `$file`: ${bytes(before)} before, ${bytes(after)} after.$note\n"
