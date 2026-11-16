package piabrota.thesis

import java.nio.file.{FileAlreadyExistsException, Files, StandardOpenOption}
import piabrota.lib.{Exit, Sh}

/** What every command of `thesis` shares: the configuration, profile.json and a private work folder
  * removed at exit.
  */
final class Kit(val config: Config, val profile: Profile, val tmp: os.Path):
  val share: os.Path = config.share
  val home: os.Path = config.home
  val outbox: os.Path = config.outbox
  val profileFile: os.Path = share / Names.ProfileJson
  val filters: os.Path = share / "filters"
  private val locksHeld = scala.collection.mutable.ListBuffer[os.Path]()

  val pandocTimeout: String = config.pandocTimeout.getOrElse(Profile.show(profile.limits.pandocTimeoutS))
  val texTimeout: String = config.texTimeout.getOrElse(Profile.show(profile.limits.texTimeoutS))
  val popplerTimeout: String = Profile.show(profile.limits.popplerTimeoutS)

  /** The environment of every program the toolkit runs: thesis.lua reads profile.json from it. */
  def childEnv: Map[String, String] = Map("THESIS_PROFILE" -> profileFile.toString)

  def projDir(slug: String): os.Path = home / Names.Projects / slug
  def outDir(slug: String): os.Path = home / Names.Out / slug

  def checkSlug(v: String): Unit = Kit.checkName("slug", v, profile.limits.slugMax)
  def checkId(v: String): Unit = Kit.checkName("section id", v, profile.limits.idMax)
  def checkSeat(v: String): Unit = Kit.checkName("seat", v, profile.limits.idMax)

  /** `need_project`: the project folder with a thesis.json that is JSON. */
  def project(slug: String): Project =
    checkSlug(slug)
    val dir = projDir(slug)
    if !os.isDir(dir) then fail(s"no project $slug (looked in $dir)")
    val file = dir / Names.ThesisJson
    if !os.isFile(file) || os.isLink(file) then fail(s"$slug: thesis.json is missing or a link")
    val json = scala.util.Try(ujson.read(os.read(file))).toOption
      .filter(v => !v.isNull && v != ujson.False)
      .getOrElse(fail(s"$slug: thesis.json is not valid JSON"))
    Project(slug, dir, json)

  /** `need_section`: the section of thesis.json with this id, exactly once. */
  def section(p: Project, id: String): Section =
    checkId(id)
    p.sections.filter(_.idValue.contains(id)) match
      case List(one) => one
      case Nil       => fail(s"${p.slug}: thesis.json has no section $id")
      case _         => fail(s"${p.slug}: the section id $id is in thesis.json twice")

  /** `seat_name`: --as, THESIS_SEAT, or the member folder the caller stands in. */
  def seatName(as: Option[String]): String =
    as.orElse(config.seat) match
      case Some(seat) => checkSeat(seat); seat
      case None =>
        Kit.memberFolder(os.pwd.toString, home.toString) match
          case Some(member) => checkSeat(member); member
          case None =>
            fail(s"who are you? give --as <seat>, or set THESIS_SEAT, or run from your member folder under $home")

  /** `log`: one line to stderr and to the project's notes/thesis.log. */
  def log(p: Project, seat: Option[String], message: String): Unit =
    note(message)
    val notes = p.dir / Names.Notes
    if os.isDir(notes) then
      val who = seat.orElse(config.logSeat).getOrElse("?")
      scala.util.Try(os.write.append(notes / Names.ThesisLog, s"${Kit.nowIso()} $who $message\n"))
      ()

  /** `lock`: a lock folder in the project (mkdir is atomic); a folder older than 120 s is from a
    * run that died. Waits about 20 s.
    */
  def lock(p: Project, name: String): Unit =
    val dir = p.dir / s".lock-$name"
    var tries = 0
    var held = false
    while !held do
      held = scala.util.Try(Files.createDirectory(dir.toNIO)).isSuccess
      if !held then
        val age = scala.util.Try(System.currentTimeMillis - os.mtime(dir)).getOrElse(0L)
        if os.isDir(dir) && age > 120000 then os.remove.all(dir)
        else
          tries += 1
          if tries > 200 then fail(s"${p.slug}: the lock $name is held by another run")
          Thread.sleep(100)
    locksHeld += dir

  def unlock(p: Project, name: String): Unit = os.remove.all(p.dir / s".lock-$name")

  def cleanup(): Unit =
    locksHeld.foreach(d => scala.util.Try(os.remove.all(d)))
    scala.util.Try(os.remove.all(tmp))
    ()

  /** This binary with `thesis` and the arguments, in its own process: a refusal in a gate stays a
    * refusal and does not end the caller. stdout and stderr together, and the exit code.
    */
  def self(cmd: Cmd, args: String*): (Int, String) =
    System.out.flush()
    val r = os.proc(Kit.selfExe, "thesis", cmd.name, args).call(env = childEnv, stdin = "", stdout = os.Pipe,
      mergeErrIntoOut = true, check = false)
    (r.exitCode, r.out.text())

  /** `timed`: the command with its seconds and peak KiB appended to the times file (GNU time). */
  def timed(cmd: Seq[String]): Seq[String] =
    if Kit.hasGnuTime then Seq("time", "-f", "%e %M", "-a", "-o", (tmp / "times").toString) ++ cmd else cmd

/** A project folder and its thesis.json. */
final case class Project(slug: String, dir: os.Path, json: ujson.Value):
  def sections: List[Section] =
    J.get(json, ThesisKey.Sections).flatMap(_.arrOpt).toList.flatten.map(s => Section(J.raw(J.get(s, SectionKey.Id)), s))

  /** `sort_by(.order)` of jq: stable, null first, then numbers, then strings. */
  def ordered: List[Section] = sections.sortWith((a, b) => J.compare(a.order, b.order) < 0)

  /** The sections that are not omitted, in order. */
  def live: List[Section] = ordered.filterNot(_.omitted)

  /** The ids of the sections that are not omitted, in order (`order_ids`). */
  def orderIds: List[String] = live.map(_.id)

  def field(key: String): Option[ujson.Value] = J.get(json, key)
  /** A field as `jq -r` prints it ("null" when missing). */
  def raw(key: String): String = J.raw(field(key))
  def title: String = raw(ThesisKey.Title)
  def course: String = raw(ThesisKey.Course)
  def year: String = raw(ThesisKey.Year)
  def isPtBr: Boolean = J.str(json, ThesisKey.Language).contains(ThesisValue.Language)
  def isAuthorDate: Boolean = J.str(json, ThesisKey.CitationStyle).contains(ThesisValue.CitationStyle)
  /** assets.ufrj_logo, when it is set. */
  def logo: Option[String] = J.path(json, ThesisKey.AssetsUfrjLogo).filterNot(J.falsy).map(J.rawValue)
  /** The template name, "" when thesis.json names none. */
  def templateName: String = field(ThesisKey.Template).filterNot(J.falsy).map(J.rawValue).getOrElse("")

  def refsBib: os.Path = dir / Names.RefsBib
  def references: os.Path = dir / Names.ReferencesMd
  def build: os.Path = dir / Names.Build
  def review: os.Path = dir / Names.Review
  def notes: os.Path = dir / Names.Notes
  def sectionFile(id: String): os.Path = dir / Names.Sections / s"$id.md"
  def stateFile(id: String): os.Path = dir / Names.State / s"$id.json"
  def claimFile(id: String): os.Path = dir / Names.Claims / s"$id.claim"

  /** The rows of REFERENCES.md, none when there is no file. */
  def refRows: Vector[RefRow] = if os.isFile(references) then RefRow.rows(os.read(references)) else Vector.empty

  /** `state_get <id> .key`: "null" when the section has no state file or no such field. */
  def stateRaw(id: String, key: StateKey): String =
    if !os.isFile(stateFile(id)) then "null" else J.raw(J.get(readState(id), key.key))

  /** `state_get <id> '.key // default'`: still "null" when there is no state file at all. */
  def stateOr(id: String, key: StateKey, default: String): String =
    if !os.isFile(stateFile(id)) then "null"
    else J.get(readState(id), key.key).filterNot(J.falsy).map(J.rawValue).getOrElse(default)

  def readState(id: String): ujson.Value =
    scala.util.Try(ujson.read(os.read(stateFile(id)))).toOption.filter(_.objOpt.isDefined).getOrElse(ujson.Obj())

  /** `state_put`: sets and removes fields of the state object and writes it back atomically. A
    * field keeps its place in the object when it is set again.
    */
  def putState(id: String)(set: (StateKey, ujson.Value)*)(remove: StateKey*): Unit =
    os.makeDir.all(dir / Names.State)
    val obj = if os.isFile(stateFile(id)) then readState(id).obj else ujson.Obj().value
    val state = ujson.Obj.from(obj)
    set.foreach((k, v) => state(k.key) = v)
    remove.foreach(k => state.value.remove(k.key))
    Kit.atomicWrite(stateFile(id), J.pretty(state))

/** One section of thesis.json; `id` is the id as `jq -r` prints it. */
final case class Section(id: String, json: ujson.Value):
  /** `sec '<.key>'`, as jq -r prints it ("null" when missing). */
  def raw(key: String): String = J.raw(J.get(json, key))
  /** `sec '.key // default'`. */
  def rawOr(key: String, default: String): String =
    J.get(json, key).filterNot(J.falsy).map(J.rawValue).getOrElse(default)
  def str(key: String): Option[String] = J.str(json, key)

  def idValue: Option[String] = str(SectionKey.Id)
  def order: Option[ujson.Value] = J.get(json, SectionKey.Order)
  def role: Option[Role] = str(SectionKey.Role).flatMap(Role.parse)
  def kind: Option[Kind] = str(SectionKey.Kind).flatMap(Kind.parse)
  def is(r: Role): Boolean = role.contains(r)
  def title: String = raw(SectionKey.Title)
  def citeClass: String = rawOr(SectionKey.CiteClass, SectionKey.DefaultCiteClass)
  def targetWords: Double = J.get(json, SectionKey.TargetWords).flatMap(_.numOpt).getOrElse(0.0)
  def targetWordsShown: String = rawOr(SectionKey.TargetWords, "0")
  /** status omit in thesis.json: the section is not in the work. */
  def omitted: Boolean = str(SectionKey.Status).contains(SectionState.Omit.render)
  /** The `sources` keys, split at blanks as the shell's word splitting did. */
  def sources: List[String] =
    J.get(json, SectionKey.Sources).filterNot(J.falsy).flatMap(_.arrOpt).toList.flatten
      .map(J.rawValue).flatMap(_.split("\\s+").filter(_.nonEmpty))
  /** `keywords | length` of jq. */
  def keywordCount: Int = J.get(json, SectionKey.Keywords) match
    case Some(ujson.Arr(a)) => a.length
    case Some(ujson.Str(s)) => s.length
    case Some(ujson.Obj(o)) => o.size
    case _                  => 0

object Kit:
  /** An id, a slug or a seat name: letters, digits, - and _; no leading -. */
  def checkName(what: String, value: String, max: Int): Unit =
    if value.isEmpty || value.startsWith("-") || !value.forall(c => c.isLetterOrDigit && c < 128 || c == '_' || c == '-') then
      fail(s"$what: letters, digits, - and _ only, and no - first (got: $value)")
    if value.length > max then fail(s"$what: at most $max characters")

  /** The member folder that `here` stands in under home, outside the shared projects/ and out/. */
  def memberFolder(here: String, home: String): Option[String] =
    val inShared = List(Names.Projects, Names.Out).exists(d => here == s"$home/$d" || here.startsWith(s"$home/$d/"))
    Option.when(!inShared && here.startsWith(s"$home/"))(here.stripPrefix(s"$home/").takeWhile(_ != '/'))

  def nowIso(): String = java.time.Instant.ofEpochSecond(nowS()).toString
  def nowS(): Long = System.currentTimeMillis / 1000

  def sha(file: os.Path): String = piabrota.lib.Sha256.file(file)

  /** A regular file, not a link: the gates read a section as it is, never through a link. */
  def plainFile(p: os.Path): Boolean = os.isFile(p, followLinks = false)

  /** plainFile for a path that a user wrote, relative to dir. */
  def plainFileAt(dir: os.Path, rel: String): Boolean =
    Files.isRegularFile(java.nio.file.Paths.get(dir.toString, rel), java.nio.file.LinkOption.NOFOLLOW_LINKS)

  /** `atomic_write`: a temp name in the same folder, mode 0644, then rename. */
  def atomicWrite(file: os.Path, content: String): Unit =
    try piabrota.lib.Files.replace(file, content.getBytes("UTF-8"), Some(os.PermSet.fromString("rw-r--r--")))
    catch case _: java.io.IOException => fail(s"cannot write in ${file / os.up}")

  /** Creates the file only if it is not there (sh's `set -C`); false if it was. */
  def createNew(file: os.Path, content: String): Boolean =
    try
      val out = Files.newOutputStream(file.toNIO, StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE)
      try out.write(content.getBytes("UTF-8")) finally out.close()
      true
    catch case _: FileAlreadyExistsException => false

  /** A fresh folder `<prefix>XXXXXX` in dir (mktemp -d), or None. */
  def tempDir(dir: os.Path, prefix: String): Option[os.Path] =
    scala.util.Try(os.temp.dir(dir = dir, prefix = prefix, deleteOnExit = false)).toOption

  lazy val selfExe: os.Path = os.Path(Files.readSymbolicLink(java.nio.file.Paths.get("/proc/self/exe")).toString)

  lazy val hasGnuTime: Boolean = Sh.ok("time", "-f", "%e %M", "true")

  /** `chmod -R u+w`. */
  def ownerWritable(dir: os.Path): Unit =
    (Iterator(dir) ++ os.walk.stream(dir).toList.iterator).filterNot(os.isLink(_)).foreach { p =>
      os.perms.set(p, os.perms(p) + java.nio.file.attribute.PosixFilePermission.OWNER_WRITE)
    }

  /** `cp -r`: links stay links. */
  def copyTree(from: os.Path, to: os.Path): Unit =
    os.copy(from, to, followLinks = false, createFolders = true)

/** "thesis: <message>" on stderr, then the exit code 1 (`die`). */
def fail(message: String): Nothing =
  System.out.flush()
  throw Exit(1, s"thesis: $message")

/** "thesis: <message>" on stderr (`note`). */
def note(message: String): Unit =
  System.out.flush()
  System.err.println(s"thesis: $message")

def say(line: String): Unit = println(line)

/** jq, the little of it that the shell version used. */
object J:
  def get(v: ujson.Value, key: String): Option[ujson.Value] = v.objOpt.flatMap(_.get(key))
  def path(v: ujson.Value, dotted: String): Option[ujson.Value] =
    dotted.split('.').foldLeft(Option(v))((acc, k) => acc.flatMap { x =>
      x.arrOpt.flatMap(a => k.toIntOption.flatMap(a.lift)).orElse(get(x, k))
    })
  def str(v: ujson.Value, key: String): Option[String] = get(v, key).flatMap(_.strOpt)

  /** null or false: what jq's `//` replaces by its default. */
  def falsy(v: ujson.Value): Boolean = v.isNull || v == ujson.False

  /** `jq -r`: a string as it is, a number without ".0", null as "null". */
  def raw(v: Option[ujson.Value]): String = v.map(rawValue).getOrElse("null")
  def rawValue(v: ujson.Value): String = v match
    case ujson.Str(s)  => s
    case ujson.Num(d)  => Text.jqNum(d)
    case ujson.Bool(b) => b.toString
    case ujson.Null    => "null"
    case other         => other.render(indent = 2)

  /** jq's output of a value: two-space indent and a newline. */
  def pretty(v: ujson.Value): String =
    v.render(indent = 2).replaceAll("\"\\\\u0001([-+.0-9eE]+)\"", "$1") + "\n"

  /** A number written as jq 1.7 writes a literal it got from --argjson or tonumber: as it was
    * ("25.40" stays 25.40). Only `pretty` knows it; anything else sees a string.
    */
  def literal(s: String): ujson.Value =
    if s.matches("-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][-+]?[0-9]+)?") then ujson.Str("\u0001" + s)
    else ujson.Num(Text.awkNum(s))

  /** jq's order: null, false, true, numbers, strings, arrays, objects. */
  def compare(a: Option[ujson.Value], b: Option[ujson.Value]): Int =
    def rank(v: ujson.Value): Int = v match
      case ujson.Null        => 0
      case ujson.False       => 1
      case ujson.True        => 2
      case _: ujson.Num      => 3
      case _: ujson.Str      => 4
      case _: ujson.Arr      => 5
      case _                 => 6
    val x = a.getOrElse(ujson.Null)
    val y = b.getOrElse(ujson.Null)
    (x, y) match
      case (ujson.Num(p), ujson.Num(q)) => p.compare(q)
      case (ujson.Str(p), ujson.Str(q)) => p.compareTo(q)
      case _ if rank(x) != rank(y)      => rank(x).compare(rank(y))
      case _                            => x.render().compareTo(y.render())
