package piabrota.scripts

import java.nio.{ByteBuffer, ByteOrder}
import piabrota.lib.TestKit

/** favicon-files-check on files made here: a well-formed set, then broken ones. */
class FaviconFilesTest extends munit.FunSuite:
  val pngMagic = Array(0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n').map(_.toByte)

  /** The PNG signature and an IHDR of this size; enough for the checks. */
  def png(px: Int): Array[Byte] =
    val b = ByteBuffer.allocate(24).order(ByteOrder.BIG_ENDIAN)
    b.put(pngMagic).putInt(13).put("IHDR".getBytes).putInt(px).putInt(px)
    b.array()

  def ico(sizes: List[Int]): Array[Byte] =
    val images = sizes.map(png)
    val b = ByteBuffer.allocate(6 + 16 * sizes.length + images.map(_.length).sum).order(ByteOrder.LITTLE_ENDIAN)
    b.putShort(0).putShort(1).putShort(sizes.length.toShort)
    sizes.zip(images).foldLeft(6 + 16 * sizes.length) { case (offset, (px, image)) =>
      b.put(px.toByte).put(px.toByte).put(0.toByte).put(0.toByte).putShort(1).putShort(32)
        .putInt(image.length).putInt(offset)
      offset + image.length
    }
    images.foreach(b.put)
    b.array()

  def output(icoBytes: Array[Byte], touch: Array[Byte] = png(180)): os.Path =
    val dir = os.temp.dir(prefix = "favicon")
    os.write(dir / "favicon.ico", icoBytes)
    os.write(dir / "apple-touch-icon.png", touch)
    os.write(dir / "favicon.svg", "<svg/>")
    dir

  test("a good output passes the 28 checks"):
    val r = TestKit.piabrota(Seq("favicon-files-check", output(ico(List(16, 32, 48))).toString))
    assertEquals(r.out.text(), "28 checks of the files, 0 failed\n")
    assertEquals(r.exitCode, 0)

  test("a wrong touch icon, a fourth file and bytes after the last image fail"):
    val dir = output(ico(List(16, 32, 48)) ++ Array[Byte](0), png(64))
    os.write(dir / "extra", "x")
    val r = TestKit.piabrota(Seq("favicon-files-check", dir.toString))
    assertEquals(r.exitCode, 1)
    val lines = r.out.lines().toList
    assert(lines.exists(_.startsWith("FAIL the output holds the three files only")), r.out.text())
    assert(lines.exists(_.startsWith("FAIL ico ends with its last image")), r.out.text())
    assert(lines.contains("FAIL touch icon is 180 by 180 px: got [(64,64)], want [(180,180)]"), r.out.text())
    assertEquals(lines.last, "28 checks of the files, 3 failed")
