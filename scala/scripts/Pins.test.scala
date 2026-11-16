package piabrota.scripts

import piabrota.lib.TestKit

/** The pinned files' shapes, copied from ww3-site/default.nix, proof-site/pirsig.nix and
  * room-site/default.nix: commits, a second source in the same file, and npmDepsHash with version.
  */
class PinsTest extends munit.FunSuite:
  val newRev = "0" * 40

  val ww3 = """  rev = "ff20ee9f82e9ee6c266cc429612e13b5ebccf4fb";
              |  # no .git, so piabrota pins one ww3 counts them and writes it here with rev.
              |  commits = 935;
              |  ww3gpu = fetchFromGitHub {
              |    owner = "h0ffmann";
              |    repo = "ww3-gpu";
              |    inherit rev;
              |    hash = "sha256-Cb+aS8Xk22RnvDK/OMNRoijEcs3oYGD8fVJSnpKpqNU=";
              |  };
              |  version = "0-unstable-${builtins.substring 0 7 rev}";
              |""".stripMargin

  val pirsig = """  pirsigRev = "caa7bc7722f875bf617f59d0eaa6fffe9f201c27";
                 |  pirsig = fetchFromGitHub {
                 |    owner = "piabrota";
                 |    repo = "pirsig";
                 |    rev = pirsigRev;
                 |    hash = "sha256-ig0hh2NwmA6gsLcTKwEU35b5IY31hYMDZ6chu7UBk8E=";
                 |  };
                 |  archify = fetchFromGitHub {
                 |    owner = "tt-a1i";
                 |    repo = "archify";
                 |    rev = "208acba8d412335185b2056fedf54b3405df43fb";
                 |    hash = "sha256-pejw78BgKDnttOAGcLvVtWa50azpCjTfESnmdYIjCoI=";
                 |  };
                 |""".stripMargin

  val room = """buildNpmPackage {
               |  pname = "piabrota-room";
               |  version = "0-unstable-2026-11-13";
               |  src = fetchFromGitHub {
               |    owner = "piabrota";
               |    repo = "room";
               |    rev = "d1cb9b7bab3ced3bee7f9f1150577545cfd7a7da";
               |    hash = "sha256-sXTIETQ8XIB+jbFZZZxB9+HG1RSSQu0tsQoFdPNWtFw=";
               |  };
               |  npmDepsHash = "sha256-/uqbxk0gN7bIosBtSKr8xF6XG4H3TaJf9LGADFd2muQ=";
               |""".stripMargin

  def rewrites(site: PinSite, text: String, values: PinValues, shown: List[String]): Unit =
    val old = Pins.revOf(text, site.revname).getOrElse(fail(s"no ${site.revname}"))
    val out = Pins.rewrite(text, site, old, newRev, values).fold(fail(_), identity)
    assertEquals(Pins.revOf(out, site.revname), Some(newRev))
    shown.foreach(v => assert(out.contains(v), out))
    // Only the pinned lines change; another source of the same file keeps its hash.
    val changed = text.linesIterator.zip(out.linesIterator).count(_ != _)
    assertEquals(changed, shown.length + 1)

  test("a file with commits rewrites"):
    rewrites(PinSite.byName("ww3"), ww3, PinValues("sha256-NEW=", commits = Some(4242)), List("\"sha256-NEW=\"", "4242"))

  test("a file with a second source changes only the pinned one"):
    rewrites(PinSite.byName("pirsig"), pirsig, PinValues("sha256-NEW="), List("\"sha256-NEW=\""))
    val out = Pins.rewrite(pirsig, PinSite.byName("pirsig"), "caa7bc7722f875bf617f59d0eaa6fffe9f201c27", newRev,
      PinValues("sha256-NEW=")).fold(fail(_), identity)
    assert(out.contains("sha256-pejw78BgKDnttOAGcLvVtWa50azpCjTfESnmdYIjCoI="))

  test("a file with npmDepsHash and version rewrites"):
    rewrites(PinSite.byName("room"), room,
      PinValues("sha256-NEW=", npm = Some(NpmPin("sha256-NPM=", "0-unstable-2001-02-03"))),
      List("\"sha256-NEW=\"", "sha256-NPM=", "0-unstable-2001-02-03"))

  test("a value the file lacks fails its rewrite"):
    val r = Pins.rewrite(pirsig, PinSite.byName("pirsig"), "caa7bc7722f875bf617f59d0eaa6fffe9f201c27", newRev,
      PinValues("sha256-NEW=", commits = Some(1)))
    assertEquals(r, Left("the rewrite of commits"))

  test("a failed step puts the file back"):
    val path = os.temp(room)
    val site = PinSite.byName("room")
    assertEquals(Pins.move(path, site, newRev, Left("prefetch"), Right(())), Left("prefetch"))
    assertEquals(os.read(path), room)
    val npm = PinValues("sha256-X=", npm = Some(NpmPin("sha256-N=", "0-unstable-2001-02-03")))
    assertEquals(Pins.move(path, site, newRev, Right(npm), Left("build")), Left("build"))
    assertEquals(os.read(path), room)
    assertEquals(Pins.move(path, site, newRev, Right(npm), Right(())), Right(()))
    assertEquals(Pins.revOf(os.read(path), "rev"), Some(newRev))

  def checkout(): os.Path =
    val dir = os.temp.dir(prefix = "pins")
    os.write(dir / "room-site" / "default.nix", room, createFolders = true)
    dir

  test("one refuses a short sha and knows the same pin"):
    val dir = checkout()
    val short = TestKit.piabrota(Seq("pins", "one", "room", "abc123"), cwd = dir)
    assertEquals(short.exitCode, 1)
    assert(short.err.text().contains("not a whole commit"), short.err.text())
    val same = TestKit.piabrota(Seq("pins", "one", "room", "d1cb9b7bab3ced3bee7f9f1150577545cfd7a7da"), cwd = dir)
    assertEquals(same.exitCode, 0)
    assertEquals(same.out.lines().last, "same=true")

  test("one names the sites when the site is unknown"):
    val r = TestKit.piabrota(Seq("pins", "one", "nope"), cwd = checkout())
    assertEquals(r.exitCode, 1)
    assert(r.err.text().contains("usage: piabrota pins one <ww3|closed|"), r.err.text())

  test("an unknown site"):
    val r = TestKit.piabrota(Seq("pins", "all", "nope"), cwd = checkout())
    assertEquals(r.exitCode, 1)
    assert(r.err.text().contains("no such site: nope"), r.err.text())

  test("no command prints the usage and exits 2; --help exits 0"):
    val r = TestKit.piabrota(Seq("pins"), cwd = checkout())
    assertEquals(r.exitCode, 2)
    assert(r.out.text().startsWith("Move the website pins"), r.out.text())
    assertEquals(TestKit.piabrota(Seq("pins", "--help")).exitCode, 0)

  test("next: what all does with each pin"):
    val site = PinSite.byName("room")
    val (a, b) = ("a" * 40, "b" * 40)
    assertEquals(Pins.next(site, None, b, listing = false), Left(PinLine.Failed("room", "no rev in room-site/default.nix")))
    assertEquals(Pins.next(site, Some(a), "", listing = false), Left(PinLine.Failed("room", "the head of piabrota/room's main")))
    assertEquals(Pins.next(site, Some(a), a, listing = false).left.map(_.render), Left(s"room same $a"))
    assertEquals(Pins.next(site, Some(a), b, listing = true).left.map(_.render), Left(s"room behind $a $b"))
    assertEquals(Pins.next(site, Some(a), b, listing = false), Right(a))
    assertEquals(PinLine.Moved("room", a, b).render, s"room moved $a $b")

  test("the prefetch answer and the unstable version"):
    assertEquals(Prefetched.parse("""{"hash":"sha256-X=","storePath":"/nix/store/s","locked":{"lastModified":86400}}"""),
      Some(Prefetched("sha256-X=", Some("/nix/store/s"), Some(86400L))))
    assertEquals(Prefetched.parse("""{"hash":"md5-X"}"""), None)
    assertEquals(Prefetched.parse("not json"), None)
    assertEquals(Pins.unstableVersion(86400L), "0-unstable-1970-01-02")
