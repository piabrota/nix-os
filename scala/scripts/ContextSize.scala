package piabrota.scripts

import scala.annotation.unused
import piabrota.lib.env
import ContextConfig.{limit, warnFrom}

/** `piabrota context-size`: the size of the files Hermes loads into its context (AGENTS.md,
  * hermes/AGENTS.md, hermes/SOUL.md), read-only. Hermes cuts a file that is too long and keeps only
  * its head and tail, so the middle, here the safety rules, never reaches the model. Run by
  * `just context-size`. Exit 0 when every file is ok or WARN, 1 when one is over the limit.
  */
object ContextSize:
  def run(@unused args: List[String]): Int =
    check(ContextConfig(piabrota.lib.Repo.root(), annotate = env("GITHUB_ACTIONS").isDefined))

  /** The level and its text for a file of `n` characters. */
  def level(n: Int): (ContextLevel, String) =
    if n > limit then (ContextLevel.Fail, s"$n / $limit: Hermes drops the middle")
    else if n > warnFrom then (ContextLevel.Warn, s"$n / $limit (margin ${limit - warnFrom})")
    else (ContextLevel.Ok, s"$n / $limit")

  def check(config: ContextConfig): Int =
    val levels = ContextConfig.files.filter(f => os.isFile(config.root / os.RelPath(f))).map { f =>
      val text = os.read(config.root / os.RelPath(f))
      // Characters as Hermes counts them (Python's len), not UTF-16 units.
      val (lvl, msg) = level(text.codePointCount(0, text.length))
      println(f"${lvl.label}%-5s $f  $msg")
      if config.annotate then lvl.annotation.foreach(kind => println(s"::$kind file=$f::$f $msg"))
      lvl
    }
    if levels.contains(ContextLevel.Fail) then 1 else 0
