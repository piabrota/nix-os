# fontxml.awk: the fonts of the text from `pdftohtml -xml` (poppler).
#
#   awk -f fontxml.awk fonts.xml
#
# Rows: BODY TAB family TAB size (the font with most characters), MAXSIZE TAB pt (the biggest size),
# NONBLACK TAB n (fonts whose colour is not black).

/<fontspec / {
  id = ""; size = 0; fam = ""; col = ""
  if (match($0, /id="[^"]*"/)) id = substr($0, RSTART + 4, RLENGTH - 5)
  if (match($0, /size="[^"]*"/)) size = substr($0, RSTART + 6, RLENGTH - 7) + 0
  if (match($0, /family="[^"]*"/)) fam = substr($0, RSTART + 8, RLENGTH - 9)
  if (match($0, /color="[^"]*"/)) col = substr($0, RSTART + 7, RLENGTH - 8)
  SIZE[id] = size; FAM[id] = fam
  if (tolower(col) != "#000000" && col != "") NB++
  next
}
/<text / {
  if (match($0, /font="[^"]*"/)) {
    id = substr($0, RSTART + 6, RLENGTH - 7)
    t = $0
    sub(/^[^>]*>/, "", t)
    sub(/<\/text>.*$/, "", t)
    gsub(/<[^>]*>/, "", t)
    CNT[id] += length(t)
    if (SIZE[id] > MAXS && length(t) > 2) MAXS = SIZE[id]
  }
}
END {
  best = ""
  for (id in CNT) if (best == "" || CNT[id] > CNT[best]) best = id
  printf "BODY\t%s\t%s\n", FAM[best], SIZE[best]
  printf "MAXSIZE\t%s\n", MAXS + 0
  printf "NONBLACK\t%d\n", NB + 0
}
