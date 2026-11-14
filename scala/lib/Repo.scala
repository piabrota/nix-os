package piabrota.lib

object Repo:
  /** The top of the git work tree around the current directory, else the current directory: the
    * checkout a command works on, as the Python scripts found it from their own path.
    */
  def root(): os.Path =
    Sh.outOpt("git", "rev-parse", "--show-toplevel").filter(_.nonEmpty).map(os.Path(_)).getOrElse(os.pwd)
