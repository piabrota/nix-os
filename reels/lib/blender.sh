# blender.sh: `reel blender`, the 3D shots. Sourced by `reel`.
# shellcheck shell=sh
#
# One shot is one Blender Python scene, <project>/blender/<beat>.py, rendered headless to the PNG
# sequence <project>/frames/<beat>/%04d.png. The engine is Cycles on the CPU, always: EEVEE needs
# a GPU and a display, and it crashes on this box. The scene file is loaded first, and then a
# driver of the toolkit sets the engine, the device, the samples, no denoising, the size and the output, so a
# scene file cannot choose another engine. docs/REELS.md ("3D shots with Blender").

# The driver: run by Blender after the scene file. Options come after "--" as name/value pairs.
# probe prints the frame range and stops; render sets the contract and renders the animation.
write_blender_driver() {
  cat >"$1" <<'EOF'
import sys

import bpy

argv = sys.argv[sys.argv.index("--") + 1:]
opt = {argv[i]: argv[i + 1] for i in range(0, len(argv) - 1, 2)}
scene = bpy.context.scene

if opt["--reel-mode"] == "probe":
    print("REEL_FRAMES %d %d" % (scene.frame_start, scene.frame_end))
    sys.exit(0)

scene.render.engine = opt["--reel-engine"]
scene.cycles.device = opt["--reel-device"]
scene.cycles.samples = int(opt["--reel-samples"])
# The denoiser (OpenImageDenoise) took 1.6 GiB more at 1080x1920 (2174 MiB against 536 MiB in one
# frame, measured), and the unit has 2 GiB for every seat. A scene cannot turn it on.
scene.cycles.use_denoising = False
scene.render.resolution_x = int(opt["--reel-width"])
scene.render.resolution_y = int(opt["--reel-height"])
scene.render.resolution_percentage = 100
scene.render.fps = int(opt["--reel-fps"])
scene.render.fps_base = 1.0
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGB"
scene.render.use_file_extension = True
scene.render.filepath = opt["--reel-out"]
bpy.ops.render.render(animation=True)
EOF
}

# blender_run <mode probe|render> <scene file> <log file> [<output prefix>]: one Blender run, in a
# home of its own inside the project, never the real one. Low priority, with the time limit.
blender_run() {
  _bmode=$1
  _bhome=$PROJ/build/blender-home
  mkdir -p "$_bhome/config" "$_bhome/cache" || die "cannot make $_bhome"
  write_blender_driver "$TMP/reel_blender.py"
  _brc=0
  timed timeout -k 5 "$(pnum .limits.blender_timeout_s)" nice -n 10 \
    env HOME="$_bhome" XDG_CONFIG_HOME="$_bhome/config" XDG_CACHE_HOME="$_bhome/cache" \
    "$BLENDER" -b --factory-startup --threads "$(pnum .blender.threads)" --python-exit-code 1 \
    --python "$2" --python "$TMP/reel_blender.py" -- \
    --reel-mode "$_bmode" --reel-engine CYCLES --reel-device CPU --reel-samples "$(pnum .blender.samples)" \
    --reel-width "$W" --reel-height "$H" --reel-fps "$(pnum .blender.fps)" --reel-out "${4:-none}" \
    >"$3" 2>&1 || _brc=$?
  if [ "$_brc" -eq 124 ]; then note "blender stopped: no result after $(pnum .limits.blender_timeout_s) s"; fi
  return "$_brc"
}

cmd_blender() {
  [ $# -eq 2 ] || die "usage: reel blender <slug> <shot id> (the shot id is the beat id)"
  _slug=$1
  _id=$2
  load_project "$_slug"
  require_shotlist "$_slug"
  case "$_id" in
    b[0-9][0-9]) ;;
    *) die "the shot id is a beat id, like b03: $_id" ;;
  esac
  _kind=$(shot_of "$_id" | jq -r '.kind // "flat"')
  [ -n "$(shot_of "$_id" | jq -r '.beat // empty')" ] || die "no shot $_id in the shotlist"
  [ "$_kind" = 3d ] || die "shot $_id is not of kind 3d: the creative director marks it in direction/shotlist.json"
  BLENDER=${REELS_BLENDER:-}
  [ -n "$BLENDER" ] || BLENDER=$(command -v blender 2>/dev/null || true)
  [ -n "$BLENDER" ] && [ -x "$BLENDER" ] || die "blender is not in the PATH: it is off on this host (piabrota.openrig.reels.blender.enable, docs/REELS.md)"
  _scene=$PROJ/blender/$_id.py
  plain_file "$_scene" || die "no scene file (or a link): the artist-3d writes $_scene"
  _max=$(pnum .blender.max_frames)

  # The frame range first, so that a scene which is too long is refused before it costs minutes.
  _log=$TMP/blender-probe.log
  blender_run probe "$_scene" "$_log" || {
    tail -n 15 "$_log" >&2
    die "shot $_id: the scene file failed (blender exit code $_brc)"
  }
  _range=$(jq -Rrse 'capture("REEL_FRAMES (?<a>-?[0-9]+) (?<b>-?[0-9]+)") | "\(.a) \(.b)"' <"$_log" 2>/dev/null) ||
    die "shot $_id: the scene file did not give a frame range"
  _f0=${_range% *}
  _f1=${_range#* }
  _n=$((_f1 - _f0 + 1))
  [ "$_n" -ge 1 ] || die "shot $_id: frame_end ($_f1) is before frame_start ($_f0)"
  [ "$_n" -le "$_max" ] || die "shot $_id needs $_n frames: the budget is $_max (blender.max_frames in profile.json, $(pnum .blender.fps) fps). Shorten the scene"

  _dir=$PROJ/frames/$_id
  _part=$PROJ/frames/$_id.part
  rm -rf "$_part"
  mkdir -p "$_part" || die "cannot make $_part"
  note "shot $_id: $_n frames, Cycles on the CPU, $(pnum .blender.samples) samples, ${W}x${H}"
  _log=$TMP/blender-render.log
  blender_run render "$_scene" "$_log" "$_part/####" || {
    tail -n 15 "$_log" >&2
    rm -rf "$_part"
    die "shot $_id: blender failed (exit code $_brc)"
  }
  _got=0
  for _p in "$_part"/*.png; do
    [ -f "$_p" ] && _got=$((_got + 1))
  done
  if [ "$_got" -ne "$_n" ]; then
    tail -n 15 "$_log" >&2
    rm -rf "$_part"
    die "shot $_id: blender wrote $_got frames, not $_n"
  fi
  rm -rf "$_dir"
  mv "$_part" "$_dir" || die "cannot move the frames into place: $_dir"
  _last=$(tail -n 1 "$TIMES")
  say "blender $_id: $_dir ($_n frames, ${_last% *} s wall, $((${_last#* } / 1024)) MiB peak)"
}
