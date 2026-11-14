package piabrota.reels

import Json.*
import Jv.{Null, Str}

/** The rules of the screenplay and of the shotlist. Each finding is an error (it blocks `reel
  * approve`) or a warning; every number comes from the profile. The rules read the file as JSON of
  * any shape and fail closed: a file that they cannot read is an error, never a pass. They were jq
  * programs (lint.jq, shotlint.jq); the checks, their order and their words are the same.
  */
object Lint:
  private def e(rule: String, beat: Jv, msg: String) = Finding(Level.Error, beatText(beat), rule, msg)
  private def w(rule: String, beat: Jv, msg: String) = Finding(Level.Warn, beatText(beat), rule, msg)
  private def beatText(b: Jv) = if b.truthy then plain(b) else Finding.NoBeat
  private def when(cond: Boolean)(f: => Finding): Seq[Finding] = if cond then Seq(f) else Nil

  private def r3(v: Jv): Jv = Jv.num(round((v * Jv.num(1000)).number) / 1000)
  private def plainText(v: Jv): String = v.matchable.replace("*", "")
  private def blank(v: Jv): Boolean = v match
    case Str(s) => codepoints(s).forall(isSpace)
    case _      => true
  private def len(s: String): Int = s.codePointCount(0, s.length)
  private def pad2(n: Int): String = if n < 10 then s"0$n" else n.toString
  private def inList(list: Jv, x: Jv): Boolean = list.indexOf(x) != Null
  private def names(list: Jv): String = join(list.iter, ", ")

  /** Control characters, and the line and paragraph separators of Unicode. */
  def control(c: Int): Boolean = c < 32 || (c >= 127 && c <= 159) || c == 8232 || c == 8233
  /** A symbol, an emoji or a joiner: the two fonts do not cover them (U+2600 and up, U+200D, U+FE0F). */
  private def noFont(c: Int): Boolean = c >= 9728 || c == 8205 || c == 65039

  /** Every value of a JSON tree, the tree first (jq's `..`). */
  private def all(v: Jv): Vector[Jv] = v +: (v match
    case Jv.Arr(xs) => xs.flatMap(all)
    case Jv.Obj(fs) => fs.values.toVector.flatMap(all)
    case _          => Vector.empty)
  private def strings(v: Jv): Vector[String] = all(v).collect { case Str(s) => s }

  /** `\bTODO\b`, where a letter, a mark, a digit or `_` of any script is a word character. */
  private def hasTodo(s: String): Boolean =
    def word(c: Int) = Character.isLetterOrDigit(c) || c == '_' || Character.getType(c) == Character.NON_SPACING_MARK ||
      Character.getType(c) == Character.COMBINING_SPACING_MARK || Character.getType(c) == Character.ENCLOSING_MARK ||
      Character.getType(c) == Character.CONNECTOR_PUNCTUATION
    val cs = codepoints(s)
    cs.indices.exists(i => cs.slice(i, i + 4) == codepoints("TODO") && (i == 0 || !word(cs(i - 1))) &&
      (i + 4 == cs.length || !word(cs(i + 4))))

  /** `^\s|\s$`: jq's `^` is the start of the text, its `$` the end or a last line break, which is a
    * space itself.
    */
  private def edgeSpace(s: String): Boolean =
    val cs = codepoints(s)
    cs.nonEmpty && (isSpace(cs.head) || isSpace(cs.last))

  private val SlugRule = "[a-z0-9][a-z0-9-]{0,40}"
  private val LanguageRule = "[a-z]{2}(-[A-Za-z]{2,4})?"
  private val PaletteKey = "[a-z_]{1,20}"
  private val PaletteColour = "#[0-9A-Fa-f]{6}"
  /** A layer of a diagram: an SVG file of the project's direction/svg/. */
  val LayerName = "direction/svg/[a-z0-9][a-z0-9_.-]*\\.svg"
  /** Matches the whole string; the rules write no line break in a name. */
  def full(s: String, rule: String): Boolean = !s.contains('\n') && s.matches(rule)

  private val TopKeys = Set("schema", "slug", "title", "format", "logline", "audience", "language", "claims", "look",
    "music", "loop", "beats")
  private val BeatKeys = Set("id", "t_in", "t_out", "role", "visual", "text", "sound", "transition", "transition_s",
    "claims", "note")
  private val TextScenes = Seq(SceneKind.TitleCard, SceneKind.BigNumber, SceneKind.Quote, SceneKind.KineticText,
    SceneKind.OutroLoop, SceneKind.DiagramReveal).map(k => Str(k.key))

  /** The findings of one screenplay; `styles` are the names of the style files. */
  def screenplay(sp: Jv, profile: Jv, styles: Seq[String]): Seq[Finding] = sp match
    case _: Jv.Obj =>
      try
        // jq evaluates the right side of `+` first, so the beats are read before the top level.
        val beats =
          if sp("beats").typeName != "array" || sp("beats").size == 0 then Seq(e("beats", Null, "beats must be a non-empty array"))
          else beatChecks(sp, profile)
        topChecks(sp, profile, styles) ++ beats
      catch case JqError(msg) => Seq(e("lint", Null, s"the rules cannot read this file: $msg"))
    case _ => Seq(e("schema", Null, "the file must hold one JSON object"))

  private def hasMusic(sp: Jv): Boolean =
    alt(sp("music") match { case o: Jv.Obj => o("preset"); case _ => Null }, Str(MusicPreset.NoMusic)) != Str(MusicPreset.NoMusic) &&
      sp("beats").iterOpt.collect { case b: Jv.Obj => b("sound") }.collect { case s: Jv.Obj => s }
        .exists(s => !(alt(s("silence"), Jv.False) === Jv.True) && !(alt(s("music"), Str(MusicLevel.On.key)) === Str(MusicLevel.Off.key)))

  private def hasSfx(sp: Jv): Boolean =
    sp("beats").iterOpt.collect { case b: Jv.Obj => b("sound") }.collect { case s: Jv.Obj => alt(s("sfx"), Jv.EmptyArr) }
      .collect { case a: Jv.Arr => a.items }.exists(_.nonEmpty)

  private def topChecks(sp: Jv, p: Jv, styles: Seq[String]): Seq[Finding] =
    def reqStr(k: String) = when(blank(sp(k)))(e("fields", Null, s"$k must be a non-empty string"))
    val styleList = Jv.Arr(styles.toVector.map(Str(_)))
    val language = alt(sp("language"), Str(""))
    val look = sp("look")
    Seq(
      when(!(sp("schema") === Str(Schema.Screenplay)))(e("schema", Null, s"schema must be \"${Schema.Screenplay}\"")),
      when(sp("slug") match { case Str(s) => !full(s, SlugRule); case _ => true })(
        e("slug", Null, "slug: lowercase letters, digits and - only, 1 to 41 characters")),
      reqStr("title"), reqStr("logline"), reqStr("audience"),
      when(language match { case Str(s) => !full(s, LanguageRule); case _ => true })(
        e("language", Null, "language must be set, as a code like pt-BR or en")),
      when(!sp("format").isNum || !inList(p("formats"), sp("format")))(
        e("format", Null, s"format must be one of ${join(p("formats").iter.map(f => Str(f.show)), ", ")} (seconds)")),
      when(sp("loop").typeName != "boolean")(e("loop", Null, "loop must be true or false")),
      if look.typeName != "object" || look("style").typeName != "string" then
        Seq(e("look", Null, s"look.style must name a style: ${styles.mkString(", ")}"))
      else when(!inList(styleList, look("style")))(e("look", Null, s"unknown style ${look("style").show}: use ${styles.mkString(", ")}")),
      sp.keysUnsorted.filterNot(k => TopKeys(k.show)).map(k => w("keys", Null, s"unknown top-level key: ${k.show}")),
      when(all(sp).exists { case o: Jv.Obj => o.has("vo"); case _ => false } && !p("voice").truthy)(
        e("voice", Null, "vo (voice-over) is not enabled: profile.voice is false")),
      when(strings(sp).exists(hasTodo))(e("placeholder", Null, "the file still has a TODO")),
      // What the file says reaches captions, a terminal and the outbox: no control character, no
      // string of a size that no reel needs.
      when(strings(sp).exists(s => codepoints(s).exists(control)))(
        e("text", Null, "a string has a control character (a line break, a tab, an escape): one line is one string")),
      when(strings(sp).exists(len(_) > 1000))(e("text", Null, "a string has more than 1000 characters")),
      when(strings(sp).exists(s => codepoints(s).exists(noFont)))(
        w("text", Null, "a string has a symbol or an emoji that the fonts (Inter, Fjalla One) may not draw")),
      if look.typeName == "object" && look.has("palette") then
        look("palette") match
          case pal: Jv.Obj =>
            pal.entries.filter { (k, v) =>
              !full(k.show, PaletteKey) || v.typeName != "string" || !full(v.show, PaletteColour)
            }.map((k, _) => e("look", Null, s"look.palette.${k.show}: a colour name and a value like #RRGGBB"))
          case _ => Seq(e("look", Null, "look.palette must be an object of colour overrides"))
      else Nil,
      when(sp("beats").typeName == "array" && !(hasMusic(sp) || hasSfx(sp)))(
        e("sound", Null, "the reel has no sound at all (no music, no effect): QA holds the loudness to a target, so it would never pass")),
      claimChecks(sp, p),
      musicCheck(sp, p),
    ).flatten

  private def claimChecks(sp: Jv, p: Jv): Seq[Finding] = sp("claims") match
    case claims: Jv.Arr =>
      claims.entries.flatMap { (k, c) =>
        val i = k.number.toInt
        c match
          case _: Jv.Obj =>
            def name = alt(c("id"), Jv.num(i + 1)).show
            Seq(
              when(blank(c("id")))(e("claims", Null, s"claim ${i + 1} has no id")),
              when(blank(c("text")))(e("claims", Null, s"claim $name has no text")),
              when(blank(c("source")))(e("claims", Null, s"claim $name has no source: write a source or \"own\"")),
              if !inList(p("claim_status"), c("status")) then
                Seq(e("claims", Null, s"claim $name: status must be one of ${names(p("claim_status"))}"))
              else if c("status") === Str("needs-check") then Seq(e("claims", Null, s"claim $name still needs a check: give a source or own"))
              else if (c("source") === Str("own")) != (c("status") === Str("own")) then
                Seq(e("claims", Null, s"claim $name: status own goes with source own, and no other"))
              else Nil,
            ).flatten
          case _ => Seq(e("claims", Null, s"claim ${i + 1} is not an object"))
      }
    case _ => Seq(e("claims", Null, "claims must be an array (it may be empty)"))

  private def musicCheck(sp: Jv, p: Jv): Seq[Finding] =
    if !sp.has("music") then Nil
    else
      val m = sp("music")
      if m.typeName != "object" || !inList(p("music_presets"), m("preset")) then
        Seq(e("music", Null, s"music.preset must be one of ${names(p("music_presets"))}"))
      else if m("preset") === Str(MusicPreset.NoMusic) then Nil
      else if !m("bpm").isNum || m("bpm") < Jv.num(60) || m("bpm") > Jv.num(160) then
        Seq(e("music", Null, "music.bpm must be a number from 60 to 160"))
      else
        val beats = div(mul(sp("format"), m("bpm")), Jv.num(60))
        when(!(beats === Jv.num(math.floor(beats.number))))(
          w("music", Null, s"music.bpm ${m("bpm").show} does not give a whole number of beats in ${sp("format").show} s: the bed will not loop clean"))

  private def beatChecks(sp: Jv, p: Jv): Seq[Finding] =
    val beats = sp("beats")
    val n = beats.size
    // The unused claims are the right side of a `+`: jq reads them first.
    val unused = alt(sp("claims"), Jv.EmptyArr).iter.collect { case c: Jv.Obj => c }.flatMap { c =>
      val cited = beats.iter.flatMap(b => alt(b("claims"), Jv.EmptyArr).iter)
      when(Jv.Arr(cited).indexOf(c("id")) == Null)(w("claims", Null, s"claim ${c("id").show} is cited by no beat"))
    }
    val each = beats.entries.flatMap((k, b) => beat(sp, p, beats, n, k.number.toInt, b))
    each ++ unused

  private def beat(sp: Jv, p: Jv, beats: Jv, n: Int, i: Int, b: Jv): Seq[Finding] =
    val id = alt(b("id"), Str("#" + (i + 1)))
    b match
      case _: Jv.Obj =>
        val okIn = b("t_in").isNum
        val okOut = b("t_out").isNum
        val dur = (try r3(b("t_out") - b("t_in")) catch case _: JqError => Jv.num(0)).or(Jv.num(0)).number
        val nc = alt(b("text"), Jv.EmptyArr).iter.collect { case s: Str => len(plainText(s)) }.sum
        val scene = alt(b("visual") match { case o: Jv.Obj => o("scene"); case _ => Null }, Str(""))
        val text = b("text")
        val prev = if i > 0 then beats(i - 1.0) else Null
        Seq(
          when(!(b("id") === Str("b" + pad2(i + 1))))(e("ids", id, s"id must be b${pad2(i + 1)} (b01.. in order)")),
          if !(okIn && okOut) then Seq(e("time", id, "t_in and t_out must be numbers (seconds)"))
          else Seq(
            when(i == 0 && !(b("t_in") === Jv.num(0)))(e("time", id, s"the first beat starts at 0, not ${b("t_in").show}")),
            when(i > 0 && { val before = r3(prev("t_out")); !(r3(b("t_in")) === before) })(
              e("time", id, s"gap or overlap: t_in ${b("t_in").show} but the beat before ends at ${prev("t_out").show}")),
            if dur <= 0 then Seq(e("time", id, "t_out must be after t_in"))
            else when(Jv.num(dur) < p("beat")("min_s"))(
              e("length", id, s"beat is ${jqDouble(dur)} s: the minimum is ${p("beat")("min_s").show} s")),
            when(i == n - 1 && !(r3(b("t_out")) === sp("format")))(
              e("total", id, s"the beats end at ${b("t_out").show} s but the format is ${sp("format").show} s")),
          ).flatten,
          when(!inList(p("roles"), b("role")))(e("role", id, s"role must be one of ${names(p("roles"))}")),
          when(i == 0 && !(b("role") === Str(Role.Hook)))(e("hook", id, "the first beat must have the role hook")),
          when(i > 0 && b("role") === Str(Role.Hook))(e("hook", id, "only the first beat is the hook")),
          when(i == 0 && okOut && b("t_out") > p("hook")("max_t_out"))(
            e("hook", id, s"the hook ends at ${b("t_out").show} s: it must end by ${p("hook")("max_t_out").show} s")),
          when(i == 0 && alt(text, Jv.EmptyArr) === Jv.EmptyArr)(
            w("hook", id, "the hook has no on-screen text: most people watch with the sound off")),
          when(b("role") === Str(Role.Cta) && i != n - 1)(e("cta", id, "a cta is allowed only in the last beat")),
          when(b("role") === Str(Role.Loop) && i != n - 1)(e("loop", id, "the role loop is allowed only in the last beat")),
          visualChecks(p, b, id, scene),
          textChecks(p, b, id, dur, nc),
          sceneTextChecks(b, id, scene),
          diagramChecks(b, id, scene),
          when(scene === Str(SceneKind.OutroLoop.key) && i != n - 1)(e("scene", id, "outro_loop is for the last beat")),
          when(i == n - 1 && sp("loop") === Jv.True && !(scene === Str(SceneKind.OutroLoop.key)))(
            e("loop", id, "loop is true: the last beat must use the scene outro_loop")),
          soundChecks(p, b, id, dur),
          transitionChecks(p, b, id, i, dur, okIn, okOut, prev),
          if b.has("claims") then
            b("claims") match
              case cs: Jv.Arr =>
                lazy val known = Jv.Arr(sp("claims").iterOpt.map(_("id")))
                cs.items.filter(c => known.indexOf(c) == Null).map(c => e("claims", id, s"cites claim ${compact(c)}, which does not exist"))
              case _ => Seq(e("claims", id, "claims must be an array of claim ids"))
          else Nil,
          when(alt(text, Jv.EmptyArr).iter.exists { case Str(s) => s.exists(c => c >= '0' && c <= '9'); case _ => false } &&
            alt(b("claims"), Jv.EmptyArr).size == 0)(w("claims", id, "a number is on screen but the beat cites no claim")),
          b.keysUnsorted.filterNot(k => BeatKeys(k.show)).map(k => w("keys", id, s"unknown beat key: ${k.show}")),
        ).flatten
      case _ => Seq(e("beat", id, "not an object"))

  private def visualChecks(p: Jv, b: Jv, id: Jv, scene: Jv): Seq[Finding] = b("visual") match
    case v: Jv.Obj =>
      Seq(
        when(blank(v("describe")))(e("visual", id, "visual.describe: say in words what is on screen")),
        when(!inList(p("scenes"), scene))(e("scene", id, s"visual.scene must be one of ${names(p("scenes"))}")),
        when(v.has("params") && v("params").typeName != "object")(e("visual", id, "visual.params must be an object")),
      ).flatten
    case _ => Seq(e("visual", id, "visual must be an object: {describe, scene, params}"))

  private def textChecks(p: Jv, b: Jv, id: Jv, dur: Double, nc: Int): Seq[Finding] =
    val text = b("text")
    if !b.has("text") || text.typeName != "array" || text.items.exists(_.typeName != "string") then
      Seq(e("text", id, "text must be an array of strings (use [] for no text)"))
    else
      val t = p("text")
      val lines = text.items.map(_.show).zipWithIndex
      Seq(
        when(Jv.num(lines.length) > t("max_lines"))(e("text", id, s"${lines.length} lines: at most ${t("max_lines").show}")),
        lines.filter((s, _) => Jv.num(len(s.replace("*", ""))) > t("max_chars_per_line")).map((s, k) =>
          e("text", id, s"line ${k + 1} has ${len(s.replace("*", ""))} characters: at most ${t("max_chars_per_line").show}")),
        lines.filter((s, _) => blank(Str(s))).map((_, k) => e("text", id, s"line ${k + 1} is empty")),
        lines.filter((s, _) => !blank(Str(s)) && edgeSpace(s)).map((_, k) => e("text", id, s"line ${k + 1} has a space at its start or end")),
        lines.filter((s, _) => s.count(_ == '*') % 2 == 1).map((_, k) =>
          e("text", id, s"line ${k + 1} has an odd number of * (emphasis marks come in pairs)")),
        lines.filter((s, _) => s.exists(c => c == '{' || c == '}' || c == '\\')).map((_, k) =>
          e("text", id, s"line ${k + 1} has a brace or a backslash: the captions use them")),
        when(dur > 0 && Jv.num(nc / dur) > t("max_cps"))(
          e("reading", id, s"$nc characters in ${jqDouble(dur)} s is ${jqDouble(round(nc / dur * 10) / 10)} per second: at most ${t("max_cps").show}")),
      ).flatten

  private def sceneTextChecks(b: Jv, id: Jv, scene: Jv): Seq[Finding] = b("text") match
    case text: Jv.Arr =>
      val n = text.items.length
      Seq(
        when(scene === Str(SceneKind.Timeline.key) && text.items.exists { case Str(s) => !s.contains(": "); case _ => false })(
          e("scene", id, "timeline: every line is \"when: label\"")),
        when(scene === Str(SceneKind.SplitCompare.key) && n < 2)(e("scene", id, "split_compare needs at least 2 lines")),
        when(scene === Str(SceneKind.BulletReveal.key) && n < 2)(e("scene", id, "bullet_reveal needs at least 2 lines")),
        when(TextScenes.exists(_ === scene) && n < 1)(e("scene", id, s"${scene.show} needs at least 1 line of text")),
        when(scene === Str(SceneKind.BigNumber.key) && len(plainText(alt(text(0.0), Str("")))) > 8)(
          w("scene", id, "big_number: the first line is the number: 8 characters or fewer reads best")),
      ).flatten
    case _ => Nil

  private def diagramChecks(b: Jv, id: Jv, scene: Jv): Seq[Finding] =
    if !(scene === Str(SceneKind.DiagramReveal.key)) then Nil
    else
      val layers = b("visual")("params")("layers")
      if layers.typeName != "array" || layers.size < 1 then
        Seq(e("scene", id, "diagram_reveal needs params.layers: a list of SVG files under direction/svg/"))
      else layers.items.filter { case Str(s) => !full(s, LayerName); case _ => true }
        .map(l => e("scene", id, s"layer ${compact(l)}: write direction/svg/<name>.svg"))

  private def soundChecks(p: Jv, b: Jv, id: Jv, dur: Double): Seq[Finding] =
    if !b.has("sound") || b("sound").typeName != "object" then Seq(e("sound", id, "sound must be an object: {music, sfx, silence}"))
    else
      val s = b("sound")
      val sfx = alt(s("sfx"), Jv.EmptyArr)
      Seq(
        when(s.has("music") && !inList(p("music_levels"), s("music")))(e("sound", id, s"sound.music must be one of ${names(p("music_levels"))}")),
        if sfx.typeName != "array" then Seq(e("sound", id, "sound.sfx must be an array of {name, at}"))
        else sfx.items.filter { x =>
          x.typeName != "object" || !inList(p("sfx"), x("name")) || !x("at").isNum || x("at") < Jv.num(0) || x("at") > Jv.num(dur)
        }.map(x => e("sound", id, s"sfx ${compact(x)}: name one of ${names(p("sfx"))} and at from 0 to ${jqDouble(dur)} s")),
        when(sfx.typeName == "array" && Jv.num(sfx.size) > p("sfx_per_beat"))(
          e("sound", id, s"at most ${p("sfx_per_beat").show} sound effects in a beat")),
        when(alt(s("silence"), Jv.False) === Jv.True &&
          (!(alt(s("music"), Str(MusicLevel.Off.key)) === Str(MusicLevel.Off.key)) || sfx.size > 0))(
          e("sound", id, "silence is true but the beat has music or sfx")),
      ).flatten

  private def transitionChecks(p: Jv, b: Jv, id: Jv, i: Int, dur: Double, okIn: Boolean, okOut: Boolean, prev: Jv): Seq[Finding] =
    val tr = b("transition")
    Seq(
      if !inList(p("transitions"), tr) then Seq(e("transition", id, s"transition must be one of ${names(p("transitions"))}"))
      else when(i == 0 && !(tr === Str(Cut.Hard)))(e("transition", id, "the first beat comes in with cut")),
      if !b.has("transition_s") then Nil
      else
        val ts = b("transition_s")
        val max = p("transition")("max_s")
        if !ts.isNum || ts <= Jv.num(0) || ts > max then
          Seq(e("transition", id, s"transition_s must be a number above 0 and at most ${max.show} s"))
        else when(i > 0 && okOut && okIn && !(tr === Str(Cut.Hard)) && {
          val half = div(Json.min(Seq(Jv.num(dur), sub(prev("t_out"), prev("t_in")))), Jv.num(2))
          ts > half
        })(e("transition", id, s"transition_s ${ts.show} is more than half of an adjacent beat")),
    ).flatten

  // ---- the shotlist ---------------------------------------------------------------------------

  /** The findings of one shotlist against its screenplay, the style and the hash of
    * screenplay.json. A shotlist that the rules cannot read raises its error (jq's message).
    */
  def shotlist(sl: Jv, sp: Jv, style: Jv, profile: Jv, hash: String): Seq[Finding] =
    val ids = sp("beats").iter.map(_("id"))
    Seq(
      when(!(sl("schema") === Str(Schema.Shotlist)))(e("schema", Null, s"schema must be \"${Schema.Shotlist}\"")),
      when(!(sl("slug") === sp("slug")))(e("slug", Null, s"slug ${sl("slug").show} is not the screenplay's ${sp("slug").show}")),
      when(!(sl("screenplay_sha256") === Str(hash)))(
        e("stale", Null, "the shotlist was made for another version of screenplay.json: the creative director redoes it")),
      if sl("shots").typeName != "array" then Seq(e("shots", Null, "shots must be an array"))
      else
        val right = Jv.Arr(ids)
        Seq(
          when(!(Jv.Arr(sl("shots").iter.map(_("beat"))) === right))(
            e("shots", Null, s"one shot for each beat, in order: ${join(ids, ", ")}")),
          sl("shots").iter.flatMap { s =>
            sp("beats").iter.find(_("id") === s("beat")).toSeq.flatMap(b => shot(s, b, sp, style, profile))
          },
        ).flatten,
    ).flatten

  private def inRange(v: Jv, lo: Double, hi: Double): Boolean = v.isNum && v >= Jv.num(lo) && v <= Jv.num(hi)

  private val Eases = Jv.arr(Str("linear"), Str("out_quad"), Str("out_cubic"), Str("out_quart"))
  private val Kinds = Jv.arr(Str(ShotKind.Flat.key), Str(ShotKind.ThreeD.key))
  private val PaletteRoles = Seq("main", "emph", "sub", "bar")

  private def shot(s: Jv, b: Jv, sp: Jv, style: Jv, p: Jv): Seq[Finding] =
    val id = s("beat")
    val kind = alt(s("kind"), Str(ShotKind.Flat.key))
    val threeD = kind === Str(ShotKind.ThreeD.key)
    def set(v: => Jv) = !(alt(v, Null) === Null)
    def range(v: => Jv, lo: Double, hi: Double, rule: String, msg: String) =
      when(set(v) && !inRange(v, lo, hi))(e(rule, id, msg))
    val colors = style("colors")
    Seq(
      when(!(s("scene") === b("visual")("scene")))(
        e("scene", id, s"scene ${s("scene").show} is not the screenplay's ${b("visual")("scene").show}: only the screenplay changes the scene")),
      when(s.has("transition") && !(s("transition") === b("transition")))(
        e("transition", id, s"transition ${s("transition").show} is not the screenplay's ${b("transition").show}")),
      when(s.has("kind") && Kinds.indexOf(s("kind")) == Null)(e("kind", id, "kind is flat or 3d")),
      when(threeD && !(alt(s("frames"), Null) === (Str("frames/") + id)))(
        e("frames", id, s"a 3d shot has \"frames\": \"frames/${id.show}\", the PNG sequence that reel blender ${sp("slug").show} ${id.show} writes")),
      when(!threeD && s.has("frames"))(e("frames", id, "frames is for a shot of kind 3d only")),
      when(threeD && Jv.num(math.ceil(((b("t_out") - b("t_in")) * p("blender")("fps")).number)) > p("blender")("max_frames"))(
        w("frames", id, s"the beat is longer than blender.max_frames (${p("blender")("max_frames").show}) at ${p("blender")("fps").show} fps: the last frame is held")),
      when(set(s("camera")("zoom")) && {
        val z = s("camera")("zoom")
        z.typeName != "array" || z.size != 2 || !z.iter.forall(inRange(_, 1, 1.3))
      })(e("camera", id, "camera.zoom is [from, to], each from 1.0 to 1.3")),
      when(set(s("motion")("ease")) && Eases.indexOf(s("motion")("ease")) == Null)(
        e("motion", id, "motion.ease is linear, out_quad, out_cubic or out_quart")),
      range(s("motion")("stagger"), 0.04, 0.4, "motion", "motion.stagger from 0.04 to 0.4 s"),
      range(s("motion")("enter_s"), 0.2, 1, "motion", "motion.enter_s from 0.2 to 1 s"),
      range(s("motion")("pop"), 1, 1.2, "motion", "motion.pop from 1 to 1.2"),
      range(s("motion")("blur"), 0, 20, "motion", "motion.blur from 0 to 20"),
      range(s("text_layout")("y"), 0.3, 0.7, "layout", "text_layout.y from 0.3 to 0.7 (a fraction of the safe area)"),
      range(s("text_layout")("scale"), 0.6, 1.2, "layout", "text_layout.scale from 0.6 to 1.2"),
      when(set(s("params") match { case o: Jv.Obj => o("layers"); case _ => Null }) && {
        val ls = s("params")("layers")
        ls.typeName != "array" || ls.iter.exists { case Str(x) => !full(x, LayerName); case _ => true }
      })(e("params", id, "params.layers: a list of direction/svg/<name>.svg")),
      alt(s("palette"), Jv.EmptyObj).entries.filter((k, _) => PaletteRoles.contains(k.show)).flatMap { (role, tok) =>
        val r = role.show
        if alt(colors.index(tok), Null) === Null then
          Seq(e("palette", id, s"palette.$r: ${tok.show} is not a colour of the style (${join(sort(colors.keysUnsorted), ", ")})"))
        else
          val c = contrast(colors.index(tok).show, colors("bg").show)
          if r != "bar" && c < 4.5 then
            Seq(e("contrast", id, s"palette.$r = ${tok.show}: contrast ${jqDouble(round(c * 10) / 10)} to the background, at least 4.5 is needed"))
          else when(r == "bar" && c < 1.5)(e("contrast", id, s"palette.bar = ${tok.show} is almost the colour of the background"))
      },
    ).flatten

  // ---- colour ---------------------------------------------------------------------------------

  /** The red, green and blue of "#RRGGBB", 0 to 255. */
  def rgb(hex: String): Seq[Int] =
    def dig(c: Int) = if c >= 97 then c - 87 else if c >= 65 then c - 55 else c - 48
    val h = codepoints(hex.stripPrefix("#"))
    Seq(0, 2, 4).map(k => dig(h(k)) * 16 + dig(h(k + 1)))

  private def luminance(hex: String): Double =
    def lin(c: Int) =
      val x = c / 255.0
      if x <= 0.03928 then x / 12.92 else math.pow((x + 0.055) / 1.055, 2.4)
    val Seq(r, g, b) = rgb(hex).map(lin): @unchecked
    (0.2126 * r) + (0.7152 * g) + (0.0722 * b)

  /** The WCAG contrast of two colours. */
  def contrast(a: String, b: String): Double =
    val (x, y) = (luminance(a), luminance(b))
    (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05)
