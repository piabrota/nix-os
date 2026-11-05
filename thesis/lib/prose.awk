# prose.awk: the prose of one pandoc-markdown section, one sentence a row, with its source line.
#
#   awk -v abbr="dr dra prof ..." -f prose.awk sections/<id>.md
#
# Row: kind TAB para TAB line TAB words TAB text
#   kind  p paragraph, l list item, q block quote, h heading, c caption (figure or table)
#   para  a number, the same for the sentences of one paragraph
#   line  the line of the file where the sentence starts
#   words words that are not marks
# Marks in the text: §C§ a citation [@key], §N§ a narrative @key, §U§ a URL, §D§ a DOI, §F§ a
# footnote, MATH inline math, CODE a code span. A cross-reference ([@fig:x]) becomes "Figura 1".
# Skipped: code fences, display math, tables, comments, **[AUTHOR ...]** and **[ANALYSIS]** markers.
# Needs gawk in a UTF-8 locale (the toolkit's wrapper sets LC_ALL=C.UTF-8).

function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }

function unlink(s,    out, a, b, txt) {
  # [text](url) -> text
  out = ""
  while (match(s, /\[[^][]*\]\([^)]*\)/)) {
    a = substr(s, RSTART, RLENGTH)
    txt = a
    sub(/\]\(.*$/, "", txt)
    sub(/^\[/, "", txt)
    out = out substr(s, 1, RSTART - 1) txt
    s = substr(s, RSTART + RLENGTH)
  }
  return out s
}

function clean(s) {
  gsub(/\r/, "", s)
  gsub(/\*\*\[(AUTHOR|ANALYSIS)[^]]*\]\*\*/, " ", s)
  gsub(/!\[[^]]*\]\([^)]*\)(\{[^}]*\})?/, " ", s)
  gsub(/\[\^[^]]*\]/, " §F§ ", s)
  gsub(/\[@(fig|tbl|eq|sec|cap):[^]]*\]/, " Figura 1 ", s)
  gsub(/@(fig|tbl|eq|sec|cap):[A-Za-z0-9_-]+/, " Figura 1 ", s)
  gsub(/\[[^][]*@[^][]*\]/, " §C§ ", s)
  gsub(/(^|[ (])@[A-Za-z][A-Za-z0-9_:.-]*[A-Za-z0-9]/, " §N§", s)
  s = unlink(s)
  gsub(/\{[#.][^}]*\}/, " ", s)
  gsub(/\$[^$]+\$/, " MATH ", s)
  gsub(/`[^`]*`/, " CODE ", s)
  gsub(/<(https?:\/\/[^>]*)>/, " §U§ ", s)
  return s
}

function is_abbr(tok,    t) {
  t = tolower(tok)
  gsub(/[.)"”’]+$/, "", t)
  if (t in ABBR) return 1
  if (tok ~ /^[[:alpha:]]\.$/) return 1
  if (tok ~ /^[[:alpha:]]{1,3}(\.[[:alpha:]]{1,3})+\.$/) return 1
  return 0
}

function counts_as_word(tok) {
  if (tok ~ /^§[A-Z]§$/) return 0
  return tok ~ /[[:alnum:]]/
}

function flush_para(    i, n, sent, nw, startline, tok, nxt, end) {
  n = NW
  if (n == 0) return
  PARA++
  sent = ""
  nw = 0
  startline = WL[1]
  for (i = 1; i <= n; i++) {
    tok = W[i]
    if (sent == "") startline = WL[i]
    sent = (sent == "" ? tok : sent " " tok)
    if (counts_as_word(tok)) nw++
    end = 0
    if (i == n) end = 1
    else if (tok ~ /[.!?…]["”’)\]]*$/ && !is_abbr(tok)) {
      nxt = W[i + 1]
      if (nxt ~ /^["“‘(\[]?([[:upper:]]|[0-9]|§)/) end = 1
    }
    if (end) {
      if (nw > 0 || KIND == "h") printf "%s\t%d\t%d\t%d\t%s\n", KIND, PARA, startline, nw, sent
      sent = ""
      nw = 0
    }
  }
  NW = 0
}

function add_text(s, ln,    k, m, parts, tok) {
  s = clean(s)
  m = split(s, parts, /[ \t]+/)
  for (k = 1; k <= m; k++) {
    tok = parts[k]
    if (tok == "") continue
    gsub(/^[*_]+|[*_]+$/, "", tok)
    if (tok ~ /^https?:\/\//) tok = "§U§"
    else if (tok ~ /10\.[0-9][0-9][0-9][0-9]+\//) tok = "§D§"
    if (tok == "") continue
    NW++
    W[NW] = tok
    WL[NW] = ln
  }
}

BEGIN {
  n = split(abbr, A, " ")
  for (i = 1; i <= n; i++) ABBR[A[i]] = 1
  PARA = 0
  NW = 0
  KIND = "p"
  fence = 0
  mathblock = 0
}

{
  line = $0
  sub(/\r$/, "", line)

  if (line ~ /^[ ]{0,3}(```|~~~)/) { flush_para(); fence = !fence; next }
  if (fence) next
  if (line ~ /^[ ]*\$\$[ ]*$/) { flush_para(); mathblock = !mathblock; next }
  if (mathblock) next
  if (line ~ /^[ ]*\$\$.*\$\$/) { flush_para(); next }
  if (line ~ /^[ ]*<!--/) { flush_para(); next }

  if (line ~ /^[ \t]*$/) { flush_para(); KIND = "p"; next }

  if (line ~ /^[ ]*\|/ || line ~ /^[ ]*[+][-=+]+[+]/) { flush_para(); next }
  if (line ~ /^[ ]*\[\^[^]]+\]:/) { flush_para(); KIND = "f"; next }

  if (line ~ /^:[ ]/) {
    flush_para(); KIND = "c"; add_text(substr(line, 3), FNR); flush_para(); KIND = "p"; next
  }
  if (line ~ /^[ ]*!\[/) {
    flush_para(); KIND = "c"
    cap = line
    sub(/^[ ]*!\[/, "", cap)
    sub(/\]\(.*$/, "", cap)
    add_text(cap, FNR); flush_para(); KIND = "p"; next
  }
  if (line ~ /^[ ]{0,3}#+[ ]/) {
    flush_para(); KIND = "h"
    h = line
    sub(/^[ ]*#+[ ]+/, "", h)
    add_text(h, FNR); flush_para(); KIND = "p"; next
  }
  if (line ~ /^[ ]{0,3}>/) {
    if (KIND != "q") flush_para()
    KIND = "q"
    q = line
    sub(/^[ ]*>[ ]?/, "", q)
    add_text(q, FNR); next
  }
  if (line ~ /^[ ]*([-*+]|[0-9]+[.)])[ ]+/) {
    flush_para(); KIND = "l"
    li = line
    sub(/^[ ]*([-*+]|[0-9]+[.)])[ ]+/, "", li)
    add_text(li, FNR); next
  }
  if (KIND == "f") next
  if (KIND == "q" && line !~ /^[ ]{0,3}>/) { flush_para(); KIND = "p" }
  add_text(line, FNR)
}

END { flush_para() }
