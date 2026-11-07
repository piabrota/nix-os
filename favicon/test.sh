#!/bin/sh
# Checks of the favicon build (favicon/default.nix). `sh favicon/test.sh <favicon output> <repo root>`.
# Needs xmllint, od and wc. Prints "N checks, M failed"; exits 1 on a failure.
set -u
out=${1:?usage: test.sh <favicon output> <repo root>}
root=${2:?usage: test.sh <favicon output> <repo root>}
checks=0 failed=0
check() { # description, got, want
  checks=$((checks + 1))
  if [ "$2" != "$3" ]; then failed=$((failed + 1)); printf 'FAIL %s: got [%s], want [%s]\n' "$1" "$2" "$3"; fi
}

svg=$out/favicon.svg
ico=$out/favicon.ico
png=$out/apple-touch-icon.png
for f in "$svg" "$ico" "$png"; do
  check "$(basename "$f") is not empty" "$([ -s "$f" ] && echo yes)" yes
done
check "the output holds the three files only" "$(cd "$out" && echo *)" "apple-touch-icon.png favicon.ico favicon.svg"

# The SVG: XML, an XML namespace, nothing that runs or loads.
check "favicon.svg is XML" "$(xmllint --noout "$svg" 2>&1 && echo yes)" yes
check "favicon.svg has the SVG namespace" "$(grep -c 'xmlns="http://www.w3.org/2000/svg"' "$svg")" 1
check "favicon.svg has no script, no link, no aria-hidden" "$(grep -cE '<script|href=|aria-hidden|onload|<image|<style|url\(' "$svg")" 0
check "favicon.svg names no URL but its namespace" "$(grep -Eo 'https?://[^"]+' "$svg")" "http://www.w3.org/2000/svg"

# The SVG is the drawing of parts.eye: the same viewBox, radius, path, circles and colours, in order.
eye=$(sed -n '/^pub fn eye/,/^}/p' "$root/site/src/piabrota_site/parts.gleam")
for attr in viewBox rx d fill cx cy r; do
  in_svg=$(grep -Eo " $attr=\"[^\"]*\"" "$svg" | sed "s/^ $attr=\"//; s/\"\$//" | tr '\n' '|')
  in_gleam=$(printf '%s\n' "$eye" | grep -Eo "a\(\"$attr\", \"[^\"]*\"\)" | sed "s/^a(\"$attr\", \"//; s/\")\$//" | tr '\n' '|')
  check "$attr is the one of parts.eye" "$in_svg" "$in_gleam"
done
# The other copies of the mark carry the same shapes.
for f in figures-site/default.nix skills-site/src/www.gleam; do
  for part in 'd=.M12 50 Q50 18 88 50 Q50 82 12 50Z' '#BC2318' '#F7F3EA' '#2E9E4F' '#0B0D12'; do
    check "$f has $part" "$(grep -cE "$part" "$root/$f" | sed 's/^0$/no/; s/^[1-9][0-9]*$/yes/')" yes
  done
done

# The ICO: a header (reserved 0, type 1, count 3), a 16-byte entry for each image (16, 32 and 48 px),
# then PNGs that fill the file to its last byte.
le() { # file, offset, bytes: the little-endian number there
  od -An -t u1 -j "$2" -N "$3" "$1" | awk '{ n = 0; for (i = NF; i >= 1; i--) n = n * 256 + $i; print n }'
}
check "ico reserved" "$(le "$ico" 0 2)" 0
check "ico type" "$(le "$ico" 2 2)" 1
check "ico count" "$(le "$ico" 4 2)" 3
end=$((6 + 16 * 3))
for i in 0 1 2; do
  e=$((6 + 16 * i))
  size=$(le "$ico" $((e + 8)) 4)
  offset=$(le "$ico" $((e + 12)) 4)
  check "ico entry $i width" "$(le "$ico" "$e" 1)" "$(echo 16 32 48 | cut -d' ' -f$((i + 1)))"
  check "ico entry $i height" "$(le "$ico" $((e + 1)) 1)" "$(echo 16 32 48 | cut -d' ' -f$((i + 1)))"
  check "ico entry $i bits" "$(le "$ico" $((e + 6)) 2)" 32
  check "ico entry $i starts where the last ended" "$offset" "$end"
  check "ico entry $i is a PNG" "$(od -An -t x1 -j "$offset" -N 8 "$ico" | tr -d ' \n')" 89504e470d0a1a0a
  check "ico entry $i PNG is as wide as its entry" "$(le "$ico" $((offset + 16 + 3)) 1)" "$(le "$ico" "$e" 1)"
  end=$((offset + size))
done
check "ico ends with its last image" "$(wc -c < "$ico" | tr -d ' ')" "$end"

# The touch icon: a PNG of 180 by 180 px (big endian width and height in the IHDR).
check "touch icon is a PNG" "$(od -An -t x1 -N 8 "$png" | tr -d ' \n')" 89504e470d0a1a0a
check "touch icon is 180 px wide" "$(od -An -t u1 -j 16 -N 4 "$png" | awk '{ print $1 * 16777216 + $2 * 65536 + $3 * 256 + $4 }')" 180
check "touch icon is 180 px high" "$(od -An -t u1 -j 20 -N 4 "$png" | awk '{ print $1 * 16777216 + $2 * 65536 + $3 * 256 + $4 }')" 180

printf '%s checks, %s failed\n' "$checks" "$failed"
[ "$failed" = 0 ]
