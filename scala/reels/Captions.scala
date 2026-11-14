package piabrota.reels

import Json.*
import Jv.{Null, Str}

/** What a beat is drawn from. `hin` is the pre-roll before the beat starts (the incoming
  * transition's handle) and `total` the length of the clip, pre-roll and post-roll included, both
  * in seconds; `last` is true for the last beat of the reel.
  */
final case class SceneInput(sp: Jv, beat: Jv, shot: Jv, style: Jv, profile: Jv, hin: Double, total: Double,
    dur: Double, last: Boolean)

/** One beat as an ASS script, and the plan of its other layers; the background of a style as SVG.
  * The words on screen are the lines of the beat's text and nothing else: `visual.params` and the
  * shot only steer the look. They were scene.jq and bg.jq.
  *
  * Sizes: libass reads \fs as the height of the font's line cell, not of its em. The widths and line
  * heights of a font are in the style (fonts.<role>.w, .lh), measured with libass. Where two parts of
  * a value can fail (a motion value of the shotlist that is null or false), they are worked out in
  * jq's order, so the error is the one jq gave.
  */
object Captions:
  /** The ASS script; with `mask`, every colour is white, to measure what the script draws. Empty
    * when a big_number beat has no number in its first line.
    */
  def ass(in: SceneInput, mask: Boolean): String =
    val d = Draw(in, mask)
    d.events().fold("")(evs => d.header + "\n" + evs.mkString("\n") + "\n" + "\n")

  /** The zoom of the background, its grain, the SVG layers and the box of a diagram. */
  def plan(in: SceneInput): Jv = Draw(in, mask = false).plan

  /** The background of a style, 1080x1920: a vertical gradient, a glow, a vignette. */
  def background(style: Jv, profile: Jv): String =
    val bg = alt(style("background"), Jv.EmptyObj)
    val w = profile("video")("width")
    val h = profile("video")("height")
    val gc = style("colors").index(alt(bg("glow_color"), Str("accent")))
    val go = alt(bg("glow_opacity"), Jv.num(0))
    val vg = alt(bg("vignette"), literal("0.4").get)
    def at(k: String, default: String, size: Jv) = (alt(bg(k), literal(default).get) * size).show
    val colors = style("colors")
    Seq(
      s"""<svg xmlns="http://www.w3.org/2000/svg" width="${w.show}" height="${h.show}" viewBox="0 0 ${w.show} ${h.show}">""",
      "<defs>",
      s"""<linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${colors("bg").show}"/><stop offset="1" stop-color="${colors("surface").show}"/></linearGradient>""",
      s"""<radialGradient id="glow" gradientUnits="userSpaceOnUse" cx="${at("glow_x", "0.5", w)}" cy="${at("glow_y", "0.5", h)}" r="${at("glow_r", "0.6", w)}"><stop offset="0" stop-color="${gc.show}" stop-opacity="${go.show}"/><stop offset="1" stop-color="${gc.show}" stop-opacity="0"/></radialGradient>""",
      s"""<radialGradient id="vig" cx="0.5" cy="0.5" r="0.75"><stop offset="0.55" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity="${vg.show}"/></radialGradient>""",
      "</defs>",
      s"""<rect width="${w.show}" height="${h.show}" fill="url(#g)"/>""",
      s"""<rect width="${w.show}" height="${h.show}" fill="url(#glow)"/>""",
      s"""<rect width="${w.show}" height="${h.show}" fill="url(#vig)"/>""",
      "</svg>",
    ).map(_ + "\n").mkString

  /** What the background is drawn from, as the text of its cache key. */
  def backgroundKey(style: Jv): String =
    compact(Jv.obj("colors" -> style("colors"), "background" -> style("background"))) + "\n"

  /** A line with *emphasis* as runs; the words are the runs that no space separates. */
  def words(line: String): Vector[Word] =
    val runs = split(line, "*").zipWithIndex.collect { case (t, k) if t != "" => Run(t, k % 2 == 1) }
    final case class Open(runs: Vector[Run], closed: Boolean)
    runs.foldLeft(Vector.empty[Open]) { (ws, r) =>
      val parts = split(r.t, " ")
      parts.indices.foldLeft(ws) { (ws, i) =>
        val p = parts(i)
        if p == "" then (if ws.nonEmpty then ws.updated(ws.length - 1, ws.last.copy(closed = true)) else ws)
        else
          val added =
            if i == 0 && ws.nonEmpty && !ws.last.closed then ws.updated(ws.length - 1, ws.last.copy(runs = ws.last.runs :+ Run(p, r.emph)))
            else ws :+ Open(Vector(Run(p, r.emph)), false)
          if i < parts.length - 1 then added.updated(added.length - 1, added.last.copy(closed = true)) else added
      }
    }.map(o => Word(o.runs))

  /** libass reads { } as an override block and \ as a command; a line break would end the Dialogue
    * line. None gets through: braces become parentheses, \ becomes /, control characters a space.
    */
  def escape(s: String): String =
    fromCodepoints(codepoints(s.replace("{", "(").replace("}", ")").replace("\\", "/"))
      .map(c => if Lint.control(c) then 32 else c))

  /** A time as ASS writes it: h:mm:ss.cc. */
  def assTime(t: Double): String =
    val cs = round(t * 100)
    def mod(a: Double, b: Double) = (a.toLong % b.toLong).toDouble
    def pad2(x: Double) = { val s = jqDouble(x); if s.length < 2 then "0" + s else s }
    s"${jqDouble(math.floor(cs / 360000))}:${pad2(math.floor(mod(cs, 360000) / 6000))}:${pad2(math.floor(mod(cs, 6000) / 100))}.${pad2(mod(cs, 100))}"

  private val Hex = Str("0123456789ABCDEF")

  /** Two hex digits of a byte. */
  def hex2(v: Double): String =
    val a = math.floor(v / 16)
    val b = (v.toLong % 16).toDouble
    Hex.slice(Some(a), Some(a + 1)).show + Hex.slice(Some(b), Some(b + 1)).show

  /** "&HBBGGRR&" of "#RRGGBB", for an override tag. */
  def assColor(v: Jv): String = s"&H${bgr(v)}&"

  /** "&H00BBGGRR" of "#RRGGBB", for a style line. */
  def assStyleColor(v: Jv): String = s"&H00${bgr(v)}"

  private def bgr(v: Jv): String =
    val s = v match
      case Str(x) => Str(x.stripPrefix("#"))
      case _      => v
    def dig(c: Int) = if c >= 97 then c - 87 else if c >= 65 then c - 55 else c - 48
    Vector((0, 2), (2, 4), (4, 6)).map { (a, b) =>
      val cs = s.slice(Some(a.toDouble), Some(b.toDouble)) match
        case Str(x) => codepoints(x).map(c => Jv.num(dig(c).toDouble))
        case _      => throw JqError("explode input must be a string")
      def at(i: Int) = cs.lift(i).getOrElse(Null)
      add(mul(at(0), Jv.num(16)), at(1)).number
    }.reverse.map(hex2).mkString

  /** The alpha tag of an opacity from 0 to 1: "&HXX&". */
  def assAlpha(x: Double): String = s"&H${hex2(round((1 - math.max(0, math.min(1, x))) * 255))}&"

  private def r1(x: Double): String = jqDouble(round(x * 10) / 10)

  private val Rect = "m 0 0 l 100 0 100 100 0 100"
  private val Dot = "m 0 50 b 0 22 22 0 50 0 b 78 0 100 22 100 50 b 100 78 78 100 50 100 b 22 100 0 78 0 50"
  private val Segments = 8
  private val DiagramH = 560

  private final class Draw(in: SceneInput, mask: Boolean):
    import in.*
    private val Fade = "\\fad(0,350)"
    val W: Jv = profile("video")("width")
    val H: Jv = profile("video")("height")
    private val reg =
      val safe = profile("safe")
      val (w, h) = (W.number, H.number)
      Region(w * safe("side").number, h * safe("top").number, w * (1 - safe("side").number), h * (1 - safe("bottom").number))

    private def mot: Jv = add(style("motion"), alt(shot("motion"), Jv.EmptyObj))
    private def enterS: Jv = mot("enter_s")
    private def lay: Jv = alt(shot("text_layout"), Jv.EmptyObj)
    private def params: Jv = add(alt(beat("visual")("params"), Jv.EmptyObj), alt(shot("params"), Jv.EmptyObj))
    private lazy val easeP: Double =
      val table = Jv.obj("linear" -> Jv.num(1), "out_quad" -> Jv.num(2), "out_cubic" -> Jv.num(3), "out_quart" -> Jv.num(4))
      alt(table.index(alt(mot("ease"), Str("out_cubic"))), Jv.num(3)).number
    private def eo(u: Double): Double = 1 - Math.pow(1 - u, easeP)
    private def tscale: Double = alt(lay("scale"), Jv.num(1)).number
    private def cyb: Double = reg.y0 + reg.h * alt(lay("y"), Jv.num(0.5)).number
    private def pal: Jv =
      add(Jv.obj("main" -> Str("fg"), "emph" -> Str("accent_text"), "sub" -> Str("muted"), "bar" -> Str("accent")),
        alt(shot("palette"), Jv.EmptyObj))
    private def col(role: String): String = if mask then "&HFFFFFF&" else assColor(style("colors").index(pal(role)))
    private def fam(k: String): String = style("fonts")(k)("family").show
    private lazy val lines: Vector[String] = alt(beat("text"), Jv.EmptyArr).iter.map(_.matchable)
    private val loopEnd = last && sp("loop") == Jv.True
    private def fadeout = if loopEnd then Fade else ""
    private def at(x: Double): Double = hin + x

    // Width of a string at \fs 1, from the font's table; the size that makes it fit; line height of a size.
    private def cw(k: String, c: Int): Double =
      val w = style("fonts")(k)("w")
      (if c == 32 then w("space")
       else if (c >= 65 && c <= 90) || (c >= 192 && c <= 222) then w("upper")
       else if c >= 48 && c <= 57 then w("digit")
       else if (c >= 97 && c <= 122) || (c >= 223 && c <= 255) then w("lower")
       else w("other")).number
    private def tw(k: String, s: String): Double =
      val sum = codepoints(s.replace("*", "")).map(cw(k, _)).reduceLeftOption(_ + _).getOrElse(0.0)
      sum * (if style("fonts")(k)("bold").truthy then 1.06 else 1)
    private def fit(k: String, s: String, w: Double, cap: Double): Double =
      val a = cap * tscale
      val t = tw(k, s)
      val b = w / ((if 0.01 >= t then 0.01 else t) * 1.1)
      math.max(math.floor(if b < a then b else a), 36)
    private def fitAll(k: String, ss: Seq[String], w: Double, cap: Double): Double = ss.map(fit(k, _, w, cap)).min
    private def lh(k: String, size: Double): Double = size * style("fonts")(k)("lh").number
    private def step(n: Double): Double =
      if n <= 1 then 0
      else
        val st = mot("stagger")
        val rest = sub(Jv.num(0.65 * dur), enterS) / Jv.num(n - 1)
        max(Seq(min(Seq(st, rest)), Jv.num(0.05))).number

    private def dlg(layer: Int, t0: Double, t1: Double, sty: String, text: String): String =
      s"Dialogue: $layer,${assTime(t0)},${assTime(t1)},$sty,,0,0,0,,$text"
    private def hold(layer: Int, t0: Double, sty: String, tags: String, text: String): String =
      dlg(layer, at(t0), total, sty, "{" + tags + fadeout + "}" + text)

    /** A line that comes in over `d` seconds, from (dx, dy) away, sharpening and fading in. */
    private def enter(layer: Int, sty: String, x: Double, y: Double, dx: Double, dy: Double, tags: String,
        text: String, t0: Double, d: Jv): Vector[String] =
      val held = hold(layer, (Jv.num(t0) + d).number, sty, s"\\an5\\pos(${r1(x)},${r1(y)})" + tags, text)
      val segs = (0 until Segments).toVector.map { k =>
        val ea = eo(k.toDouble / Segments)
        val eb = eo((k + 1).toDouble / Segments)
        val from = at(t0 + (d * Jv.num(k) / Jv.num(Segments)).number)
        val to = at(t0 + (d * Jv.num(k + 1) / Jv.num(Segments)).number)
        val blur = jqDouble(round((mul(mot("blur"), Jv.num(1 - eb)) * Jv.num(10)).number) / 10)
        dlg(layer, from, to, sty,
          s"{\\an5\\move(${r1(x + dx * (1 - ea))},${r1(y + dy * (1 - ea))},${r1(x + dx * (1 - eb))},${r1(y + dy * (1 - eb))})" +
            s"\\alpha${assAlpha(eb)}\\blur$blur" + tags + "}" + text)
      }
      segs :+ held

    /** A line of text: runs in the main colour, emphasis in the accent. */
    private def lineText(s: String, base: => String = col("main")): String =
      words(s).map(_.runs.map(r => s"{\\1c${if r.emph then col("emph") else base}}" + escape(r.t)).mkString).mkString(" ")

    // Drawings (layer 0). The unit square is 100 x 100 and starts at 0: libass centres a drawing on
    // its box, and a box with negative coordinates is read as starting at the origin.
    /** A bar that grows from its centre, sideways. */
    private def bar(x: Double, y: Double, w: Double, h: Double, role: String, t0: Double, d: Double): String =
      dlg(0, at(t0), total, "Default",
        s"{\\an5\\pos(${r1(x)},${r1(y)})\\bord0\\shad0\\1c${col(role)}\\p1\\fscx0\\fscy${r1(h)}\\t(0,${jqDouble(round(d * 1000))},0.5,\\fscx${r1(w)})" +
          fadeout + "}" + Rect + "{\\p0}")
    /** A bar that grows down from its top. */
    private def barV(x: Double, y: Double, w: Double, h: Double, role: String, t0: Double, d: Double): String =
      dlg(0, at(t0), total, "Default",
        s"{\\an8\\pos(${r1(x)},${r1(y)})\\bord0\\shad0\\1c${col(role)}\\p1\\fscx${r1(w)}\\fscy0\\t(0,${jqDouble(round(d * 1000))},0.5,\\fscy${r1(h)})" +
          fadeout + "}" + Rect + "{\\p0}")
    private def dot(x: Double, y: Double, d: Double, role: String, t0: Double): String =
      dlg(0, at(t0), total, "Default",
        s"{\\an5\\pos(${r1(x)},${r1(y)})\\bord0\\shad0\\1c${col(role)}\\p1\\fscx0\\fscy0\\t(0,200,0.5,\\fscx${r1(d * 1.25)}\\fscy${r1(d * 1.25)})\\t(200,380,\\fscx${r1(d)}\\fscy${r1(d)})" +
          fadeout + "}" + Dot + "{\\p0}")
    private def tstyle(s: Double): String = s"\\fs${jqDouble(math.floor(s))}\\bord0\\shad0"

    // ---- scenes: in each, the parts joined with jq's + are made right to left, as jq makes them.

    /** Words slam in one by one, the lines centred, a bar draws under them. */
    private def kineticText: Vector[String] =
      val n = lines.length
      val ws = lines.map(words)
      val s = fitAll("title", lines, reg.w, 230)
      val l = lh("title", s)
      val bh = n * l
      val nw = ws.map(_.length).sum
      val wstep =
        if nw <= 1 then 0.0
        else max(Seq(min(Seq(mot("stagger"), Jv.num((0.65 * dur - 0.3) / (nw - 1)))), Jv.num(0.04))).number
      val under = bar(reg.cx, cyb + (bh / 2) + 70, 260, 14, "bar", (nw - 1) * wstep, 0.45)
      val evs = (0 until n).foldLeft((0, Vector.empty[String])) { case ((g0, ev), i) =>
        val y = cyb - (bh / 2) + (l * (i + 0.5))
        val body = words(lines(i)).zipWithIndex.map { (w, key) =>
          val ms = jqDouble(round((g0 + key) * wstep * 1000))
          val ms120 = jqDouble(round((g0 + key) * wstep * 1000) + 120)
          val ms300 = jqDouble(round((g0 + key) * wstep * 1000) + 300)
          val runs = w.runs.map(r => s"{\\1c${if r.emph then col("emph") else col("main")}}" + escape(r.t)).mkString
          val popY = jqDouble(round((mot("pop") * Jv.num(112)).number))
          val popX = jqDouble(round((mot("pop") * Jv.num(112)).number))
          s"{\\alpha&HFF&\\blur${mot("blur").show}\\fscx$popX\\fscy$popY\\t($ms,$ms120,\\alpha&H00&)\\t($ms,$ms300,\\blur0\\fscx100\\fscy100)}" + runs
        }.mkString(" ")
        (g0 + ws(i).length, ev :+ dlg(1, at(0), total, "Title", s"{\\an5\\pos(${r1(reg.cx)},${r1(y)})" + tstyle(s) + fadeout + "}" + body))
      }._2
      evs :+ under

    /** Title lines rise in; with params.subtitle the last line is a quieter subtitle. */
    private def titleCard: Vector[String] =
      val n = lines.length
      val ns = if alt(params("subtitle"), Jv.False).truthy && n >= 2 then 1 else 0
      val tl = lines.take(n - ns)
      val sl = lines.drop(n - ns)
      val s = fitAll("title", tl, reg.w, 200)
      val l = lh("title", s)
      val ss = if ns == 1 then fit("text", sl(0), reg.w, 72) else 0.0
      val tb = tl.length * l
      val sb = if ns == 1 then 56 + lh("text", ss) else 0.0
      val top = cyb - ((tb + 56 + sb) / 2)
      val st = step(n)
      val subtitle =
        if ns == 1 then
          enter(1, "Body", reg.cx, top + tb + 96 + (lh("text", ss) / 2), 0, 30, tstyle(ss), lineText(sl(0), col("sub")),
            tl.length * st + 0.15, enterS)
        else Vector.empty
      val under = bar(reg.cx, top + tb + 40, 220, 14, "bar", tl.length * st, 0.4)
      val title = tl.indices.toVector.flatMap(i =>
        enter(1, "Title", reg.cx, top + (l * (i + 0.5)), 0, 56, tstyle(s), lineText(tl(i)), i * st, enterS))
      title ++ Vector(under) ++ subtitle

    private def fmtn(x: Double, d: Int, sep: String): String =
      val s = jqDouble(round(x * Math.pow(10, d)))
      val z = if s.length <= d then "0" * (d - s.length + 1) + s else s
      if d == 0 then z else z.take(z.length - d) + sep + z.drop(z.length - d)

    // jq's $ also matches before a final line break; this one (RE2) only at the end.
    private val NumberLine = """^([^0-9]*)([0-9]+(?:[.,][0-9]+)?)(.*)$""".r
    private def numberIn(s: String) =
      NumberLine.findFirstMatchIn(s).orElse(Option.when(s.endsWith("\n"))(s.dropRight(1)).flatMap(NumberLine.findFirstMatchIn))

    /** Line 1 is the number, which counts up; the other lines label it. Nothing when line 1 has no
      * number (jq's capture gave no value, so the script was empty).
      */
    private def bigNumber: Option[Vector[String]] =
      val num = lines.headOption.getOrElse("").replace("*", "")
      val lab = lines.drop(1)
      numberIn(num).map { m =>
        val (pre, n, suf) = (m.group(1), m.group(2), m.group(3))
        val s1 = fit("title", num, reg.w, 760)
        val s2 = if lab.nonEmpty then fitAll("text", lab, reg.w, 66) else 0.0
        val l = lh("text", s2)
        val hn = s1 * 0.62
        val hb = lab.length * l
        val top = cyb - ((hn + (if hb > 0 then 100 + hb else 0)) / 2)
        val ny = top + (hn / 2)
        val cd = if 0.5 * dur < 0.9 then 0.5 * dur else 0.9
        val k = math.max(math.floor(cd * 15), 2).toInt
        val sep = if n.contains(",") then "," else "."
        val nn = n.replace(",", ".")
        val v = literal(nn).map(_.d).getOrElse(throw JqError(s"${Str(nn).named} cannot be parsed as a number"))
        val parts = split(nn, ".")
        val d = if parts.length > 1 then codepoints(parts(1)).length else 0
        val count = (0 until k).toVector.map { j =>
          dlg(1, at(cd * j / k), at(cd * (j + 1) / k), "Title",
            s"{\\an5\\pos(${r1(reg.cx)},${r1(ny)})" + tstyle(s1) + s"\\1c${col("emph")}}" + escape(pre) +
              fmtn(v * eo((j + 0.5) / k), d, sep) + escape(suf))
        }
        val labels =
          if hb > 0 then
            val ls = lab.indices.toVector.flatMap(i =>
              enter(1, "Body", reg.cx, top + hn + 100 + (l * (i + 0.5)), 0, 34, tstyle(s2), lineText(lab(i)),
                cd * 0.7 + 0.2 + (i * 0.15), enterS))
            bar(reg.cx, top + hn + 40, 160, 10, "bar", cd * 0.7, 0.35) +: ls
          else Vector.empty
        val held = hold(1, cd, "Title",
          s"\\an5\\pos(${r1(reg.cx)},${r1(ny)})" + tstyle(s1) + s"\\1c${col("emph")}" + "\\fscx108\\fscy108\\t(0,260,0.5,\\fscx100\\fscy100)",
          escape(pre) + n + escape(suf))
        count ++ Vector(held) ++ labels
      }

    /** Each line is a bullet, sliding in from the left. */
    private def bulletReveal: Vector[String] =
      val n = lines.length
      val s = fitAll("title", lines, reg.w - 80, 150)
      val mw = lines.map(tw("title", _) * s).max
      val x0 = reg.cx - ((mw + 70) / 2)
      val gap = s * 1.0
      val y0 = cyb - ((n - 1) * gap / 2)
      val st = step(n)
      (0 until n).toVector.flatMap { i =>
        val y = y0 + (gap * i)
        val d = dot(x0 + 14, y, 26, "bar", i * st)
        d +: enter(1, "Title", x0 + 70 + ((tw("title", lines(i)) * s) / 2), y, -70, 0, tstyle(s), lineText(lines(i)), i * st, enterS)
      }

    /** A big quotation mark, then the lines fade in one after the other. */
    private def quote: Vector[String] =
      val n = lines.length
      val na = if alt(params("attribution"), Jv.False).truthy && n >= 2 then 1 else 0
      val ql = lines.take(n - na)
      val al = lines.drop(n - na)
      val s = fitAll("text", ql, reg.w, 100)
      val l = lh("text", s)
      val qb = ql.length * l
      val top = cyb - ((qb + (if na == 1 then 100 else 0) + 190) / 2)
      val st = step(n)
      val attribution =
        if na == 1 then
          val e = enter(1, "Body", reg.cx + 30, top + 220 + qb + 50, 0, 20, tstyle(s * 0.6), lineText(al(0), col("sub")),
            0.15 + (ql.length * st), enterS)
          bar(reg.cx - 200, top + 220 + qb + 50, 60, 8, "bar", 0.15 + (ql.length * st), 0.3) +: e
        else Vector.empty
      val body = ql.indices.toVector.flatMap(i =>
        enter(1, "Body", reg.cx, top + 220 + (l * (i + 0.5)), 0, 30, tstyle(s), lineText(ql(i)), 0.15 + (i * st), enterS))
      val mark = dlg(1, at(0), total, "Title",
        s"{\\an5\\pos(${r1(reg.cx)},${r1(top + 90)})\\fs420\\bord0\\shad0\\1c${col("bar")}\\alpha&HFF&\\t(0,300,\\alpha&H00&)" +
          fadeout + "}" + "“")
      Vector(mark) ++ body ++ attribution

    /** Two panels with a line between: the first lines are the quiet panel, the rest the point. */
    private def splitCompare: Vector[String] =
      val n = lines.length
      val k = sort(Seq(alt(params("split"), Jv.num(math.ceil(n / 2.0))), Jv.num(1), Jv.num(n - 1)))(1)
      val all = Jv.Arr(lines.map(Str(_)))
      def strs(v: Jv) = v.items.map(_.matchable)
      val topL = strs(all.slice(Some(0), Some(k.number)))
      val botL = strs(all.slice(Some(k.number), None))
      val off = cyb - reg.cy
      val yt = reg.y0 + (reg.h * 0.25) + off
      val yb = reg.y0 + (reg.h * 0.75) + off
      val s1 = fitAll("title", topL, reg.w, 130)
      val s2 = fitAll("title", botL, reg.w, 180)
      val l1 = lh("title", s1)
      val l2 = lh("title", s2)
      val g = max(Seq(mot("stagger"), Jv.num(0.3))).number
      val bottom = botL.indices.toVector.flatMap(i =>
        enter(1, "Title", reg.cx, yb - ((botL.length * l2) / 2) + (l2 * (i + 0.5)), 0, 40, tstyle(s2), lineText(botL(i)),
          g + 0.35 + (i * 0.12), enterS))
      val line = bar(reg.cx, (yt + yb) / 2, 760, 8, "bar", g, 0.45)
      val upper = topL.indices.toVector.flatMap(i =>
        enter(1, "Title", reg.cx, yt - ((topL.length * l1) / 2) + (l1 * (i + 0.5)), 0, 40, tstyle(s1),
          lineText(topL(i), col("sub")), i * 0.12, enterS))
      upper ++ Vector(line) ++ bottom

    /** Lines are "when: label". A line grows down, a dot and a pair of lines come in for each. */
    private def timeline: Vector[String] =
      val items = lines.map { l =>
        val parts = split(l, ": ")
        (parts.headOption.getOrElse(""), parts.drop(1).mkString(": "))
      }
      val n = items.length
      val per = div(Jv.num(reg.h - 100), Jv.num(n)).number
      val gap = if per < 280 then per else 280.0
      val y0 = cyb - ((n - 1) * gap / 2)
      val width = reg.w - 110
      val s1 = fitAll("title", items.map(_._1), width, 150)
      val s2 = fitAll("text", items.map(_._2), width, 84)
      val mw = math.max(items.map(e => tw("title", e._1) * s1).max, items.map(e => tw("text", e._2) * s2).max)
      val lx = reg.cx - ((mw + 70) / 2)
      val tx = lx + 70
      val st = step(n)
      val marks = (0 until n).toVector.flatMap { i =>
        val y = y0 + (gap * i)
        val (when, label) = items(i)
        val d = dot(lx, y, 30, "bar", i * st)
        val w = enter(1, "Title", tx + ((tw("title", when) * s1) / 2), y - (s1 * 0.34), 40, 0, tstyle(s1),
          lineText(when, col("emph")), i * st, enterS)
        val b = enter(1, "Body", tx + ((tw("text", label) * s2) / 2), y + (s1 * 0.42), 40, 0, tstyle(s2), lineText(label),
          i * st + 0.1, enterS)
        (d +: w) ++ b
      }
      barV(lx, y0, 8, (n - 1) * gap, "sub", 0, 0.65 * dur) +: marks

    /** SVG layers come in one by one above (see the plan), a caption line for each below. */
    private def diagramReveal: Vector[String] =
      val n = lines.length
      val nl = params("layers").length.number
      val m = math.max(n, nl)
      val s = fitAll("text", lines, reg.w, 84)
      val l = lh("text", s)
      val cy0 = cyb - reg.cy + reg.y0 + DiagramH + 70
      val st = step(m)
      (0 until n).toVector.flatMap(i =>
        enter(1, "Body", reg.cx, cy0 + (l * (i + 0.5)), 0, 30, tstyle(s), lineText(lines(i)),
          0.15 + math.min(i, nl - 1) * st + (if i >= nl then (i - nl + 1) * 0.2 else 0), enterS))

    /** The closing lines; the last one is the handle, with a bar. In a loop reel the picture fades
      * out on the last beat, so the last frame is the empty sheet the first beat starts from.
      */
    private def outroLoop: Vector[String] =
      val n = lines.length
      val s = if n >= 2 then fitAll("title", lines.take(n - 1), reg.w, 190) else 0.0
      val sh = fit("title", lines(n - 1), reg.w, 170)
      val l = lh("title", s)
      val lhh = lh("title", sh)
      val top = cyb - (((n - 1) * l + lhh + 70) / 2)
      val st = step(n)
      val under = bar(reg.cx, top + ((n - 1) * l) + lhh + 36, 220, 12, "bar", (n - 1) * st + 0.1, 0.45)
      val handle = enter(1, "Title", reg.cx, top + ((n - 1) * l) + (lhh / 2), 0, 50, tstyle(sh), lineText(lines(n - 1), col("emph")),
        (n - 1) * st, enterS)
      val rest = (0 until n - 1).toVector.flatMap(i =>
        enter(1, "Title", reg.cx, top + (l * (i + 0.5)), 0, 50, tstyle(s), lineText(lines(i)), i * st, enterS))
      rest ++ handle ++ Vector(under)

    def events(): Option[Vector[String]] =
      val scene = beat("visual")("scene")
      SceneKind.parse(scene) match
        case Some(SceneKind.KineticText)   => Some(kineticText)
        case Some(SceneKind.TitleCard)     => Some(titleCard)
        case Some(SceneKind.BigNumber)     => bigNumber
        case Some(SceneKind.BulletReveal)  => Some(bulletReveal)
        case Some(SceneKind.Quote)         => Some(quote)
        case Some(SceneKind.SplitCompare)  => Some(splitCompare)
        case Some(SceneKind.Timeline)      => Some(timeline)
        case Some(SceneKind.DiagramReveal) => Some(diagramReveal)
        case Some(SceneKind.OutroLoop)     => Some(outroLoop)
        case None                          => throw JqError(s"unknown scene ${scene.show}")

    def header: String =
      val c = style("colors")
      def styleLine(name: String, font: String, size: Int, bold: String) =
        s"Style: $name,${fam(font)},$size,${assStyleColor(c("fg"))},${assStyleColor(c("fg"))},${assStyleColor(c("bg"))},${assStyleColor(c("bg"))},$bold,0,0,0,100,100,0,0,1,0,0,5,0,0,0,1"
      def bold(font: String) = if style("fonts")(font)("bold").truthy then "-1" else "0"
      Seq(
        "[Script Info]",
        s"; beat ${beat("id").show}, scene ${beat("visual")("scene").show}",
        "ScriptType: v4.00+",
        s"PlayResX: ${W.show}",
        s"PlayResY: ${H.show}",
        "WrapStyle: 2",
        "ScaledBorderAndShadow: yes",
        "",
        "[V4+ Styles]",
        "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding",
        styleLine("Default", "text", 60, "0"),
        styleLine("Title", "title", 100, bold("title")),
        styleLine("Body", "text", 60, bold("text")),
        "",
        "[Events]",
        "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text",
      ).mkString("\n")

    def plan: Jv =
      val ls = alt(params("layers"), Jv.EmptyArr)
      val zoom = alt(shot("camera")("zoom"), style("motion")("bg_zoom"))
      Jv.obj(
        "zoom" -> (if loopEnd then Jv.arr(zoom(1.0), zoom(0.0)) else zoom),
        "grain" -> style("motion")("grain"),
        "layers" -> Jv.Arr(ls.entries.map { (k, v) =>
          val svg = v match
            case Str(s) if Lint.full(s, Lint.LayerName) => v
            case _ => throw JqError(s"layer ${compact(v)}: write direction/svg/<name>.svg")
          val st = step(max(Seq(ls.length, Jv.num(lines.length))).number)
          Jv.obj("svg" -> svg, "at" -> (Jv.num(hin) + add(literal("0.15").get, k * Jv.num(st))))
        }.map(_ + Jv.obj("fade" -> literal("0.35").get))),
        "diagram" -> Jv.obj("y0" -> Jv.num(cyb - reg.cy + reg.y0), "h" -> Jv.num(DiagramH), "w" -> Jv.num(math.floor(reg.w))),
      )
