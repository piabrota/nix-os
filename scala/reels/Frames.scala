package piabrota.reels

import Json.*
import Jv.Str

/** The frame plan of a reel and where QA looks at it. They were timeline.jq and qaplan.jq. */
object Frames:
  /** One cut a beat. The beats are cut at round(t * fps), so the reel has exactly format * fps
    * frames, whatever the decimals of the screenplay. A cut is a one-frame blend (hin 1, hout 0 on
    * its sides); a fade has an even length, centred on the boundary: half in each clip.
    */
  def timeline(sp: Jv, profile: Jv): Vector[Cut] =
    val fps = profile("video")("fps")
    final case class B(id: Jv, tr: Jv, s: Double, e: Double, dq: Double, a: Double)
    val b = sp("beats").iter.map { x =>
      val tr = alt(x("transition"), Str(Cut.Hard))
      val q = round((alt(x("transition_s"), profile("transition")("default_s")) * fps).number)
      val dq =
        if tr === Str(Cut.Hard) then 1.0
        else
          val m = math.max(q, 2.0)
          if m.toLong % 2 == 1 then m + 1 else m
      B(x("id"), tr, round((x("t_in") * fps).number), round((x("t_out") * fps).number), dq,
        if tr === Str(Cut.Hard) then 1.0 else dq / 2)
    }
    val n = b.length
    val f = fps.number
    b.indices.toVector.map { i =>
      val x = b(i)
      val hin = if i == 0 then 0.0 else x.a
      val hout = if i == n - 1 then 0.0 else b(i + 1).dq - b(i + 1).a
      Cut(plain(x.id), plain(x.tr), x.s, x.e, hin, hout, hin + (x.e - x.s) + hout, if i == 0 then 0.0 else x.dq,
        if i == 0 then 0.0 else (x.s - x.a) / f)
    }

  /** Where QA looks at each beat: at qa.probe_frac of it, moved clear of the two transitions that
    * overlap it, so the frame shows the beat and not a blend; and the first frame of the beat.
    */
  def probes(tl: Vector[Cut], sp: Jv, profile: Jv): Vector[Probe] =
    val fps = profile("video")("fps").number
    val pf = profile("qa")("probe_frac").number
    def r3(d: Double) = jqDouble(round(d * 1000) / 1000)
    tl.indices.toVector.map { i =>
      val t = tl(i)
      val aout = tl.lift(i + 1).map(_.hin).getOrElse(0.0)
      val lo = t.s + t.hin + 1
      val hi = t.e - aout - 2
      val want = t.s + round((t.e - t.s) * pf)
      val p = if lo > hi then want else if want < lo then lo else if want > hi then hi else want
      val text = alt(sp("beats")(i.toDouble)("text"), Jv.EmptyArr)
      Probe(t.id, r3(p / fps), r3(t.s / fps), text.length > Jv.num(0))
    }
