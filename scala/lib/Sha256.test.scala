package piabrota.lib

import java.nio.charset.StandardCharsets.UTF_8

class Sha256Test extends munit.FunSuite:
  test("the FIPS 180-4 vectors"):
    assertEquals(Sha256.hex(Array.emptyByteArray), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    assertEquals(Sha256.hex("abc".getBytes(UTF_8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    assertEquals(Sha256.hex(("a" * 1000).getBytes(UTF_8)), "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3")
