package piabrota.design

/** The string rules of JavaScript that the pages depend on: the kit was written in node, and the
  * pages it makes must stay the same to the byte.
  */
private[design] object Js:
  /** The characters of JavaScript's `\s` and `trim()`, as the inside of a regex class. */
  val spaceClass: String =
    "\t\n\u000B\f\r    -     　﻿"

  /** One character of `\s`, as a regex. */
  val space: String = s"[$spaceClass]"

  def isSpace(c: Char): Boolean =
    "\t\n\u000B\f\r       　﻿".indexOf(c.toInt) >= 0 ||
      (c >= ' ' && c <= ' ')

  /** `String.prototype.trim`: Java's `strip` keeps U+00A0 and U+FEFF, JavaScript drops them. */
  def trim(s: String): String = s.dropWhile(isSpace).reverse.dropWhile(isSpace).reverse

  /** The text with only A-Z lowered, so it keeps its length: a match found in it is at the same
    * place in the text. This is what a JavaScript `/i` regex of ASCII letters matches; Java's
    * `(?i)` folds more letters (the Kelvin sign is a K).
    */
  def lowerAscii(s: String): String = s.map(c => if c >= 'A' && c <= 'Z' then (c + 32).toChar else c)
