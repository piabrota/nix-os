# ufrj.sh: gate 3, the patterns of the UFRJ final project (whole work). Sourced by `thesis`.
# Every rule prints PASS, FAIL or CANNOT-CHECK with its source. Sources:
#   R = Resolução nº 05/2012 of the Escola Politécnica, Anexo "Normas de Elaboração Gráfica" (IN FORCE)
#   N = Norma Gráfica 2026 (a PROPOSAL for the Congregação; the 2012 text stays in force until it is approved)
#   M = SiBI Manual for UFRJ academic works, 9th ed. (read only as search snippets: not checked in full)
# shellcheck shell=sh
# shellcheck disable=SC2034,SC2329,SC2015,SC2129,SC2016
# (SC2034 and SC2329: the libraries share variables and functions through `thesis`, which sources them all;
# SC2015: the `A && B || C` forms end in a die; SC2016: sh -c and awk programs in single quotes are meant.)

UF_PASS=0
UF_FAIL=0
UF_CC=0
# uf <PASS|FAIL|CANNOT-CHECK> <source> <id> <rule> <detail>
uf() {
  case "$1" in
    PASS) UF_PASS=$((UF_PASS + 1)) ;;
    FAIL) UF_FAIL=$((UF_FAIL + 1)) ;;
    *) UF_CC=$((UF_CC + 1)) ;;
  esac
  printf '%-12s %-22s %-4s %s: %s\n' "$1" "[$2]" "$3" "$4" "$5"
}

squash() { tr '\n' ' ' | sed 's/[ \t][ \t]*/ /g; s/^ //; s/ $//'; }

# page_has <n> <text>: the squashed page n contains the text (exact).
page_has() {
  [ -f "$UFP/$1.txt" ] || return 1
  squash <"$UFP/$1.txt" | grep -Fq -- "$2"
}

# first_page <text>: the first page whose text has the line or phrase; empty when none.
first_page() {
  _fp=1
  while [ "$_fp" -le "$UFN" ]; do
    if grep -Fq -- "$1" "$UFP/$_fp.txt"; then printf '%s' "$_fp"; return 0; fi
    _fp=$((_fp + 1))
  done
  return 0
}

roman() { # <n up to 39>
  awk -v n="$1" 'BEGIN { split("x xx xxx xl", t, " "); split("i ii iii iv v vi vii viii ix", o, " "); s = ""; if (n >= 10) { s = t[int(n / 10)] } if (n % 10) s = s o[n % 10]; print s }'
}

cmd_ufrj_check() {
  [ $# -eq 1 ] || die "usage: thesis ufrj-check <slug>"
  need_tools pdftotext pdfinfo
  need_project "$1"
  need_template "$(jq -r '.template // empty' "$P/thesis.json")"
  _pdf=$P/build/thesis.pdf
  UFP=$TMP/ufpages
  mkdir -p "$UFP"
  say "ufrj-check: $SLUG"
  say "  R = Resolução nº 05/2012 (in force). N = Norma Gráfica 2026 (a proposal, not in force). M = SiBI Manual 9th ed. (read only as snippets)."
  _j() { jq -r "$1" "$P/thesis.json"; }

  # --- rules from thesis.json alone
  if [ "$(_j .language)" = pt-BR ]; then uf PASS "R intro; N 6.1" U01 language "Portuguese (pt-BR)"; else uf FAIL "R intro; N 6.1" U01 language "the work is written in Portuguese; English or Spanish need a justification to the Curso"; fi
  _course=$(_j .course)
  if jq -e --arg c "$_course" '.courses | map(.name) | index($c)' "$PROFILE" >/dev/null 2>&1; then uf PASS "N 5.1, 5.2" U02 course "\"$_course\" is a course of the Escola Politécnica (\"Curso de $_course\" form in every sheet is checked below)"; else uf FAIL "N 5.1" U02 course "\"$_course\" is not in the list of courses"; fi
  _degree=$(jq -r --arg c "$_course" '.courses[] | select(.name == $c) | .title' "$PROFILE")
  if [ "$(_j .citation_style)" = author-date ]; then uf PASS "R 3.1; N 9.1" U03 citation-system "author-date for the whole work (one CSL file, one reference list)"; else uf FAIL "R 3.1; N 9.1" U03 citation-system "one system for the whole work: author-date"; fi
  _numcit=0
  for _id in $(order_ids); do
    _f=$(section_file "$_id")
    plain_file "$_f" || continue
    _n=$(awk -v maxq=9999 -f "$LIB/cites.awk" "$_f" | awk -F'\t' '$1 == "NUM" { n++ } END { print n + 0 }')
    _numcit=$((_numcit + _n))
  done
  if [ "$_numcit" -eq 0 ]; then uf PASS "R 3.1" U04 no-numbered-citations "no [n] citation in any section"; else uf FAIL "R 3.1" U04 no-numbered-citations "$_numcit numbered citation(s): the system is author-date"; fi
  # The textual parts of the Resolution: Introdução, Revisão, Metodologia, Resultados, Conclusões (Discussão may be grouped).
  _missing=
  for _part in introducao revisao metodologia resultados conclusoes; do
    jq -e --arg p "$_part" '.sections | any(.status != "omit" and .part == $p)' "$P/thesis.json" >/dev/null || _missing="$_missing $_part"
  done
  if [ -z "$_missing" ]; then uf PASS "R §2" U05 textual-parts "Introdução, Revisão da Literatura, Metodologia, Resultados and Conclusões are there (Discussão may be grouped with Resultados)"; else uf FAIL "R §2" U05 textual-parts "no section for:$_missing (field part in thesis.json)"; fi
  if jq -e '.sections | any(.status != "omit" and .role == "resumo") and any(.status != "omit" and .role == "abstract")' "$P/thesis.json" >/dev/null; then uf PASS "R §1 g; N 7.1" U06 resumo-and-abstract "both sections are in the work"; else uf FAIL "R §1 g; N 7.1" U06 resumo-and-abstract "the work needs a resumo and an abstract"; fi
  _pt=$(jq -r '.sections | map(select(.status != "omit" and .kind == "pretextual")) | max_by(.order) | .order // 0' "$P/thesis.json")
  _tx=$(jq -r '.sections | map(select(.status != "omit" and .kind == "textual")) | min_by(.order) | .order // 0' "$P/thesis.json")
  if [ "$_pt" -lt "$_tx" ]; then uf PASS "R §1, §2" U07 order-of-parts "pre-textual, textual, post-textual sections are in that order"; else uf FAIL "R §1, §2" U07 order-of-parts "a pre-textual section has a higher order than a textual one"; fi

  # --- rules that need the built PDF
  if ! plain_file "$_pdf"; then
    uf CANNOT-CHECK "-" U10 pdf "no build/thesis.pdf: run thesis assemble, then ufrj-check again"
    say "ufrj-check: $SLUG: $UF_PASS pass, $UF_FAIL fail, $UF_CC cannot-check"
    [ "$UF_FAIL" -eq 0 ]
    return
  fi
  timeout -k 5 "$POPPLER_TIMEOUT" pdftotext -layout "$_pdf" "$TMP/uf.txt" || die "$SLUG: pdftotext failed"
  awk -v d="$UFP" 'BEGIN { RS = "\f" } { if ($0 ~ /[^ \t\n]/) print > (d "/" NR ".txt") }' "$TMP/uf.txt"
  UFN=$(find "$UFP" -name '*.txt' | wc -l | tr -d ' ')
  _courseup=$(printf '%s' "$_course" | jq -R "$JQ_UPCASE upcase")
  _courseup=$(printf '%s' "$_courseup" | sed 's/^"//; s/"$//')
  _title=$(_j .title)
  _titleup=$(jq -n -r --arg t "$_title" "$JQ_UPCASE"'$t | upcase')
  _year=$(_j .year)
  _month=$(jq -r --argjson m "$MONTHS" '$m[.month - 1]' "$P/thesis.json")
  _monthup=$(jq -n -r --arg t "$_month" "$JQ_UPCASE"'$t | upcase')

  # capa (page 1)
  if page_has 1 "UNIVERSIDADE FEDERAL DO RIO DE JANEIRO" && page_has 1 "ESCOLA POLITÉCNICA" && page_has 1 "CURSO DE $_courseup" && page_has 1 "$_titleup"; then
    _l1=$(grep -n 'UNIVERSIDADE FEDERAL' "$UFP/1.txt" | head -n 1 | cut -d: -f1)
    _l2=$(grep -n 'ESCOLA POLITÉCNICA' "$UFP/1.txt" | head -n 1 | cut -d: -f1)
    _l3=$(grep -n "CURSO DE $_courseup" "$UFP/1.txt" | head -n 1 | cut -d: -f1)
    if [ "$_l1" -lt "$_l2" ] && [ "$_l2" -lt "$_l3" ]; then uf PASS "N 3.3; R §1 a" U10 capa "the institution in three capital lines (UFRJ, Escola Politécnica, Curso de ...) and the title"; else uf FAIL "N 3.3" U10 capa "the three institution lines are not in order"; fi
  else
    uf FAIL "N 3.3; R §1 a" U10 capa "page 1 lacks the three capital lines or the title"
  fi
  _logo=$(_j '.assets.ufrj_logo // empty')
  if [ -n "$_logo" ] && plain_file "$P/$_logo"; then uf PASS "N 3.1" U11 capa-logos "UFRJ logo ($_logo) left and the Poli logo right, same height (by construction of the overlay; the look is not measured)"; else uf FAIL "N 3.1" U11 capa-logos "no UFRJ logo: put the file under assets/ and set assets.ufrj_logo in thesis.json (the toolkit does not carry the UFRJ mark)"; fi
  _nlogo=$(grep -c 'includegraphics' "$P/build/tex/pt/main.tex" || true)
  _incover=$(awk '/% --- Capa/ { on = 1 } /% --- Folha de rosto/ { on = 0 } on && /includegraphics/ { n++ } END { print n + 0 }' "$P/build/tex/pt/main.tex")
  if [ "$_nlogo" -eq "$_incover" ] && [ "$_incover" -le 2 ]; then uf PASS "N 3.2, 4.1" U12 no-other-logo "the only images the overlay places are on the cover ($_incover); no logo on the folha de rosto or de aprovação"; else uf FAIL "N 3.2, 4.1" U12 no-other-logo "$_nlogo images in the front pages, $_incover on the cover"; fi
  uf CANNOT-CHECK "N 3.2" U13 figures-are-not-logos "whether a figure inside a chapter is a logo cannot be told by a script"

  # folha de rosto (page 2): the natureza sentence of norma 4.2
  _nat="Projeto de Graduação apresentado ao Curso de $_course da Escola Politécnica, Universidade Federal do Rio de Janeiro, como requisito parcial à obtenção do título de $_degree."
  if page_has 2 "$_nat"; then uf PASS "N 4.2; R §1 b" U14 natureza "the sentence of norma 4.2 is on the folha de rosto, with the course and the title conferred"; else uf FAIL "N 4.2; R §1 b" U14 natureza "the sentence \"$_nat\" is not on page 2"; fi
  if page_has 2 "$_month de $_year"; then uf PASS "R §1 b" U15 rosto-date "month and year of the defence"; else uf FAIL "R §1 b" U15 rosto-date "\"$_month de $_year\" is not on page 2"; fi
  # folha de aprovação (page 3)
  if page_has 3 "Examinada por" && page_has 3 "RIO DE JANEIRO, RJ" && page_has 3 "$_monthup DE $_year" && page_has 3 "$_titleup"; then uf PASS "R Anexo III" U16 aprovacao "title in capitals, \"Examinada por\", the city and state in capitals, the month and year in capitals"; else uf FAIL "R Anexo III" U16 aprovacao "page 3 lacks the title in capitals, \"Examinada por\", the city or the date in capitals"; fi
  _hy=$(grep -c -- '-[ ]*$' "$UFP/3.txt" || true)
  if [ "$_hy" -eq 0 ]; then uf PASS "R Anexo III item 9" U17 aprovacao-no-hyphenation "no line of the folha de aprovação ends in a hyphen"; else uf FAIL "R Anexo III item 9" U17 aprovacao-no-hyphenation "$_hy line(s) end in a hyphen"; fi
  _last3=$(awk 'NF { l = $0 } END { gsub(/^[ \t]+|[ \t]+$/, "", l); print l }' "$UFP/3.txt")
  case "$_last3" in
    *[!0-9ivxl]* | '') uf PASS "R Anexo III item 1" U18 aprovacao-no-number "no page number (the last line is \"$_last3\")" ;;
    *) uf FAIL "R Anexo III item 1" U18 aprovacao-no-number "the last line is a page number: $_last3" ;;
  esac
  # ficha catalográfica (page 4): a placeholder; the card is not made here
  if page_has 4 "FICHA CATALOGRÁFICA" && page_has 4 "fichacatalografica.sibi.ufrj.br"; then uf PASS "R §1 d; N 8.1" U19 ficha-sheet "a sheet for the ficha catalográfica is in the right place (placeholder)"; else uf FAIL "R §1 d; N 8.1" U19 ficha-sheet "page 4 is not the ficha sheet"; fi
  uf CANNOT-CHECK "R §1 d; N 8.1" U20 ficha-card "the card itself comes from the SiBI generator (http://fichacatalografica.sibi.ufrj.br/) and is put on that sheet by a person; it is not invented here"

  # order of the pre-textual sheets
  _p_res=$(first_page "RESUMO")
  _p_abs=$(first_page "ABSTRACT")
  _p_toc=$(first_page "Sumário")
  _p_ref=
  _firstch=$(jq -r '.sections | sort_by(.order) | map(select(.status != "omit" and .role == "chapter")) | .[0].title' "$P/thesis.json")
  _p_ch=$(awk -v t="$_firstch" -v from="$((${_p_toc:-0} + 1))" 'BEGIN { RS = "\f" } NR >= from { n = split($0, l, "\n"); for (i = 1; i <= n; i++) { x = l[i]; gsub(/^[ \t]+|[ \t]+$/, "", x); if (x == t) { print NR; exit } } }' "$TMP/uf.txt")
  _p_ref=$(awk -v from="$((${_p_ch:-0} + 1))" 'BEGIN { RS = "\f" } NR >= from { n = split($0, l, "\n"); for (i = 1; i <= n; i++) { x = l[i]; gsub(/^[ \t]+|[ \t]+$/, "", x); if (x == "Referências Bibliográficas") { print NR; exit } } }' "$TMP/uf.txt")
  if [ -n "$_p_res" ] && [ -n "$_p_abs" ] && [ -n "$_p_toc" ] && [ -n "$_p_ch" ] && [ -n "$_p_ref" ] && [ 4 -lt "$_p_res" ] && [ "$_p_res" -lt "$_p_abs" ] && [ "$_p_abs" -lt "$_p_toc" ] && [ "$_p_toc" -lt "$_p_ch" ] && [ "$_p_ch" -lt "$_p_ref" ]; then
    uf PASS "R §1, §2, §3; N 7.1" U21 order "capa, folha de rosto, aprovação, ficha, resumo (p. $_p_res), abstract (p. $_p_abs), sumário (p. $_p_toc), chapters (p. $_p_ch), referências (p. $_p_ref)"
  else
    uf FAIL "R §1, §2, §3; N 7.1" U21 order "the sheets are not in the order capa, rosto, aprovação, ficha, resumo, abstract, sumário, chapters, referências (found: resumo ${_p_res:--}, abstract ${_p_abs:--}, sumário ${_p_toc:--}, chapter ${_p_ch:--}, referências ${_p_ref:--})"
  fi
  # resumo and abstract: own sheet, reference, up to 250 words, keywords
  _max=$(pn .words.resumo_max)
  for _kind in resumo abstract; do
    if [ "$_kind" = resumo ]; then _pg=$_p_res; _kw=Palavras-chave; _grad="Graduação em $_course"; else _pg=$_p_abs; _kw=Keywords; _grad="Graduação em $_course"; fi
    [ -n "$_pg" ] || continue
    _own=1
    [ "$_kind" = resumo ] && page_has "$_pg" "ABSTRACT" && _own=0
    [ "$_kind" = abstract ] && page_has "$_pg" "RESUMO" && _own=0
    _w=$(awk -v kw="$_kw" '/^[ \t]*$/ { next } { l = $0; gsub(/^[ \t]+|[ \t]+$/, "", l); if (index(l, kw) == 1) stop = 1; if (!stop) t = t " " l } END { print t }' "$UFP/$_pg.txt" | awk '{ n = 0; for (i = 1; i <= NF; i++) if ($i ~ /[[:alnum:]]/) n++; print n }')
    if [ "$_own" -eq 1 ] && page_has "$_pg" "$_kw" && page_has "$_pg" "$_grad"; then
      uf PASS "N 7.1, 7.2, 5.2 d" "U22$(printf '%.1s' "$_kind")" "$_kind-sheet" "own sheet, title, reference with \"$_grad\", text, keywords (the page holds about $_w words with the title and the reference)"
    else
      uf FAIL "N 7.1, 7.2, 5.2 d" "U22$(printf '%.1s' "$_kind")" "$_kind-sheet" "the $_kind sheet is not alone, or lacks \"$_kw\" or \"$_grad\""
    fi
    _sid=$(jq -r --arg r "$_kind" '.sections[] | select(.role == $r and .status != "omit") | .id' "$P/thesis.json" | head -n 1)
    if [ -n "$_sid" ] && plain_file "$(section_file "$_sid")"; then
      _wc=$(words_of "$(section_file "$_sid")")
      if [ "$_wc" -le "$_max" ]; then uf PASS "R §1 g; N 7.3" "U23$(printf '%.1s' "$_kind")" "$_kind-words" "$_wc words, at most $_max"; else uf FAIL "R §1 g; N 7.3" "U23$(printf '%.1s' "$_kind")" "$_kind-words" "$_wc words, over $_max"; fi
    fi
  done
  # roman numbers in the pre-textual part, arabic after
  _romanok=1
  _pg=$((${_p_res:-5}))
  while [ "$_pg" -lt "${_p_ch:-0}" ] && [ "$_pg" -le "$UFN" ]; do
    _foot=$(awk 'NF { l = $0 } END { gsub(/^[ \t]+|[ \t]+$/, "", l); print l }' "$UFP/$_pg.txt")
    [ "$_foot" = "$(roman "$_pg")" ] || _romanok=0
    _pg=$((_pg + 1))
  done
  _arab=$(awk 'NF { l = $0 } END { gsub(/^[ \t]+|[ \t]+$/, "", l); print l }' "${UFP}/${_p_ch:-1}.txt")
  if [ "$_romanok" -eq 1 ] && [ "$_arab" = 1 ]; then uf PASS "R §1 (last paragraph), §2" U24 numbering "roman numerals (i, ii, ...) from the resumo to the sumário, arabic from the first chapter, which is page 1"; else uf FAIL "R §1, §2" U24 numbering "the pre-textual pages are not numbered i, ii, ... or the first chapter is not page 1 (last line of that page: \"$_arab\")"; fi
  # the table of contents names every chapter with a number
  _tocok=1
  while IFS= read -r _t; do
    [ -n "$_t" ] || continue
    sed -n "${_p_toc:-1}p" /dev/null
    squash <"$UFP/$_p_toc.txt" | grep -Eq "[0-9]+ +$(printf '%s' "$_t" | sed 's/[][\.*^$/]/\\&/g')" || _tocok=0
  done <<EOF
$(jq -r '.sections | sort_by(.order)[] | select(.status != "omit" and .role == "chapter") | .title' "$P/thesis.json")
EOF
  if [ "$_tocok" -eq 1 ]; then uf PASS "R §1 h, §2" U25 sumario "the sumário lists every chapter with its number"; else uf FAIL "R §1 h, §2" U25 sumario "a chapter is missing from the sumário page (or not numbered)"; fi
  # references list
  if [ -n "$_p_ref" ]; then uf PASS "R §3" U26 referencias "the list \"Referências Bibliográficas\" is after the last chapter"; else uf FAIL "R §3" U26 referencias "no \"Referências Bibliográficas\" heading"; fi
  uf CANNOT-CHECK "R §3.1; N 9.2 (NBR 6023:2025, NBR 10520:2023)" U27 reference-form "the form of each reference and of each in-text mark follows the CSL file (an ABNT author-date style whose accuracy against the 2023 and 2025 norms is unverified); only cite-check's field rules are checked"

  # figures and tables: numbered, cited, caption above (table) and below (figure)
  _capok=1
  _capdetail=
  for _f in "$P"/build/tex/pt/sections/s*.tex; do
    [ -f "$_f" ] || continue
    _r=$(awk '
      /^\\begin\{longtable\}/ { lt = 1; next }
      lt == 1 { if ($0 !~ /^\\caption\{/) bad_t++; lt = 0 }
      /^\\begin\{figure\}/ { fg = 1; img = 0; next }
      fg && /\\includegraphics/ { img = 1 }
      fg && /^\\caption\{/ { if (!img) bad_f++ ; fg = 0 }
      END { printf "%d %d", bad_t + 0, bad_f + 0 }' "$_f")
    [ "$_r" = "0 0" ] || { _capok=0; _capdetail="$_capdetail $(basename -- "$_f"):$_r"; }
  done
  if [ "$_capok" -eq 1 ]; then uf PASS "R §4" U28 caption-position "table captions above, figure captions below (checked in the LaTeX of every section)"; else uf FAIL "R §4" U28 caption-position "a caption is on the wrong side:$_capdetail"; fi
  _uncited=0
  jq -r '.sections | sort_by(.order)[] | select(.status != "omit") | .id' "$P/thesis.json" | while IFS= read -r _id; do
    plain_file "$(section_file "$_id")" || continue
    jq -r '.lists.allowed_chars[] | "\(.[0]) \(.[1])"' "$PROFILE" >"$TMP/ranges"
    : >"$TMP/markers"
    SECTION_ROLE=x awk -v ranges="$TMP/ranges" -v markers="$TMP/markers" -f "$LIB/lint.awk" "$(section_file "$_id")" | awk -F'\t' '$1 == "LABEL" { lab[$2] = 1 } $1 == "REF" { ref[$2] = 1 } END { for (l in lab) if (l ~ /^(fig|tbl):/ && !(l in ref)) n++; print n + 0 }'
  done >"$TMP/uncited"
  _uncited=$(awk '{ n += $1 } END { print n + 0 }' "$TMP/uncited")
  if [ "$_uncited" -eq 0 ]; then uf PASS "R §4" U29 figures-tables-cited "every figure and table has a number (LaTeX) and is cited in its section"; else uf FAIL "R §4" U29 figures-tables-cited "$_uncited figure(s) or table(s) never cited"; fi

  # the layout, from pdf-qa
  if [ ! -f "$P/build/qa.json" ]; then
    uf CANNOT-CHECK "R intro" U30 layout "no build/qa.json: run thesis pdf-qa"
  else
    _q=$P/build/qa.json
    if [ "$(jq -r .page_size_ok "$_q")" = true ]; then uf PASS "R intro" U30 a4 "every page is A4 (210 x 297 mm)"; else uf FAIL "R intro" U30 a4 "$(jq -r .pages_not_a4 "$_q") page(s) are not A4"; fi
    if [ "$(jq -r .margins_ok "$_q")" = true ]; then uf PASS "R Anexo VII" U31 margins "smallest margins top $(jq -r .min_margins_mm.top "$_q"), bottom $(jq -r .min_margins_mm.bottom "$_q"), left $(jq -r .min_margins_mm.left "$_q"), right $(jq -r .min_margins_mm.right "$_q") mm; minimum 25, 25, 30, 30 (text boxes only; page numbers excluded)"; else uf FAIL "R Anexo VII" U31 margins "a margin is under the minimum 25, 25, 30, 30 mm: top $(jq -r .min_margins_mm.top "$_q"), bottom $(jq -r .min_margins_mm.bottom "$_q"), left $(jq -r .min_margins_mm.left "$_q"), right $(jq -r .min_margins_mm.right "$_q")"; fi
    _sp=$(jq -r '.line_spacing // 0' "$_q")
    _spt=$(pn .layout.line_spacing_tolerance)
    if awk -v s="$_sp" -v t="$_spt" 'BEGIN { exit !((s >= 1.5 - t && s <= 1.5 + t) || (s >= 2 - t && s <= 2 + t)) }'; then uf PASS "R intro; M" U32 spacing "line pitch of the body $(jq -r .line_pitch_pt "$_q") pt = $_sp x the single spacing of 12 pt type (1.5 or 2 allowed)"; else uf FAIL "R intro; M" U32 spacing "measured spacing $_sp is not 1.5 or 2"; fi
    _fam=$(jq -r .body_font.family "$_q")
    _siz=$(jq -r .body_font.size_pt "$_q")
    _famok=$(jq -r --arg f "$_fam" '.layout.font_families_ok | map(. as $k | $f | test($k; "i")) | any' "$PROFILE")
    _want=$(pn .layout.body_font_pt)
    if [ "$_famok" = true ] && [ "$_siz" = "$_want" ]; then uf PASS "R intro; N 2.1, 2.2" U33 font "body font $_fam at $_siz pt: a Times clone (TeX Gyre Termes) for \"Times New Roman 12\""; else uf FAIL "R intro; N 2.1, 2.2" U33 font "body font $_fam at $_siz pt; wanted a Times or Arial clone at $_want pt"; fi
    if awk -v m="$(jq -r .max_font_size_pt "$_q")" -v t="$(pn .layout.title_font_max_pt)" 'BEGIN { exit !(m <= t) }'; then uf PASS "R intro" U34 title-size "the largest type is $(jq -r .max_font_size_pt "$_q") pt, at most $(pn .layout.title_font_max_pt) (Times 24)"; else uf FAIL "R intro" U34 title-size "a type of $(jq -r .max_font_size_pt "$_q") pt is over the title limit"; fi
    if [ "$(jq -r .non_black_fonts "$_q")" -eq 0 ]; then uf PASS "R §2" U35 black-text "every font colour in the PDF is black (hyperref uses no coloured links)"; else uf FAIL "R §2" U35 black-text "$(jq -r .non_black_fonts "$_q") font(s) are not black"; fi
  fi
  uf CANNOT-CHECK "R §2, §4" U36 figure-colour "colour inside figures is not read; figures should read in black and white"
  if grep -q 'oneside' "$TPL/pinned/pt/project_main.tex"; then uf PASS "R intro" U37 one-sided "the class option oneside of the pinned template (pre- and post-textual one-sided)"; else uf FAIL "R intro" U37 one-sided "the template is not oneside"; fi
  _rag=$(grep -l -E 'raggedright|flushleft|raggedleft' "$P"/build/tex/pt/sections/s*.tex 2>/dev/null | wc -l | tr -d ' ')
  if [ "$_rag" -eq 0 ]; then uf PASS "R intro" U38 justified "no section turns justification off (the body is justified by default)"; else uf FAIL "R intro" U38 justified "$_rag section file(s) set the alignment"; fi
  uf CANNOT-CHECK "R intro" U39 originality "that the work is original and credits third parties is for the author and the examiners; cite-check only checks that sources are recorded"
  uf CANNOT-CHECK "R intro" U40 spelling "the current orthography is not checked by a script"
  uf CANNOT-CHECK "M" U41 manual "the SiBI Manual (9th ed., 2025) was read only as search snippets; its rules (single spacing in quotes, footnotes, references and captions) are applied by the overlay, not checked against the full text"
  say "ufrj-check: $SLUG: $UF_PASS pass, $UF_FAIL fail, $UF_CC cannot-check"
  [ "$UF_FAIL" -eq 0 ]
}
