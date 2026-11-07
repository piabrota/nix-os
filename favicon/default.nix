# The org's mark as the icon of every site under piabrota.art: favicon.svg (favicon.svg of this
# directory, the drawing of parts.eye), favicon.ico (PNGs of 16, 32 and 48 px in one ICO) and
# apple-touch-icon.png (180 px). resvg runs on the builder only. allowedReferences = [ ] fails the
# build if the output names any store path, so resvg never reaches a host's closure.
{ lib, runCommand, resvg }:
runCommand "piabrota-favicon"
{
  nativeBuildInputs = [ resvg ];
  allowedReferences = [ ];
} ''
  mkdir -p $out
  cp ${./favicon.svg} $out/favicon.svg
  resvg -w 180 -h 180 ${./favicon.svg} $out/apple-touch-icon.png

  # An ICO is a header, one 16-byte entry for each image, then the images: here PNGs. Numbers are
  # little endian; printf writes the bytes in octal, as POSIX sh has no \x.
  le() { # $1 bytes, $2 value
    n=$2; i=0
    while [ "$i" -lt "$1" ]; do
      printf "\\$(printf %03o $((n % 256)))"
      n=$((n / 256)); i=$((i + 1))
    done
  }
  sizes="${lib.concatStringsSep " " (map toString [ 16 32 48 ])}"
  count=0; for s in $sizes; do count=$((count + 1)); resvg -w $s -h $s ${./favicon.svg} icon-$s.png; done
  {
    le 2 0; le 2 1; le 2 $count
    offset=$((6 + 16 * count))
    for s in $sizes; do
      bytes=$(wc -c < icon-$s.png)
      le 1 $s; le 1 $s; le 1 0; le 1 0; le 2 1; le 2 32; le 4 $bytes; le 4 $offset
      offset=$((offset + bytes))
    done
    for s in $sizes; do cat icon-$s.png; done
  } > $out/favicon.ico
''
