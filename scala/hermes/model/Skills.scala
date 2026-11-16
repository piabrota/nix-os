package piabrota.hermes

/** What export-skills reads from the environment, once, at its start. */
final case class SkillsConfig(skillsDir: os.Path, hermesHome: os.Path, repoDir: os.Path, repo: String,
    tokenFile: os.Path)

object SkillsConfig:
  def read(env: String => Option[String]): SkillsConfig =
    val home = env("HOME").getOrElse("")
    SkillsConfig(
      skillsDir = CronEnv.pathVar(env, "SKILLS_DIR", s"$home/.hermes/skills"),
      hermesHome = CronEnv.pathVar(env, "HERMES_HOME", s"$home/.hermes"),
      repoDir = CronEnv.pathVar(env, "REPO_DIR", "/var/lib/hermes/workspace/skills-src"),
      repo = env("REPO").getOrElse("piabrota/skills"),
      tokenFile = CronEnv.pathVar(env, "TOKEN_FILE", GitHub.DefaultTokenFile),
    )

/** Where a skill that Hermes loads comes from, as the README of skills/hermes names it. */
enum Origin:
  case Bundled
  case Hub
  case MadeHere
  case Plugin(name: String)
  case NixOs(dir: String)

  def render: String = this match
    case Bundled      => "Bundled with Hermes Agent"
    case Hub          => "Installed from a skills hub"
    case MadeHere     => "Made by Hermes on this box"
    case Plugin(name) => s"Plugin $name"
    case NixOs(dir)   => s"Added by nix-os ($dir)"

  /** The owner wrote or changed it for Hermes: made on this box, a pirsig plugin's, or one of
    * nix-os's own skills directory. Bundled, hub, catalog and other plugin skills are others'.
    */
  def isOwn: Boolean = this match
    case MadeHere     => true
    case Plugin(name) => name.startsWith("pirsig-")
    case NixOs(dir)   => dir == "skills"
    case _            => false

/** One skill to export: its name, its directory and where it comes from. */
final case class Skill(name: String, dir: os.Path, origin: Origin)

/** The skills to export, and the names left out because another skill had them first. */
final case class Found(skills: List[Skill], dups: List[String])

object Found:
  /** The first skill of each name is kept; a later one with the same name is a duplicate. */
  def of(skills: List[Skill]): Found =
    val (kept, dups) = skills.foldLeft((Vector.empty[Skill], Vector.empty[String])) { case ((kept, dups), s) =>
      if kept.exists(_.name == s.name) then (kept, dups :+ s.name) else (kept :+ s, dups)
    }
    Found(kept.toList, dups.toList)

/** The front matter of a SKILL.md: the lines between the first "---" and the next, the closing
  * line, and the rest of the file.
  */
final case class FrontMatter(head: String, close: String, rest: String)

/** The names and files of piabrota/skills that the export reads or writes. */
object SkillsRepo:
  val Tag = "hermes-skill"
  val Category = "hermes"
  val Target = os.SubPath("skills/hermes")
  val Tags = os.SubPath("www/tags.txt")
  val Check = os.SubPath("scripts/check.py")
  val SkillFile = "SKILL.md"
  val Title = "feat(skills): export the skills of Hermes"
  val branches = Branches("hermes/skills-export")
  /** The front-matter keys of the Agent Skills format. */
  val AgentSkillsKeys = Set("name", "description", "license", "compatibility", "allowed-tools")
