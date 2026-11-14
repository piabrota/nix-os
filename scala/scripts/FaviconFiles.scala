package piabrota.scripts

import java.nio.{ByteBuffer, ByteOrder}
import piabrota.lib.die
import FaviconOutput.png

/** `piabrota favicon-files-check <favicon output>`: the files of the favicon build, whose bytes Nix
  * cannot read: the three files and nothing else, the ICO (a header, a 16-byte entry for each of the
  * 16, 32 and 48 px images, then PNGs that fill the file to its last byte) and the 180 px touch icon.
  * favicon/check.nix runs it. Prints "N checks of the files, M failed"; exits 1 on a failure.
  */
object FaviconFiles:
  def run(args: List[String]): Int = args match
    case List(dir) => check(os.Path(dir, os.pwd))
    case _         => die("usage: piabrota favicon-files-check <favicon output>", 2)

  def check(out: os.Path): Int =
    val all = files(out) ++ icoChecks(os.read.bytes(out / FaviconOutput.ico)) ++
      touchChecks(os.read.bytes(out / FaviconOutput.touchIcon))
    val failed = all.filterNot(_.passed)
    failed.foreach(c => println(c.render))
    println(s"${all.length} checks of the files, ${failed.length} failed")
    if failed.isEmpty then 0 else 1

  private def files(out: os.Path): List[FileCheck] =
    FaviconOutput.files.map(f => FileCheck(s"$f is not empty", os.isFile(out / f) && os.size(out / f) > 0, true)) :+
      FileCheck("the output holds the three files only", os.list(out).map(_.last).sorted.toList, FaviconOutput.files)

  /** A header, one entry per size, then the PNGs, each where the last one ended. */
  def icoChecks(ico: Array[Byte]): List[FileCheck] =
    val le = ByteBuffer.wrap(ico).order(ByteOrder.LITTLE_ENDIAN)
    val be = ByteBuffer.wrap(ico).order(ByteOrder.BIG_ENDIAN)
    def u16(at: Int) = le.getShort(at) & 0xffff
    def u32le(at: Int) = le.getInt(at) & 0xffffffffL
    def u32be(at: Int) = be.getInt(at) & 0xffffffffL
    val sizes = FaviconOutput.icoSizes
    val header = List(FileCheck("ico reserved", u16(0), 0), FileCheck("ico type", u16(2), 1),
      FileCheck("ico count", u16(4), sizes.length))
    val (end, entries) = sizes.zipWithIndex.foldLeft((6L + 16 * sizes.length, List.empty[FileCheck])) {
      case ((end, checks), (px, i)) =>
        val at = 6 + 16 * i
        val (w, h, bits) = (ico(at) & 0xff, ico(at + 1) & 0xff, u16(at + 6))
        val (size, offset) = (u32le(at + 8), u32le(at + 12))
        (offset + size, checks ++ List(
          FileCheck(s"ico entry $i width", w, px),
          FileCheck(s"ico entry $i height", h, px),
          FileCheck(s"ico entry $i bits", bits, 32),
          FileCheck(s"ico entry $i starts where the last ended", offset, end),
          FileCheck(s"ico entry $i is a PNG", ico.slice(offset.toInt, offset.toInt + 8).toList, png),
          FileCheck(s"ico entry $i PNG is as wide as its entry", u32be(offset.toInt + 16), w.toLong)))
    }
    header ++ entries :+ FileCheck("ico ends with its last image", ico.length.toLong, end)

  def touchChecks(touch: Array[Byte]): List[FileCheck] =
    val be = ByteBuffer.wrap(touch).order(ByteOrder.BIG_ENDIAN)
    val px = FaviconOutput.touchPx
    List(FileCheck("touch icon is a PNG", touch.take(8).toList, png),
      FileCheck(s"touch icon is $px by $px px", (be.getInt(16), be.getInt(20)), (px, px)))
