package piabrota.scripts

import piabrota.lib.Sh
import HermesLive.{bin, home}
import CheckLine.{Fail, Info, Section}

/** `piabrota hermes-check`: checks on the box that the Hermes add-ons of the last deploy are live:
  * the unit restarted after the deploy, the plugins of hermes.nix are linked and loaded, the
  * hermes-omp, kvm4-health and hermes-manim skills are found, and omp, yt-dlp, manim and
  * kvm4-health answer. Read-only. Run it as h0ffmann (passwordless sudo), not root: it reads the
  * Hermes home and calls hermes through `sudo -n -u hermes`, as h0ffmann is not in the hermes group
  * (`just remote-hermes-check`). It never reads /var/lib/hermes-secrets or the .env, and prints no
  * environment. `HermesLive` lists what it expects.
  */
object HermesCheck:
  private val unit = Units.hermesAgent
  private val plugins = HermesLive.community

  private def asHermes(cmd: String*): Boolean = Sh.run(Seq("sudo", "-n", "-u", HermesLive.user) ++ cmd) == 0
  private def asHermesOut(cmd: String*): String = Util.merged((Seq("sudo", "-n", "-u", HermesLive.user) ++ cmd)*)._2
  private def show(prop: String) = Sh.call("systemctl", "show", unit, "-p", prop, "--value").out.text().stripTrailing()

  /** Prints the lines; returns how many failed. */
  private def emit(lines: List[CheckLine]): Int =
    lines.foreach(l => println(l.render))
    lines.count(_.isInstanceOf[Fail])

  def run(@annotation.unused args: List[String]): Int =
    val hasHermes = Sh.which("hermes").isDefined
    val (unitLines, started) = unitSection()
    // Each section prints before the next one runs its commands.
    val fails = emit(unitLines) + emit(linked()) + emit(enabled(hasHermes)) + emit(skills(hasHermes)) +
      emit(tools()) + emit(journal(started))
    if fails == 0 then { println("\nhermes-check: all live"); 0 }
    else { println(s"\nhermes-check: $fails failed"); 1 }

  /** Every section prints its header first, so that it comes before its commands' own output. The
    * unit section also gives the unit's start, from which the journal is read.
    */
  private def unitSection(): (List[CheckLine], String) =
    println(Section("unit").render)
    val state = Sh.call("systemctl", "is-active", unit).out.text().stripTrailing()
    val started = show("ActiveEnterTimestamp")
    List(
      CheckLine.of(state == UnitState.active, "hermes-agent is active", s"hermes-agent is $state"),
      Info(s"      unit started  $started"),
      Info(s"      last switch   ${Sh.outOpt("stat", "-c", "%y", BoxPaths.systemProfile).getOrElse("")}"),
      Info(s"      system        ${Sh.outOpt("readlink", BoxPaths.currentSystem).getOrElse("")}"),
      Info(s"      memory peak   ${show("MemoryPeak")}")) -> started

  private def linked(): List[CheckLine] =
    println(Section(s"plugins linked by activation ($home/plugins)").render)
    plugins.map(p => CheckLine.of(asHermes("test", "-f", s"$home/plugins/nix-managed-$p/plugin.yaml"), p,
      s"$p: no nix-managed-$p"))

  private def enabled(hasHermes: Boolean): List[CheckLine] =
    println(Section("plugins enabled (hermes plugins list --enabled)").render)
    if hasHermes then
      val list = asHermesOut("hermes", "plugins", "list", "--enabled", "--plain")
      plugins.map(p => CheckLine.of(hasWord(list, p), p, s"$p: not in the enabled list"))
    else List(Fail("no hermes CLI on PATH"))

  private def skills(hasHermes: Boolean): List[CheckLine] =
    println(Section("skills").render)
    val found = if hasHermes then
      val list = asHermesOut("hermes", "skills", "list")
      HermesLive.skills.map(s => CheckLine.of(hasWord(list, s), s, s"$s: not in hermes skills list"))
    else Nil
    found ++ List(
      CheckLine.of(asHermes("test", "-f", s"$home/scripts/kvm4-health-alert.sh"), s"kvm4-health-alert.sh in $home/scripts",
        s"no $home/scripts/kvm4-health-alert.sh"),
      CheckLine.of(asHermes("test", "-d", "/var/lib/hermes/workspace/omp-tasks"), "omp-tasks directory",
        "no /var/lib/hermes/workspace/omp-tasks"))

  private def tools(): List[CheckLine] =
    println(Section(s"tools on Hermes's PATH ($bin)").render)
    def first(cmd: String*) = Util.firstLine(Util.merged(cmd*)._2)
    def orNone(v: String) = if v.isEmpty then "no output" else v
    val omp = first(s"$bin/omp", "--version")
    val ytdlp = first(s"$bin/yt-dlp", "--version")
    val manim = first(s"$bin/manim", "--version")
    // kvm4-health exits 1 on a finding; that is the report, not a failure of this check.
    val health = Util.merged(s"$bin/kvm4-health")._2.linesIterator.toList.lastOption.getOrElse("")
    List(
      CheckLine.of(omp.contains(HermesLive.ompVersion), s"omp: $omp", s"omp: ${orNone(omp)}"),
      CheckLine.of(ytdlp.nonEmpty, s"yt-dlp: $ytdlp", "yt-dlp: no output"),
      CheckLine.of(manim.startsWith("Manim Community"), s"manim: $manim", s"manim: ${orNone(manim)}"),
      CheckLine.of(health.startsWith("kvm4-health:"), health, s"kvm4-health: ${orNone(health)}"))

  private def journal(started: String): List[CheckLine] =
    println(Section("plugin warnings and errors since the unit started").render)
    val log = Sh.call("journalctl", "-u", unit, "--since", started, "--no-pager", "-o", "cat")
    log.out.text().linesIterator.filter(problem).toList.takeRight(20).map(Info(_))

  private val problemWords = "(?i).*(error|fail|warn|traceback|cannot|skipp).*".r

  /** A journal line about a plugin that warns or fails; the integrity hash notice is not one. */
  def problem(line: String): Boolean =
    line.toLowerCase.contains("plugin") && problemWords.matches(line) && !line.contains("integrity hash")

  /** `grep -qw -- word`: `word` with no letter, digit or underscore right before or after it. */
  def hasWord(text: String, word: String): Boolean =
    def isWordChar(c: Char) = c.isLetterOrDigit || c == '_'
    text.linesIterator.exists { line =>
      Iterator.iterate(line.indexOf(word))(i => line.indexOf(word, i + 1)).takeWhile(_ >= 0).exists { i =>
        val end = i + word.length
        (i == 0 || !isWordChar(line(i - 1))) && (end == line.length || !isWordChar(line(end)))
      }
    }
