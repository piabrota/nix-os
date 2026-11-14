package piabrota.reels

import Json.*
import Jv.Str

/** The first drafts the toolkit writes: the empty screenplay of `reel new` and the default
  * shotlist. They were skeleton.jq and shotlist.jq.
  */
object Drafts:
  private def n(text: String): Jv = literal(text).getOrElse(throw IllegalArgumentException(text))

  /** One beat of the skeleton: every text a TODO that the lint refuses. */
  private def beat(id: String, t0: String, t1: String, role: String, scene: SceneKind, tr: String): Jv =
    Jv.obj(
      "id" -> Str(id), "t_in" -> n(t0), "t_out" -> n(t1), "role" -> Str(role),
      "visual" -> Jv.obj("describe" -> Str("TODO: what is on screen"), "scene" -> Str(scene.key), "params" -> Jv.EmptyObj),
      "text" -> Jv.arr(Str("TODO")),
      "sound" -> Jv.obj("music" -> Str(MusicLevel.On.key), "sfx" -> Jv.EmptyArr),
      "transition" -> Str(tr),
      "note" -> Str(""),
    )

  /** The empty screenplay of `reel new`, with the shape of a 15 or a 30 s reel. */
  def skeleton(slug: String, format: Jv): Jv =
    import SceneKind.*
    val short = format === Jv.num(15)
    val fade = "fade"
    Jv.obj(
      "schema" -> Str(Schema.Screenplay),
      "slug" -> Str(slug),
      "title" -> Str("TODO"),
      "format" -> format,
      "logline" -> Str("TODO: one sentence, the whole reel"),
      "audience" -> Str("TODO: who watches, and where"),
      "language" -> Str("TODO"),
      "loop" -> Jv.False,
      "claims" -> Jv.EmptyArr,
      "look" -> Jv.obj("style" -> Str("piabrota")),
      "music" -> Jv.obj("preset" -> Str(MusicPreset.Pulse.key), "bpm" -> n(if short then "112" else "96")),
      "beats" -> Jv.Arr(
        if short then Vector(
          beat("b01", "0", "2.5", Role.Hook, KineticText, Cut.Hard),
          beat("b02", "2.5", "6", "setup", TitleCard, fade),
          beat("b03", "6", "10", "turn", KineticText, fade),
          beat("b04", "10", "12.8", "payoff", BulletReveal, fade),
          beat("b05", "12.8", "15", Role.Cta, OutroLoop, fade))
        else Vector(
          beat("b01", "0", "2.8", Role.Hook, KineticText, Cut.Hard),
          beat("b02", "2.8", "6.8", "setup", TitleCard, fade),
          beat("b03", "6.8", "11.3", "setup", BulletReveal, fade),
          beat("b04", "11.3", "15.3", "turn", SplitCompare, fade),
          beat("b05", "15.3", "19.8", "proof", BigNumber, fade),
          beat("b06", "19.8", "23.8", "proof", Timeline, fade),
          beat("b07", "23.8", "27.3", "payoff", Quote, fade),
          beat("b08", "27.3", "30", Role.Cta, OutroLoop, fade))),
    )

  /** The example screenplay under another slug (jq's `.slug = $slug`). */
  def example(sp: Jv, slug: String): Jv = sp match
    case Jv.Obj(fs) => Jv.Obj(fs.updated("slug", Str(slug)))
    case Jv.Null    => Jv.obj("slug" -> Str(slug))
    case _          => throw JqError(s"Cannot index ${sp.typeName} with \"slug\"")

  /** The default shotlist: one shot a beat, the look taken from the style. The creative director
    * starts from it and changes what the picture needs.
    */
  def shotlist(sp: Jv, style: Jv, hash: String): Jv =
    val motion = style("motion")
    Jv.obj(
      "schema" -> Str(Schema.Shotlist),
      "slug" -> sp("slug"),
      RenderClaim.ScreenplaySha -> Str(hash),
      "shots" -> Jv.Arr(sp("beats").iter.map { b =>
        Jv.obj(
          "beat" -> b("id"),
          "scene" -> b("visual")("scene"),
          "kind" -> Str(ShotKind.Flat.key),
          "params" -> Jv.EmptyObj,
          "camera" -> Jv.obj("zoom" -> motion("bg_zoom")),
          "motion" -> Jv.obj("ease" -> motion("ease"), "stagger" -> motion("stagger"), "enter_s" -> motion("enter_s"),
            "pop" -> motion("pop"), "blur" -> motion("blur")),
          "text_layout" -> Jv.obj("y" -> n("0.5"), "scale" -> n("1")),
          "palette" -> Jv.obj("main" -> Str("fg"), "emph" -> Str("accent_text"), "sub" -> Str("muted"), "bar" -> Str("accent")),
          "transition" -> b("transition"),
          "note" -> Str(""),
        )
      }),
    )
