# render.sh: the clips, the sound and the assembly into out/<slug>/reel.mp4. Sourced by `reel`.
# shellcheck shell=sh

# stats_json: seconds and peak memory of the ffmpeg runs so far, from $TIMES.
stats_json() {
  jq -Rs 'split("\n") | map(select(length > 0) | split(" ") | {s: (.[0] | tonumber), mib: ((.[1] | tonumber) / 1024 | . * 10 | round / 10)}) as $r
          | {ffmpeg_wall_s: ($r | map(.s) | add // 0), peak_rss_mib: ($r | map(.mib) | max // 0), runs: ($r | length), per_run: ($r | map([.s, .mib]))}' <"$TIMES"
}

# assemble_stage <acc file or ""> <first clip> <after the last clip> <final true|false> <out>
# One xfade chain over the clips [first, after-last), starting from the stream of the stages before
# it (acc), when there is one. The offsets of the frame plan are on the chain's own timeline, so a
# chain can be cut anywhere. ffmpeg reads every input at once, and each open input costs memory
# (docs/REELS.md, "Limits"), so a long reel is built in stages of at most video.max_inputs inputs.
# A stage that is not the last writes the video again at the quality of the scene clips, no sound.
assemble_stage() {
  _acc=$1
  _from=$2
  _to=$3
  _final=$4
  _o=$5
  set --
  _graph=''
  _prev=''
  _k=0
  if [ -n "$_acc" ]; then
    set -- -threads 1 -i "$_acc"
    _graph='[0:v]settb=AVTB,setpts=PTS-STARTPTS[acc];'
    _prev=acc
    _k=1
  fi
  _i=$_from
  while [ "$_i" -lt "$_to" ]; do
    set -- "$@" -threads 1 -i "$PROJ/build/scenes/$(printf '%s' "$TL" | jq -r --argjson i "$_i" '.[$i].id').mp4"
    _graph="${_graph}[$_k:v]settb=AVTB,setpts=PTS-STARTPTS[c$_i];"
    if [ -z "$_prev" ]; then
      _prev=c$_i
    else
      # The offset is 5 ms before the frame it names. ffmpeg 8.1's xfade `slideup` reads stray memory in
      # the one frame where progress is exactly 0 (the first of the transition, when the offset falls on a
      # frame), so two renders of one screenplay differed in that frame. The `fps` filter below puts every
      # frame back on the grid, and the frames after the transition are unchanged (tested).
      _x=$(printf '%s' "$TL" | jq -r --argjson i "$_i" --argjson fps "$FPS" '.[$i] | "\(if .tr == "cut" then "fade" else .tr end) \(.dq / $fps) \(.offset - 0.005)"')
      _kind=${_x%% *}
      _rest=${_x#* }
      _graph="${_graph}[$_prev][c$_i]xfade=transition=$_kind:duration=${_rest% *}:offset=${_rest#* }[x$_i];"
      _prev=x$_i
    fi
    _k=$((_k + 1))
    _i=$((_i + 1))
  done
  _graph="${_graph}[$_prev]fps=$FPS,format=yuv420p[v]"
  _fmt=$(printf '%s' "$SPJ" | jq -r '.format')
  if [ "$_final" = true ]; then
    _title=$(printf '%s' "$SPJ" | jq -r '.title')
    ffp "$@" -i "$PROJ/build/audio/mix.wav" -filter_complex "$_graph" -map "[v]" -map "$_k:a" \
      -c:v libx264 -preset "$(pnum .video.preset)" -crf "$(pnum .video.crf)" -profile:v high -level 4.0 -pix_fmt yuv420p \
      -colorspace bt709 -color_primaries bt709 -color_trc bt709 -color_range tv -g "$((FPS * 2))" -x264-params "$(pnum .video.x264_params)" -threads "$(pnum .video.threads)" \
      -c:a "$(pnum .audio.codec)" -b:a "$(pnum .audio.bitrate)" -ar "$(pnum .audio.rate)" -ac "$(pnum .audio.channels)" \
      -t "$_fmt" -map_metadata -1 -metadata title="$_title" -movflags +faststart \
      -fflags +bitexact -flags:v +bitexact -flags:a +bitexact \
      -f mp4 "$_o" || die "assembly failed"
  else
    ffp "$@" -filter_complex "$_graph" -map "[v]" -an \
      -c:v libx264 -preset veryfast -crf "$(pnum .video.scene_crf)" -pix_fmt yuv420p \
      -colorspace bt709 -color_primaries bt709 -color_trc bt709 -color_range tv -r "$FPS" -threads 2 \
      -fflags +bitexact -flags:v +bitexact -f mp4 "$_o" || die "assembly failed"
  fi
}

# render_lock <project folder>: one render at a time in a project. A lock left by a render that
# died (a killed seat, a restart) names a process that is gone, and is taken over.
render_lock() {
  _lk=$1/build/render.lock
  if ! mkdir "$_lk" 2>/dev/null; then
    _lp=$(cat "$_lk/pid" 2>/dev/null || echo 0)
    if [ "$_lp" -gt 0 ] 2>/dev/null && kill -0 "$_lp" 2>/dev/null; then
      die "another render of this project is running (process $_lp). Wait for it, or remove $_lk if it is not"
    fi
    rm -rf "$_lk"
    mkdir "$_lk" || die "cannot take the render lock $_lk"
  fi
  echo $$ >"$_lk/pid"
  LOCK=$_lk
}

cmd_render() {
  [ $# -eq 1 ] || die "usage: reel render <slug>"
  _slug=$1
  load_project "$_slug"
  require_shotlist "$_slug"
  _rd=$(out_dir "$_slug")
  mkdir -p "$_rd"
  render_lock "$PROJ"
  # What an earlier run left is of no use now, and a file of an old screenplay must not be taken for
  # this one's: the finished files go first, then the half-written ones of a run that died.
  rm -f "$_rd/reel.mp4" "$_rd/render.json" "$_rd/qa.json" "$_rd"/*.part
  rm -f "$PROJ"/build/stage*.mp4 "$PROJ"/build/scenes/*.part "$PROJ"/build/scenes/*.key.part "$PROJ"/build/audio/*.part
  _t0=$(date +%s)
  note "sound"
  mix_run >/dev/null
  _ids=$(printf '%s' "$TL" | jq -r '.[].id')
  _n=0
  for _b in $_ids; do
    note "scene $_b"
    build_clip "$_b"
    _n=$((_n + 1))
  done
  note "assemble $_n clips"

  _max=$(pnum .video.max_inputs)
  _acc=''
  _from=0
  _stage=0
  while [ "$_from" -lt "$_n" ]; do
    _take=$_max
    [ -z "$_acc" ] || _take=$((_max - 1))
    _to=$((_from + _take))
    _final=false
    if [ "$_to" -ge "$_n" ]; then
      _to=$_n
      _final=true
    fi
    _stage=$((_stage + 1))
    if [ "$_final" = true ]; then _stage_out=$_rd/reel.mp4.part; else _stage_out=$PROJ/build/stage$_stage.mp4; fi
    note "assemble: stage $_stage, clips $((_from + 1)) to $_to of $_n"
    assemble_stage "$_acc" "$_from" "$_to" "$_final" "$_stage_out"
    _acc=$_stage_out
    _from=$_to
  done
  rm -f "$PROJ"/build/stage*.mp4
  mv -f "$_rd/reel.mp4.part" "$_rd/reel.mp4"
  _t1=$(date +%s)
  _bytes=$(wc -c <"$_rd/reel.mp4" | tr -d ' ')
  stats_json | jq -c --arg slug "$_slug" --argjson wall "$((_t1 - _t0))" --argjson bytes "$_bytes" \
    --arg sha "$(sha_of "$_rd/reel.mp4")" --arg approved "$APPROVED_HASH" \
    '. + {slug: $slug, wall_s: $wall, bytes: $bytes, reel_sha256: $sha, screenplay_sha256: $approved}' >"$_rd/render.json.part" || die "cannot write render.json"
  mv -f "$_rd/render.json.part" "$_rd/render.json"
  say "render: $_rd/reel.mp4 ($_bytes bytes, $((_t1 - _t0)) s wall, $(jq -r .peak_rss_mib "$_rd/render.json") MiB peak in one ffmpeg)"
}
