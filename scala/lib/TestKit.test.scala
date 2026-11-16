package piabrota.lib

/** For tests that run the built binary as a box would: `PIABROTA` is its path (`just scala-test`
  * and scala/default.nix set it).
  */
object TestKit:
  lazy val bin: os.Path = os.Path(sys.env.getOrElse("PIABROTA", sys.error("PIABROTA is not set")), os.pwd)

  /** `piabrota <args>` with `env` added and `fakes` first on the PATH. */
  def piabrota(args: Seq[String], env: Map[String, String] = Map.empty, cwd: os.Path = os.pwd,
      stdin: String = "", fakes: Option[os.Path] = None): os.CommandResult =
    val path = (fakes.map(_.toString).toList :+ sys.env.getOrElse("PATH", "")).mkString(":")
    os.proc(bin, args).call(cwd = cwd, env = env + ("PATH" -> path), stdin = stdin,
      stdout = os.Pipe, stderr = os.Pipe, check = false)

  /** A directory of stand-in programs: each value is the program's text, a `#!/bin/sh` stub that
    * records its arguments or prints a fixture. The test's only shell, and it never leaves the test.
    */
  def fakes(programs: (String, String)*): os.Path =
    val dir = os.temp.dir(prefix = "fakes")
    programs.foreach((name, text) => os.write(dir / name, text, perms = "rwxr-xr-x"))
    dir
