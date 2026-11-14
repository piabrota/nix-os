//> using scala 3.10.1
//> using jvm system

// `just scala-lock`: writes scala/deps.lock.json, every file of a Coursier cache that a build of
// scala/ filled, by its path under maven2/ and its SRI hash. scala/default.nix fetches each one
// into a cache of the same shape, so the build in the Nix sandbox needs no network.
//
//   scala-cli run scala/lock/Lock.scala -- <coursier cache> <out.json>
import java.nio.file.{Files, Path, Paths}
import java.security.MessageDigest
import java.util.Base64
import scala.jdk.CollectionConverters.*

@main def lock(cache: String, out: String): Unit =
  val root = Paths.get(cache, "https")
  val files = Files.walk(root).iterator.asScala.filter(Files.isRegularFile(_)).flatMap(entry(root, _))
  val rows = files.toList.distinctBy(_._1).sortBy(_._1)
  val json = rows.map((path, hash) => s"""  { "path": "$path", "hash": "$hash" }""")
  Files.writeString(Paths.get(out), json.mkString("[\n", ",\n", "\n]\n"))
  println(s"${rows.size} files in $out")

/** A pom or a jar, by its path under maven2/ (whatever mirror it came from). Coursier's own
  * markers and checksum files are left out: offline, it does not read them.
  */
def entry(root: Path, file: Path): Option[(String, String)] =
  val rel = root.relativize(file).toString
  val name = file.getFileName.toString
  val keep = (name.endsWith(".pom") || name.endsWith(".jar")) && rel.contains("/maven2/")
  Option.when(keep)(rel.substring(rel.indexOf("/maven2/") + "/maven2/".length) -> sri(file))

def sri(file: Path): String =
  val digest = MessageDigest.getInstance("SHA-256").digest(Files.readAllBytes(file))
  "sha256-" + Base64.getEncoder.encodeToString(digest)
