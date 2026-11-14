package piabrota.design

import piabrota.lib.die

/** `proof-dark-gate`, a build step of proof-site/common.nix. archify pages open dark, always:
  * proof.nix sends an archify page asked for without ?theme=dark to that address, and archify reads
  * the address before localStorage and the system setting. So each archify page must still read it,
  * and must sit where proof.nix's location looks. A pattern is a path as the shell's `case` reads
  * it: `*` is any text, `/` included, and `?` one character.
  *
  *   proof-dark-gate <dir> <pattern>...
  */
object DarkGate:

  /** The shell pattern as a regex. */
  def pattern(glob: String): scala.util.matching.Regex =
    glob.map {
      case '*' => ".*"
      case '?' => "."
      case c   => java.util.regex.Pattern.quote(c.toString)
    }.mkString.r

  /** The first archify page that breaks the rule; none when they all keep it. */
  def problem(dir: os.Path, shown: String, allowed: Seq[String]): Option[DarkBreach] =
    val patterns = allowed.map(pattern)
    Inject.htmlFiles(dir).iterator
      .map(p => (s"$shown/${p.relativeTo(dir)}", os.read(p)))
      .filter((_, html) => Archify.drew(html))
      .collectFirst {
        case (page, _) if !patterns.exists(_.matches(page))   => DarkBreach.Outside(page)
        case (page, html) if !html.contains(Archify.readsTheme) => DarkBreach.Blind(page)
      }

  def run(args: List[String]): Int = args match
    case dir :: allowed =>
      problem(os.Path(dir, os.pwd), dir, allowed).foreach(b => die(b.render))
      0
    case _ => die("usage: proof-dark-gate <dir> <pattern>...", 2)
