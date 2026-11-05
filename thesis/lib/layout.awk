# From `thesis-layout key=value` lines of the TeX log: the exact margins in mm and the baselineskip in pt.
{ if (match($0, /^thesis-layout [a-z]+=/)) { k = substr($0, 15, RLENGTH - 15); v = substr($0, RLENGTH + 1); sub(/pt.*$/, "", v); V[k] = v + 0 } }
END {
  if (!("textwidth" in V)) exit 0
  pt = 25.4 / 72.27
  left = (72.27 + V["hoffset"] + V["oddsidemargin"]) * pt
  right = V["paperwidth"] * pt - left - V["textwidth"] * pt
  top = (72.27 + V["voffset"] + V["topmargin"] + V["headheight"] + V["headsep"]) * pt
  bottom = V["paperheight"] * pt - top - V["textheight"] * pt
  printf "%.2f %.2f %.2f %.2f %.2f\n", top, bottom, left, right, V["baselineskip"]
}
