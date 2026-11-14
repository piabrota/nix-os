package piabrota.reels

import Json.*
import Jv.{Null, Str}

/** What QA measured, besides the ffprobe JSON of the file: the loudnorm measurement (null when the
  * file has no audio), the byte offsets of the moov and mdat boxes (-1 when missing), the measured
  * beats, the box drawn at qa.hook_probe_s, and the hashes of the file, of the approved screenplay
  * and of what render.json names.
  */
final case class QaFacts(slug: String, format: Jv, loud: Jv, moov: Long, mdat: Long, beats: Vector[Jv],
    hook: String, reelSha: String, spSha: String, renderSha: String, renderReel: String)

/** qa.json. Every number is read from the file; a field that is missing makes its check fail, not
  * the report. `pass` is true only when every check and every beat passes. It was qareport.jq.
  */
object QaReport:
  private def chk(name: String, ok: Boolean, got: Jv, want: Jv): Jv =
    Jv.obj("name" -> Str(name), "pass" -> Jv.Bool(ok), "got" -> got, "want" -> want)

  /** loudnorm prints "-inf" for digital silence: that is a very low number, not a parse error. */
  private def level(v: Jv): Jv = v match
    case _: Jv.Num        => v
    case Str("-inf")      => Jv.num(-99)
    case Str("inf")       => Jv.num(99)
    case _                => try tonumber(v) catch case _: JqError => Null

  private def str(s: String): Jv = Str(s)
  private def first8(s: String): String = s.take(8)

  def report(probe: Jv, profile: Jv, f: QaFacts): Jv =
    val streams = alt(probe("streams"), Jv.EmptyArr).iter
    val vs = streams.filter(_("codec_type") === str("video"))
    val as = streams.filter(_("codec_type") === str("audio"))
    val v = alt(vs.headOption.getOrElse(Null), Jv.EmptyObj)
    val a = alt(as.headOption.getOrElse(Null), Jv.EmptyObj)
    val fm = alt(probe("format"), Jv.EmptyObj)
    val pv = profile("video")
    val pa = profile("audio")
    val qa = profile("qa")
    val fmt = f.format
    val dur = tonumber(alt(fm("duration"), str("0")))
    val lufs = if f.loud == Null then Null else level(f.loud("input_i"))
    val tp = if f.loud == Null then Null else level(f.loud("input_tp"))
    val adur = tonumber(alt(a("duration"), str("0")))
    def near(x: Jv, tol: Jv) = Jv.num(math.abs((x - fmt).number)) <= tol
    def shown(sha: String) = if first8(sha).isEmpty then "no render.json" else first8(sha)
    val peak = pa("true_peak") + pa("true_peak_slack")
    val checks = Vector(
      chk("container", alt(fm("format_name"), str("")).show.contains("mp4"), fm("format_name"), str("mp4")),
      chk("streams", vs.length == 1 && as.length == 1, str(s"${vs.length} video, ${as.length} audio"), str("1 video, 1 audio")),
      chk("video codec", v("codec_name") === pv("codec"), v("codec_name"), pv("codec")),
      chk("size", v("width") === pv("width") && v("height") === pv("height"),
        str(s"${v("width").show}x${v("height").show}"), str(s"${pv("width").show}x${pv("height").show}")),
      chk("pixel aspect", alt(v("sample_aspect_ratio"), str("1:1")) === str("1:1"), alt(v("sample_aspect_ratio"), str("1:1")), str("1:1")),
      chk("pixel format", v("pix_fmt") === pv("pix_fmt"), v("pix_fmt"), pv("pix_fmt")),
      chk("frame rate", v("r_frame_rate") === str(s"${pv("fps").show}/1"), v("r_frame_rate"), str(s"${pv("fps").show}/1")),
      chk("frames", tonumber(alt(v("nb_frames"), str("0"))) === fmt * pv("fps"), v("nb_frames"), fmt * pv("fps")),
      chk("duration", near(dur, qa("duration_tolerance_s")), dur, str(s"${fmt.show} +- ${qa("duration_tolerance_s").show}")),
      chk("audio codec", a("codec_name") === pa("codec"), alt(a("codec_name"), str("none")), pa("codec")),
      chk("audio rate", tonumber(alt(a("sample_rate"), str("0"))) === pa("rate"), alt(a("sample_rate"), str("none")), pa("rate")),
      chk("audio channels", a("channels") === pa("channels"), alt(a("channels"), str("none")), pa("channels")),
      chk("audio length", near(adur, qa("audio_tolerance_s")), adur, str(s"${fmt.show} +- ${qa("audio_tolerance_s").show}")),
      chk("faststart (moov before mdat)", f.moov >= 0 && f.mdat >= 0 && f.moov < f.mdat,
        str(s"moov at ${f.moov}, mdat at ${f.mdat}"), str("moov first")),
      chk("loudness (LUFS)", lufs != Null && Jv.num(math.abs((lufs - pa("target_lufs")).number)) <= pa("lufs_tolerance"),
        alt(lufs, str("no audio")), str(s"${pa("target_lufs").show} +- ${pa("lufs_tolerance").show}")),
      chk("true peak (dBTP)", tp != Null && tp <= peak, alt(tp, str("no audio")), str(s"at most ${peak.show}")),
      chk("made from the approved screenplay", f.renderSha == f.spSha, str(shown(f.renderSha)), str(first8(f.spSha))),
      chk("is the file that reel render wrote", f.renderReel == f.reelSha, str(shown(f.renderReel)), str(first8(f.reelSha))),
      chk(s"hook picture at ${qa("hook_probe_s").show} s", f.hook != Box.Empty, str(f.hook), str("something drawn")),
    )
    val bad = f.beats.filter(b => !b("pass").truthy)
    val failures =
      checks.filter(c => !c("pass").truthy).map(c => str(s"${c("name").show}: got ${c("got").show}, want ${c("want").show}")) ++
        bad.flatMap(b => b("problems").iter.map(p => str(s"beat ${b("id").show}: ${p.show}")))
    Jv.obj(
      "schema" -> str(Schema.Qa),
      "slug" -> str(f.slug),
      "format" -> fmt,
      "pass" -> Jv.Bool(checks.forall(_("pass").truthy) && bad.isEmpty),
      RenderClaim.ReelSha -> str(f.reelSha),
      RenderClaim.ScreenplaySha -> str(f.spSha),
      "facts" -> Jv.obj(
        "bytes" -> tonumber(alt(fm("size"), str("0"))),
        "duration_s" -> dur,
        "size" -> str(s"${v("width").show}x${v("height").show}"),
        "fps" -> v("r_frame_rate"),
        "video" -> str(s"${v("codec_name").show} ${alt(v("profile"), str("")).show} ${v("pix_fmt").show}"),
        "audio" -> str(s"${a("codec_name").show} ${a("sample_rate").show} Hz ${a("channels").show} ch"),
        "bit_rate" -> tonumber(alt(fm("bit_rate"), str("0"))),
      ),
      "loudness" -> Jv.obj("lufs" -> lufs, "true_peak_dbtp" -> tp,
        "lra" -> (if f.loud == Null then Null else level(f.loud("input_lra")))),
      "checks" -> Jv.Arr(checks),
      "beats" -> Jv.Arr(f.beats),
      "failures" -> Jv.Arr(failures),
    )

  /** The lines QA prints: each check, each beat, each failure. */
  def lines(report: Jv): Vector[String] =
    def verdict(x: Jv) = if x("pass").truthy then "pass" else "FAIL"
    report("checks").iter.map(c => s"${verdict(c)}  ${c("name").show}: ${c("got").show}") ++
      report("beats").iter.map(b =>
        s"${verdict(b)}  beat ${b("id").show} at ${b("probe_s").show} s: drawn ${b("drawn").show}, luminance range ${b("luminance_range").show}") ++
      report("failures").iter.map(x => s"  -> ${x.show}")
