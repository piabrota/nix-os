package piabrota.metrics

import java.io.File
import java.nio.charset.StandardCharsets.ISO_8859_1
import java.nio.file.{Files, Path, Paths, StandardCopyOption}
import scala.scalanative.posix.sys.stat
import scala.scalanative.posix.unistd
import scala.scalanative.unsafe.{alloc, extern, toCString, CInt, CString, Ptr, Zone}
import scala.scalanative.unsigned.*

@extern
private object LibC:
  def statvfs(path: CString, buf: Ptr[Long]): CInt = extern

/** The effects the metrics commands share: the files they write, the clock and the system's
  * numbers that `getconf` and `df` used to give.
  */
private[metrics] object Host:
  /** The scripts ran `umask 022`: every file they write is 0644, whatever umask started them. */
  def umask022(): Unit = stat.umask(Integer.parseInt("022", 8).toUInt)

  def pid: Int = unistd.getpid()

  def now(): Long = System.currentTimeMillis() / 1000

  /** `getconf CLK_TCK` and `getconf PAGESIZE`, with the scripts' fallbacks. */
  def clockTicks: Long = sysconf(unistd._SC_CLK_TCK, 100)
  def pageSize: Long = sysconf(unistd._SC_PAGESIZE, 4096)
  def sysConf: SysConf = SysConf(clockTicks.toDouble, pageSize.toDouble)

  private def sysconf(name: Int, fallback: Long): Long =
    val v = unistd.sysconf(name).toLong
    if v > 0 then v else fallback

  /** What `df -kP` prints for the file system of `dir`, in bytes: its size and its used part, each
    * a whole number of KiB rounded up as df rounds them. None when statvfs fails. A child `df` costs
    * more than the rest of a collector run, so it is read here.
    */
  def diskSpace(dir: String): Option[(Long, Long)] = Zone {
    val buf = alloc[Long](32)
    if LibC.statvfs(toCString(dir), buf) != 0 then None
    else
      // glibc's struct statvfs on 64-bit Linux starts f_bsize, f_frsize, f_blocks, f_bfree, 8 bytes
      // each. posixlib's own statvfs leaves f_blocks and f_bfree out (Scala Native 0.5.12).
      val block = if buf(1) != 0 then buf(1) else buf(0)
      def kib(blocks: Long) = (BigInt(blocks) * block + 1023) / 1024 * 1024
      Some((kib(buf(2)).toLong, kib(buf(2) - buf(3)).toLong))
  }

  def path(p: String): Path = Paths.get(p)

  /** The names in a folder, sorted as the shell's glob sorts them; none when it is not there. */
  def listing(dir: String): Vector[String] = Option(File(dir).list()).fold(Vector.empty)(_.toVector.sorted)

  def mkdirs(dir: String): Unit = Files.createDirectories(path(dir))

  /** `<file>.<pid>.tmp`, beside the file, so the move into place is atomic. */
  def temp(file: String): String = s"$file.$pid.tmp"

  def write(file: String, text: String): Unit = Files.write(path(file), text.getBytes(ISO_8859_1))

  def move(from: String, to: String): Unit =
    Files.move(path(from), path(to), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)

  /** Runs `body`, then removes the temporary files that are left (the scripts' `trap ... EXIT`). */
  def cleaning[A](temps: String*)(body: => A): A =
    try body
    finally temps.foreach(t => Files.deleteIfExists(path(t)))
