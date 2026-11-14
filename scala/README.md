# scala/

Every script of this repository, in Scala 3, built into one Scala Native binary: `piabrota`.
`piabrota <command> [args...]` runs one script; `piabrota --help` lists them. The binary needs only
glibc, so no JVM reaches a box (AGENTS.md, "Resource budget", rule 4).

The approach comes from [arturaz/nixos-conf-scala-scripts-comparison](https://github.com/arturaz/nixos-conf-scala-scripts-comparison):
scripts that do what CLI tools do (subprocesses, files, JSON, exit codes) in plain Scala 3 with
os-lib and upickle, one shared library, expected failures as values or exit codes, a thrown
exception only for a bug. Of its seven variants this follows the one with no effect runtime (Ox:
direct style, plain blocking code), without Ox itself, which needs a JVM. Scala Native gives a
small binary and a start in milliseconds instead of its jar plus AOT cache.

## Layout

| Path | Is |
|---|---|
| `project.scala` | The Scala and Scala Native versions, the compiler options and the libraries. |
| `Main.scala` | `piabrota <command>`: finds the command and turns an `Exit` into an exit code. |
| `lib/` | What every script shares: `Command`, `Exit`, `die`, `warn`, `env` (`Script.scala`), other programs (`Sh.scala`), and the test kit (`TestKit.test.scala`). |
| `<area>/package.scala` | The commands of one area of the repository (`scripts`, `metrics`, `hermes`, `feeds`, `thesis`, `reels`, `design`, `pirsig`, `repo`). |
| `<area>/<Name>.scala` | One script. `<Name>.test.scala` holds its tests. |
| `default.nix` | The Nix build: offline, from `deps.lock.json`, tests in `checkPhase`. `passthru.command` makes one command a program of its own. |
| `deps.lock.json`, `lock/Lock.scala` | Every jar and pom the build reads, by path and hash. `just scala-lock` writes it. |

## Commands

```console
just scala-test     # compile and run the tests in the dev shell (network on); fast while you edit
just scala-build    # the Nix build, offline, tests included: what CI and the boxes get
just scala-lock     # after a version changes in project.scala
nix run .#piabrota -- <command> [args...]
```

## Adding a script

1. Write `scala/<area>/<Name>.scala` with an `object <Name>` and `def run(args: List[String]): Int`.
2. Add `Command("<name>", "<one line>", <Name>.run)` to `<area>/package.scala`.
3. Write `<Name>.test.scala`.
4. Where Nix runs it, take the command with its own PATH:

   ```nix
   let scripts = pkgs.callPackage ./scala { }; in
   scripts.command { name = "freeze"; runtimeInputs = [ pkgs.coreutils ]; }
   ```

   `bin/freeze` then runs `piabrota freeze "$@"`. `exclusivePath = true` sets the PATH to the
   inputs only, as the rig toolkits want.

## Style

The goal is code that reads like the script it replaced and that the next agent changes without
surprise. Simplicity, composition and functional programming come first (the owner, 2026-11-14).

- **A domain model per area.** `scala/<area>/model.scala` holds the area's case classes and enums:
  what its commands read, decide and write. Commands work on these types, never on raw strings,
  maps or JSON past the edge where they are parsed. Parse at the edge (`Foo.parse(text):
  Either[String, Foo]`), render at the edge (`foo.render`).
- **No magic strings.** A status, a kind, a unit name, a file name or a JSON key that the code
  compares or builds is an enum case or a named value in the model, written once.
- **No implicit configuration.** Environment variables, profile files and defaults are read once,
  in the command's entry point, into a `Config` case class that is passed as an argument. No
  `using` for configuration, no global `val` that reads the environment.
- **Pure core, effects at the edge.** Decisions are plain functions from values to values; files,
  processes, clocks and the network are touched only by the command's top level and small
  adapters. Small functions composed, `map`/`flatMap`/`fold` over loops; a `var` only in a tiny
  local loop.
- No private constructors, no smart-constructor ceremony: a case class is its data.

- **Arguments by pattern match**, the way a script reads `case "$1" in`:

  ```scala
  def run(args: List[String]): Int = args match
    case List("one", site)        => one(site, rev = None)
    case List("one", site, rev)   => one(site, Some(rev))
    case "--list" :: Nil          => list()
    case _                        => die("usage: piabrota pins one <site> [rev] | all", 2)
  ```

  No CLI library: the usage line is written where the cases are.
- **Expected failures** end the command with `die(message, code)`, which `Main` prints to stderr.
  A function that can fail in an expected way and whose caller goes on returns `Either` or
  `Option`. Never catch `Throwable` or `Exception` around a whole body: a bug must show its stack.
- **Other programs** through `Sh` (`Sh.run`, `Sh.ok`, `Sh.out`, `Sh.outOpt`, `Sh.call`,
  `Sh.which`), always with the arguments as separate values. `Sh.out` dies when the program fails,
  with its stderr. Options per call: `Sh.out("git", "log")(using Sh.Opts(cwd = repo))`.
- **Files** with os-lib (`os.read`, `os.write.over`, `os.list`, `os.walk`); JSON with ujson
  (`ujson.read`, `ujson.Obj`); XML with scala-xml; times with java.time (scala-java-time).
- No `null`.
- Comments say why, not what (AGENTS.md of the repository). A command's doc comment says what it
  does, who runs it and where.
- The same messages, exit codes, output format and files as the script it replaced, unless the
  pull request says otherwise. Tests check them.

## Scala Native: what is not there

- No `java.net.http`, no `javax.net.ssl`, no `javax.xml`: HTTP and TLS go through `curl` or
  `openssl` with `Sh`; XML through scala-xml.
- `java.util.regex` is RE2: no look-ahead, no look-behind, no back-references.
- No `sun.misc.Signal`: signals through `scala.scalanative.posix.signal`.
- `java.time` comes from scala-java-time; the time zone database is not linked, so use offsets
  (`ZoneOffset`), not zone names.
- Threads work (`multithreading` is on); `scala.concurrent.Future` too.

## Tests

munit. A unit test calls a function. A test of a whole command runs the built binary with
`TestKit.piabrota(args, env, cwd, stdin, fakes)`: `TestKit.fakes("systemctl" -> "...")` puts
stand-in programs first on the PATH, as the shell tests used to. Tests run offline, in the Nix
sandbox: no network, no `/run`, no systemd.
