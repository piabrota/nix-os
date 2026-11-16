package piabrota.thesis

/** The emulations of printf, awk, jq, read and fold, each against what the tool printed. */
class TextTest extends munit.FunSuite:
  test("fixed rounds the exact binary value half to even, as printf does"):
    assertEquals(List(0.125, 2.675, 0.5, 1.5).map(Text.fixed(_, 2)), List("0.12", "2.67", "0.50", "1.50"))
    assertEquals(List(0.5, 1.5, 2.5).map(Text.fixed(_, 0)), List("0", "2", "2"))

  test("g6 prints a number as awk does"):
    assertEquals(List(1.0, 0.06, 0.1 + 0.2, 2.0 / 3).map(Text.g6), List("1", "0.06", "0.3", "0.666667"))

  test("jqNum drops the fraction of a whole number"):
    assertEquals(List(30.0, 1.5, -2.0).map(Text.jqNum), List("30", "1.5", "-2"))

  test("awkNum takes the numeric prefix"):
    assertEquals(List("12abc", " 3.5", "x", "", "-1e2").map(Text.awkNum), List(12.0, 3.5, 0.0, 0.0, -100.0))

  test("padBytes counts bytes, as bash's printf %-6s does"):
    assertEquals(Text.padBytes("§a", 6), "§a   ")
    assertEquals(Text.padBytes("toolong", 3), "toolong")

  test("take counts characters"):
    assertEquals(Text.take("ação", 2), "aç")

  test("upcase changes a-z and Latin-1 letters only"):
    assertEquals(Text.upcase("ação ÷ ǆ"), "AÇÃO ÷ ǆ")

  test("ifsRead joins runs of tabs and gives the rest to the last name"):
    assertEquals(Text.ifsRead("\ta\t\tb\tc\td\t", 3), Vector("a", "b", "c\td"))

  test("foldSpaces breaks after the last blank and counts characters (coreutils 9.11)"):
    assertEquals(Text.foldSpaces("ação ação ação ação\n", 10), "ação ação \nação ação\n")
    assertEquals(Text.foldSpaces("abcdefghijklmno pq\n", 10), "abcdefghij\nklmno pq\n")

  test("grepContext gives the first matches with their context and --"):
    val lines = Vector("a1", "x", "a2", "y", "z", "w", "a3")
    assertEquals(Text.grepContext(lines, "^a".r, 2, 1), List("a1", "x", "a2", "y"))

  test("J.literal keeps a number as it was written"):
    val v = ujson.Obj("a" -> J.literal("25.40"), "b" -> J.literal("x"), "c" -> ujson.Str("\u0001 not a number"))
    assertEquals(J.pretty(v), "{\n  \"a\": 25.40,\n  \"b\": 0,\n  \"c\": \"\\u0001 not a number\"\n}\n")

  test("J.path reads array indices"):
    assertEquals(J.path(ujson.read("""{"a":[1,{"b":2}]}"""), "a.1.b"), Some(ujson.Num(2)))

  test("Ufrj.roman"):
    assertEquals((1 to 12).map(Ufrj.roman).toList, List("i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix", "x", "xi", "xii"))

  test("Ufrj.captions finds a table caption below and a figure caption above"):
    val good = Vector("\\begin{longtable}[]{@{}ll@{}}", "\\caption{T}", "\\begin{figure}", "\\includegraphics{x}", "\\caption{F}")
    assertEquals(Ufrj.captions(good), (0, 0))
    val bad = Vector("\\begin{longtable}[]{@{}ll@{}}", "\\toprule", "\\begin{figure}", "\\caption{F}", "\\includegraphics{x}")
    assertEquals(Ufrj.captions(bad), (1, 1))
