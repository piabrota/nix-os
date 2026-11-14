package piabrota.reels

import Json.*

/** Procedural music and sound effects, the mix, the loudness. Every sound is an expression or a
  * filtered noise, made by ffmpeg on this box: no sample, no download, no model.
  */
object Audio:
  /** One voice of a music preset: its name (for the reader), its filters, and an expression for
    * aevalsrc (mono, 48 kHz).
    */
  final case class Voice(name: String, filters: String, expr: String)

  /** The voices of a preset, for beats of `b` seconds; `bt` is the time in the beat. */
  def voices(preset: MusicPreset, b: String): Seq[Voice] =
    val bt = s"mod(t,$b)"
    val hb = s"mod(t,$b/2)"
    val nb = s"floor(mod(t/$b,4))"
    preset match
      case MusicPreset.Pulse => Seq(
          Voice("kick", "volume=0.9", s"sin(2*PI*(48*$bt+130*(1-exp(-30*$bt))/30))*exp(-7*$bt)"),
          Voice("hat", "highpass=f=6500,volume=0.5", s"(random(1)*2-1)*0.25*exp(-70*mod(t+$b/2,$b))"),
          Voice("bass", "lowpass=f=300,volume=0.8", s"0.5*sin(2*PI*55*pow(2,if(eq($nb,2),3,if(eq($nb,3),-2,0))/12)*t)*exp(-3*$hb)*(1-exp(-300*$hb))"),
          Voice("pad", "lowpass=f=1200,volume=0.5", s"0.09*(sin(2*PI*220*t)+sin(2*PI*261.63*t)+sin(2*PI*329.63*t))*(0.7+0.3*sin(2*PI*t/($b*8)))"))
      case MusicPreset.Ambient =>
        def env(phase: String) = s"pow(max(0,1-abs(mod(t/(4*$b)-$phase+10,4)-2)),1.5)"
        // Four chords, one a bar: Am, F, C, G. Each voice has its own bar-long swell.
        def chord(f1: String, f2: String, f3: String, phase: String) =
          s"(sin(2*PI*$f1*t)+0.8*sin(2*PI*$f2*t)+0.6*sin(2*PI*$f3*t))*${env(phase)}"
        Seq(
          Voice("pad", "lowpass=f=1800,volume=0.6", s"0.10*(${chord("110", "164.81", "220", "0.5")}+${chord("87.31", "130.81", "174.61", "1.5")}+${chord("130.81", "196", "261.63", "2.5")}+${chord("98", "146.83", "196", "3.5")})"),
          Voice("air", "highpass=f=900,lowpass=f=5000,volume=0.5", s"(random(2)*2-1)*0.03*(0.5+0.5*sin(2*PI*t/($b*6)))"),
          Voice("sub", "lowpass=f=120,volume=0.6", s"0.25*sin(2*PI*55*t)*(0.6+0.4*sin(2*PI*t/($b*16)))"))
      case MusicPreset.Tension => Seq(
          Voice("drone", "lowpass=f=400,volume=0.9", s"0.3*(sin(2*PI*55*t)+sin(2*PI*55.6*t))*(0.7+0.3*sin(2*PI*t/($b*4)))"),
          Voice("tick", "highpass=f=1500,volume=0.5", s"sin(2*PI*2400*t)*exp(-90*$bt)*0.5"),
          Voice("sub", "lowpass=f=120,volume=0.8", s"sin(2*PI*(42*mod(t,2*$b)+90*(1-exp(-25*mod(t,2*$b)))/25))*exp(-6*mod(t,2*$b))*0.6"),
          Voice("rise", "highpass=f=700,volume=0.7", s"(random(3)*2-1)*0.12*pow(mod(t/($b*16),1),3)"))
      case MusicPreset.Upbeat =>
        val i = s"floor(mod(t/($b/2),8))"
        val step = s"if(eq($i,0),0,if(eq($i,1),3,if(eq($i,2),7,if(eq($i,3),10,if(eq($i,4),12,if(eq($i,5),10,if(eq($i,6),7,3)))))))"
        Seq(
          Voice("kick", "volume=0.8", s"sin(2*PI*(50*$bt+120*(1-exp(-32*$bt))/32))*exp(-8*$bt)"),
          Voice("clap", "highpass=f=900,lowpass=f=6000,volume=0.5", s"(random(3)*2-1)*exp(-28*$bt)*gte(mod(t,2*$b),$b)*0.7"),
          Voice("hat", "highpass=f=7000,volume=0.45", s"(random(1)*2-1)*0.3*exp(-90*mod(t,$b/4))"),
          Voice("arp", "lowpass=f=3500,volume=0.55", s"0.35*(sin(2*PI*220*pow(2,$step/12)*t)+0.3*sin(4*PI*220*pow(2,$step/12)*t))*exp(-9*$hb)*(1-exp(-500*$hb))"),
          Voice("bass", "lowpass=f=250,volume=0.7", s"0.5*sin(2*PI*55*pow(2,if(eq(mod(floor(t/($b/2)),4),3),7,if(eq(mod(floor(t/($b/2)),4),2),3,0))/12)*t)*exp(-4*$hb)*(1-exp(-300*$hb))"))

  def makeMusic(tk: Toolkit, preset: String, bpm: Option[Double], bpmText: String, dur: String, loop: Boolean, out: os.Path): Unit =
    val beat = bpm.map(b => Json.num(60 / b)).getOrElse(fail(s"music: bpm is not a number: $bpmText"))
    val vs = voices(MusicPreset.parse(preset).getOrElse(fail(s"unknown music preset: $preset")), beat)
    val inputs = vs.flatMap(v => Seq("-f", "lavfi", "-i", s"aevalsrc=exprs='${v.expr}':s=48000:d=$dur"))
    val chains = vs.zipWithIndex.map((v, n) => s"[$n:a]${v.filters}[v$n];").mkString
    val labels = vs.indices.map(n => s"[v$n]").mkString
    val fadeOut = dur.toDoubleOption.map(d => s",afade=t=out:st=${Json.num(d - 0.6)}:d=0.6").getOrElse("")
    val tail = "afade=t=in:d=0.01" + (if loop then "" else fadeOut)
    val graph = s"$chains${labels}amix=inputs=${vs.length}:normalize=0,alimiter=limit=0.9:level=disabled,$tail,aformat=sample_fmts=s16:sample_rates=48000:channel_layouts=stereo[m]"
    val part = Name.part(out)
    if !tk.ffp(inputs ++ Seq("-filter_complex", graph, "-map", "[m]", "-t", dur, "-c:a", "pcm_s16le", "-f", "wav", part.toString)*) then
      fail("music: ffmpeg failed")
    os.move(part, out, replaceExisting = true)

  def makeSfx(tk: Toolkit, name: String, out: os.Path): Unit =
    val s = Sfx.parse(name).getOrElse(fail(s"unknown sound effect: $name"))
    val part = Name.part(out)
    if !tk.ffp("-f", "lavfi", "-i", s.source, "-af", s"${s.filters},aformat=sample_fmts=s16:sample_rates=48000:channel_layouts=stereo",
        "-t", s.seconds, "-c:a", "pcm_s16le", "-f", "wav", part.toString) then fail(s"sfx $name: ffmpeg failed")
    os.move(part, out, replaceExisting = true)

  def music(tk: Toolkit, args: List[String]): Int =
    if args.length != 1 then fail("usage: reel music <slug>")
    musicRun(tk, Gate.load(tk, args.head), quiet = false)
    0

  /** The bed of a loaded project, to build/audio/music.wav. */
  def musicRun(tk: Toolkit, p: Project, quiet: Boolean): Unit =
    val sp = p.screenplay
    val m = sp.music
    if !m.isOn then
      if !quiet then say("music: the screenplay has no music")
    else
      val out = p.dir.audio / Name.Music
      makeMusic(tk, m.preset, m.bpm, m.bpmText, sp.format, sp.loop, out)
      if !quiet then say(s"music: $out (${m.preset}, ${m.bpmText} bpm, ${sp.format} s)")

  /** The gain of the music, beat by beat: on, low or off (sound.music; "on" when the beat does not
    * say). An ffmpeg expression of t that moves between the levels over 0.3 s at each cut.
    */
  def gainExpr(beats: Seq[Beat]): String =
    val gains = beats.map { b =>
      val gain = if b.sound.silence then 0.0 else MusicLevel.parse(b.sound.music).fold(0.0)(_.gain)
      (b.tIn.getOrElse(fail("mix: the time of a beat is not a number")), gain)
    }
    val steps = gains.sliding(2).collect {
      case Seq((_, g0), (t, g1)) if g1 - g0 != 0 => s"(${Json.num(g1 - g0)})*clip((t-${Json.num(t - 0.15)})/0.3,0,1)"
    }
    (gains.headOption.map(b => Json.num(b._2)).toSeq ++ steps).mkString("+")

  /** The inputs and the filter of one source of the mix, the `n`th input. */
  final case class Source(input: os.Path, filter: Int => String, label: Int => String)

  def mix(tk: Toolkit, args: List[String]): Int =
    if args.length != 1 then fail("usage: reel mix <slug>")
    mixRun(tk, Gate.load(tk, args.head), quiet = false)
    0

  /** The sound of a loaded project, music and effects, normalised, to build/audio/mix.wav. */
  def mixRun(tk: Toolkit, p: Project, quiet: Boolean): Unit =
    val sp = p.screenplay
    val fmt = sp.format
    val aud = p.dir.audio
    val music = Option.when(sp.music.isOn) {
      musicRun(tk, p, quiet = true)
      Source(aud / Name.Music, n => s"[$n:a]volume='${gainExpr(sp.beats)}':eval=frame[m$n];", n => s"[m$n]")
    }
    // every sound effect the beats ask for: made once, delayed to its place
    val effects = for
      b <- sp.beats
      e <- b.sound.sfx
    yield
      val wav = aud / s"sfx-${e.name}.wav"
      if !os.isFile(wav) then makeSfx(tk, e.name, wav)
      val ms = (b.tIn, e.at) match
        case (Some(t), Some(at)) => jqRound((t + at) * 1000)
        case _                   => fail("mix: the time of an effect is not a number")
      Source(wav, n => s"[$n:a]adelay=delays=$ms:all=1[s$n];", n => s"[s$n]")
    val sources = music.toSeq ++ effects
    val n = sources.length
    val sr = tk.p("audio", "rate")
    val mixWav = aud / Name.Mix
    if n == 0 then
      // no music and no effect: a silent track, so the file still has audio
      if !tk.ffp("-f", "lavfi", "-i", s"anullsrc=r=$sr:cl=stereo:d=$fmt", "-t", fmt, "-c:a", "pcm_s16le", "-f", "wav",
          Name.part(mixWav).toString) then fail("mix: ffmpeg failed")
      os.move(Name.part(mixWav), mixWav, replaceExisting = true)
      if !quiet then say(s"mix: $mixWav (silence)")
    else
      val inputs = sources.flatMap(s => Seq("-i", s.input.toString))
      val labels = sources.zipWithIndex.map((s, i) => s.label(i)).mkString
      val graph = sources.zipWithIndex.map((s, i) => s.filter(i)).mkString +
        s"${labels}amix=inputs=$n:normalize=0:duration=longest,apad=whole_dur=$fmt,atrim=0:$fmt,aformat=sample_fmts=fltp:sample_rates=$sr:channel_layouts=stereo[mixed]"
      val premix = aud / Name.Premix
      if !tk.ffp(inputs ++ Seq("-filter_complex", graph, "-map", "[mixed]", "-c:a", "pcm_s16le", "-f", "wav",
          Name.part(premix).toString)*) then fail("mix: ffmpeg failed")
      os.move(Name.part(premix), premix, replaceExisting = true)
      normalise(tk, premix, mixWav)
      if !quiet then say(s"mix: $mixWav ($n sources, $fmt s, ${tk.p("audio", "target_lufs")} LUFS target)")

  /** The JSON block that loudnorm prints in its log. */
  def loudnormBlock(log: String): Option[ujson.Value] =
    """\{[^}]*\}""".r.findFirstIn(log).flatMap(Json.read)

  /** loudnorm in two passes, to the target of the profile. The peak ceiling is audio.premix_peak,
    * 1 dB under the one QA holds the file to: the AAC encoder adds to it.
    */
  def normalise(tk: Toolkit, in: os.Path, out: os.Path): Unit =
    val i = tk.p("audio", "target_lufs")
    val tp = tk.p("audio", "premix_peak")
    val log = tk.ffl("-i", in.toString, "-af", s"loudnorm=I=$i:TP=$tp:LRA=11:print_format=json", "-f", "null", "-")
      .getOrElse(fail("loudnorm (pass 1) failed"))
    val m = loudnormBlock(log).getOrElse(fail("cannot read the loudnorm measurement"))
    def g(k: String) = m.at(k).text
    val part = Name.part(out)
    if !tk.ffp("-i", in.toString, "-af",
        s"loudnorm=I=$i:TP=$tp:LRA=11:measured_I=${g("input_i")}:measured_TP=${g("input_tp")}:measured_LRA=${g("input_lra")}:measured_thresh=${g("input_thresh")}:offset=${g("target_offset")}:linear=true,aresample=${tk.p("audio", "rate")},aformat=sample_fmts=s16:channel_layouts=stereo",
        "-c:a", "pcm_s16le", "-f", "wav", part.toString) then fail("loudnorm (pass 2) failed")
    os.move(part, out, replaceExisting = true)
