package piabrota.pirsig

class PyTest extends munit.FunSuite:
  test("whitespace as Python sees it"):
    assertEquals(Py.strip("  a b\n "), "a b")
    assertEquals(Py.split(" a b\tc  "), List("a", "b", "c"))
    assertEquals(Py.splitlines("a\r\nb\n\nc\n"), List("a", "b", "", "c"))
    assertEquals(Py.splitlines(""), Nil)

  test("repr"):
    assertEquals(Py.repr("Big"), "'Big'")
    assertEquals(Py.repr("x\ny"), "'x\\ny'")
    assertEquals(Py.repr("it's"), "\"it's\"")
    assertEquals(Py.repr("a'\"b"), "'a\\'\"b'")
    assertEquals(Py.repr("\u0000ação"), "'\\x00ação'")
    assertEquals(Py.repr(ujson.Num(5)), "5")

  test("json.dumps"):
    val v = ujson.Obj("a" -> 1, "b" -> ujson.Arr("ç\n\"", ujson.Null, true), "c" -> ujson.Obj(), "d" -> 1.5)
    assertEquals(Py.dumps(v), """{"a": 1, "b": ["ç\n\"", null, true], "c": {}, "d": 1.5}""")
    assertEquals(Py.dumpsIndented(v),
      "{\n  \"a\": 1,\n  \"b\": [\n    \"ç\\n\\\"\",\n    null,\n    true\n  ],\n  \"c\": {},\n  \"d\": 1.5\n}")

  test("str of a JSON value"):
    assertEquals(Py.str(ujson.Null), "None")
    assertEquals(Py.str(ujson.Str("x")), "x")
    assertEquals(Py.str(ujson.Bool(true)), "True")
