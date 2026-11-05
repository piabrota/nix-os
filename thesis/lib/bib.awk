# bib.awk: the entries of a BibTeX or BibLaTeX file, one field a row.
#
#   awk -f bib.awk refs.bib
#
# Row: key TAB type TAB field TAB value. The row with the field @entry has the line of the entry.
# Braces and quotes around a value are removed, white space is made one space, and the field name and
# the entry type are in lower case. @comment, @string and @preamble are skipped.

function skip_ws() { while (pos <= len && substr(S, pos, 1) ~ /[ \t\r\n]/) pos++ }

# A balanced {...} or (...) starting at pos; returns the inside, leaves pos after the close.
function balanced(    op, cl, depth, start, c) {
  op = substr(S, pos, 1)
  cl = (op == "{") ? "}" : ")"
  depth = 0
  start = pos + 1
  while (pos <= len) {
    c = substr(S, pos, 1)
    if (c == "\\") { pos += 2; continue }
    if (c == op) depth++
    else if (c == cl) { depth--; if (depth == 0) { pos++; return substr(S, start, pos - 1 - start) } }
    pos++
  }
  return substr(S, start)
}

function value(    c, v, start) {
  skip_ws()
  c = substr(S, pos, 1)
  if (c == "{") { v = balanced(); return v }
  if (c == "\"") {
    start = ++pos
    while (pos <= len && substr(S, pos, 1) != "\"") { if (substr(S, pos, 1) == "\\") pos++; pos++ }
    v = substr(S, start, pos - start)
    pos++
    return v
  }
  start = pos
  while (pos <= len && substr(S, pos, 1) !~ /[,} \t\r\n]/) pos++
  return substr(S, start, pos - start)
}

function lineof(p,    pre) { pre = substr(S, 1, p); return gsub(/\n/, "\n", pre) + 1 }

BEGIN { RS = "^$" }

{
  S = $0
  len = length(S)
  pos = 1
  while (pos <= len) {
    at = index(substr(S, pos), "@")
    if (at == 0) break
    pos += at
    atpos = pos
    start = pos
    while (pos <= len && substr(S, pos, 1) ~ /[A-Za-z]/) pos++
    type = tolower(substr(S, start, pos - start))
    skip_ws()
    if (type == "comment" || type == "string" || type == "preamble") {
      if (substr(S, pos, 1) == "{" || substr(S, pos, 1) == "(") balanced()
      continue
    }
    opener = substr(S, pos, 1)
    if (opener != "{" && opener != "(") continue
    pos++
    skip_ws()
    start = pos
    while (pos <= len && substr(S, pos, 1) !~ /[,}) \t\r\n]/) pos++
    key = substr(S, start, pos - start)
    printf "%s\t%s\t@entry\t%d\n", key, type, lineof(atpos)
    while (pos <= len) {
      skip_ws()
      c = substr(S, pos, 1)
      if (c == ",") { pos++; continue }
      if (c == "}" || c == ")") { pos++; break }
      start = pos
      while (pos <= len && substr(S, pos, 1) !~ /[= \t\r\n,}]/) pos++
      name = tolower(substr(S, start, pos - start))
      skip_ws()
      if (substr(S, pos, 1) != "=") { pos++; continue }
      pos++
      v = value()
      gsub(/[ \t\r\n]+/, " ", v)
      gsub(/^ | $/, "", v)
      printf "%s\t%s\t%s\t%s\n", key, type, name, v
    }
  }
}
