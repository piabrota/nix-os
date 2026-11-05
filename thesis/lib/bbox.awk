# bbox.awk: margins and line pitch from `pdftotext -bbox-layout` (poppler), page by page.
#
#   awk -v zone=60 -f bbox.awk bbox.html
#
# Rows: MIN TAB top|bottom|left|right TAB mm (the smallest margin of any page, in mm), PITCH TAB pt (the
# median distance between consecutive lines of the pages with 20 lines or more). A line that is only a
# page number (digits or roman numerals) in the last `zone` pt of the page is the footer and is left
# out: the template puts the number inside the bottom margin.

function attr(s, name,    re) {
  re = name "=\"[^\"]*\""
  if (match(s, re)) return substr(s, RSTART + length(name) + 2, RLENGTH - length(name) - 3) + 0
  return 0
}

function median(arr, n,    i, j, t, a2) {
  for (i = 1; i <= n; i++) a2[i] = arr[i]
  for (i = 2; i <= n; i++) { t = a2[i]; for (j = i - 1; j >= 1 && a2[j] > t; j--) a2[j + 1] = a2[j]; a2[j + 1] = t }
  if (n == 0) return 0
  return (n % 2) ? a2[(n + 1) / 2] : (a2[n / 2] + a2[n / 2 + 1]) / 2
}

function end_page(    i, d) {
  if (nl >= 20) for (i = 2; i <= nl; i++) { d = Y[i] - Y[i - 1]; if (d >= 15 && d <= 40) P[++np] = d }
  nl = 0
}

BEGIN { mt = 1e9; mb = 1e9; ml = 1e9; mr = 1e9; np = 0; nl = 0 }

/<page / { end_page(); W = attr($0, "width"); H = attr($0, "height"); next }
/<line / { lx0 = attr($0, "xMin"); ly0 = attr($0, "yMin"); lx1 = attr($0, "xMax"); ly1 = attr($0, "yMax"); words = 0; txt = ""; next }
/<word / {
  words++
  t = $0
  sub(/^[^>]*>/, "", t)
  sub(/<\/word>.*$/, "", t)
  txt = (words == 1 ? t : txt " " t)
  next
}
/<\/line>/ {
  if (words == 1 && txt ~ /^([0-9]+|[ivxlcdm]+)$/ && ly0 > H - zone) next
  nl++
  Y[nl] = ly0
  if (lx0 * 25.4 / 72 < ml) ml = lx0 * 25.4 / 72
  if ((W - lx1) * 25.4 / 72 < mr) mr = (W - lx1) * 25.4 / 72
  if (ly0 * 25.4 / 72 < mt) mt = ly0 * 25.4 / 72
  if ((H - ly1) * 25.4 / 72 < mb) mb = (H - ly1) * 25.4 / 72
  next
}

END {
  end_page()
  printf "MIN\ttop\t%.1f\nMIN\tbottom\t%.1f\nMIN\tleft\t%.1f\nMIN\tright\t%.1f\n", mt, mb, ml, mr
  printf "PITCH\t%.2f\n", median(P, np)
}
