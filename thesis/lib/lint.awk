# lint.awk: the line checks of `thesis lint`, on the raw markdown of one section.
#
#   SECTION_ROLE=chapter SECTION_TITLE=... awk -v ranges=FILE -v markers=FILE -f lint.awk section.md
#
# Rows: FAIL|WARN TAB line TAB rule TAB message
#       LABEL TAB name TAB line     a label {#fig:x} {#tbl:x} {#eq:x} {#sec:x}
#       REF TAB name TAB line       a reference @fig:x or [@fig:x]
#       FIGFILE TAB path TAB line   the file of an image
# The cross-checks (a label that nobody cites, a file that is missing) are done by lint.sh.

function out(level, ln, rule, msg) { printf "%s\t%d\t%s\t%s\n", level, ln, rule, msg }

BEGIN {
  while ((getline line < ranges) > 0) {
    split(line, a, " ")
    for (cp = a[1] + 0; cp <= a[2] + 0; cp++) OK[sprintf("%c", cp)] = 1
  }
  close(ranges)
  NM = 0
  while ((getline line < markers) > 0) if (line != "") MARK[++NM] = line
  close(markers)
  role = ENVIRON["SECTION_ROLE"]
  pretext = (role == "resumo" || role == "abstract" || role == "agradecimentos" || role == "dedicatoria")
  fence = 0
  mathblock = 0
  tblopen = 0
  tblpending = 0
  lastnonblank = ""
}

{
  line = $0
  sub(/\r$/, "", line)
  ln = FNR

  # Characters the PDF engine can set. One finding a line.
  n = split(line, ch, "")
  for (i = 1; i <= n; i++) {
    if (!(ch[i] in OK)) {
      out("FAIL", ln, "character", "the character \"" ch[i] "\" cannot be set by the PDF engine (Portuguese letters and common punctuation only; math goes in $...$, symbols as words)")
      break
    }
  }

  # Placeholders.
  low = tolower(line)
  for (m = 1; m <= NM; m++) {
    if (index(line, MARK[m]) > 0 || index(low, tolower(MARK[m])) > 0 && MARK[m] ~ /^[a-z ]+$/) {
      out("FAIL", ln, "placeholder", "marker " MARK[m] " is still in the text")
      break
    }
  }

  if (line ~ /^[ ]{0,3}(```|~~~)/) { fence = !fence; next }
  if (fence) next
  if (line ~ /^[ ]*\$\$[ ]*$/) { mathblock = !mathblock; next }
  if (mathblock) next
  if (line ~ /^[ ]*\$\$.*\$\$/) {
    if (match(line, /\{#eq:[A-Za-z0-9_-]+\}/)) printf "LABEL\t%s\t%d\n", substr(line, RSTART + 2, RLENGTH - 3), ln
    next
  }

  # References, anywhere in the prose.
  rest = line
  while (match(rest, /@(fig|tbl|eq|sec|cap):[A-Za-z0-9_-]+/)) {
    printf "REF\t%s\t%d\n", substr(rest, RSTART + 1, RLENGTH - 1), ln
    rest = substr(rest, RSTART + RLENGTH)
  }

  stripped = line
  gsub(/`[^`]*`/, "", stripped)
  gsub(/\$[^$]*\$/, "", stripped)

  if (stripped ~ /\\[A-Za-z@]+/) out("WARN", ln, "raw-tex", "a backslash command is printed as text: raw TeX is switched off")
  if (stripped ~ /<[A-Za-z\/!]/ && stripped !~ /<https?:/) out("WARN", ln, "raw-html", "HTML is dropped: raw HTML is switched off")
  if (stripped ~ /\[[0-9]+([,–-][0-9]+)*\]/ && stripped !~ /\]\(/) out("FAIL", ln, "numeric-citation", "a numbered citation [n]: the system is author-date, write [@key]")

  if (line ~ /^[ ]*$/) {
    if (tblopen) { tblopen = 0; tblpending = 1 }
    next
  }

  # Headings.
  if (line ~ /^[ ]{0,3}#+[ ]/) {
    h = line
    lvl = h
    sub(/[^#].*$/, "", lvl)
    sub(/^[ ]*#+[ ]+/, "", h)
    if (pretext) out("FAIL", ln, "pretext-heading", "this sheet has no headings")
    if (h ~ /^[0-9]+([.][0-9]+)*[.)]?[ ]/) out("FAIL", ln, "heading-number", "do not number headings by hand: LaTeX numbers them")
    if (length(lvl) > 4) out("WARN", ln, "heading-depth", "heading of level " length(lvl) " (at most 4 are used)")
    if (match(h, /\{#sec:[A-Za-z0-9_-]+\}/)) printf "LABEL\t%s\t%d\n", substr(h, RSTART + 2, RLENGTH - 3), ln
    hseen++
    tblpending = 0
    lastnonblank = line
    next
  }

  # Lists on a sheet that must be one paragraph.
  if (pretext && line ~ /^[ ]*([-*+]|[0-9]+[.)])[ ]+/) out("FAIL", ln, "pretext-list", "this sheet is one paragraph of text, not a list")

  # Images: a caption and a label are required, so that the figure is numbered and can be cited.
  if (line ~ /^[ ]*!\[/) {
    cap = line
    sub(/^[ ]*!\[/, "", cap)
    sub(/\]\([^)]*\)[^]]*$/, "", cap)
    path = line
    sub(/^.*\]\(/, "", path)
    sub(/[)].*$/, "", path)
    sub(/[ ].*$/, "", path)
    if (cap ~ /^[ ]*$/) out("FAIL", ln, "figure-caption", "a figure needs a caption (the text between [ ])")
    if (!match(line, /\{[^}]*#fig:[A-Za-z0-9_-]+[^}]*\}/)) out("FAIL", ln, "figure-label", "a figure needs a label, as {#fig:name}, so that the text can cite it")
    else {
      lab = substr(line, RSTART, RLENGTH)
      match(lab, /#fig:[A-Za-z0-9_-]+/)
      printf "LABEL\t%s\t%d\n", substr(lab, RSTART + 1, RLENGTH - 1), ln
    }
    printf "FIGFILE\t%s\t%d\n", path, ln
    figs++
    next
  }

  # Tables: pipe or grid rows, a caption `: text {#tbl:name}` above or below.
  if (line ~ /^[ ]*\|/ || line ~ /^[ ]*[+][-=+]+[+][ ]*$/) {
    if (!tblopen) { tblopen = 1; tbls++; tblstart = ln }
    next
  }
  if (line ~ /^:[ ]/) {
    caplines++
    if (match(line, /\{#tbl:[A-Za-z0-9_-]+\}/)) printf "LABEL\t%s\t%d\n", substr(line, RSTART + 2, RLENGTH - 3), ln
    else out("FAIL", ln, "table-label", "a table caption needs a label, as {#tbl:name}, so that the text can cite it")
    tblopen = 0
    lastnonblank = line
    next
  }
  if (tblopen) { tblopen = 0 }
  tblpending = 0
  lastnonblank = line
}

END {
  if (tbls != caplines + 0) {
    out("FAIL", tblstart, "table-caption", tbls " table(s) but " caplines + 0 " caption line(s) `: caption {#tbl:name}`")
  }
  printf "COUNT\theadings\t%d\n", hseen
  printf "COUNT\tfigures\t%d\n", figs
  printf "COUNT\ttables\t%d\n", tbls
}
