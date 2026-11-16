package piabrota.scripts

import piabrota.lib.{Sh, env}

/** `piabrota marola-boards-check [base]`: each area's latest.json on a marola site, from outside
  * (marola-boards.yml, on a GitHub runner). One Markdown table row per area; fails when a board is
  * older than MAX_AGE_HOURS (default 12; the box builds every 6 hours) or does not answer.
  */
object MarolaBoardsCheck:
  def run(args: List[String]): Int =
    val config = BoardsCheckConfig(
      base = args.headOption.getOrElse(BoardsCheckConfig.defaultBase),
      maxAge = env("MAX_AGE_HOURS").flatMap(_.toLongOption).getOrElse(BoardsCheckConfig.defaultMaxHours) * 3600,
      now = java.time.Instant.now().getEpochSecond)
    val areas = Boards.areas(Sh.out("curl", "-fsS", s"${config.base}/data/${Boards.areasFile}"))
    val rows = areas.map { area =>
      val row = generatedAt(s"${config.base}/data/$area/${Boards.latestFile}") match
        case None      => BoardRow.Missing(area)
        case Some(gen) => BoardRow.Dated(area, gen, config.now - Sh.out("date", "-u", "-d", gen, "+%s").toLong, config.maxAge)
      println(row.render)
      row
    }
    if rows.exists(!_.fresh) then
      System.err.println(s"marola boards are stale on ${config.base}: journalctl -u marola-boards-build on the box (docs/MAROLA-SITE.md)")
      1
    else 0

  /** `.generated_at` of the JSON at `url`, as `curl -fsS | jq -er` gives it; None if either fails. */
  private def generatedAt(url: String): Option[String] =
    val r = Sh.call("curl", "-fsS", url)
    System.err.print(r.err.text())
    if r.exitCode != 0 then None else Boards.generatedAt(r.out.text())
