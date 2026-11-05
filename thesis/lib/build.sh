# build.sh: build-section, assemble, pdf-qa, publish. Sourced by `thesis`.
# pandoc turns markdown into LaTeX and fills the front pages from thesis.json; pdfLaTeX makes the
# PDF. No network, no shell escape, a time limit on every pandoc and TeX call.
# shellcheck shell=sh
# shellcheck disable=SC2034,SC2329,SC2015,SC2129,SC2016
# (SC2034 and SC2329: the libraries share variables and functions through `thesis`, which sources them all;
# SC2015: the `A && B || C` forms end in a die; SC2016: sh -c and awk programs in single quotes are meant.)

# The reader: raw TeX, raw attributes, raw HTML, YAML blocks, TeX macros and automatic identifiers
# are OFF. What the author writes is text and markdown, never TeX. (Math is the one place that
# reaches TeX as written; filters/thesis.lua allows only listed macros.)
PD_FROM='markdown-raw_tex-raw_attribute-raw_html-yaml_metadata_block-latex_macros-auto_identifiers'
TEX_TIMEOUT=${THESIS_TEX_TIMEOUT:-$TEX_TIMEOUT}
PANDOC_TIMEOUT=${THESIS_PANDOC_TIMEOUT:-$PANDOC_TIMEOUT}

# timed <command...>: seconds and peak KiB of the command, appended to $TIMES.
TIMES=$TMP/times
: >"$TIMES"
if env time -f "%e %M" true >/dev/null 2>&1; then
  timed() { env time -f "%e %M" -a -o "$TIMES" "$@"; }
else
  timed() {
    _ts=$(date +%s)
    _trc=0
    "$@" || _trc=$?
    echo "$(($(date +%s) - _ts)) 0" >>"$TIMES"
    return "$_trc"
  }
fi

pd() { # <pandoc arguments>: timed, quiet, stderr kept in $TMP/pandoc.err
  _prc=0
  timed timeout -k 5 "$PANDOC_TIMEOUT" pandoc --fail-if-warnings "$@" 2>"$TMP/pandoc.err" || _prc=$?
  if [ "$_prc" -eq 124 ] || [ "$_prc" -eq 137 ]; then note "pandoc stopped: no result after $PANDOC_TIMEOUT s"; fi
  return "$_prc"
}

pd_fail() { # <what>: the pandoc messages, then die
  sed 's/^/  pandoc: /' "$TMP/pandoc.err" >&2
  die "$1"
}

# tex_escape <text>: a title or a name for a chapter command, escaped by pandoc.
tex_escape() {
  printf '%s\n' "$1" | timeout -k 5 "$PANDOC_TIMEOUT" pandoc -f "$PD_FROM" -t latex --wrap=none | tr '\n' ' ' | sed 's/ *$//'
}

# make_fragment <id> <out.tex> <mode>: mode final (every cited work only through nocite, no list) or
# preview (the section's own references at the end).
make_fragment() {
  _fid=$1
  _fout=$2
  _mode=$3
  _fsf=$(section_file "$_fid")
  _ids=$(jq -r '.sections | map(.id) | join(",")' "$P/thesis.json")
  {
    printf "section-id: '%s'\nsection-ids: '%s'\nlang: pt-BR\n" "$_fid" "$_ids"
    if [ "$_mode" = final ]; then printf "nocite: '@*'\nsuppress-bibliography: true\n"; fi
  } >"$TMP/meta-$_fid.yaml"
  _csl=$SHARE/csl/$(jq -r .bibliography.csl "$TPL/template.json")
  [ -f "$_csl" ] || die "the CSL file is missing: $_csl"
  _frc=0
  # shellcheck disable=SC2086
  pd -f "$PD_FROM" -t latex --wrap=none --top-level-division=chapter --shift-heading-level-by=1 --no-highlight \
    --lua-filter "$FILTERS/thesis.lua" --metadata-file "$TMP/meta-$_fid.yaml" \
    --bibliography "$P/refs.bib" --csl "$_csl" --citeproc \
    -o "$TMP/frag-$_fid.body" "$_fsf" || _frc=$?
  [ "$_frc" -eq 0 ] || pd_fail "$SLUG/$_fid: pandoc refused the section (the messages above; every warning fails the build)"
  _role=$(printf '%s' "$SEC" | jq -r .role)
  : >"$_fout.tmp"
  case "$_role" in
    chapter | appendix)
      printf '\\chapter{%s}\\label{ch:%s}\n' "$(tex_escape "$(printf '%s' "$SEC" | jq -r .title)")" "$_fid" >>"$_fout.tmp"
      ;;
  esac
  if [ "$_mode" = preview ]; then
    sed 's/^\\protect\\phantomsection\\label{refs}$/\\chapter*{Referências Bibliográficas}\n&/' "$TMP/frag-$_fid.body" >>"$_fout.tmp"
  else
    cat "$TMP/frag-$_fid.body" >>"$_fout.tmp"
  fi
  mv -f "$_fout.tmp" "$_fout"
}

# tex_tree <dir>: dir/shared (pinned), dir/overlay, dir/assets, dir/figures, dir/pt (to build in).
tex_tree() {
  _td=$1
  mkdir -p "$_td/pt/sections" "$_td/overlay" "$_td/assets"
  for _d in $(jq -r '.pinned_dirs[]' "$TPL/template.json"); do
    [ -d "$TPL/pinned/$_d" ] || die "template $TPLNAME: the pinned folder $_d is missing ($TPL/pinned/$_d)"
    cp -r "$TPL/pinned/$_d" "$_td/$_d"
  done
  chmod -R u+w "$_td"
  for _f in $(jq -r '.overlay.preamble' "$TPL/template.json"); do
    [ -f "$TPL/$_f" ] || die "template $TPLNAME: the overlay file $_f is missing"
    cp "$TPL/$_f" "$_td/overlay/"
  done
  [ ! -d "$P/figures" ] || cp -r "$P/figures" "$_td/figures"
  chmod -R u+w "$_td"
}

# documentclass_line: the \documentclass line of the pinned main file.
documentclass_line() {
  _mf=$TPL/$(jq -r .documentclass_from "$TPL/template.json")
  [ -f "$_mf" ] || die "template $TPLNAME: the main file $_mf is missing"
  _dl=$(grep -m 1 '^\\documentclass' "$_mf") || die "template $TPLNAME: no \\documentclass line in the main file"
  printf '%s' "$_dl"
}

# run_tex <dir with main.tex>: pdfLaTeX passes until the references settle. 0 when main.pdf is made.
run_tex() {
  _rd=$1
  _passes=$(pn .limits.tex_passes_max)
  _n=0
  while [ "$_n" -lt "$_passes" ]; do
    _n=$((_n + 1))
    _trc=0
    (cd "$_rd" && HOME=$TMP timed timeout -k 5 "$TEX_TIMEOUT" nice -n 10 pdflatex -no-shell-escape -interaction=nonstopmode -halt-on-error -file-line-error main.tex >tex-run.out 2>&1) || _trc=$?
    if [ "$_trc" -eq 124 ] || [ "$_trc" -eq 137 ]; then
      note "pdflatex stopped: no result after $TEX_TIMEOUT s (pass $_n)"
      return 1
    fi
    if [ "$_trc" -ne 0 ]; then
      note "pdflatex failed (pass $_n). The first errors:"
      grep -m 6 -A 3 -E '^[^ ]+:[0-9]+:|^!' "$_rd/tex-run.out" | sed 's/^/  tex: /' >&2 || true
      return 1
    fi
    grep -q -E 'Rerun to get|Label\(s\) may have changed|Please \(re\)run' "$_rd/main.log" || return 0
  done
  note "the references did not settle in $_passes passes"
  return 1
}

# tex_log_findings <log>: problems in the TeX log that a successful run can still have. FAIL lines.
tex_log_findings() {
  grep -E "LaTeX Warning: (Reference|Citation) .* undefined|Missing character|Undefined control sequence|LaTeX Warning: There were undefined references|Package hyperref Warning: Token not allowed" "$1" | head -n 10 || true
}

# ---------------------------------------------------------------- build-section

cmd_build_section() {
  [ $# -eq 2 ] || die "usage: thesis build-section <slug> <id>"
  need_tools pandoc pdflatex
  gate_prepare "$1" "$2"
  need_template "$(jq -r '.template // empty' "$P/thesis.json")"
  mkdir -p "$P/build"
  _w=$(mktemp -d "$P/build/.work.XXXXXX") || die "cannot make a folder in $P/build"
  _cleanup_w() { rm -rf "$_w"; }
  trap '_cleanup_w; cleanup' EXIT
  jq -r '.lists.allowed_chars[] | "\(.[0]) \(.[1])"' "$PROFILE" >"$TMP/ranges"
  : >"$TMP/markers"
  SECTION_ROLE=$(sec .role) awk -v ranges="$TMP/ranges" -v markers="$TMP/markers" -f "$LIB/lint.awk" "$SF" >"$TMP/bs.lint"
  if grep -q "^FAIL$(printf '\t')[0-9]*$(printf '\t')character" "$TMP/bs.lint"; then
    grep "^FAIL$(printf '\t')[0-9]*$(printf '\t')character" "$TMP/bs.lint" | head -n 3 | while IFS="$(printf '\t')" read -r _l _n _r _m; do note "line $_n: $_m"; done
    die "$SLUG/$SID: the text has characters the PDF engine cannot set (see above)"
  fi
  tex_tree "$_w/tex"
  make_fragment "$SID" "$P/build/$SID.tex" final
  make_fragment "$SID" "$_w/tex/pt/sections/frag.tex" preview
  _pre=false
  case "$(sec .role)" in resumo | abstract | agradecimentos | dedicatoria) _pre=true ;; esac
  jq -n --arg dc "$(documentclass_line)" --arg t "$(sec .title)" --argjson pre "$_pre" \
    '{ "section-title": $t, pretext: $pre }' >"$TMP/preview.json"
  _frc=0
  pd -f "$PD_FROM" -t latex -s --template "$TPL/overlay/preview.latex" --metadata-file "$TMP/preview.json" \
    -V "documentclass-line=$(documentclass_line)" -V tables=true -V graphics=true -V csl-refs=true -V indent=true \
    -o "$_w/tex/pt/main.tex" </dev/null || _frc=$?
  [ "$_frc" -eq 0 ] || pd_fail "$SLUG/$SID: pandoc cannot make the preview page"
  _t0=$(now_s)
  if ! run_tex "$_w/tex/pt"; then
    cp "$_w/tex/pt/main.log" "$P/build/$SID.preview.log" 2>/dev/null || true
    die "$SLUG/$SID: the preview did not build (log: build/$SID.preview.log)"
  fi
  # An @cap: reference points at another chapter: it is open in a preview and resolves in the whole work.
  _bad=$(tex_log_findings "$_w/tex/pt/main.log")
  _real=$(printf '%s\n' "$_bad" | grep -v -E "Reference .ch:[^']*' .*undefined|There were undefined references" || true)
  if [ -n "$_real" ]; then
    cp "$_w/tex/pt/main.log" "$P/build/$SID.preview.log"
    printf '%s\n' "$_real" | sed 's/^/  tex: /' >&2
    die "$SLUG/$SID: the preview has unresolved references or missing characters (log: build/$SID.preview.log)"
  fi
  if [ -n "$_bad" ]; then note "the references to other chapters stay open in the preview; they resolve in the whole work"; fi
  cp "$_w/tex/pt/main.pdf" "$P/build/$SID.preview.pdf.tmp" && mv -f "$P/build/$SID.preview.pdf.tmp" "$P/build/$SID.preview.pdf"
  _pages=$(pdfinfo "$P/build/$SID.preview.pdf" 2>/dev/null | awk '/^Pages:/ { print $2 }')
  log "build-section $SID: ${_pages:-?} page(s), $(($(now_s) - _t0)) s"
  say "thesis: $SLUG/$SID: build/$SID.tex and build/$SID.preview.pdf (${_pages:-?} pages)"
}

# ---------------------------------------------------------------- assemble

MONTHS='["janeiro","fevereiro","março","abril","maio","junho","julho","agosto","setembro","outubro","novembro","dezembro"]'

cmd_assemble() {
  [ $# -eq 1 ] || die "usage: thesis assemble <slug>"
  need_tools pandoc pdflatex pdfinfo
  need_project "$1"
  need_template "$(jq -r '.template // empty' "$P/thesis.json")"
  _T0=$(now_s)
  _prob=$(jq -r --slurpfile prof "$PROFILE" --argjson final true -f "$LIB/validate.jq" "$P/thesis.json") || die "$SLUG: thesis.json cannot be checked"
  if [ -n "$_prob" ]; then
    printf '%s\n' "$_prob" | sed 's/^/  thesis.json: /' >&2
    die "$SLUG: thesis.json is not ready (see above)"
  fi
  # Every section accepted by a recorded verdict, and unchanged since.
  : >"$TMP/notacc"
  for _id in $(order_ids); do
    need_section "$_id"
    sec_status "$_id"
    [ "$ST" = accepted ] || printf '  %s is %s\n' "$_id" "$ST" >>"$TMP/notacc"
  done
  if [ -s "$TMP/notacc" ]; then
    cat "$TMP/notacc" >&2
    die "$SLUG: not every section is accepted by a verdict (a section edited after its accept counts as changed)"
  fi
  lock assemble
  mkdir -p "$P/build" "$(out_dir "$SLUG")"
  # The gates that need the whole work: lint without placeholders on every section, cite-check.
  for _id in $(order_ids); do
    "$SELF" lint "$SLUG" "$_id" >"$TMP/asm-lint.out" 2>&1 || {
      sed 's/^/  /' "$TMP/asm-lint.out" >&2
      die "$SLUG/$_id: lint fails (placeholders such as **[AUTHOR: ...]** or **[ANALYSIS]** must be gone)"
    }
  done
  "$SELF" cite-check "$SLUG" >"$TMP/asm-cc.out" 2>&1 || {
    sed 's/^/  /' "$TMP/asm-cc.out" >&2
    die "$SLUG: cite-check of the whole work fails"
  }
  _w=$(mktemp -d "$P/build/.asm.XXXXXX") || die "cannot make a folder in $P/build"
  _cleanup_asm() { rm -rf "$_w"; }
  trap '_cleanup_asm; cleanup' EXIT
  tex_tree "$_w/tex"
  jq -r '.assets.ufrj_logo // empty' "$P/thesis.json" >"$TMP/logo"
  _haslogo=false
  if [ -s "$TMP/logo" ]; then
    _lg=$(cat "$TMP/logo")
    case "$_lg" in
      assets/*[!A-Za-z0-9._/-]* | */../* | *..* | /*) die "$SLUG: assets.ufrj_logo must be a plain path under assets/ (letters, digits, . _ / -)" ;;
      assets/*.pdf | assets/*.png | assets/*.jpg | assets/*.jpeg) ;;
      *) die "$SLUG: assets.ufrj_logo must be a PDF, PNG or JPEG file under assets/" ;;
    esac
    plain_file "$P/$_lg" || die "$SLUG: the UFRJ logo file $_lg is missing"
    cp "$P/$_lg" "$_w/tex/assets/ufrj-logo.${_lg##*.}"
    _haslogo=true
  fi
  # Fragments, in order, as s01.tex, s02.tex, ...
  : >"$TMP/files.tsv"
  _n=0
  for _id in $(order_ids); do
    _n=$((_n + 1))
    _f=$(printf 's%02d' "$_n")
    need_section "$_id"
    make_fragment "$_id" "$_w/tex/pt/sections/$_f.tex" final
    printf '%s\t%s\n' "$_id" "$_f" >>"$TMP/files.tsv"
  done
  # The reference list of every entry of refs.bib (cite-check made sure none is unused).
  printf "nocite: '@*'\nlang: pt-BR\n" >"$TMP/meta-refs.yaml"
  printf '::: {#refs}\n:::\n' >"$TMP/stub.md"
  _csl=$SHARE/csl/$(jq -r .bibliography.csl "$TPL/template.json")
  _rrc=0
  pd -f "$PD_FROM" -t latex --wrap=none --metadata-file "$TMP/meta-refs.yaml" --bibliography "$P/refs.bib" --csl "$_csl" --citeproc \
    -o "$_w/tex/pt/refs.tex" "$TMP/stub.md" || _rrc=$?
  [ "$_rrc" -eq 0 ] || pd_fail "$SLUG: pandoc cannot make the reference list"
  # The data of the front pages and the order of the sections.
  jq --slurpfile prof "$PROFILE" --argjson months "$MONTHS" --argjson haslogo "$_haslogo" --rawfile files "$TMP/files.tsv" "$JQ_UPCASE"'
    . as $t
    | ($prof[0].courses[] | select(.name == $t.course)) as $c
    | ($files | split("\n") | map(select(. != "") | split("\t") | {key: .[0], value: .[1]}) | from_entries) as $f
    | {
        title: .title, "title-plain": .title, "title-upper": (.title | upcase),
        author: .author, "author-plain": .author, "author-ref": .author_ref, advisor: .advisor,
        examiners: .examiners, "no-examiners": ((.examiners | length) == 0),
        course: .course, "course-upper": (.course | upcase), degree: $c.title, "degree-upper": ($c.title | upcase),
        "month-name": $months[.month - 1], "month-upper": ($months[.month - 1] | upcase), year: (.year | tostring),
        "has-ufrj-logo": $haslogo, "list-figures": .lists.figures, "list-tables": .lists.tables,
        "has-appendix": (.sections | any(.role == "appendix" and .status != "omit")),
        sections: (.sections | sort_by(.order) | map(select(.status != "omit")) | map({
          id, file: $f[.id], keywords: (.keywords // []),
          "is-resumo": (.role == "resumo"), "is-abstract": (.role == "abstract"),
          "is-agradecimentos": (.role == "agradecimentos"), "is-dedicatoria": (.role == "dedicatoria"),
          "is-chapter": (.role == "chapter"), "is-appendix": (.role == "appendix")
        }))
      }' "$P/thesis.json" >"$TMP/meta.json" || die "$SLUG: cannot build the front-page data from thesis.json"
  _mrc=0
  pd -f "$PD_FROM" -t latex -s --template "$TPL/overlay/main.latex" --metadata-file "$TMP/meta.json" \
    -V "documentclass-line=$(documentclass_line)" -V tables=true -V graphics=true -V csl-refs=true -V indent=true \
    -o "$_w/tex/pt/main.tex" </dev/null || _mrc=$?
  [ "$_mrc" -eq 0 ] || pd_fail "$SLUG: pandoc cannot fill the template"
  if ! run_tex "$_w/tex/pt"; then
    cp "$_w/tex/pt/main.log" "$P/build/main.log" 2>/dev/null || true
    die "$SLUG: the PDF did not build (log: build/main.log)"
  fi
  tex_log_findings "$_w/tex/pt/main.log" >"$TMP/asm-findings"
  if [ -s "$TMP/asm-findings" ]; then
    cp "$_w/tex/pt/main.log" "$P/build/main.log"
    sed 's/^/  tex: /' "$TMP/asm-findings" >&2
    die "$SLUG: the PDF has unresolved references or missing characters (log: build/main.log)"
  fi
  # Keep the tree and the log, replace the PDF atomically.
  rm -rf "$P/build/tex"
  mkdir -p "$P/build/tex"
  cp -r "$_w/tex/." "$P/build/tex/"
  cp "$_w/tex/pt/main.pdf" "$P/build/thesis.pdf.tmp"
  mv -f "$P/build/thesis.pdf.tmp" "$P/build/thesis.pdf"
  cp "$_w/tex/pt/main.log" "$P/build/main.log"
  # What was assembled: the hash of every accepted section, for publish.
  for _id in $(order_ids); do printf '%s\t%s\n' "$_id" "$(sha_of "$(section_file "$_id")")"; done | jq -R -s 'split("\n") | map(select(. != "") | split("\t") | {key: .[0], value: .[1]}) | from_entries' | atomic_write "$P/build/assembled.json"
  cp "$P/build/thesis.pdf" "$(out_dir "$SLUG")/thesis.pdf.tmp" && mv -f "$(out_dir "$SLUG")/thesis.pdf.tmp" "$(out_dir "$SLUG")/thesis.pdf"
  _secs=$(($(now_s) - _T0))
  _peak=$(awk '{ if ($2 > m) m = $2 } END { print m + 0 }' "$TIMES")
  log "assemble: $(pdfinfo "$P/build/thesis.pdf" | awk '/^Pages:/ { print $2 }') pages, $_secs s, peak child $_peak KiB"
  unlock assemble
  cmd_pdf_qa "$SLUG"
}

# ---------------------------------------------------------------- pdf-qa

cmd_pdf_qa() {
  [ $# -eq 1 ] || die "usage: thesis pdf-qa <slug>"
  need_tools pdfinfo pdftotext pdffonts pdftohtml
  need_project "$1"
  _pdf=$P/build/thesis.pdf
  plain_file "$_pdf" || die "$SLUG: no build/thesis.pdf: run thesis assemble first"
  _q=$TMP/qa
  mkdir -p "$_q"
  _prc=0
  timeout -k 5 "$POPPLER_TIMEOUT" pdfinfo -f 1 -l 9999 "$_pdf" >"$_q/info.txt" 2>"$_q/info.err" || _prc=$?
  [ "$_prc" -eq 0 ] || die "$SLUG: pdfinfo cannot read the PDF: $(head -n 1 "$_q/info.err")"
  _pages=$(awk '/^Pages:/ { print $2 }' "$_q/info.txt")
  _ver=$(awk '/^PDF version:/ { print $3 }' "$_q/info.txt")
  _tol=$(pn .layout.paper_tolerance_mm)
  _pw=$(pn '.layout.paper_mm[0]')
  _ph=$(pn '.layout.paper_mm[1]')
  # Page sizes in pt, each page against A4.
  awk -v w="$_pw" -v h="$_ph" -v tol="$_tol" '
    /^Page +[0-9]+ size:/ { pw = $4 * 25.4 / 72; ph = $6 * 25.4 / 72; n++; if (pw < w - tol || pw > w + tol || ph < h - tol || ph > h + tol) bad++ }
    END { printf "%d %d\n", n, bad + 0 }' "$_q/info.txt" >"$_q/sizes"
  _a4bad=$(cut -d' ' -f2 "$_q/sizes")
  timeout -k 5 "$POPPLER_TIMEOUT" pdffonts "$_pdf" >"$_q/fonts.txt" 2>/dev/null || true
  jq -R -s '[split("\n")[2:][] | select(. != "") | split(" +"; "g") | {name: .[0], emb: .[-5], type: (.[1:-6] | join(" "))}]' "$_q/fonts.txt" >"$_q/fonts.json" 2>/dev/null || echo '[]' >"$_q/fonts.json"
  _notemb=$(jq '[.[] | select(.emb != "yes")] | length' "$_q/fonts.json")
  timeout -k 5 "$POPPLER_TIMEOUT" pdftotext -layout "$_pdf" "$_q/text.txt" || die "$SLUG: pdftotext failed"
  _qq=$(grep -c '??' "$_q/text.txt" || true)
  _null=$(grep -c '(null)' "$_q/text.txt" || true)
  # Section titles in order: every chapter title is a line of the text, in the order of thesis.json,
  # after the table of contents.
  jq -r '.sections | sort_by(.order)[] | select(.status != "omit" and .role == "chapter") | .title' "$P/thesis.json" >"$_q/titles"
  _tocpage=$(awk 'BEGIN { RS = "\f" } /(^|\n) *Sumário *\n/ { print NR; exit }' "$_q/text.txt")
  : >"$_q/missing"
  _lastpage=${_tocpage:-1}
  while IFS= read -r _t; do
    [ -n "$_t" ] || continue
    _pg=$(awk -v t="$_t" -v from="$((_lastpage + 1))" 'BEGIN { RS = "\f" } NR >= from { n = split($0, l, "\n"); for (i = 1; i <= n; i++) { x = l[i]; gsub(/^[ \t]+|[ \t]+$/, "", x); if (x == t) { print NR; exit } } }' "$_q/text.txt")
    if [ -z "$_pg" ]; then printf '%s\n' "$_t" >>"$_q/missing"; else _lastpage=$_pg; fi
  done <"$_q/titles"
  # Margins and the line pitch, from the boxes of the lines.
  timeout -k 5 "$POPPLER_TIMEOUT" pdftotext -bbox-layout "$_pdf" "$_q/bbox.html" || die "$SLUG: pdftotext -bbox-layout failed"
  awk -v zone="$(pn .layout.bbox_footer_zone_pt)" -f "$LIB/bbox.awk" "$_q/bbox.html" >"$_q/bbox.out"
  _min() { awk -F'\t' -v k="$1" '$1 == "MIN" && $2 == k { print $3 }' "$_q/bbox.out"; }
  _tolm=$(pn .layout.margin_tolerance_mm)
  _mtop=$(_min top)
  _mbot=$(_min bottom)
  _mleft=$(_min left)
  _mright=$(_min right)
  _pitch=$(awk -F'\t' '$1 == "PITCH" { print $2 }' "$_q/bbox.out")
  # Fonts of the text: the dominant family and size, the biggest size, every colour.
  timeout -k 5 "$POPPLER_TIMEOUT" pdftohtml -xml -zoom 1 -i -q -stdout "$_pdf" >"$_q/fonts.xml" 2>/dev/null || : >"$_q/fonts.xml"
  awk -f "$LIB/fontxml.awk" "$_q/fonts.xml" >"$_q/fontxml.out"
  _bodyfam=$(awk -F'\t' '$1 == "BODY" { print $2 }' "$_q/fontxml.out")
  _bodysize=$(awk -F'\t' '$1 == "BODY" { print $3 }' "$_q/fontxml.out")
  _maxsize=$(awk -F'\t' '$1 == "MAXSIZE" { print $2 }' "$_q/fontxml.out")
  _nonblack=$(awk -F'\t' '$1 == "NONBLACK" { print $2 }' "$_q/fontxml.out")
  _overfull=$(grep -c 'Overfull \\hbox' "$P/build/main.log" 2>/dev/null || true)
  _overmax=$(sed -n 's/^Overfull \\hbox (\([0-9.]*\)pt too wide).*/\1/p' "$P/build/main.log" 2>/dev/null | sort -n | tail -n 1)
  _exact=$(awk -f "$LIB/layout.awk" "$P/build/main.log" 2>/dev/null)
  [ -n "$_exact" ] || _exact="0 0 0 0 0"
  # shellcheck disable=SC2086
  set -- $_exact
  _etop=$1 _ebot=$2 _eleft=$3 _eright=$4 _ebase=$5
  _mkpass=$(awk -v t="$_mtop" -v b="$_mbot" -v l="$_mleft" -v r="$_mright" -v et="$_etop" -v eb="$_ebot" -v el="$_eleft" -v er="$_eright" \
    -v mt="$(pn .layout.margin_min_mm.top)" -v mb="$(pn .layout.margin_min_mm.bottom)" -v ml="$(pn .layout.margin_min_mm.left)" -v mr="$(pn .layout.margin_min_mm.right)" -v tol="$_tolm" -v om="${_overmax:-0}" -v omax="$(pn .layout.overfull_max_pt)" \
    'BEGIN { ex = (et + 0.05 >= mt && eb + 0.05 >= mb && el + 0.05 >= ml && er + 0.05 >= mr)
             me = (t + tol >= mt && b + tol >= mb && l + tol >= ml && r + tol >= mr)
             print ((ex && me && om <= omax) ? "true" : "false") }')
  _titles_ok=true
  [ ! -s "$_q/missing" ] || _titles_ok=false
  _pass=true
  { [ "$_a4bad" -eq 0 ] && [ "$_notemb" -eq 0 ] && [ "$_qq" -eq 0 ] && [ "$_null" -eq 0 ] && [ "$_titles_ok" = true ] && [ "$_mkpass" = true ] && [ -n "$_pages" ]; } || _pass=false
  jq -n --arg pass "$_pass" --argjson pages "${_pages:-0}" --arg ver "$_ver" --argjson a4bad "$_a4bad" \
    --slurpfile fonts "$_q/fonts.json" --argjson notemb "$_notemb" --argjson qq "$_qq" --argjson nul "$_null" \
    --arg titles_ok "$_titles_ok" --rawfile missing "$_q/missing" \
    --arg mtop "${_mtop:-0}" --arg mbot "${_mbot:-0}" --arg mleft "${_mleft:-0}" --arg mright "${_mright:-0}" --arg mkpass "$_mkpass" \
    --arg pitch "${_pitch:-0}" --arg bodyfam "$_bodyfam" --arg bodysize "${_bodysize:-0}" --arg maxsize "${_maxsize:-0}" --argjson nonblack "${_nonblack:-0}" \
    --argjson overfull "${_overfull:-0}" --argjson single "$(pn .layout.single_baselineskip_pt)" \
    --argjson etop "$_etop" --argjson ebot "$_ebot" --argjson eleft "$_eleft" --argjson eright "$_eright" --argjson overmax "${_overmax:-0}" \
    '{
      pass: ($pass == "true"),
      pages: $pages, pdf_version: $ver,
      page_size_ok: ($a4bad == 0), pages_not_a4: $a4bad,
      fonts: $fonts[0], fonts_all_embedded: ($notemb == 0),
      unresolved_refs: $qq, null_strings: $nul,
      titles_in_order: ($titles_ok == "true"), titles_missing: ($missing | split("\n") | map(select(. != ""))),
      min_margins_mm: { top: ($mtop | tonumber), bottom: ($mbot | tonumber), left: ($mleft | tonumber), right: ($mright | tonumber) },
      layout_margins_mm: { top: $etop, bottom: $ebot, left: $eleft, right: $eright },
      margins_ok: ($mkpass == "true"),
      line_pitch_pt: ($pitch | tonumber), line_spacing: (if ($pitch | tonumber) > 0 then (($pitch | tonumber) / $single * 100 | round / 100) else null end),
      body_font: { family: $bodyfam, size_pt: ($bodysize | tonumber) }, max_font_size_pt: ($maxsize | tonumber), non_black_fonts: $nonblack,
      overfull_boxes: $overfull, overfull_max_pt: $overmax,
      note: "layout_margins_mm is exact: the text block of the TeX run (log lines thesis-layout). min_margins_mm is measured on the line boxes of poppler (pdftotext -bbox-layout), page numbers in the footer zone left out; those boxes stand about 1.2 mm outside the glyphs, so they get a tolerance (profile layout.margin_tolerance_mm). Figures are not measured. The pitch is the median distance of consecutive body lines."
    }' | atomic_write "$P/build/qa.json"
  say "pdf-qa: $SLUG: $(jq -r '"\(.pages) pages, A4 " + (.page_size_ok | tostring) + ", fonts embedded " + (.fonts_all_embedded | tostring) + ", ?? " + (.unresolved_refs | tostring) + ", (null) " + (.null_strings | tostring) + ", titles in order " + (.titles_in_order | tostring) + ", margins ok " + (.margins_ok | tostring)' "$P/build/qa.json")"
  say "  margins mm (top bottom left right): $_mtop $_mbot $_mleft $_mright; line pitch $_pitch pt; body font $_bodyfam $_bodysize pt; largest $_maxsize pt; overfull boxes $_overfull"
  [ ! -s "$_q/missing" ] || sed 's/^/  title not found in order: /' "$_q/missing"
  say "pdf-qa: $SLUG: $([ "$_pass" = true ] && echo PASS || echo FAIL) (build/qa.json)"
  [ "$_pass" = true ]
}

# ---------------------------------------------------------------- publish

cmd_publish() {
  _slug=
  _replace=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --replace) _replace=1 ;;
      -*) die "publish: unknown option $1" ;;
      *) [ -z "$_slug" ] || die "publish: too many arguments"; _slug=$1 ;;
    esac
    shift
  done
  [ -n "$_slug" ] || die "usage: thesis publish <slug> [--replace]"
  need_project "$_slug"
  [ -f "$P/build/qa.json" ] && [ "$(jq -r .pass "$P/build/qa.json")" = true ] || die "$SLUG: no passing pdf-qa (build/qa.json): run thesis assemble"
  plain_file "$P/build/thesis.pdf" || die "$SLUG: no build/thesis.pdf"
  [ "$P/build/thesis.pdf" -nt "$P/thesis.json" ] || die "$SLUG: thesis.json is newer than the PDF: assemble again"
  # Every section as accepted, still the same text as assembled.
  [ -f "$P/build/assembled.json" ] || die "$SLUG: no build/assembled.json: assemble again"
  for _id in $(order_ids); do
    need_section "$_id"
    sec_status "$_id"
    [ "$ST" = accepted ] || die "$SLUG/$_id is $ST: assemble and review again before publish"
    [ "$(jq -r --arg id "$_id" '.[$id] // empty' "$P/build/assembled.json")" = "$(sha_of "$(section_file "$_id")")" ] || die "$SLUG/$_id changed after the PDF was assembled: assemble again"
  done
  _dest=$OUTBOX/$_slug
  if [ -e "$_dest" ] && [ "$_replace" -eq 0 ]; then
    die "$_dest exists (another run?): use --replace to overwrite it"
  fi
  mkdir -p "$OUTBOX" || die "cannot make the outbox $OUTBOX"
  _t=$(mktemp -d "$OUTBOX/.pub.$_slug.XXXXXX") || die "cannot write in the outbox $OUTBOX"
  cp "$P/build/thesis.pdf" "$_t/thesis.pdf" && cp "$P/build/qa.json" "$_t/qa.json" && cp "$P/REFERENCES.md" "$_t/REFERENCES.md" || {
    rm -rf "$_t"
    die "publish: cannot copy the files"
  }
  mkdir "$_t/review"
  if [ -d "$P/review" ]; then cp "$P/review/"* "$_t/review/" 2>/dev/null || true; fi
  chmod 0755 "$_t"
  if [ -e "$_dest" ]; then rm -rf "$_dest"; fi
  mv "$_t" "$_dest" || {
    rm -rf "$_t"
    die "publish: cannot move the files into $_dest"
  }
  log "publish to $_dest"
  say "thesis: published $SLUG to $_dest (thesis.pdf, qa.json, REFERENCES.md, review/)"
}
