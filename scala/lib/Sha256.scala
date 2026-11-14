package piabrota.lib

/** SHA-256 (FIPS 180-4). Scala Native has no `java.security.MessageDigest`. */
object Sha256:
  private val K = Array(
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  )

  /** Lowercase hex, as sha256sum prints it. */
  def hex(data: Array[Byte]): String = digest(data).map(b => f"${b & 0xff}%02x").mkString

  def file(path: os.Path): String = hex(os.read.bytes(path))

  def digest(data: Array[Byte]): Array[Byte] =
    val h = Array(0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19)
    val padded = data.length + 9 + (64 - (data.length + 9) % 64) % 64
    val msg = java.util.Arrays.copyOf(data, padded)
    msg(data.length) = 0x80.toByte
    val bits = data.length.toLong * 8
    for i <- 0 until 8 do msg(padded - 1 - i) = (bits >>> (8 * i)).toByte
    val w = new Array[Int](64)
    for block <- 0 until padded by 64 do
      for t <- 0 until 16 do w(t) = java.nio.ByteBuffer.wrap(msg, block + 4 * t, 4).getInt
      for t <- 16 until 64 do
        val s0 = Integer.rotateRight(w(t - 15), 7) ^ Integer.rotateRight(w(t - 15), 18) ^ (w(t - 15) >>> 3)
        val s1 = Integer.rotateRight(w(t - 2), 17) ^ Integer.rotateRight(w(t - 2), 19) ^ (w(t - 2) >>> 10)
        w(t) = w(t - 16) + s0 + w(t - 7) + s1
      var a = h(0); var b = h(1); var c = h(2); var d = h(3)
      var e = h(4); var f = h(5); var g = h(6); var hh = h(7)
      for t <- 0 until 64 do
        val t1 = hh + (Integer.rotateRight(e, 6) ^ Integer.rotateRight(e, 11) ^ Integer.rotateRight(e, 25)) +
          ((e & f) ^ (~e & g)) + K(t) + w(t)
        val t2 = (Integer.rotateRight(a, 2) ^ Integer.rotateRight(a, 13) ^ Integer.rotateRight(a, 22)) +
          ((a & b) ^ (a & c) ^ (b & c))
        hh = g; g = f; f = e; e = d + t1; d = c; c = b; b = a; a = t1 + t2
      val out = Array(a, b, c, d, e, f, g, hh)
      for i <- 0 until 8 do h(i) += out(i)
    h.flatMap(x => java.nio.ByteBuffer.allocate(4).putInt(x).array)
