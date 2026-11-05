# gates.sh: lint, readability and slop (gates 1 and 2 of the reviewer). Sourced by `thesis`.
# No model and no network: awk, jq and the lists of profile.json.
# shellcheck shell=sh
# shellcheck disable=SC2034,SC2329,SC2015,SC2129,SC2016
# (SC2034 and SC2329: the libraries share variables and functions through `thesis`, which sources them all;
# SC2015: the `A && B || C` forms end in a die; SC2016: sh -c and awk programs in single quotes are meant.)

# gate_prepare <slug> <id>: P, SEC, SID, SF (the section file); the lists in $TMP.
gate_prepare() {
  need_project "$1"
  need_section "$2"
  SF=$(section_file "$SID")
  plain_file "$SF" || die "$SLUG/$SID: no sections/$SID.md (or it is a link)"
  [ "$(wc -c <"$SF")" -le "$(pn .limits.section_max_bytes)" ] || die "$SLUG/$SID: sections/$SID.md is over $(pn .limits.section_max_bytes) bytes"
  [ -s "$SF" ] || die "$SLUG/$SID: sections/$SID.md is empty"
}

# list_file <jq filter that prints one item a line> <file>
list_file() { jq -r "$1" "$PROFILE" >"$2"; }

# params_file <jq path> <file>: key TAB value, nested keys joined by a dot.
params_file() {
  jq -r "$1 | [paths(scalars) as \$p | (\$p | map(tostring) | join(\".\")) + \"\\t\" + (getpath(\$p) | tostring)] | .[]" "$PROFILE" >"$2"
}

# prose_tsv <file> <out>: the rows of prose.awk.
prose_tsv() { awk -v abbr="$ABBR" -f "$LIB/prose.awk" "$1" >"$2"; }

# words_of <section file>: the words of the prose (paragraphs, lists, quotes).
words_of() {
  prose_tsv "$1" "$TMP/w.tsv"
  awk -F'\t' '$1 == "p" || $1 == "l" || $1 == "q" { n += $4 } END { print n + 0 }' "$TMP/w.tsv"
}

# ---------------------------------------------------------------- lint

cmd_lint() {
  _allow=0
  _slug=
  _id=
  while [ $# -gt 0 ]; do
    case "$1" in
      --allow-placeholders) _allow=1 ;;
      -*) die "lint: unknown option $1" ;;
      *) if [ -z "$_slug" ]; then _slug=$1; elif [ -z "$_id" ]; then _id=$1; else die "lint: too many arguments"; fi ;;
    esac
    shift
  done
  [ -n "$_slug" ] && [ -n "$_id" ] || die "usage: thesis lint <slug> <id> [--allow-placeholders]"
  gate_prepare "$_slug" "$_id"
  _role=$(sec .role)
  _title=$(sec .title)

  jq -r '.lists.allowed_chars[] | "\(.[0]) \(.[1])"' "$PROFILE" >"$TMP/ranges"
  if [ "$_allow" -eq 1 ]; then : >"$TMP/markers"; else jq -r '.lists.placeholder_markers[]' "$PROFILE" >"$TMP/markers"; fi
  SECTION_ROLE=$_role SECTION_TITLE=$_title awk -v ranges="$TMP/ranges" -v markers="$TMP/markers" -f "$LIB/lint.awk" "$SF" >"$TMP/lint.raw" || die "lint: awk failed"

  : >"$TMP/lint.out"
  awk -F'\t' '$1 == "FAIL" || $1 == "WARN"' "$TMP/lint.raw" >"$TMP/lint.out"

  # Labels that nobody cites, references with no label, files that are missing.
  awk -F'\t' '$1 == "LABEL" { lab[$2] = $3 } $1 == "REF" { ref[$2] = $3 }
    END {
      for (l in lab) if (l ~ /^(fig|tbl):/ && !(l in ref)) printf "FAIL\t%d\tnot-cited\t%s is never cited in the text (write @%s)\n", lab[l], l, l
      for (r in ref) if (r !~ /^cap:/ && !(r in lab)) printf "FAIL\t%d\tno-label\t@%s has no label in this section: a section may cite only its own figures, tables and equations\n", ref[r], r
    }' "$TMP/lint.raw" >>"$TMP/lint.out"
  awk -F'\t' '$1 == "REF" && $2 ~ /^cap:/ { print substr($2, 5) "\t" $3 }' "$TMP/lint.raw" | while IFS="$(printf '\t')" read -r _cid _cl; do
    jq -e --arg id "$_cid" '.sections[] | select(.id == $id)' "$P/thesis.json" >/dev/null 2>&1 ||
      printf 'FAIL\t%s\tno-chapter\t@cap:%s names no section of thesis.json\n' "$_cl" "$_cid"
  done >>"$TMP/lint.out"
  awk -F'\t' '$1 == "FIGFILE" { print $2 "\t" $3 }' "$TMP/lint.raw" | while IFS="$(printf '\t')" read -r _fp _fl; do
    case "$_fp" in
      figures/*[!A-Za-z0-9._/-]* | */../* | *..*) printf 'FAIL\t%s\tfigure-path\tthe figure path %s may hold letters, digits, . _ / - only\n' "$_fl" "$_fp"; continue ;;
      figures/*) ;;
      *) printf 'FAIL\t%s\tfigure-path\tthe figure path %s must start with figures/\n' "$_fl" "$_fp"; continue ;;
    esac
    plain_file "$P/$_fp" || printf 'FAIL\t%s\tfigure-file\tthe figure file %s is missing (put it in the project folder figures/; PDF, PNG or JPEG)\n' "$_fl" "$_fp"
  done >>"$TMP/lint.out"

  # Length against the target, and the sheets with a hard limit.
  _words=$(words_of "$SF")
  _target=$(sec '.target_words // 0')
  _tl=$(pn .words.target_tolerance_low)
  _th=$(pn .words.target_tolerance_high)
  if [ "$_target" -gt 0 ]; then
    awk -v w="$_words" -v t="$_target" -v lo="$_tl" -v hi="$_th" 'BEGIN {
      if (w < t * lo) printf "FAIL\t0\tlength\t%d words, under %d %% of the target %d\n", w, lo * 100, t
      else if (w > t * hi) printf "WARN\t0\tlength\t%d words, over %d %% of the target %d\n", w, hi * 100, t
    }' >>"$TMP/lint.out"
  fi
  case "$_role" in
    resumo | abstract)
      _max=$(pn .words.resumo_max)
      [ "$_words" -le "$_max" ] || printf 'FAIL\t0\tresumo-words\t%s words: the %s sheet holds at most %s (Res. 05/2012; Norma 2026, 7.3)\n' "$_words" "$_role" "$_max" >>"$TMP/lint.out"
      _kmin=$(pn .words.keywords_min)
      _kmax=$(pn .words.keywords_max)
      _kn=$(sec '.keywords // [] | length')
      if [ "$_kn" -lt "$_kmin" ] || [ "$_kn" -gt "$_kmax" ]; then
        printf 'FAIL\t0\tkeywords\t%s keywords in thesis.json, need %s to %s\n' "$_kn" "$_kmin" "$_kmax" >>"$TMP/lint.out"
      fi
      _paras=$(awk -F'\t' '$1 == "p" { s[$2] = 1 } END { n = 0; for (k in s) n++; print n }' "$TMP/w.tsv")
      [ "$_paras" -le 1 ] || printf 'WARN\t0\tresumo-paragraphs\t%s paragraphs: a resumo is one paragraph (NBR 6028, from memory)\n' "$_paras" >>"$TMP/lint.out"
      ;;
    chapter)
      _hs=$(awk -F'\t' '$1 == "COUNT" && $2 == "headings" { print $3 }' "$TMP/lint.raw")
      if [ "${_hs:-0}" -eq 0 ] && [ "$_words" -gt 800 ]; then printf 'WARN\t0\tstructure\t%s words and no heading: split the chapter in sections (# Heading)\n' "$_words" >>"$TMP/lint.out"; fi
      ;;
  esac

  _fail=$(grep -c '^FAIL' "$TMP/lint.out" || true)
  _warn=$(grep -c '^WARN' "$TMP/lint.out" || true)
  sort -t "$(printf '\t')" -k2,2n "$TMP/lint.out" | while IFS="$(printf '\t')" read -r _lv _ln _rule _msg; do
    if [ "$_ln" = 0 ]; then say "$_lv $_rule: $_msg"; else say "$_lv line $_ln $_rule: $_msg"; fi
  done
  say "lint: $SLUG/$SID: $_words words, $_fail fail, $_warn warn"
  [ "$_fail" -eq 0 ]
}

# ---------------------------------------------------------------- readability

cmd_readability() {
  [ $# -eq 2 ] || die "usage: thesis readability <slug> <id>"
  gate_prepare "$1" "$2"
  prose_tsv "$SF" "$TMP/prose.tsv"
  params_file .readability "$TMP/rd.params"
  list_file '.lists.ser_forms[]' "$TMP/ser"
  list_file '.lists.irregular_participles[]' "$TMP/irr"
  list_file '.lists.adjective_like_participles[]' "$TMP/adj"
  list_file '.lists.anglicisms[]' "$TMP/ang"
  jq -r '.terms.mixed[] | join("\t")' "$PROFILE" >"$TMP/groups"
  glossary_terms >"$TMP/gloss"
  awk -v params="$TMP/rd.params" -v passive_aux="$TMP/ser" -v irregular="$TMP/irr" -v adjlike="$TMP/adj" \
    -v anglicisms="$TMP/ang" -v glossary="$TMP/gloss" -v groups="$TMP/groups" \
    -f "$LIB/readability.awk" "$TMP/prose.tsv" >"$TMP/rd.out" || die "readability: awk failed"

  _m() { awk -v k="$1" '$1 == "METRIC" && $2 == k { print $3 }' "$TMP/rd.out"; }
  say "readability: $SLUG/$SID (pt-BR heuristics; approximate; numbers first, a verdict only for the hard limits)"
  say "  sentences $(_m sentences), words $(_m words)"
  if [ "$(_m enough)" = 0 ]; then
    say "  fewer than $(pn .readability.min_sentences) sentences: the ratios are not computed"
    FAILS=
  else
    _lim() { pn ".readability.$1"; }
    FAILS=
    _mean=$(_m sentence_mean)
    say "  sentence length: mean $_mean, median $(_m sentence_median) words; over $(_lim sentence_long_words) words: $(_m sentence_long) ($(awk -v s="$(_m sentence_long_share)" 'BEGIN { printf "%.1f", s * 100 }') %)   [limits: mean $(_lim sentence_mean_max), share $(awk -v s="$(_lim sentence_long_share_max)" 'BEGIN { printf "%d", s * 100 }') %]"
    awk -v a="$_mean" -v b="$(_lim sentence_mean_max)" 'BEGIN { exit !(a > b) }' && FAILS="$FAILS mean sentence length $_mean > $(_lim sentence_mean_max);"
    awk -v a="$(_m sentence_long_share)" -v b="$(_lim sentence_long_share_max)" 'BEGIN { exit !(a > b) }' && FAILS="$FAILS $(_m sentence_long) sentences over $(_lim sentence_long_words) words;"
    if [ -n "$(_m paragraphs)" ]; then
      say "  paragraphs: $(_m paragraphs), mean $(_m paragraph_mean) words, longest $(_m paragraph_max); over $(_lim paragraph_words_max) words: $(_m paragraph_over); one-sentence: $(_m one_sentence_paragraphs) ($(awk -v s="$(_m one_sentence_share)" 'BEGIN { printf "%.0f", s * 100 }') %)   [limit $(awk -v s="$(_lim one_sentence_paragraph_share_max)" 'BEGIN { printf "%d", s * 100 }') %]"
      [ "$(_m paragraph_over)" -eq 0 ] || FAILS="$FAILS $(_m paragraph_over) paragraph(s) over $(_lim paragraph_words_max) words;"
      awk -v a="$(_m one_sentence_share)" -v b="$(_lim one_sentence_paragraph_share_max)" -v n="$(_m paragraphs)" 'BEGIN { exit !(a > b && n >= 4) }' && FAILS="$FAILS too many one-sentence paragraphs;"
    fi
    say "  passive (ser + participle; the -se passive is NOT counted): $(_m passive) of $(_m sentences) ($(awk -v s="$(_m passive_share)" 'BEGIN { printf "%.1f", s * 100 }') %)   [limit $(awk -v s="$(_lim passive_share_max)" 'BEGIN { printf "%d", s * 100 }') %]"
    awk -v a="$(_m passive_share)" -v b="$(_lim passive_share_max)" 'BEGIN { exit !(a > b) }' && FAILS="$FAILS passive voice share over the limit;"
    say "  Flesch-style index for pt (Martins et al. 1996 constants; syllable count approximate): $(_m flesch_pt)   [min $(_lim flesch_pt_min)]"
    awk -v a="$(_m flesch_pt)" -v b="$(_lim flesch_pt_min)" 'BEGIN { exit !(a < b) }' && FAILS="$FAILS Flesch-style index $(_m flesch_pt) < $(_lim flesch_pt_min);"
  fi

  _na=$(_m anglicisms_distinct)
  _na=${_na:-0}
  say "  anglicisms not in notes/glossary.md: $_na distinct"
  awk -F'\t' '$1 ~ /^ANGLICISM / { t = $1; sub(/^ANGLICISM /, "", t); printf "    line %s: %s (x%s)\n", $2, t, $3 }' "$TMP/rd.out" | head -n 12
  [ "$_na" -lt "$(pn .readability.anglicism_fail_distinct)" ] || FAILS="$FAILS $_na distinct anglicisms;"
  _nm=$(_m mixed_groups)
  _nm=${_nm:-0}
  say "  mixed terms: $_nm group(s)"
  awk '$1 == "MIXED" { sub(/^MIXED /, ""); print "    one thing, several words: " $0 }' "$TMP/rd.out"
  [ "$_nm" -eq 0 ] || FAILS="$FAILS mixed terms ($_nm group(s));"

  # Figures, tables and equations cited in the text.
  jq -r '.lists.allowed_chars[] | "\(.[0]) \(.[1])"' "$PROFILE" >"$TMP/ranges"
  : >"$TMP/markers"
  SECTION_ROLE=$(sec .role) awk -v ranges="$TMP/ranges" -v markers="$TMP/markers" -f "$LIB/lint.awk" "$SF" >"$TMP/lint.raw"
  _unc=$(awk -F'\t' '$1 == "LABEL" { lab[$2] = 1 } $1 == "REF" { ref[$2] = 1 } END { n = 0; for (l in lab) if (l ~ /^(fig|tbl|eq):/ && !(l in ref)) { n++; printf "    %s is never cited\n", l > "/dev/stderr" } print n }' "$TMP/lint.raw" 2>"$TMP/unc.txt")
  say "  figures, tables, equations not cited in the text: $_unc"
  cat "$TMP/unc.txt"
  [ "$_unc" -eq 0 ] || FAILS="$FAILS $_unc label(s) never cited;"

  say "  longest sentences (line, words):"
  awk -F'\t' '$1 ~ /^WORST/ { sub(/^WORST /, "", $1); printf "    line %s, %s words: %s\n", $1, $2, substr($3, 1, 110) }' "$TMP/rd.out"
  say "  passive examples:"
  awk -F'\t' '$1 ~ /^PASSIVE/ { sub(/^PASSIVE /, "", $1); printf "    line %s: %s\n", $1, substr($2, 1, 110) }' "$TMP/rd.out"
  if [ -n "$FAILS" ]; then
    say "readability: $SLUG/$SID: FAIL:$FAILS"
    return 1
  fi
  say "readability: $SLUG/$SID: PASS (the hard limits only; read the numbers)"
}

# glossary_terms: the terms of notes/glossary.md (the first cell of a table row, or the first words of
# a list item before a dash or a colon), one a line, lower case.
glossary_terms() {
  [ -f "$P/notes/glossary.md" ] || return 0
  awk '
    /^[ ]*\|/ { n = split($0, c, "|"); t = c[2]; gsub(/^[ \t]+|[ \t]+$/, "", t); if (t != "" && t !~ /^-+$/ && tolower(t) != "termo") print tolower(t); next }
    /^[ ]*[-*][ ]+/ { t = $0; sub(/^[ ]*[-*][ ]+/, "", t); sub(/[ ]*([:—–]|--| - ).*$/, "", t); gsub(/\*/, "", t); if (t != "") print tolower(t) }
  ' "$P/notes/glossary.md"
}

# ---------------------------------------------------------------- slop

cmd_slop() {
  [ $# -eq 2 ] || die "usage: thesis slop <slug> <id>"
  gate_prepare "$1" "$2"
  prose_tsv "$SF" "$TMP/prose.tsv"
  params_file .slop "$TMP/slop.params"
  list_file '.lists.slop_phrases[]' "$TMP/ph"
  list_file '.lists.transitions[]' "$TMP/tr"
  list_file '.lists.summary_openers[]' "$TMP/su"
  list_file '.lists.hedges[]' "$TMP/he"
  SLOP_TITLE=$(sec .title) awk -v params="$TMP/slop.params" -v phrases="$TMP/ph" -v transitions="$TMP/tr" -v summaries="$TMP/su" -v hedges="$TMP/he" \
    -f "$LIB/slop.awk" "$TMP/prose.tsv" "$SF" >"$TMP/slop.out" || die "slop: awk failed"
  _score=$(awk '$1 == "SCORE" { print $2 }' "$TMP/slop.out")
  _thr=$(pn .slop.threshold)
  say "slop: $SLUG/$SID: surface patterns of model-written text, local rules only"
  say "  This measures patterns, not authorship. No detector is reliable and this one is not a detector:"
  say "  it cannot promise any external tool's score. A person writes some of these patterns. To lower the"
  say "  score, rewrite from facts and add what only the author knows (**[AUTHOR: ...]** markers, never"
  say "  invented experience); paraphrasing the same sentences keeps the pattern."
  if awk '$1 == "TOOSHORT" { f = 1 } END { exit !f }' "$TMP/slop.out"; then
    say "  $(awk '$1 == "WORDS" { print $2 }' "$TMP/slop.out") words: under $(pn .slop.min_words), too short to score. Score 0 (not scored)."
    say "slop: $SLUG/$SID: score 0/100 (threshold $_thr): PASS (not scored)"
    return 0
  fi
  say "  signal             value   warn    max  points"
  awk '$1 == "SIGNAL" { printf "  %-17s %6s %6s %6s %7s\n", $2, $3, $4, $5, $6 }' "$TMP/slop.out"
  say "  offending spans (line, signal):"
  awk -F'\t' '$1 ~ /^SPAN/ { split($1, h, " "); printf "    line %s %s: %s\n", h[3], h[2], substr($2, 1, 90) }' "$TMP/slop.out" | head -n 40
  if [ "$_score" -ge "$_thr" ]; then
    say "slop: $SLUG/$SID: score $_score/100 (threshold $_thr): FAIL"
    return 1
  fi
  say "slop: $SLUG/$SID: score $_score/100 (threshold $_thr): PASS"
}
