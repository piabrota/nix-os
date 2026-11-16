package piabrota.scripts

/** What a pinned file holds besides rev and the source hash. */
enum PinExtra:
  case Nothing, Commits, Npm

/** One website pin: the site, its source repository, the Nix file that pins it, the name of its
  * rev attribute, its extra values, and a file its build must hold.
  */
final case class PinSite(name: String, repo: RepoSlug, file: String, revname: String = "rev",
    extra: PinExtra = PinExtra.Nothing, must: String = "index.html"):
  def link: String = s"result-$name"

object PinSite:
  val all: List[PinSite] = List(
    PinSite("ww3", RepoSlug("h0ffmann", "ww3-gpu"), "ww3-site/default.nix", extra = PinExtra.Commits),
    PinSite("closed", RepoSlug("h0ffmann", "closed-source"), "closed-site/default.nix", extra = PinExtra.Commits),
    PinSite("hffmnn", RepoSlug("h0ffmann", "h0ffmann"), "hffmnn-site/default.nix"),
    PinSite("marola-site", RepoSlug("marola-dev", "marola-site"), "marola-site/default.nix", must = "bin/marola-server"),
    PinSite("skills", RepoSlug("piabrota", "skills"), "skills-site/default.nix"),
    PinSite("proof", RepoSlug("h0ffmann", "proof"), "proof-site/default.nix", revname = "proofRev"),
    PinSite("pirsig", RepoSlug("piabrota", "pirsig"), "proof-site/pirsig.nix", revname = "pirsigRev"),
    PinSite("room", RepoSlug("piabrota", "room"), "room-site/default.nix", extra = PinExtra.Npm),
  )
  val byName: Map[String, PinSite] = all.map(s => s.name -> s).toMap

/** npmDepsHash and the version of a package-lock pin. */
final case class NpmPin(depsHash: String, version: String)

/** The new values of a pinned file besides rev. */
final case class PinValues(hash: String, commits: Option[Long] = None, npm: Option[NpmPin] = None)

/** What `nix flake prefetch --json` says of a source. */
final case class Prefetched(hash: String, storePath: Option[String], lastModified: Option[Long])

object Prefetched:
  val hashPrefix = "sha256-"

  /** None unless the text is JSON with a `sha256-` hash. lastModified is the top one, else
    * `locked`'s; 0 counts as missing.
    */
  def parse(text: String): Option[Prefetched] =
    def num(v: Option[ujson.Value]) = v.flatMap(_.numOpt).map(_.toLong).filter(_ != 0)
    for
      obj <- Jq.parse(text).flatMap(_.objOpt)
      hash <- obj.get("hash").flatMap(_.strOpt).filter(_.startsWith(hashPrefix))
    yield Prefetched(hash, obj.get("storePath").flatMap(_.strOpt),
      num(obj.get("lastModified")).orElse(num(obj.get("locked").flatMap(_.objOpt).flatMap(_.get("lastModified")))))

/** A step that failed, named for the output: `Left("build")`. */
type PinStep[A] = Either[String, A]

/** A whole commit id. */
object Sha:
  def isSha(s: String): Boolean = s.matches("[0-9a-f]{40}")

/** The line `pins all` prints for a site. */
enum PinLine:
  case Same(site: String, rev: String)
  case Behind(site: String, old: String, sha: String)
  case Moved(site: String, old: String, sha: String)
  case Failed(site: String, why: String)

  def render: String = this match
    case Same(site, rev)          => s"$site same $rev"
    case Behind(site, old, sha)   => s"$site behind $old $sha"
    case Moved(site, old, sha)    => s"$site moved $old $sha"
    case Failed(site, why)        => s"$site FAILED $why"

  def failed: Boolean = this match
    case _: Failed => true
    case _         => false

/** `pins`'s settings: the checkout it writes in, and whether it builds each site (PIN_BUILD). */
final case class PinsConfig(root: os.Path, build: Boolean)
