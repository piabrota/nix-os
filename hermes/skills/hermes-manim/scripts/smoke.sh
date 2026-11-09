#!/bin/sh
# Render smoke.py (a title, an equation and a circle) to a temp dir and check the video.
# Prints the path and size of Smoke.mp4 and `ok`. Exit 1: the render failed. Exit 2: no manim.
# No network, no secret.
set -eu

if ! command -v manim >/dev/null 2>&1; then
  echo "manim: not found on PATH"
  exit 2
fi

here=$(cd "$(dirname "$0")" && pwd)
d=$(mktemp -d "${TMPDIR:-/tmp}/hermes-manim.XXXXXX")
trap 'rm -rf "$d"' EXIT

if ! manim -ql --disable_caching --media_dir "$d/media" "$here/smoke.py" Smoke >"$d/out.log" 2>&1; then
  tail -n 20 "$d/out.log"
  exit 1
fi

mp4=$(find "$d/media" -name Smoke.mp4 | head -n 1)
if [ -z "$mp4" ] || [ ! -s "$mp4" ]; then
  echo "Smoke.mp4 is missing or empty"
  tail -n 20 "$d/out.log"
  exit 1
fi

echo "$mp4 $(wc -c <"$mp4") bytes"
echo ok
