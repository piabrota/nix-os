package piabrota.metrics

import piabrota.lib.{die, env}

/** What the commands read from the environment, read once at each command's entry (metrics.nix
  * sets it on the boxes; the tests point the sources at fixtures).
  */
object Defaults:
  val OutDir = "/run/metrics-web"
  val StateDir = "/run/metrics-state"
  val NameVariable = "METRICS_NAME"

  /** A host name from `variable`: required, and a valid file name. `prog` starts the message, as
    * the scripts did.
    */
  def hostName(prog: String, variable: String = NameVariable): String =
    val name = env(variable).getOrElse(die(s"$prog: $variable is not set"))
    if !HostName.valid(name) then die(s"$prog: bad $variable", 2)
    name

/** metrics-collect's environment (Collect's doc comment has each variable). */
final case class CollectConfig(name: String, label: String, interval: Double, outDir: String, stateDir: String,
    inventory: Option[String], probe: Option[String], repo: Option[String], systemProfile: String,
    nixosVersionFile: String, procRoot: String, cgroupRoot: String, passwdFile: String, dfPath: String):
  def outFile: String = s"$outDir/${OutFile.host(name)}"
  def stateFile: String = s"$stateDir/$name.state"

object CollectConfig:
  def fromEnv(): CollectConfig =
    val name = Defaults.hostName("collect")
    CollectConfig(
      name = name,
      // awk got the label as bytes: one char for each byte of its UTF-8.
      label = Awk.bytewise(env("METRICS_LABEL").getOrElse(name)),
      interval = Awk.num(env("METRICS_INTERVAL").getOrElse("10")),
      outDir = env("OUT_DIR").getOrElse(Defaults.OutDir),
      stateDir = env("STATE_DIR").getOrElse(Defaults.StateDir),
      inventory = env("METRICS_INVENTORY"),
      probe = env("METRICS_PROBE"),
      repo = env("METRICS_REPO").filter(RepoName.valid),
      systemProfile = env("SYSTEM_PROFILE").getOrElse("/nix/var/nix/profiles/system"),
      nixosVersionFile = env("NIXOS_VERSION_FILE").getOrElse("/run/current-system/nixos-version"),
      procRoot = env("PROC_ROOT").getOrElse("/proc"),
      cgroupRoot = env("CGROUP_ROOT").getOrElse("/sys/fs/cgroup"),
      passwdFile = env("PASSWD_FILE").getOrElse("/etc/passwd"),
      dfPath = env("DF_PATH").getOrElse("/"),
    )

/** metrics-probe's environment (Probe's doc comment has each variable). `now` is PROBE_NOW or the
  * clock, read here once.
  */
final case class ProbeConfig(name: String, sitesFile: String, repo: Option[String], branch: String,
    stateDir: String, repoEvery: String, visitsLog: Option[String], now: Long, githubApi: String):
  def outFile: String = s"$stateDir/$name.probe"
  def visitsFile: String = s"$stateDir/$name.visits"

object ProbeConfig:
  def fromEnv(): ProbeConfig = ProbeConfig(
    name = Defaults.hostName("probe"),
    sitesFile = env("PROBE_SITES").getOrElse("/dev/null"),
    repo = env("PROBE_REPO").filter(RepoName.valid),
    branch = env("PROBE_BRANCH").filter(RepoName.valid).getOrElse("main"),
    stateDir = env("STATE_DIR").getOrElse(Defaults.StateDir),
    repoEvery = env("PROBE_REPO_EVERY").getOrElse("600"),
    visitsLog = env("PROBE_VISITS_LOG"),
    now = env("PROBE_NOW").filter(Awk.isDigits).map(_.toLong).getOrElse(Host.now()),
    githubApi = env("GITHUB_API").getOrElse("https://api.github.com"),
  )

/** metrics-export's environment: `stale` and `now` are whole numbers of seconds. */
final case class ExportConfig(outDir: String, stale: String, now: String):
  /** What is wrong with it, as the message says it. */
  def problem: Option[String] =
    if !Awk.isDigits(stale) then Some("bad METRICS_STALE")
    else Option.when(!Awk.isDigits(now))("bad METRICS_NOW")

object ExportConfig:
  def fromEnv(): ExportConfig =
    val config = ExportConfig(env("OUT_DIR").getOrElse(Defaults.OutDir), env("METRICS_STALE").getOrElse("30"),
      env("METRICS_NOW").getOrElse(Host.now().toString))
    config.problem.foreach(p => die(s"export: $p", 2))
    config

/** metrics-pull's environment. */
final case class PullConfig(url: String, name: String, outDir: String):
  def outFile: String = s"$outDir/${OutFile.host(name)}"

object PullConfig:
  def fromEnv(): PullConfig =
    val url = env("METRICS_PULL_URL").getOrElse(die("pull: METRICS_PULL_URL is not set"))
    PullConfig(url, Defaults.hostName("pull", "METRICS_PULL_NAME"), env("OUT_DIR").getOrElse(Defaults.OutDir))
