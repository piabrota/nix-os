# audio.sh: procedural music and sound effects, the mix, the loudness. Sourced by `reel`.
# Every sound is an expression or a filtered noise, made by ffmpeg on this box: no sample, no
# download, no model.
# shellcheck shell=sh

TAB=$(printf '\t')

# voices_for <preset> <seconds a beat>: one line a voice, "name TAB filters TAB expression".
# The expression is for aevalsrc (mono, 48 kHz). B is the length of a beat; bt the time in it.
voices_for() {
  _B=$2
  _bt="mod(t,$_B)"
  _hb="mod(t,$_B/2)"
  _nb="floor(mod(t/$_B,4))"
  case "$1" in
    pulse)
      printf 'kick\tvolume=0.9\t%s\n' "sin(2*PI*(48*$_bt+130*(1-exp(-30*$_bt))/30))*exp(-7*$_bt)"
      printf 'hat\thighpass=f=6500,volume=0.5\t%s\n' "(random(1)*2-1)*0.25*exp(-70*mod(t+$_B/2,$_B))"
      printf 'bass\tlowpass=f=300,volume=0.8\t%s\n' "0.5*sin(2*PI*55*pow(2,if(eq($_nb,2),3,if(eq($_nb,3),-2,0))/12)*t)*exp(-3*$_hb)*(1-exp(-300*$_hb))"
      printf 'pad\tlowpass=f=1200,volume=0.5\t%s\n' "0.09*(sin(2*PI*220*t)+sin(2*PI*261.63*t)+sin(2*PI*329.63*t))*(0.7+0.3*sin(2*PI*t/($_B*8)))"
      ;;
    ambient)
      _env() { printf 'pow(max(0,1-abs(mod(t/(4*%s)-%s+10,4)-2)),1.5)' "$_B" "$1"; }
      # Four chords, one a bar: Am, F, C, G. Each voice has its own bar-long swell.
      _chord() { printf '(sin(2*PI*%s*t)+0.8*sin(2*PI*%s*t)+0.6*sin(2*PI*%s*t))*%s' "$1" "$2" "$3" "$(_env "$4")"; }
      printf 'pad\tlowpass=f=1800,volume=0.6\t%s\n' "0.10*($(_chord 110 164.81 220 0.5)+$(_chord 87.31 130.81 174.61 1.5)+$(_chord 130.81 196 261.63 2.5)+$(_chord 98 146.83 196 3.5))"
      printf 'air\thighpass=f=900,lowpass=f=5000,volume=0.5\t%s\n' "(random(2)*2-1)*0.03*(0.5+0.5*sin(2*PI*t/($_B*6)))"
      printf 'sub\tlowpass=f=120,volume=0.6\t%s\n' "0.25*sin(2*PI*55*t)*(0.6+0.4*sin(2*PI*t/($_B*16)))"
      ;;
    tension)
      printf 'drone\tlowpass=f=400,volume=0.9\t%s\n' "0.3*(sin(2*PI*55*t)+sin(2*PI*55.6*t))*(0.7+0.3*sin(2*PI*t/($_B*4)))"
      printf 'tick\thighpass=f=1500,volume=0.5\t%s\n' "sin(2*PI*2400*t)*exp(-90*$_bt)*0.5"
      printf 'sub\tlowpass=f=120,volume=0.8\t%s\n' "sin(2*PI*(42*mod(t,2*$_B)+90*(1-exp(-25*mod(t,2*$_B)))/25))*exp(-6*mod(t,2*$_B))*0.6"
      printf 'rise\thighpass=f=700,volume=0.7\t%s\n' "(random(3)*2-1)*0.12*pow(mod(t/($_B*16),1),3)"
      ;;
    upbeat)
      printf 'kick\tvolume=0.8\t%s\n' "sin(2*PI*(50*$_bt+120*(1-exp(-32*$_bt))/32))*exp(-8*$_bt)"
      printf 'clap\thighpass=f=900,lowpass=f=6000,volume=0.5\t%s\n' "(random(3)*2-1)*exp(-28*$_bt)*gte(mod(t,2*$_B),$_B)*0.7"
      printf 'hat\thighpass=f=7000,volume=0.45\t%s\n' "(random(1)*2-1)*0.3*exp(-90*mod(t,$_B/4))"
      _i="floor(mod(t/($_B/2),8))"
      _s="if(eq($_i,0),0,if(eq($_i,1),3,if(eq($_i,2),7,if(eq($_i,3),10,if(eq($_i,4),12,if(eq($_i,5),10,if(eq($_i,6),7,3)))))))"
      printf 'arp\tlowpass=f=3500,volume=0.55\t%s\n' "0.35*(sin(2*PI*220*pow(2,$_s/12)*t)+0.3*sin(4*PI*220*pow(2,$_s/12)*t))*exp(-9*$_hb)*(1-exp(-500*$_hb))"
      printf 'bass\tlowpass=f=250,volume=0.7\t%s\n' "0.5*sin(2*PI*55*pow(2,if(eq(mod(floor(t/($_B/2)),4),3),7,if(eq(mod(floor(t/($_B/2)),4),2),3,0))/12)*t)*exp(-4*$_hb)*(1-exp(-300*$_hb))"
      ;;
    *) return 1 ;;
  esac
}

# make_music <preset> <bpm> <seconds> <loop true|false> <out.wav>
make_music() {
  _preset=$1
  _bpm=$2
  _dur=$3
  _loop=$4
  _out=$5
  _bsec=$(jq -nr --argjson b "$_bpm" '60 / $b') || die "music: bpm is not a number: $_bpm"
  _voices=$(voices_for "$_preset" "$_bsec") || die "unknown music preset: $_preset"
  set --
  _graph=
  _labels=
  _n=0
  # One voice a line: name, filters, expression (the name is for the reader of voices_for).
  while IFS=$TAB read -r _ _post _expr; do
    set -- "$@" -f lavfi -i "aevalsrc=exprs='$_expr':s=48000:d=$_dur"
    _graph="${_graph}[$_n:a]${_post}[v$_n];"
    _labels="${_labels}[v$_n]"
    _n=$((_n + 1))
  done <<EOF
$_voices
EOF
  _tail="afade=t=in:d=0.01"
  [ "$_loop" = true ] || _tail="$_tail,afade=t=out:st=$(jq -nr --argjson d "$_dur" '$d - 0.6'):d=0.6"
  _graph="$_graph${_labels}amix=inputs=$_n:normalize=0,alimiter=limit=0.9:level=disabled,$_tail,aformat=sample_fmts=s16:sample_rates=48000:channel_layouts=stereo[m]"
  ffp "$@" -filter_complex "$_graph" -map "[m]" -t "$_dur" -c:a pcm_s16le -f wav "$_out.part" || die "music: ffmpeg failed"
  mv -f "$_out.part" "$_out"
}

# sfx_spec <name>: "duration TAB input TAB filters" of one effect.
sfx_spec() {
  case "$1" in
    hit) printf '0.9\taevalsrc=exprs=%s:s=48000:d=0.9\talimiter=limit=0.9:level=disabled\n' "'0.9*sin(2*PI*(42*t+110*(1-exp(-28*t))/28))*exp(-5*t)+0.3*(random(0)*2-1)*exp(-60*t)'" ;;
    tick) printf '0.1\taevalsrc=exprs=%s:s=48000:d=0.1\tvolume=0.8\n' "'0.7*sin(2*PI*2300*t)*exp(-85*t)'" ;;
    pop) printf '0.25\taevalsrc=exprs=%s:s=48000:d=0.25\tvolume=0.9\n' "'0.8*sin(2*PI*(320*t+650*(1-exp(-38*t))/38))*exp(-22*t)'" ;;
    whoosh) printf '0.8\tanoisesrc=d=0.8:c=pink:a=0.9:r=48000:seed=7\thighpass=f=350,lowpass=f=7500,volume=%s:eval=frame\n' "'pow(sin(PI*t/0.8),2)*0.8'" ;;
    riser) printf '2.2\taevalsrc=exprs=%s:s=48000:d=2.2\thighpass=f=200,volume=0.7\n' "'((random(0)*2-1)*0.5+0.6*sin(2*PI*(180*t+200*t*t)))*pow(t/2.2,2.2)'" ;;
    *) return 1 ;;
  esac
}

# make_sfx <name> <out.wav>
make_sfx() {
  _spec=$(sfx_spec "$1") || die "unknown sound effect: $1"
  _sd=${_spec%%"$TAB"*}
  _rest=${_spec#*"$TAB"}
  _src=${_rest%%"$TAB"*}
  _flt=${_rest#*"$TAB"}
  ffp -f lavfi -i "$_src" -af "$_flt,aformat=sample_fmts=s16:sample_rates=48000:channel_layouts=stereo" -t "$_sd" -c:a pcm_s16le -f wav "$2.part" || die "sfx $1: ffmpeg failed"
  mv -f "$2.part" "$2"
}

cmd_music() {
  [ $# -eq 1 ] || die "usage: reel music <slug>"
  load_project "$1"
  music_run
}

# music_run: the bed of the loaded project (load_project has passed the gate).
music_run() {
  _preset=$(printf '%s' "$SPJ" | jq -r '.music.preset // "none"')
  if [ "$_preset" = none ]; then
    say "music: the screenplay has no music"
    return 0
  fi
  _bpm=$(printf '%s' "$SPJ" | jq -r '.music.bpm')
  _fmt=$(printf '%s' "$SPJ" | jq -r '.format')
  _loop=$(printf '%s' "$SPJ" | jq -r '.loop')
  make_music "$_preset" "$_bpm" "$_fmt" "$_loop" "$PROJ/build/audio/music.wav"
  say "music: $PROJ/build/audio/music.wav ($_preset, $_bpm bpm, $_fmt s)"
}

# The gain of the music a beat: on, low or off (sound.music; "on" when the beat does not say).
# gain_expr: an ffmpeg expression of t that moves between the levels over 0.3 s at each cut.
gain_expr() {
  printf '%s' "$SPJ" | jq -r '
    {on: 0.55, low: 0.22, off: 0} as $lv
    | [.beats[] | {t: .t_in, g: (if .sound.silence == true then 0 else $lv[.sound.music // "on"] end)}] as $b
    | ([$b[0].g | tostring] + [range(1; $b | length) as $i
        | ($b[$i].g - $b[$i - 1].g) as $d
        | select($d != 0)
        | "(\($d))*clip((t-\($b[$i].t - 0.15))/0.3,0,1)"]) | join("+")'
}

cmd_mix() {
  [ $# -eq 1 ] || die "usage: reel mix <slug>"
  load_project "$1"
  mix_run
}

# mix_run: the sound of the loaded project, music and effects, normalised.
mix_run() {
  _fmt=$(printf '%s' "$SPJ" | jq -r '.format')
  _preset=$(printf '%s' "$SPJ" | jq -r '.music.preset // "none"')
  _aud=$PROJ/build/audio
  set --
  _graph=
  _labels=
  _n=0
  if [ "$_preset" != none ]; then
    music_run >/dev/null
    set -- -i "$_aud/music.wav"
    _graph="[0:a]volume='$(gain_expr)':eval=frame[m0];"
    _labels="[m0]"
    _n=1
  fi
  # every sound effect the beats ask for: made once, delayed to its place
  _list=$(printf '%s' "$SPJ" | jq -r '.beats[] | .t_in as $t | (.sound.sfx // [])[] | "\(.name) \($t + .at)"')
  if [ -n "$_list" ]; then
    while read -r _name _when; do
      [ -f "$_aud/sfx-$_name.wav" ] || make_sfx "$_name" "$_aud/sfx-$_name.wav"
      set -- "$@" -i "$_aud/sfx-$_name.wav"
      _ms=$(jq -nr --argjson w "$_when" '$w * 1000 | round') || die "mix: the time of an effect is not a number: $_when"
      _graph="${_graph}[$_n:a]adelay=delays=$_ms:all=1[s$_n];"
      _labels="${_labels}[s$_n]"
      _n=$((_n + 1))
    done <<EOF
$_list
EOF
  fi
  _sr=$(pnum .audio.rate)
  if [ "$_n" -eq 0 ]; then
    # no music and no effect: a silent track, so the file still has audio
    ffp -f lavfi -i "anullsrc=r=$_sr:cl=stereo:d=$_fmt" -t "$_fmt" -c:a pcm_s16le -f wav "$_aud/mix.wav.part" || die "mix: ffmpeg failed"
    mv -f "$_aud/mix.wav.part" "$_aud/mix.wav"
    say "mix: $_aud/mix.wav (silence)"
    return 0
  fi
  _graph="$_graph${_labels}amix=inputs=$_n:normalize=0:duration=longest,apad=whole_dur=$_fmt,atrim=0:$_fmt,aformat=sample_fmts=fltp:sample_rates=$_sr:channel_layouts=stereo[mixed]"
  ffp "$@" -filter_complex "$_graph" -map "[mixed]" -c:a pcm_s16le -f wav "$_aud/premix.wav.part" || die "mix: ffmpeg failed"
  mv -f "$_aud/premix.wav.part" "$_aud/premix.wav"
  normalise "$_aud/premix.wav" "$_aud/mix.wav"
  say "mix: $_aud/mix.wav ($_n sources, $_fmt s, $(pnum .audio.target_lufs) LUFS target)"
}

# normalise <in.wav> <out.wav>: loudnorm in two passes, to the target of the profile. The peak
# ceiling is audio.premix_peak, 1 dB under the one QA holds the file to: the AAC encoder adds to it.
normalise() {
  _i=$(pnum .audio.target_lufs)
  _tp=$(pnum .audio.premix_peak)
  _sr=$(pnum .audio.rate)
  ffl -i "$1" \
    -af "loudnorm=I=$_i:TP=$_tp:LRA=11:print_format=json" -f null - 2>"$TMP/ln1.txt" || die "loudnorm (pass 1) failed"
  _m=$(jq -Rs 'capture("(?<j>\\{[^}]*\\})").j | fromjson' <"$TMP/ln1.txt") || die "cannot read the loudnorm measurement"
  _mi=$(printf '%s' "$_m" | jq -r .input_i)
  _mtp=$(printf '%s' "$_m" | jq -r .input_tp)
  _mlra=$(printf '%s' "$_m" | jq -r .input_lra)
  _mth=$(printf '%s' "$_m" | jq -r .input_thresh)
  _off=$(printf '%s' "$_m" | jq -r .target_offset)
  ffp -i "$1" -af "loudnorm=I=$_i:TP=$_tp:LRA=11:measured_I=$_mi:measured_TP=$_mtp:measured_LRA=$_mlra:measured_thresh=$_mth:offset=$_off:linear=true,aresample=$_sr,aformat=sample_fmts=s16:channel_layouts=stereo" \
    -c:a pcm_s16le -f wav "$2.part" || die "loudnorm (pass 2) failed"
  mv -f "$2.part" "$2"
}
