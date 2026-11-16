package piabrota.design

import piabrota.lib.die

/** `proof-loc`, a build step of proof-site/default.nix: the lines of code of the proofs of
  * h0ffmann/proof, as JSON, for the hero of `proof-index`. The build runs it on the pinned source,
  * so the numbers are those of the commit the pages come from.
  *
  * A line of code is a line that is not blank and not only a comment, the rule of the repository's
  * own badge (its scripts/loc.py), with its scan: a comment after code on a line is not read, so a
  * block comment that opens there is not seen. vendor/ is other people's code and is left out. The
  * languages are `Language`.
  *
  *   proof-loc <source> > loc.json
  */
object Loc:
  // Python's str.splitlines, so the counts are the badge's to the line.
  private val lineEnd = "\r\n|[\n\r\u000B\f\u001C\u001D\u001E\u0085  ]".r

  /** Lines that are not blank and not only a comment. */
  def countCode(text: String, lang: Language): Int =
    lineEnd.split(text).foldLeft((0, false)) { case ((n, inBlock), raw) =>
      val (code, open) = scan(Js.trim(raw), inBlock, lang)
      (if code then n + 1 else n, open)
    }._1

  /** Whether a line holds code, and whether a block comment is open at its end. Code comes first:
    * what follows it on the line is not read.
    */
  @scala.annotation.tailrec
  private def scan(s: String, inBlock: Boolean, lang: Language): (Boolean, Boolean) =
    if s.isEmpty then (false, inBlock)
    else if inBlock then
      val i = s.indexOf(lang.close)
      if i < 0 then (false, true) else scan(Js.trim(s.substring(i + lang.close.length)), false, lang)
    else if s.startsWith(lang.open) then scan(s.substring(lang.open.length), true, lang)
    else if s.startsWith(lang.line) then (false, false)
    else (true, false)

  /** Every file under `root`, as a path relative to it; vendor/ at the top and .git are left out. */
  private def files(root: os.Path): Seq[String] =
    def skip(p: os.Path) = os.isDir(p, followLinks = false) && (p.relativeTo(root).toString == "vendor" || p.last == ".git")
    os.walk(root, skip = skip).filter(os.isFile(_, followLinks = false)).map(_.relativeTo(root).segments.mkString("/"))

  /** The count of each language, in the order of `Language`, for the source tree at `root`. */
  def count(root: os.Path): List[LocCount] =
    val all = files(root)
    Language.values.toList.map { l =>
      val mine = all.filter(l.matches)
      LocCount(l, mine.size, mine.map(rel => countCode(os.read(root / os.RelPath(rel)), l)).sum)
    }

  def run(args: List[String]): Int = args match
    case List(root) =>
      // A language with no file is left out, so the hero does not show it: h0ffmann/proof removed
      // z3-scala/ in its #60. No file of any language means a wrong root.
      val counted = count(os.Path(root, os.pwd)).filter(_.files > 0)
      if counted.isEmpty then die(s"proof-loc: no Lean 4, Agda or Z3 file under $root")
      print(ujson.write(LocCount.render(counted)))
      0
    case _ => die("usage: proof-loc <source> > loc.json", 2)
