package piabrota.lib

/** One subcommand of `piabrota`: `run` gets the arguments after the name and returns the exit code. */
final case class Command(name: String, summary: String, run: List[String] => Int)

/** An expected failure: `Main` prints `message` (if any) to stderr and exits with `code`.
  * Anything else that is thrown is a bug, and `Main` prints its stack trace.
  */
final case class Exit(code: Int, message: String = "") extends Exception(message, null, false, false)

/** Stops the command, as `echo "$message" >&2; exit $code` does in sh. */
def die(message: String, code: Int = 1): Nothing = throw Exit(code, message)

/** A line on stderr. */
def warn(message: String): Unit = System.err.println(message)

/** The value of an environment variable, if it is set and not empty (sh's `${NAME:-}`). */
def env(name: String): Option[String] = sys.env.get(name).filter(_.nonEmpty)
