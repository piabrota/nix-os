# cites.awk: the citation facts of one section's raw markdown.
#
#   awk -v maxq=40 -f cites.awk sections/<id>.md
#
# Rows: KEY TAB key TAB line        a source key (@key or [@key]); cross-references @fig:x are not keys
#       QUOTE TAB line TAB words    an inline quotation longer than maxq words (must be a block quote)
#       HAND TAB line TAB text      a hand-typed (Author, 2016) mark
#       NUM TAB line TAB text       a numbered citation [3]
# Code fences, code spans and math are skipped.

function flush_para(    s, rest, w, q) {
  if (para == "") return
  s = para
  rest = s
  while (match(rest, /“[^”]+”/) || match(rest, /"[^"]+"/)) {
    q = substr(rest, RSTART, RLENGTH)
    w = split(q, tmp, /[ \t]+/)
    if (w > maxq + 0) printf "QUOTE\t%d\t%d\n", pline, w
    rest = substr(rest, RSTART + RLENGTH)
  }
  para = ""
}

BEGIN { fence = 0; mathblock = 0; para = "" }

{
  line = $0
  sub(/\r$/, "", line)
  if (line ~ /^[ ]{0,3}(```|~~~)/) { flush_para(); fence = !fence; next }
  if (fence) next
  if (line ~ /^[ ]*\$\$[ ]*$/) { flush_para(); mathblock = !mathblock; next }
  if (mathblock) next
  if (line ~ /^[ ]*\$\$.*\$\$/) next
  if (line ~ /^[ ]*$/) { flush_para(); next }
  gsub(/`[^`]*`/, "", line)
  gsub(/\$[^$]*\$/, "", line)

  rest = line
  while (match(rest, /(^|[^[:alnum:]_@\/.])@[A-Za-z0-9_][A-Za-z0-9_:.-]*[A-Za-z0-9_]/)) {
    k = substr(rest, RSTART, RLENGTH)
    sub(/^[^@]*@/, "", k)
    if (k !~ /^(fig|tbl|eq|sec|cap):/) printf "KEY\t%s\t%d\n", k, FNR
    rest = substr(rest, RSTART + RLENGTH)
  }
  rest = line
  while (match(rest, /\([A-ZÀ-Ú][A-Za-zÀ-ú' -]+( et al\.)?,[ ]?[0-9]{4}[a-z]?\)/)) {
    printf "HAND\t%d\t%s\n", FNR, substr(rest, RSTART, RLENGTH)
    rest = substr(rest, RSTART + RLENGTH)
  }
  rest = line
  while (match(rest, /\[[0-9]+([,–-][ ]?[0-9]+)*\]/)) {
    after = substr(rest, RSTART + RLENGTH, 1)
    if (after != "(" && after != ":") printf "NUM\t%d\t%s\n", FNR, substr(rest, RSTART, RLENGTH)
    rest = substr(rest, RSTART + RLENGTH)
  }
  if (para == "") pline = FNR
  para = (para == "" ? line : para " " line)
}

END { flush_para() }
