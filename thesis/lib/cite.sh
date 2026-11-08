# cite.sh: gate 4, professional citation (the rules of h0ffmann/closed-source: never invent a
# reference, fetch every source before citing it, record the check in REFERENCES.md). Sourced by
# `thesis`. cite-check says what is wrong; cite-score counts marks, not truth (idea:
# closed-source's citation-score skill, written again here for pt-BR).
# shellcheck shell=sh
# shellcheck disable=SC2034,SC2329,SC2015,SC2129,SC2016
# (SC2034 and SC2329: the libraries share variables and functions through `thesis`, which sources them all;
# SC2015: the `A && B || C` forms end in a die; SC2016: sh -c and awk programs in single quotes are meant.)

TAB=$(printf '\t')

# bib_tsv <file>: key type field value.
bib_tsv() { if [ -f "$1" ]; then awk -f "$LIB/bib.awk" "$1"; fi; }

# refs_rows <REFERENCES.md>: key TAB status TAB checked TAB note, from the table rows.
refs_rows() {
  [ -f "$1" ] || return 0
  awk -F'|' '
    /^[ ]*\|/ {
      k = $2; s = $3; c = $4; n = $5
      gsub(/^[ \t`]+|[ \t`]+$/, "", k); gsub(/^[ \t*`]+|[ \t*`]+$/, "", s); gsub(/^[ \t]+|[ \t]+$/, "", c); gsub(/^[ \t]+|[ \t]+$/, "", n)
      if (k == "" || tolower(k) == "key" || k ~ /^[-: ]+$/) next
      printf "%s\t%s\t%s\t%s\n", k, tolower(s), c, n
    }' "$1"
}

# cc_add <FAIL|WARN> <where> <message>
cc_add() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >>"$TMP/cc.out"; }

# has_field <key> <field>: the value of a bib field (aliases of BibLaTeX), or nothing.
has_field() {
  awk -F'\t' -v k="$1" -v f="$2" '
    BEGIN { alias["journal"] = "journaltitle"; alias["address"] = "location"; alias["year"] = "date"; alias["school"] = "institution"; alias["institution"] = "school" }
    $1 == k && $3 != "@entry" && ($3 == f || $3 == alias[f]) && $4 != "" { print $4; exit }' "$TMP/bib.tsv"
}

check_entry_fields() { # <key>
  _k=$1
  _type=$(awk -F'\t' -v k="$_k" '$1 == k { print $2; exit }' "$TMP/bib.tsv")
  _req=$(jq -r --arg t "$_type" '.cite.bib_required[$t] // empty | .[]' "$PROFILE")
  if [ -z "$_req" ]; then
    cc_add WARN "refs.bib:$_k" "entry type @$_type has no field rule in the profile: fields not checked"
  else
    for _r in $_req; do
      _ok=0
      _oldifs=$IFS
      IFS='|'
      for _alt in $_r; do
        IFS=$_oldifs
        [ -z "$(has_field "$_k" "$_alt")" ] || _ok=1
        IFS='|'
      done
      IFS=$_oldifs
      [ "$_ok" -eq 1 ] || cc_add FAIL "refs.bib:$_k" "@$_type needs the field $(printf '%s' "$_r" | tr '|' ' or ') (NBR 6023)"
    done
  fi
  _y=$(has_field "$_k" year)
  case "$_y" in
    [0-9][0-9][0-9][0-9] | [0-9][0-9][0-9][0-9]-*) ;;
    *) cc_add FAIL "refs.bib:$_k" "the year is not four digits: \"$_y\"" ;;
  esac
  _doi=$(has_field "$_k" doi)
  if [ -n "$_doi" ] && ! printf '%s\n' "$_doi" | grep -Eq "$(pn .cite.doi_regex)"; then
    cc_add FAIL "refs.bib:$_k" "doi \"$_doi\" is not a bare DOI (10.NNNN/suffix, no https://doi.org/ in front)"
  fi
  _url=$(has_field "$_k" url)
  if [ -n "$_url" ]; then
    [ -n "$(has_field "$_k" urldate)" ] || cc_add FAIL "refs.bib:$_k" "a url needs the access date (urldate = {YYYY-MM-DD}): NBR 6023"
    printf '%s\n' "$_url" | grep -Eq '^https?://[^ ]+$' || cc_add FAIL "refs.bib:$_k" "url \"$_url\" is not an http(s) address"
  fi
}

check_source_file() { # <key>
  _sf=$P/sources/$1.md
  if ! plain_file "$_sf"; then
    cc_add FAIL "sources/$1.md" "no capture file for the key $1 (the librarian writes it: URL, retrieval date, quoted passages, DOI check)"
    return 0
  fi
  awk -v k="$1" '
    { l = $0; gsub(/\*/, "", l); sub(/^[ \t]*[-+][ \t]+/, "", l); sub(/^[ \t]+/, "", l); low = tolower(l) }
    low ~ /^url:[ \t]*(https?:\/\/[^ \t]+|none)/ { url = 1 }
    low ~ /^retrieved:[ \t]*[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/ { ret = 1 }
    low ~ /^doi check:[ \t]*[^ \t]/ { doi = 1 }
    l ~ /^>[ \t]*[^ \t]/ { quote++ }
    END {
      if (!url) print "FAIL\tsources/" k ".md\tno line `URL: https://...` (or `URL: none` for a printed work)"
      if (!ret) print "FAIL\tsources/" k ".md\tno line `Retrieved: YYYY-MM-DD`"
      if (!doi) print "FAIL\tsources/" k ".md\tno line `DOI check: ...` (say `none` when the work has no DOI)"
      if (!quote) print "FAIL\tsources/" k ".md\tno quoted passage (a line starting with >): the claim must rest on what the source says"
    }' "$_sf" >>"$TMP/cc.out"
}

cmd_cite_check() {
  [ $# -ge 1 ] && [ $# -le 2 ] || die "usage: thesis cite-check <slug> [<id>]"
  need_project "$1"
  : >"$TMP/cc.out"
  _whole=1
  if [ $# -eq 2 ]; then
    need_section "$2"
    plain_file "$(section_file "$SID")" || die "$SLUG/$SID: no sections/$SID.md"
    printf '%s\n' "$SID" >"$TMP/cc.sections"
    _whole=0
  else
    jq -r '.sections | sort_by(.order)[] | select(.status != "omit") | .id' "$P/thesis.json" >"$TMP/cc.sections"
  fi

  plain_file "$P/refs.bib" || die "$SLUG: no refs.bib"
  plain_file "$P/REFERENCES.md" || die "$SLUG: no REFERENCES.md"
  bib_tsv "$P/refs.bib" >"$TMP/bib.tsv"
  refs_rows "$P/REFERENCES.md" >"$TMP/rows.tsv"
  awk -F'\t' '$3 == "@entry" { print $1 }' "$TMP/bib.tsv" | sort >"$TMP/bibkeys"
  cut -f1 "$TMP/rows.tsv" | sort >"$TMP/rowkeys"
  : >"$TMP/cited.all"

  _qmax=$(pn .words.inline_quote_max_words)
  while IFS= read -r _sid; do
    [ -n "$_sid" ] || continue
    _f=$(section_file "$_sid")
    if ! plain_file "$_f"; then
      [ "$_whole" -eq 0 ] || cc_add FAIL "sections/$_sid.md" "the section file is missing"
      continue
    fi
    awk -v maxq="$_qmax" -f "$LIB/cites.awk" "$_f" >"$TMP/cites.out"
    awk -F'\t' -v s="$_sid" '$1 == "KEY" { print $2 "\t" s "\t" $3 }' "$TMP/cites.out" >>"$TMP/cited.all"
    awk -F'\t' -v s="$_sid" '
      $1 == "QUOTE" { printf "FAIL\tsections/%s.md:%s\tan inline quotation of %s words: a quotation of three lines or more goes in a block (> text), NBR 10520\n", s, $2, $3 }
      $1 == "HAND" { printf "WARN\tsections/%s.md:%s\t%s typed by hand: write [@key], so that the reference list and the mark agree\n", s, $2, $3 }
      $1 == "NUM" { printf "FAIL\tsections/%s.md:%s\tthe numbered citation %s: one system for the whole work, author-date (Res. 05/2012; Norma 2026, 9.1)\n", s, $2, $3 }' "$TMP/cites.out" >>"$TMP/cc.out"
  done <"$TMP/cc.sections"

  sort -u "$TMP/cited.all" >"$TMP/cited.sorted"
  cut -f1 "$TMP/cited.sorted" | sort -u >"$TMP/citedkeys"

  # duplicate keys in refs.bib
  awk -F'\t' '$3 == "@entry" { c[$1]++; l[$1] = l[$1] " " $4 } END { for (k in c) if (c[k] > 1) printf "FAIL\trefs.bib:%s\tthe key %s is defined %d times (lines%s)\n", k, k, c[k], l[k] }' "$TMP/bib.tsv" >>"$TMP/cc.out"
  awk -F'\t' '{ c[$1]++ } END { for (k in c) if (c[k] > 1) printf "FAIL\tREFERENCES.md:%s\tthe key %s has %d rows\n", k, k, c[k] }' "$TMP/rows.tsv" >>"$TMP/cc.out"

  # every cited key: in refs.bib, a verified row, a capture file
  while IFS="$TAB" read -r _key _sid _ln; do
    if ! grep -qx -- "$_key" "$TMP/bibkeys"; then
      cc_add FAIL "sections/$_sid.md:$_ln" "@$_key is not in refs.bib: never invent a reference; ask the librarian to fetch it first"
      continue
    fi
    _st=$(awk -F'\t' -v k="$_key" '$1 == k { print $2; exit }' "$TMP/rows.tsv")
    case "$_st" in
      verified) ;;
      '') cc_add FAIL "sections/$_sid.md:$_ln" "@$_key has no row in REFERENCES.md: not cited until it is verified" ;;
      partial | unverified) cc_add FAIL "sections/$_sid.md:$_ln" "@$_key has the status $_st: only verified sources may be cited" ;;
      *) cc_add FAIL "sections/$_sid.md:$_ln" "@$_key has the unknown status \"$_st\" (verified, partial or unverified)" ;;
    esac
  done <"$TMP/cited.sorted"

  # entries to check: the cited ones, or all of refs.bib in the whole mode
  if [ "$_whole" -eq 1 ]; then cp "$TMP/bibkeys" "$TMP/check.keys"; else grep -Fx -f "$TMP/citedkeys" "$TMP/bibkeys" >"$TMP/check.keys" 2>/dev/null || : >"$TMP/check.keys"; fi
  while IFS= read -r _key; do
    [ -n "$_key" ] || continue
    check_entry_fields "$_key"
    check_source_file "$_key"
  done <"$TMP/check.keys"
  # The ABNT CSL puts the disambiguation letter before the year (a2022) and also on the access date.
  awk -F'\t' '
    $3 == "author" { a = $4; sub(/ and .*$/, "", a); sub(/,.*$/, "", a); au[$1] = tolower(a) }
    $3 == "year" { yr[$1] = $4 }
    END { for (k in au) if (k in yr) { s = au[k] "|" yr[k]; n[s]++; l[s] = l[s] " " k }
          for (s in n) if (n[s] > 1) { split(s, p, "|"); printf "WARN\trefs.bib\t%d entries with the first author %s and the year %s (%s): the CSL file letters them badly (a2022, and the access date too); check the list in the PDF, or tell the reviewer\n", n[s], p[1], p[2], substr(l[s], 2) } }' "$TMP/bib.tsv" >>"$TMP/cc.out"

  if [ "$_whole" -eq 1 ]; then
    while IFS= read -r _key; do
      [ -n "$_key" ] || continue
      grep -qx -- "$_key" "$TMP/rowkeys" || cc_add FAIL "REFERENCES.md" "the key $_key of refs.bib has no row"
      grep -qx -- "$_key" "$TMP/citedkeys" || cc_add FAIL "refs.bib:$_key" "the entry $_key is cited by no section (the reference list would show it): remove it"
    done <"$TMP/bibkeys"
    while IFS="$TAB" read -r _key _st _chk _note; do
      grep -qx -- "$_key" "$TMP/bibkeys" && continue
      if [ "$_st" = unverified ]; then cc_add WARN "REFERENCES.md:$_key" "unverified row with no refs.bib entry (fine: it may not be cited)"
      else cc_add FAIL "REFERENCES.md:$_key" "a row with the status $_st and no entry in refs.bib"; fi
    done <"$TMP/rows.tsv"
  fi
  # partial rows: the unconfirmed field must not be in the entry
  while IFS="$TAB" read -r _key _st _chk _note; do
    [ "$_st" = partial ] || continue
    _uc=$(printf '%s' "$_note" | sed -n 's/.*[Uu]nconfirmed:[ ]*\([A-Za-z, ]*\).*/\1/p' | tr ',' ' ')
    if [ -z "$_uc" ]; then cc_add FAIL "REFERENCES.md:$_key" "a partial row must say which detail is unconfirmed: \"unconfirmed: field\" in the Note"; continue; fi
    for _f in $_uc; do
      [ -z "$(has_field "$_key" "$_f")" ] || cc_add FAIL "refs.bib:$_key" "the field $_f is unconfirmed (REFERENCES.md) and must not be in the entry"
    done
  done <"$TMP/rows.tsv"

  _fail=$(grep -c "^FAIL" "$TMP/cc.out" || true)
  _warn=$(grep -c "^WARN" "$TMP/cc.out" || true)
  sort -u "$TMP/cc.out" | while IFS="$TAB" read -r _lv _where _msg; do say "$_lv $_where: $_msg"; done
  _nk=$(wc -l <"$TMP/citedkeys" | tr -d ' ')
  say "cite-check: $SLUG$([ "$_whole" -eq 1 ] || printf '/%s' "$SID"): $_nk cited key(s), $_fail fail, $_warn warn"
  say "  Not checked by a machine: that a source supports the claim it is cited for. The reviewer reads sources/<key>.md for that."
  say "  Not checked: the same key used with different meanings in two sections."
  [ "$_fail" -eq 0 ]
}

# ---------------------------------------------------------------- cite-score

cmd_cite_score() {
  _strict=0
  _a=
  for _x in "$@"; do
    case "$_x" in
      --strict) _strict=1 ;;
      *) _a="$_a $_x" ;;
    esac
  done
  # shellcheck disable=SC2086
  set -- $_a
  [ $# -eq 2 ] || die "usage: thesis cite-score <slug> <id> [--strict]"
  gate_prepare "$1" "$2"
  prose_tsv "$SF" "$TMP/prose.tsv"
  _class=$(sec '.cite_class // "medium"')
  _target=$(jq -r --arg c "$_class" '.cite.score_targets[$c] // empty' "$PROFILE")
  [ -n "$_target" ] || die "$SLUG/$SID: cite_class \"$_class\" is not in profile.json cite.score_targets"
  _minw=$(pn .cite.score_min_words)
  awk -F'\t' -v minw="$_minw" '
    ($1 == "p" || $1 == "l" || $1 == "q") && $4 >= minw {
      n++
      if ($5 ~ /§[CNDUF]§/ || $5 ~ /\([A-ZÀ-Ú][A-Za-zÀ-ú'"'"' -]+( et al\.)?,[ ]?[0-9][0-9][0-9][0-9][a-z]?\)/) m++
      else if (++u <= 5) un[u] = $3 "\t" substr($5, 1, 100)
    }
    END {
      printf "SCORE\t%d\t%d\n", n + 0, m + 0
      for (i = 1; i <= u && i <= 5; i++) printf "UNMARKED\t%s\n", un[i]
    }' "$TMP/prose.tsv" >"$TMP/cs.out"
  _n=$(awk -F'\t' '$1 == "SCORE" { print $2 }' "$TMP/cs.out")
  _m=$(awk -F'\t' '$1 == "SCORE" { print $3 }' "$TMP/cs.out")
  _pct=$(awk -v n="$_n" -v m="$_m" 'BEGIN { if (n == 0) print "0.0"; else printf "%.1f", 100 * m / n }')
  _ok=$(awk -v p="$_pct" -v t="$_target" -v n="$_n" 'BEGIN { print ((n == 0 || p / 100 >= t) ? "OK" : "BELOW TARGET") }')
  say "cite-score: $SLUG/$SID: $_m of $_n sentences of $_minw words or more carry a citation mark = $_pct % (class $_class, target >= $(awk -v t="$_target" 'BEGIN { printf "%.0f", t * 100 }') %): $_ok"
  say "  It counts marks ([@key], DOI, URL, footnote, (Author, 2016)), not truth. 100 % is not the goal: Resultados and Conclusões own their results."
  if [ "$_ok" != OK ]; then
    say "  sentences with no mark (first 5; line, text):"
    awk -F'\t' '$1 == "UNMARKED" { printf "    line %s: %s\n", $2, $3 }' "$TMP/cs.out"
  fi
  [ "$_strict" -eq 0 ] || [ "$_ok" = OK ]
}
