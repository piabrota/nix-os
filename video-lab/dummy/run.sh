#!/bin/sh
# Dummy video pipeline: a smoke check of the render path (stages 5 to 7 of
# docs/VIDEO-PIPELINE.md). It needs only ffmpeg and ffprobe. It tests nothing else.
set -eu

OUT="${VIDEO_LAB_OUT:-video-lab/out/dummy}"
SCENES="brief script voice visuals render"
FILE="$OUT/dummy.mp4"
fail() { echo "ARTIFACT FAILED: $1" >&2; exit 1; }

mkdir -p "$OUT"
rm -f "$FILE" "$OUT/captions.srt" "$OUT/report.json"
T="$OUT/tmp"
rm -rf "$T"
mkdir -p "$T"
: >"$T/times"

# Run a command at low priority. Record seconds and peak KiB in $T/times.
if env time -f "%e %M" true >/dev/null 2>&1; then
  timed() { env time -f "%e %M" -a -o "$T/times" nice -n 10 "$@"; }
else
  timed() {
    s=$(date +%s)
    nice -n 10 "$@"
    echo "$(($(date +%s) - s)) 0" >>"$T/times"
  }
fi
ff() { timed ffmpeg -nostdin -hide_banner -loglevel error -y -threads 2 "$@"; }

FONT=$(fc-list 2>/dev/null | grep -i -m1 '\.ttf' | cut -d: -f1 || true)
if [ -z "$FONT" ]; then echo "No .ttf font found: the clips have no text." >&2; fi

FREQS="220 262 330 392 440"
set -- 0x1d3557:0xa8dadc 0x6a040f:0xf48c06 0x1b4332:0x95d5b2 0x3c096c:0xe0aaff 0x03045e:0x90e0ef
i=0
START=0
for name in $SCENES; do
  i=$((i + 1))
  c0=${1%:*}
  c1=${1#*:}
  shift
  text="Scene $i: $name"
  printf '%s' "$text" >"$T/text$i.txt"
  vf="null"
  if [ -n "$FONT" ]; then
    vf="drawtext=fontfile=$FONT:textfile=$T/text$i.txt:fontsize=64:fontcolor=white:borderw=3:bordercolor=black:x=(w-text_w)/2+120*sin(t):y=(h-text_h)/2+30*cos(t)"
  fi
  # 1. Visuals: a moving gradient with a moving text.
  ff -f lavfi -i "gradients=s=1280x720:r=25:d=6:c0=$c0:c1=$c1:speed=0.05" \
    -vf "$vf,format=yuv420p" -c:v libx264 -preset veryfast -crf 23 "$T/v$i.mp4"
  # 2. Voice: a tone. This stands in for the TTS stage (stage 3) of the spec.
  freq=$(echo "$FREQS" | cut -d' ' -f"$i")
  ff -f lavfi -i "sine=f=$freq:r=44100:d=6" -af "afade=t=in:d=0.3,afade=t=out:st=5.7:d=0.3" \
    -ac 2 "$T/a$i.wav"
  # 4. Captions: one cue for each scene. A scene starts every 5.5 s (6 s minus the 0.5 s fade).
  {
    echo "$i"
    printf '00:00:%02d,%03d --> 00:00:%02d,%03d\n' \
      $((START / 1000)) $((START % 1000)) $(((START + 5000) / 1000)) $((START % 1000))
    echo "$text"
    echo
  } >>"$OUT/captions.srt"
  START=$((START + 5500))
done

# 3. Join: xfade for video, acrossfade for audio, then loudnorm.
inputs=""
graph=""
n=0
while [ "$n" -lt 5 ]; do
  inputs="$inputs -i $T/v$((n + 1)).mp4"
  n=$((n + 1))
done
n=0
while [ "$n" -lt 5 ]; do
  inputs="$inputs -i $T/a$((n + 1)).wav"
  n=$((n + 1))
done
prev="[0:v]"
aprev="[5:a]"
n=1
while [ "$n" -lt 5 ]; do
  graph="$graph${prev}[$n:v]xfade=transition=fade:duration=0.5:offset=$((n * 11 / 2)).$((n * 11 % 2 * 5))[v$n];"
  graph="$graph${aprev}[$((n + 5)):a]acrossfade=d=0.5[a$n];"
  prev="[v$n]"
  aprev="[a$n]"
  n=$((n + 1))
done
graph="${graph}${aprev}loudnorm=I=-16:TP=-1.5:LRA=11,aresample=48000[aout]"

# shellcheck disable=SC2086
ff $inputs -i "$OUT/captions.srt" -filter_complex "$graph" \
  -map "[v4]" -map "[aout]" -map 10:0 \
  -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p -r 25 \
  -c:a aac -b:a 128k -c:s mov_text -movflags +faststart "$FILE"

# 5. Report.
[ -f "$FILE" ] || fail "no output file"
probe() { ffprobe -v error "$@" -of csv=p=0 "$FILE"; }
bytes=$(wc -c <"$FILE" | tr -d ' ')
dur=$(probe -show_entries format=duration)
dur=$(echo "$dur" | awk '{printf "%.1f", $1}')
vstreams=$(probe -select_streams v -show_entries stream=index | wc -l)
astreams=$(probe -select_streams a -show_entries stream=index | wc -l)
sstreams=$(probe -select_streams s -show_entries stream=index | wc -l)
vcodec=$(probe -select_streams v:0 -show_entries stream=codec_name)
acodec=$(probe -select_streams a:0 -show_entries stream=codec_name)
wh=$(probe -select_streams v:0 -show_entries stream=width,height)
width=${wh%,*}
height=${wh#*,}
wall=$(awk '{s += $1} END {printf "%.1f", s}' "$T/times")
peak=$(awk '$2 > m {m = $2} END {printf "%d", m / 1024}' "$T/times")
mib=$(awk -v b="$bytes" 'BEGIN {printf "%.1f", b / 1048576}')
printf '{"file":"%s","bytes":%s,"duration_s":%s,"width":%s,"height":%s,"video_codec":"%s","audio_codec":"%s","subtitle_tracks":%s,"wall_s":%s,"peak_mib":%s}\n' \
  "$FILE" "$bytes" "$dur" "$width" "$height" "$vcodec" "$acodec" "$sstreams" "$wall" "$peak" >"$OUT/report.json"
rm -rf "$T"

# 6. Verdict.
[ "$bytes" -gt 102400 ] || fail "file is $bytes bytes, 100 KB or less"
[ "$vstreams" -eq 1 ] || fail "$vstreams video streams, expected 1"
[ "$astreams" -eq 1 ] || fail "$astreams audio streams, expected 1"
awk -v d="$dur" 'BEGIN {exit !(d >= 24 && d <= 32)}' || fail "duration $dur s, expected 24 to 32 s"
echo "ARTIFACT OK: $FILE (${dur}s, ${width}x${height}, $vcodec+$acodec, $mib MiB, peak $peak MiB)"
