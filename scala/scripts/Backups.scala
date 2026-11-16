package piabrota.scripts

import piabrota.lib.{Sh, die}
import Util.step

/** Nightly copies of the SQLite databases. sqlite3's .backup is safe while the app writes; a cp of a
  * live WAL database is not. Any step that fails stops the copy with its exit code, as the `set -e`
  * scripts these replace did.
  */
object Backups:
  private def today(): String = Sh.out("date", "+%F")

  /** sqlite3's online copy of `db` into `copy`. */
  private def backup(db: os.Path, copy: os.Path): Unit = step("sqlite3", db, s".backup '$copy'")

  /** `piabrota loco-backup STATE` (loco.nix, loco-NAME-backup.service, as the app's user):
    * STATE/db.sqlite to STATE/backup/db-<date>.sqlite; copies older than seven days go.
    */
  def loco(args: List[String]): Int = args match
    case List(dir) =>
      val state = os.Path(dir, os.pwd)
      val (db, dest) = (state / "db.sqlite", state / "backup")
      step("mkdir", "-p", dest)
      if os.isFile(db) then backup(db, dest / s"db-${today()}.sqlite")
      step("find", dest, "-name", "db-*.sqlite", "-mtime", "+7", "-delete")
      0
    case _ => die("usage: piabrota loco-backup STATE", 2)

  /** `piabrota marola-backup STATE` (marola-site.nix, marola-backup.service): marola's database,
    * then csrf.key, then the studies, into /var/backups/marola. Database first, studies second: a
    * file without a row is harmless, a row without a file is not. Databases older than 14 days go.
    */
  def marola(args: List[String]): Int = args match
    case List(dir) =>
      val state = os.Path(dir, os.pwd)
      val dest = MarolaPaths.backups
      val (db, csrf, studies) = (state / "marola.db", state / "csrf.key", state / "studies")
      step("install", "-d", "-m", "0700", dest, dest / "studies")
      if os.isFile(db) then
        val copy = dest / s"marola-${today()}.db"
        backup(db, copy)
        step("chmod", "0600", copy)
      if os.isFile(csrf) then step("install", "-m", "0600", csrf, dest / "csrf.key")
      if os.isDir(studies) then step("rsync", "-a", "--exclude", ".incoming", s"$studies/", s"${dest / "studies"}/")
      step("find", dest, "-maxdepth", "1", "-name", "marola-*.db", "-mtime", "+14", "-delete")
      0
    case _ => die("usage: piabrota marola-backup STATE", 2)
