package piabrota

import piabrota.lib.{Command, Exit}

/** `piabrota <command> [args...]`. Each area of the repository lists its commands in its own
  * `commands` value; add a new area's list here.
  */
object Main:
  val commands: List[Command] =
    scripts.commands ++ metrics.commands ++ hermes.commands ++ feeds.commands ++
      thesis.commands ++ reels.commands ++ design.commands ++ pirsig.commands ++ repo.commands

  def main(args: Array[String]): Unit =
    val code = args.toList match
      case Nil | ("-h" | "--help" | "help") :: _ => usage(); 0
      case name :: rest =>
        commands.find(_.name == name) match
          case Some(c) => runCommand(c, rest)
          case None    => System.err.println(s"piabrota: no command '$name'"); usage(); 2
    System.out.flush()
    sys.exit(code)

  private def runCommand(c: Command, args: List[String]): Int =
    try c.run(args)
    catch
      case Exit(code, message) =>
        if message.nonEmpty then System.err.println(message)
        code

  private def usage(): Unit =
    val width = commands.map(_.name.length).maxOption.getOrElse(0)
    System.err.println("usage: piabrota <command> [args...]\n")
    commands.sortBy(_.name).foreach(c => System.err.println(s"  ${c.name.padTo(width, ' ')}  ${c.summary}"))
