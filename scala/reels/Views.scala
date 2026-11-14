package piabrota.reels

import Json.*
import Jv.{Null, Str}

/** What a view printed: its lines, and one error line for each value of the file that it could not
  * read (the lines before the error stay).
  */
final case class Printed(out: String, err: Vector[String])

/** The two views of a screenplay, for people: the A/V script and the table read. Nothing reads
  * them back. They were view.jq and timing.jq; a file of several JSON values gives one view each.
  */
object Views:
  /** Runs `program` on each value of the file; `file` names it in the error lines. */
  def each(docs: Vector[Doc], file: String)(program: (Jv, String => Unit) => Unit): Printed =
    val out = StringBuilder()
    val err = Vector.newBuilder[String]
    docs.foreach { d =>
      try program(d.value, line => { out ++= line; out += '\n' })
      catch case JqError(msg) => err += s"jq: error (at $file:${d.line}): $msg"
    }
    Printed(out.result(), err.result())

  private def padr(v: Jv, n: Int): Jv = if v.length >= Jv.num(n) then v else v + Str(" ") * (Jv.num(n) - v.length)
  private def padl(v: Jv, n: Int): Jv = if v.length >= Jv.num(n) then v else (Str(" ") * (Jv.num(n) - v.length)) + v

  /** A number to one decimal, always with a point: 2 is "2.0". */
  private def tenths(v: Jv): String =
    val s = (Jv.num(round((v * Jv.num(10)).number)) / Jv.num(10)).show
    if s.contains('.') then s else s + ".0"

  private def plainText(v: Jv): String = v.matchable.replace("*", "")

  /** The words of a text in lines of at most `w` characters. */
  private def wrap(v: Jv, w: Int): Vector[String] =
    if v === Str("") then Vector("")
    else
      val words = v match
        case Str(s) => split(s, " ")
        case _      => throw JqError("split input and separator must be strings")
      words.foldLeft(Vector("")) { (ls, word) =>
        val last = ls.last
        val n = last.codePointCount(0, last.length)
        if n == 0 then ls.updated(ls.length - 1, word)
        else if n + 1 + word.codePointCount(0, word.length) <= w then ls.updated(ls.length - 1, last + " " + word)
        else ls :+ word
      }

  private def soundLines(b: Jv): Vector[String] =
    val s = alt(b("sound"), Jv.EmptyObj)
    if alt(s("silence"), Jv.False).truthy then Vector("(silence)")
    else
      val sfx = alt(s("sfx"), Jv.EmptyArr).iter.map { x =>
        val at = tenths(x("at"))
        s"sfx: ${x("name").show} at $at s"
      }
      val music = alt(s("music"), Str(""))
      (if music === Str("") then Vector.empty else Vector(s"music: ${s("music").show}")) ++ sfx

  private def block(b: Jv, lw: Int, rw: Int): String =
    val pic = wrap(alt(b("visual")("describe"), Str("")), lw)
    val wrapped = alt(b("text"), Jv.EmptyArr).iter.map(t => Str(plainText(t))).map(wrap(_, rw))
    val txt = if wrapped.isEmpty then Vector("(no text)") else wrapped.flatten
    val right = txt ++ Vector("") ++ soundLines(b)
    val rows = (0 until math.max(pic.length, right.length)).map { i =>
      "    " + padr(Str(pic.lift(i).getOrElse("")), lw).show + "  |  " + right.lift(i).getOrElse("")
    }.mkString("\n")
    val note = if !(alt(b("note"), Str("")) === Str("")) then s"\n    note: ${b("note").show}" else ""
    val tr = alt(b("transition"), Str(Cut.Hard)).show
    val scene = alt(b("visual")("scene"), Str("?")).show
    val role = upcase(b("role"))
    val out = tenths(b("t_out"))
    val in = tenths(b("t_in"))
    s"${b("id").show}  $in - $out s  $role  [$scene]  in: $tr" + note + "\n" + rows

  /** The screenplay as an A/V script: one block a beat, picture on the left, text and sound on the right. */
  def screenplay(sp: Jv, emit: String => Unit): Unit =
    val beats = alt(sp("beats"), Jv.EmptyArr)
    locally {
      val loop = if sp("loop").truthy then "loops" else "no loop"
      val language = sp("language").show
      val format = sp("format").show
      val slug = sp("slug").show
      emit(s"${sp("title").show}  ($slug, $format s, $language, $loop)")
    }
    emit(s"logline:  ${sp("logline").show}")
    emit(s"audience: ${sp("audience").show}")
    locally {
      val bpm = if sp("music")("bpm").truthy then s" ${sp("music")("bpm").show} bpm" else ""
      val preset = alt(sp("music")("preset"), Str("none")).show
      emit(s"look:     ${alt(sp("look")("style"), Str("?")).show}    music: $preset$bpm")
    }
    emit("")
    emit("    PICTURE" + " " * 41 + "|  TEXT, SOUND")
    emit("-" * 100)
    beats.iter.foreach { b =>
      emit(block(b, 44, 44))
      emit("")
    }
    val claims = alt(sp("claims"), Jv.EmptyArr)
    if claims.length > Jv.num(0) then
      emit("CLAIMS")
      claims.iter.foreach { c =>
        val source = c("source").show
        val text = c("text").show
        val status = c("status").show
        emit(s"  ${c("id").show}  [$status]  $text  (source: $source)")
      }

  /** The table read: the reading speed and the hold time of every beat. A beat is FAST when it needs
    * more reading time than it has, TIGHT when less than 0.4 s is left to hold the text after it is read.
    */
  def timing(sp: Jv, profile: Jv, emit: String => Unit): Unit =
    val cps = profile("text")("max_cps")
    final case class Row(id: Jv, role: Jv, dur: Jv, chars: Jv, cps: Jv, need: Jv, hold: Jv, flag: String)
    val rows = alt(sp("beats"), Jv.EmptyArr).iter.map { b =>
      val d = Jv.num(round((sub(b("t_out"), b("t_in")) * Jv.num(1000)).number) / 1000)
      val lens = alt(b("text"), Jv.EmptyArr).iter.map(t => Jv.num(codepoints(plainText(t)).length.toDouble))
      val c = alt(lens.reduceLeftOption(_ + _).getOrElse(Null), Jv.num(0))
      val need = c / cps
      val id = b("id")
      val role = b("role")
      val rate = if d > Jv.num(0) then c / d else Jv.num(0)
      val hold = d - need
      val flag =
        if c === Jv.num(0) then "no text"
        else if d > Jv.num(0) && (c / d) > cps then "FAST"
        else if (d - need) < Jv.num(0.4) then "TIGHT"
        else ""
      Row(id, role, d, c, rate, need, hold, flag)
    }
    val worst = rows.filter(_.chars > Jv.num(0)).sortWith((x, y) =>
      compare(Jv.arr(-x.cps, x.hold), Jv.arr(-y.cps, y.hold)) < 0).headOption
    emit(s"TABLE READ  (reading speed limit ${cps.show} characters per second)")
    emit("")
    emit(Seq(padr(Str("beat"), 5), padr(Str("role"), 8), padl(Str("length"), 7), padl(Str("chars"), 6),
      padl(Str("cps"), 6), padl(Str("needs"), 7), padl(Str("hold"), 7), Str("flag")).map(_.show).mkString("  "))
    rows.foreach { r =>
      emit(join(Seq(padr(r.id, 5), padr(r.role, 8), padl(Str(tenths(r.dur) + " s"), 7), padl(Str(r.chars.show), 6),
        padl(Str(tenths(r.cps)), 6), padl(Str(tenths(r.need) + " s"), 7), padl(Str(tenths(r.hold) + " s"), 7), Str(r.flag)), "  "))
    }
    emit("")
    emit(worst.fold("no text on screen") { w =>
      val hold = tenths(w.hold)
      val rate = tenths(w.cps)
      s"worst beat: ${w.id.show}  $rate cps, $hold s to hold after reading"
    })
    def total(xs: Seq[Jv]) = xs.reduceLeftOption(_ + _).getOrElse(Null)
    locally {
      val durs = total(rows.map(_.dur))
      val chars = total(rows.map(_.chars))
      val average = tenths(div(chars, durs))
      emit(s"total: ${tenths(durs)} s, ${chars.show} characters, $average cps on average")
    }
    val fast = rows.filter(_.flag == "FAST")
    val tight = rows.filter(_.flag == "TIGHT")
    emit(
      if fast.nonEmpty then s"result: FAIL (${join(fast.map(_.id), ", ")} too fast)"
      else if tight.nonEmpty then s"result: OK, tight beats: ${join(tight.map(_.id), ", ")}"
      else "result: OK")
