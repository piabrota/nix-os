package piabrota.hermes

/** A program that a cron job runs, by its name on the PATH. */
enum Tool(val cmd: String):
  case Git extends Tool("git")
  case Gh extends Tool("gh")
  case Timeout extends Tool("timeout")
  case Env extends Tool("env")
  case Bash extends Tool("bash")
  case Date extends Tool("date")

/** What both pull-request cron jobs read from the environment, once, at their start. */
final case class CronEnv(path: String, dryRun: Boolean, outPatch: Option[String], tmpDir: String)

object CronEnv:
  // Cron runs the jobs with the PATH of the hermes-agent unit. The system profile has nix and the
  // hermes CLI, so it goes at the end: the unit's own tools keep their order.
  val SystemProfile = "/run/current-system/sw/bin"

  /** `rawPath` is $PATH as it is, empty or not; `env` reads a variable that is set and not empty. */
  def read(rawPath: String, env: String => Option[String]): CronEnv =
    CronEnv(
      path = s"$rawPath:$SystemProfile",
      dryRun = env("DRY_RUN").contains("1"),
      outPatch = env("OUT_PATCH"),
      tmpDir = env("TMPDIR").getOrElse("/tmp"),
    )

  /** A variable as a path, with its default. */
  def pathVar(env: String => Option[String], name: String, default: String): os.Path =
    os.Path(env(name).getOrElse(default), os.pwd)

/** The GitHub side of the cron jobs: the token of the piabrota-hermes App and its bot identity. */
object GitHub:
  val DefaultTokenFile = "/run/hermes-github/piabrota"
  val TokenVar = "GH_TOKEN"
  val Identity: Seq[String] =
    Seq("-c", "user.name=piabrota-hermes", "-c", "user.email=piabrota-hermes@users.noreply.github.com")

/** One open pull request, as `gh pr list --json headRefName,url` gives it. */
final case class OpenPr(branch: String, url: String)

object OpenPr:
  /** The pull requests of `gh pr list --json`; a field it was not asked for is empty. */
  def parseList(json: String): List[OpenPr] =
    ujson.read(json).arr.toList.map { pr =>
      def str(key: String) = pr.obj.get(key).flatMap(_.strOpt).getOrElse("")
      OpenPr(str("headRefName"), str("url"))
    }

/** The branches of one job: `<prefix>-<date>` (then `-2`, `-3`, ...), or `<prefix>-dry`. */
final case class Branches(prefix: String):
  def dated(day: String): String = s"$prefix-$day"
  def dry: String = s"$prefix-dry"
  def owns(branch: String): Boolean = branch.startsWith(prefix)
  def ownsAny(prs: List[OpenPr]): Option[OpenPr] = prs.find(pr => owns(pr.branch))
