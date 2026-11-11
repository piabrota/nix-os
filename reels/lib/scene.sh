# scene.sh: one beat to a picture: a background, SVG layers, the ASS captions. Sourced by `reel`.
# shellcheck shell=sh

# load_project <slug>: the gate, then the screenplay, its style, its frame plan and its shotlist.
# Sets PROJ SP SPJ STYLE TL SHOTS SHOTS_SHA. The shotlist is read once into a private copy, like the
# screenplay, so a render uses one version of both from its first beat to its last.
load_project() {
  require_approved "$1"
  SPJ=$(cat "$SP")
  STYLE=$(style_json "$SP")
  TL=$(jq -c -L "$LIB" --argjson profile "$PJ" -f "$LIB/timeline.jq" "$SP") || die "cannot plan the frames of $1"
  SHOTS=$TMP/shotlist.json
  SHOTS_SHA=none
  _sf=$PROJ/direction/shotlist.json
  if [ -e "$_sf" ] || [ -L "$_sf" ]; then
    plain_file "$_sf" || die "the shotlist is a link or not a file: $_sf"
    cp "$_sf" "$SHOTS" || die "cannot read $_sf"
    SHOTS_SHA=$(sha_of "$SHOTS")
  else
    rm -f "$SHOTS"
  fi
  mkdir -p "$PROJ/build/scenes" "$PROJ/build/cache" "$PROJ/build/layers" "$PROJ/build/audio" "$PROJ/direction/storyboard"
  setup_fonts
}

# require_shotlist: the creative director's file must exist, be valid and be made for this screenplay.
require_shotlist() {
  [ -f "$SHOTS" ] || die "no shotlist: the creative director runs reel shotlist $1, then edits direction/shotlist.json"
  valid_json "$SHOTS"
  _sf=$(shotlist_lint "$SP" "$SHOTS")
  if ! _so=$(print_findings "$_sf"); then
    printf '%s\n' "$_so" >&2
    die "the shotlist fails its lint (reel lint $1)"
  fi
}

shot_of() {
  if [ -f "$SHOTS" ]; then
    jq -c --arg id "$1" '(.shots[]? | select(.beat == $id)) // {}' "$SHOTS"
  else
    echo '{}'
  fi
}

# tl_vals <beat id>: "S E hin hout frames" of the beat.
tl_vals() {
  printf '%s' "$TL" | jq -r --arg id "$1" '.[] | select(.id == $id) | "\(.S) \(.E) \(.hin) \(.hout) \(.frames)"'
}

# The safe area, in whole pixels: x0 y0 x1 y1.
safe_rect() {
  printf '%s' "$PJ" | jq -r '[(.video.width * .safe.side), (.video.height * .safe.top), (.video.width * (1 - .safe.side)), (.video.height * (1 - .safe.bottom))] | map(round) | join(" ")'
}

# textbox <ass file> <seconds>: the bounding box of what the captions draw at that time, as
# "x1 y1 x2 y2", or "none". The file is the mask variant of the script (everything white).
textbox() {
  _bb=$TMP/bbox.txt
  : >"$_bb"
  ff -f lavfi -i "color=c=black:s=${W}x${H}:r=$FPS:d=1" \
    -vf "setpts=PTS+$2/TB,ass=filename=$1:fontsdir=$FONTS,format=gray,bbox=min_val=40,metadata=mode=print:file=$_bb" \
    -frames:v 1 -f null - || die "cannot measure the captions"
  _x1='' _y1='' _x2='' _y2=''
  while IFS='=' read -r _k _v; do
    case "$_k" in
      lavfi.bbox.x1) _x1=$_v ;;
      lavfi.bbox.y1) _y1=$_v ;;
      lavfi.bbox.x2) _x2=$_v ;;
      lavfi.bbox.y2) _y2=$_v ;;
    esac
  done <"$_bb"
  if [ -z "$_x1" ]; then echo none; else echo "$_x1 $_y1 $_x2 $_y2"; fi
}

# inside_safe <box "x1 y1 x2 y2">: true when the box is in the safe area (2 px of slack for the edges).
inside_safe() {
  read -r _sx0 _sy0 _sx1 _sy1 <<EOF
$(safe_rect)
EOF
  read -r _bx1 _by1 _bx2 _by2 <<EOF
$1
EOF
  [ "$_bx1" -ge $((_sx0 - 2)) ] && [ "$_by1" -ge $((_sy0 - 2)) ] && [ "$_bx2" -le $((_sx1 + 2)) ] && [ "$_by2" -le $((_sy1 + 2)) ]
}

# scene_jq <mode ass|plan> <mask true|false>: needs BEAT SHOT HIN TOTAL DUR LAST.
scene_jq() {
  jq -n -r -L "$LIB" --argjson sp "$SPJ" --argjson beat "$BEAT" --argjson shot "$SHOT" \
    --argjson style "$STYLE" --argjson profile "$PJ" --argjson hin "$HIN" --argjson total "$TOTAL" \
    --argjson dur "$DUR" --argjson last "$LAST" --argjson mask "$2" --arg mode "$1" -f "$LIB/scene.jq"
}

# ensure_bg: the background PNG of the style, cached by its content. Sets BG.
ensure_bg() {
  _bk=$(printf '%s' "$STYLE" | jq -c '{colors: .colors, background: .background}' | sha256sum | cut -c1-12)
  BG=$PROJ/build/cache/bg-$_bk.png
  [ -f "$BG" ] && return 0
  printf '%s' "$STYLE" | jq -r -L "$LIB" --argjson profile "$PJ" -f "$LIB/bg.jq" >"$TMP/bg.svg" || die "cannot draw the background"
  svg_to_png -w "$W" -h "$H" "$TMP/bg.svg" "$BG.part.png" || die "resvg failed on the background"
  mv -f "$BG.part.png" "$BG"
}

# beat_context <id> <hin_s> <total_s> <dur_s> <last>: sets BEAT SHOT HIN TOTAL DUR LAST for scene_jq.
beat_context() {
  BEAT=$(printf '%s' "$SPJ" | jq -c --arg id "$1" '.beats[] | select(.id == $id)')
  [ -n "$BEAT" ] || die "no beat $1 in the screenplay"
  SHOT=$(shot_of "$1")
  HIN=$2
  TOTAL=$3
  DUR=$4
  LAST=$5
}

# mask_box <id> <hin_s> <total_s> <dur_s> <last>: the box of everything the beat draws, when its
# animations are done (75 % of the beat): "x1 y1 x2 y2" or none.
mask_box() {
  beat_context "$@"
  scene_jq ass true >"$TMP/$1.mask.ass" || die "beat $1: the mask script failed"
  _probe=$(printf '%s %s' "$HIN" "$DUR" | jq -Rr 'split(" ") | map(tonumber) | (.[0] + (.[1] * 0.75))')
  textbox "$TMP/$1.mask.ass" "$_probe"
}

# scene_render <id> <out> <hin_s> <total_s> <dur_s> <last true|false> [<at_s>]
# A .png out makes a still at <at_s> (seconds into the clip); anything else a clip of <total_s>.
scene_render() {
  _id=$1
  _out=$2
  _at=${7:-}
  beat_context "$_id" "$3" "$4" "$5" "$6"
  ASS=$PROJ/build/scenes/$_id.ass
  scene_jq ass false >"$ASS.part" || die "beat $_id: the scene script failed"
  mv -f "$ASS.part" "$ASS"
  PLAN=$(scene_jq plan false) || die "beat $_id: the scene plan failed"

  # The captions must stay in the safe area: one frame of the mask, when the animations are done.
  _box=$(mask_box "$_id" "$HIN" "$TOTAL" "$DUR" "$LAST")
  if [ "$_box" = none ]; then
    note "beat $_id: warning: no caption or drawing in the picture"
  elif ! inside_safe "$_box"; then
    die "beat $_id: the picture leaves the safe area: box $_box, safe $(safe_rect) (x1 y1 x2 y2). Shorten the lines or lower text_layout.scale in the shotlist"
  fi

  # A 3d shot (shotlist kind "3d") takes the PNG sequence of reel blender as its picture, in place of
  # the background and its slow zoom. The captions and the SVG layers go over it as on any beat.
  # A still of a 3d beat before its frames exist falls back to the flat background.
  _fdir=$PROJ/frames/$_id
  _3d=false
  _fsha=
  if [ "$(printf '%s' "$SHOT" | jq -r '.kind // "flat"')" = 3d ]; then
    _first=
    for _p in "$_fdir"/*.png; do
      if [ -f "$_p" ] && [ ! -L "$_p" ]; then
        _first=$_p
        break
      fi
    done
    if [ -n "$_first" ]; then
      _3d=true
    else
      case "$_out" in
        *.png) note "beat $_id: warning: a 3d shot with no frames yet: the picture shows the flat background" ;;
        *) die "beat $_id is a 3d shot with no frames: the artist-3d runs reel blender $(basename "$PROJ") $_id" ;;
      esac
    fi
  fi
  _nf=$(printf '%s' "$TOTAL" | jq -Rr "tonumber * $FPS | round")
  if [ "$_3d" = true ]; then
    no_links "$_fdir" || die "beat $_id: frames/$_id has a symbolic link: reel blender writes files, not links"
    _bfps=$(pnum .blender.fps)
    _fsha=$(cat "$_fdir"/*.png | sha256sum | cut -d' ' -f1)
    _bgsha=3d
    _num=$(basename "$_first" .png)
    _start=$(printf '%s' "$_num" | jq -Rr 'tonumber')
    set -- -framerate "$_bfps" -start_number "$_start" -i "$_fdir/%04d.png"
    _graph="[0:v]fps=$FPS,scale=$W:$H:force_original_aspect_ratio=increase,crop=$W:$H,setsar=1,tpad=stop_mode=clone:stop_duration=$TOTAL[b0]"
  else
    ensure_bg
    _bgsha=$(sha_of "$BG")
    _z0=$(printf '%s' "$PLAN" | jq -r '.zoom[0]')
    _z1=$(printf '%s' "$PLAN" | jq -r '.zoom[1]')
    _grain=$(printf '%s' "$PLAN" | jq -r '.grain')
    set -- -framerate "$FPS" -loop 1 -t "$TOTAL" -i "$BG"
    _graph="[0:v]zoompan=z='$_z0+($_z1-$_z0)*on/$_nf':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=1:s=${W}x${H}:fps=$FPS"
    # The grain is seeded from the approved screenplay, so the same screenplay gives the same pixels.
    if [ "$_grain" != 0 ]; then _graph="$_graph,noise=alls=$_grain:allf=t:all_seed=$((0x$(printf '%.7s' "$APPROVED_HASH")))"; fi
    _graph="${_graph}[b0]"
  fi
  _dy0=$(printf '%s' "$PLAN" | jq -r '.diagram.y0')
  _dh=$(printf '%s' "$PLAN" | jq -r '.diagram.h')
  _dw=$(printf '%s' "$PLAN" | jq -r '.diagram.w')
  _k=0
  _keyfiles=
  # The layer names were checked by the plan (direction/svg/<name>.svg, no other folder, no space),
  # so the word split below cannot meet a space or a glob character.
  for _svg in $(printf '%s' "$PLAN" | jq -r '.layers[].svg'); do
    _k=$((_k + 1))
    plain_file "$PROJ/$_svg" || die "beat $_id: the layer $_svg is missing or is a link: the creative director draws it in direction/svg/"
    _png=$PROJ/build/layers/$_id-$_k.png
    svg_to_png -w "$_dw" -h "$_dh" "$PROJ/$_svg" "$_png" || die "resvg failed on $_svg"
    _at_k=$(printf '%s' "$PLAN" | jq -r ".layers[$((_k - 1))].at")
    _fade=$(printf '%s' "$PLAN" | jq -r ".layers[$((_k - 1))].fade")
    set -- "$@" -framerate "$FPS" -loop 1 -t "$TOTAL" -i "$_png"
    _graph="$_graph;[$_k:v]format=rgba,fade=t=in:st=$_at_k:d=$_fade:alpha=1[l$_k];[b$((_k - 1))][l$_k]overlay=x=(W-w)/2:y=$_dy0+($_dh-h)/2:format=auto[b$_k]"
    _keyfiles="$_keyfiles $PROJ/$_svg"
  done
  _graph="$_graph;[b$_k]ass=filename=$ASS:fontsdir=$FONTS,scale=out_color_matrix=bt709:out_range=tv,format=yuv420p[v]"

  # A clip is skipped only when nothing it depends on changed: the frame graph, the plan, the
  # captions, the SVG layers, the background, the profile, the fonts folder, and the two files
  # the gate stands on: the approved screenplay and the shotlist. A re-approved screenplay or a
  # new shotlist therefore renders every beat again; a clip never outlives its approval.
  # shellcheck disable=SC2086
  _key=$({
    printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n' "$_graph" "$PLAN" "$_nf" "$_bgsha" "$PJ" "$APPROVED_HASH" "$SHOTS_SHA" "$FONTS" "$_fsha"
    cat "$ASS" $_keyfiles
  } | sha256sum | cut -d' ' -f1)
  case "$_out" in
    *.png) ;;
    *)
      if [ -f "$_out" ] && [ -f "$_out.key" ] && [ "$(cat "$_out.key")" = "$_key" ]; then
        note "beat $_id: up to date"
        return 0
      fi
      rm -f "$_out" "$_out.key" "$_out.part"
      ;;
  esac

  case "$_out" in
    *.png)
      rm -f "$_out.part.png"
      ffp "$@" -filter_complex "$_graph" -map "[v]" -threads 2 -ss "$_at" -frames:v 1 -f image2 -update 1 "$_out.part.png" || die "beat $_id: ffmpeg failed"
      mv -f "$_out.part.png" "$_out"
      ;;
    *)
      ffp "$@" -filter_complex "$_graph" -map "[v]" -an -c:v libx264 -preset veryfast -crf "$(pnum .video.scene_crf)" \
        -pix_fmt yuv420p -colorspace bt709 -color_primaries bt709 -color_trc bt709 -color_range tv -r "$FPS" -frames:v "$_nf" -threads 2 \
        -fflags +bitexact -flags:v +bitexact -map_metadata -1 \
        -f mp4 "$_out.part" || die "beat $_id: ffmpeg failed"
      mv -f "$_out.part" "$_out"
      printf '%s\n' "$_key" >"$_out.key.part"
      mv -f "$_out.key.part" "$_out.key"
      ;;
  esac
}

# build_clip <beat id>: the clip of a beat, with the handles of its transitions, in build/scenes/.
build_clip() {
  # shellcheck disable=SC2046 # tl_vals prints five numbers; the split is the point
  set -- "$1" $(tl_vals "$1")
  [ $# -eq 6 ] || die "no beat $1 in the screenplay"
  _id=$1
  _s=$2
  _e=$3
  _hin=$4
  _frames=$6
  _last=false
  [ "$_id" = "$(printf '%s' "$TL" | jq -r '.[-1].id')" ] && _last=true
  _hin_s=$(printf '%s' "$_hin" | jq -Rr "tonumber / $FPS")
  _tot_s=$(printf '%s' "$_frames" | jq -Rr "tonumber / $FPS")
  _dur_s=$(printf '%s %s' "$_s" "$_e" | jq -Rr "split(\" \") | map(tonumber) | (.[1] - .[0]) / $FPS")
  scene_render "$_id" "$PROJ/build/scenes/$_id.mp4" "$_hin_s" "$_tot_s" "$_dur_s" "$_last"
}

cmd_scene() {
  [ $# -eq 2 ] || die "usage: reel scene <slug> <beat>"
  load_project "$1"
  require_shotlist "$1"
  build_clip "$2"
  say "scene $2: $PROJ/build/scenes/$2.mp4"
}

# still <slug> <beat> [--at <s>] [-o <file>]
cmd_still() {
  [ $# -ge 2 ] || die "usage: reel still <slug> <beat> [--at <seconds into the beat>] [-o <file.png>]"
  _slug=$1
  _id=$2
  shift 2
  _at=
  _o=
  while [ $# -gt 0 ]; do
    case "$1" in
      --at)
        [ $# -ge 2 ] || die "--at needs seconds"
        _at=$2
        shift 2
        ;;
      -o)
        [ $# -ge 2 ] || die "-o needs a file"
        _o=$2
        shift 2
        ;;
      *) die "unknown option: $1" ;;
    esac
  done
  case "$_o" in '' | *.png) ;; *) die "-o: the file must end in .png" ;; esac
  load_project "$_slug"
  if [ -f "$SHOTS" ]; then require_shotlist "$_slug"; fi
  # shellcheck disable=SC2046 # tl_vals prints five numbers; the split is the point
  set -- $(tl_vals "$_id")
  [ $# -eq 5 ] || die "no beat $_id in the screenplay"
  _dur_s=$(printf '%s %s' "$1" "$2" | jq -Rr "split(\" \") | map(tonumber) | (.[1] - .[0]) / $FPS")
  [ -n "$_at" ] || _at=$(printf '%s' "$_dur_s" | jq -Rr 'tonumber * 0.75 * 1000 | round / 1000')
  printf '%s %s' "$_at" "$_dur_s" | jq -Re 'split(" ") | map(tonumber) | .[0] >= 0 and .[0] < .[1]' >/dev/null 2>&1 || die "--at must be from 0 to $_dur_s seconds"
  _last=false
  [ "$_id" = "$(printf '%s' "$TL" | jq -r '.[-1].id')" ] && _last=true
  [ -n "$_o" ] || _o=$PROJ/direction/storyboard/$_id.png
  scene_render "$_id" "$_o" 0 "$_dur_s" "$_dur_s" "$_last" "$_at"
  say "still $_id at $_at s: $_o"
}
