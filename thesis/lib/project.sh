# project.sh: new, sections, status, fetch, release, submit, verdict, review-report. Sourced by `thesis`.
# shellcheck shell=sh
# shellcheck disable=SC2034,SC2329,SC2015,SC2129,SC2016
# (SC2034 and SC2329: the libraries share variables and functions through `thesis`, which sources them all;
# SC2015: the `A && B || C` forms end in a die; SC2016: sh -c and awk programs in single quotes are meant.)

TPL_DIR() { printf '%s/templates/%s' "$SHARE" "$1"; }

need_template() {
  _tn=${1:-$(pn .template.default)}
  check_name template "$_tn" 48
  TPL=$(TPL_DIR "$_tn")
  [ -f "$TPL/template.json" ] || die "no template $_tn (looked in $TPL)"
  TPLNAME=$_tn
}

# ---------------------------------------------------------------- new

cmd_new() {
  _slug=
  _tpl=
  while [ $# -gt 0 ]; do
    case "$1" in
      --template)
        [ $# -ge 2 ] || die "new: --template needs a name"
        _tpl=$2
        shift
        ;;
      -*) die "new: unknown option $1" ;;
      *) [ -z "$_slug" ] || die "new: too many arguments"; _slug=$1 ;;
    esac
    shift
  done
  [ -n "$_slug" ] || die "usage: thesis new <slug> [--template <name>]"
  check_slug "$_slug"
  need_template "$_tpl"
  _dest=$(proj_dir "$_slug")
  [ ! -e "$_dest" ] || die "the project $_slug exists ($_dest)"
  mkdir -p "$HOME_DIR/projects" || die "cannot make $HOME_DIR/projects"
  _tmp=$(mktemp -d "$HOME_DIR/projects/.new-$_slug.XXXXXX") || die "cannot make a folder in $HOME_DIR/projects"
  for _d in sections sources claims review build notes state figures assets; do mkdir "$_tmp/$_d"; done
  _month=$(date +%-m)
  _year=$(date +%Y)
  jq -n --slurpfile t "$TPL/template.json" --arg tpl "$TPLNAME" --argjson month "$_month" --argjson year "$_year" '
    {
      version: 1,
      template: $tpl,
      title: "A PREENCHER",
      title_en: "A PREENCHER",
      author: "A PREENCHER",
      author_ref: "A PREENCHER",
      advisor: "A PREENCHER",
      examiners: [],
      course: "Engenharia Eletrônica e de Computação",
      month: $month,
      year: $year,
      language: "pt-BR",
      citation_style: "author-date",
      lists: { figures: true, tables: true },
      assets: { ufrj_logo: null },
      sections: $t[0].default_sections
    }' >"$_tmp/thesis.json" || {
    rm -rf "$_tmp"
    die "new: cannot write thesis.json"
  }
  cat >"$_tmp/notes/facts.md" <<'EOF'
# Facts of the thesis

One file for the whole work. Every section reads it; no section reads another section's text.
Write only what is true and checked: numbers with their unit, the setup, the dates, who decided what.
The author writes or confirms this file. A writer never adds an experience of the author.

| Fact | Value | Where it comes from |
|---|---|---|
EOF
  cat >"$_tmp/notes/glossary.md" <<'EOF'
# Glossário

One row a term. The first column is the word the thesis uses. A term that is an English word and is
listed here is not flagged as an anglicism, and the forms of one row count as one term.

| Termo | Definição | Observação |
|---|---|---|
EOF
  cat >"$_tmp/refs.bib" <<'EOF'
% The sources of the thesis. Only the librarian adds an entry, and only after fetching the work and
% writing sources/<key>.md and a row in REFERENCES.md. Never invent an entry.
EOF
  cat >"$_tmp/REFERENCES.md" <<'EOF'
# REFERENCES

| Key | Status | Checked against | Note |
|---|---|---|---|

Status: `verified` (fetched, details match), `partial` (fetched, one detail unconfirmed: leave the field out
of refs.bib and write `unconfirmed: field` in the Note), `unverified` (not fetched: must not be cited).
EOF
  printf '%s %s new project from template %s\n' "$(now_iso)" "${USER:-?}" "$TPLNAME" >"$_tmp/notes/thesis.log"
  chmod 0755 "$_tmp"
  mv "$_tmp" "$_dest" || {
    rm -rf "$_tmp"
    die "new: cannot move the project into place"
  }
  say "thesis: new project $_slug at $_dest (template $TPLNAME)"
  say "  next: fill thesis.json (title, title_en, author, author_ref, advisor, examiners, course, month, year),"
  say "        write notes/facts.md and notes/glossary.md, set the sources of each section, then writers run:"
  say "        thesis fetch $_slug --as <seat>"
}

# ---------------------------------------------------------------- state of a section

claim_file() { printf '%s/claims/%s.claim' "$P" "$1"; }

# claim_info <id>: "seat epoch" of a claim, or nothing.
claim_info() {
  _cf=$(claim_file "$1")
  plain_file "$_cf" || return 0
  _s=$(sed -n 's/^seat=//p' "$_cf" | head -n 1)
  _e=$(sed -n 's/^epoch=//p' "$_cf" | head -n 1)
  [ -n "$_s" ] && [ -n "$_e" ] && printf '%s %s\n' "$_s" "$_e"
}

claim_is_stale() { # <epoch>
  [ $(($(now_s) - $1)) -gt "$(pn .limits.claim_stale_s)" ]
}

# sec_status <id>: sets ST to omit, claimed, drafted, linted, revise, accepted, changed (accepted, then edited) or todo.
# Needs SEC for the id. Sets ST_BY (the holder of a claim) and ST_STALE.
sec_status() {
  ST_BY=
  ST_STALE=0
  _id=$1
  _base=$(printf '%s' "$SEC" | jq -r '.status // "todo"')
  if [ "$_base" = omit ]; then
    ST=omit
    return 0
  fi
  _ci=$(claim_info "$_id")
  if [ -n "$_ci" ]; then
    ST_BY=${_ci% *}
    if claim_is_stale "${_ci#* }"; then ST_STALE=1; else
      ST=claimed
      return 0
    fi
  fi
  _st=$(state_get "$_id" '.status // "todo"')
  if [ "$_st" = accepted ]; then
    _sf=$(section_file "$_id")
    _want=$(state_get "$_id" '.accepted_sha')
    if plain_file "$_sf" && [ "$(sha_of "$_sf")" = "$_want" ]; then ST=accepted; else ST=changed; fi
    return 0
  fi
  [ "$_st" != null ] || _st=todo
  ST=$_st
}

# ---------------------------------------------------------------- sections, status

cmd_sections() {
  if [ $# -eq 0 ]; then
    [ -d "$HOME_DIR/projects" ] || die "no projects folder ($HOME_DIR/projects)"
    for _d in "$HOME_DIR"/projects/*/; do
      [ -f "${_d}thesis.json" ] && say "$(basename -- "$_d")"
    done
    return 0
  fi
  [ $# -eq 1 ] || die "usage: thesis sections [<slug>]"
  need_project "$1"
  printf '%-6s %-18s %-11s %-10s %-16s %-6s %s\n' ORDER ID KIND STATUS BY ROUND "WORDS/TARGET"
  jq -r '.sections | sort_by(.order)[] | .id' "$P/thesis.json" | while IFS= read -r _id; do
    need_section "$_id"
    sec_status "$_id"
    _s=$ST
    _by=$ST_BY
    [ "$_s" = claimed ] || _by=$(state_get "$_id" '.by // ""')
    [ "$_by" != null ] || _by=
    [ "$ST_STALE" -eq 0 ] || _s="$_s (stale claim)"
    _round=$(state_get "$_id" '.round // 0')
    [ "$_round" != null ] || _round=0
    _sf=$(section_file "$_id")
    _w=-
    plain_file "$_sf" && _w=$(words_of "$_sf")
    printf '%-6s %-18s %-11s %-10s %-16s %-6s %s/%s\n' "$(sec .order)" "$_id" "$(sec .kind)" "$_s" "${_by:--}" "$_round" "$_w" "$(sec '.target_words // 0')"
  done
}

cmd_status() {
  [ $# -eq 1 ] || die "usage: thesis status <slug>"
  need_project "$1"
  _title=$(jq -r '.title' "$P/thesis.json")
  say "thesis status: $SLUG  ($_title)"
  _nq=$(find "$P/notes" -name '*.questions.md' -size +0 2>/dev/null | wc -l | tr -d ' ')
  _verified=$(refs_rows "$P/REFERENCES.md" | awk -F'\t' '$2 == "verified" { n++ } END { print n + 0 }')
  _bib=$(bib_tsv "$P/refs.bib" | awk -F'\t' '$3 == "@entry" { n++ } END { print n + 0 }')
  say "  verified sources: $_verified of $_bib entries in refs.bib; open questions for the editor: $_nq"
  cmd_sections "$SLUG" | sed 's/^/  /'
  # What blocks assemble.
  : >"$TMP/blocks"
  jq -r --slurpfile prof "$PROFILE" --argjson final true -f "$LIB/validate.jq" "$P/thesis.json" >>"$TMP/blocks" 2>/dev/null || true
  jq -r '.sections | sort_by(.order)[] | select(.status != "omit") | .id' "$P/thesis.json" | while IFS= read -r _id; do
    need_section "$_id"
    sec_status "$_id"
    _s=$ST
    [ "$_s" = accepted ] || printf 'section %s is %s, not accepted\n' "$_id" "$_s"
  done >>"$TMP/blocks"
  if [ -s "$TMP/blocks" ]; then
    say "  blocks assemble:"
    sed 's/^/    /' "$TMP/blocks"
  else
    say "  nothing blocks assemble (it still runs the whole-work cite-check first)"
  fi
  if [ -f "$P/build/qa.json" ]; then say "  last pdf-qa: $(jq -r 'if .pass then "PASS" else "FAIL" end + " (" + (.pages | tostring) + " pages)"' "$P/build/qa.json")"; fi
}

# ---------------------------------------------------------------- fetch, release

# order_ids <slug>: ids of the sections that are not omitted, in order.
order_ids() { jq -r '.sections | sort_by(.order)[] | select(.status != "omit") | .id' "$P/thesis.json"; }

# try_claim <id> <seat>: atomic. 0 when the claim is yours now.
try_claim() {
  mkdir -p "$P/claims"
  _cf=$(claim_file "$1")
  if ( set -C; printf 'seat=%s\nepoch=%s\niso=%s\nsection=%s\n' "$2" "$(now_s)" "$(now_iso)" "$1" >"$_cf" ) 2>/dev/null; then return 0; fi
  # The file exists: yours (resume), stale (take it over, under a lock), or somebody else's.
  _ci=$(claim_info "$1")
  [ -n "$_ci" ] || return 1
  if [ "${_ci% *}" = "$2" ]; then return 0; fi
  claim_is_stale "${_ci#* }" || return 1
  lock claims
  _ci=$(claim_info "$1")
  if [ -n "$_ci" ] && claim_is_stale "${_ci#* }"; then
    log "claim of ${_ci% *} on $1 is stale: taken over by $2"
    rm -f "$_cf"
    if ( set -C; printf 'seat=%s\nepoch=%s\niso=%s\nsection=%s\n' "$2" "$(now_s)" "$(now_iso)" "$1" >"$_cf" ) 2>/dev/null; then
      unlock claims
      return 0
    fi
  fi
  unlock claims
  return 1
}

cmd_fetch() {
  _slug=
  _id=
  _as=
  while [ $# -gt 0 ]; do
    case "$1" in
      --as)
        [ $# -ge 2 ] || die "fetch: --as needs a seat"
        _as=$2
        shift
        ;;
      -*) die "fetch: unknown option $1" ;;
      *) if [ -z "$_slug" ]; then _slug=$1; elif [ -z "$_id" ]; then _id=$1; else die "fetch: too many arguments"; fi ;;
    esac
    shift
  done
  [ -n "$_slug" ] || die "usage: thesis fetch <slug> [<id>] [--as <seat>]"
  need_project "$_slug"
  SEAT=$(seat_name "$_as")
  mkdir -p "$P/claims" "$P/state" "$P/sections" "$P/notes"
  _got=
  if [ -n "$_id" ]; then
    need_section "$_id"
    sec_status "$_id"
    _s=$ST
    case "$_s" in
      todo | revise | claimed) ;;
      omit) die "$SLUG/$_id is omitted in thesis.json (status omit): the editor must set it to todo" ;;
      *) die "$SLUG/$_id is $_s: not for writing (the editor reopens a section with a revise verdict)" ;;
    esac
    try_claim "$_id" "$SEAT" || die "$SLUG/$_id is claimed by $(claim_info "$_id" | cut -d' ' -f1) and the claim is not stale (after $(pn .limits.claim_stale_s) s)"
    _got=$_id
  else
    # First the sections that this seat already holds, then the first free one in order.
    for _pass in mine free; do
      for _c in $(order_ids); do
        need_section "$_c"
        sec_status "$_c"
        _s=$ST
        if [ "$_pass" = mine ]; then
          [ "$_s" = claimed ] && [ "$ST_BY" = "$SEAT" ] && { _got=$_c; break; }
          continue
        fi
        case "$_s" in
          todo | revise) ;;
          *) continue ;;
        esac
        if try_claim "$_c" "$SEAT"; then _got=$_c; break; fi
      done
      [ -z "$_got" ] || break
    done
    [ -n "$_got" ] || {
      say "thesis: nothing to fetch in $SLUG for $SEAT (every section is claimed, drafted or accepted, or omitted)"
      return 3
    }
  fi
  need_section "$_got"
  log "fetch $_got by $SEAT"
  work_order "$_got"
}

cmd_release() {
  _slug=
  _id=
  _as=
  _force=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --as)
        [ $# -ge 2 ] || die "release: --as needs a seat"
        _as=$2
        shift
        ;;
      --force) _force=1 ;;
      -*) die "release: unknown option $1" ;;
      *) if [ -z "$_slug" ]; then _slug=$1; elif [ -z "$_id" ]; then _id=$1; else die "release: too many arguments"; fi ;;
    esac
    shift
  done
  [ -n "$_slug" ] && [ -n "$_id" ] || die "usage: thesis release <slug> <id> [--as <seat>] [--force]"
  need_project "$_slug"
  need_section "$_id"
  SEAT=$(seat_name "$_as")
  _ci=$(claim_info "$_id")
  [ -n "$_ci" ] || die "$SLUG/$_id has no claim"
  if [ "${_ci% *}" != "$SEAT" ] && [ "$_force" -eq 0 ] && ! claim_is_stale "${_ci#* }"; then
    die "$SLUG/$_id is claimed by ${_ci% *}, not by $SEAT (--force to take it back)"
  fi
  rm -f "$(claim_file "$_id")"
  log "release $_id by $SEAT"
  say "thesis: released $SLUG/$_id"
}

# work_order <id>: one self-contained work order on the standard output.
work_order() {
  _id=$1
  _role=$(sec .role)
  _class=$(sec '.cite_class // "medium"')
  _tgt=$(jq -r --arg c "$_class" '.cite.score_targets[$c]' "$PROFILE")
  _w=$(sec '.target_words // 0')
  _lo=$(awk -v w="$_w" -v f="$(pn .words.target_tolerance_low)" 'BEGIN { printf "%d", w * f }')
  _hi=$(awk -v w="$_w" -v f="$(pn .words.target_tolerance_high)" 'BEGIN { printf "%d", w * f }')
  _rows=$TMP/wo.rows
  refs_rows "$P/REFERENCES.md" >"$_rows"
  _round=$(state_get "$_id" '.round // 0')
  say "THESIS WORK ORDER"
  say "project:  $SLUG"
  say "section:  $_id   ($(sec .kind), role $_role)"
  say "title:    $(sec .title)"
  say "seat:     $SEAT, claimed $(now_iso); the claim is stale after $(pn .limits.claim_stale_s) s"
  say "length:   about $_w words ($_lo to $_hi accepted)"
  say "citation: class $_class: aim at $(awk -v t="$_tgt" 'BEGIN { printf "%.0f", t * 100 }') % of sentences with a mark (cite-score)"
  [ "$_round" = null ] || [ "$_round" -eq 0 ] || say "round:    $_round (the reviewer asked for changes: read review/$_id.verdict.md and review/$_id.review.md)"
  say ""
  say "BRIEF"
  sec .brief | fold -s -w 100 | sed 's/^/  /'
  say ""
  say "SOURCES YOU MAY CITE (status verified in REFERENCES.md; the capture of each is the file named):"
  _any=0
  for _k in $(sec '(.sources // [])[]'); do
    _st=$(awk -F'\t' -v k="$_k" '$1 == k { print $2; exit }' "$_rows")
    if [ "$_st" = verified ]; then
      say "  [@$_k]  sources/$_k.md"
      _any=1
    fi
  done
  [ "$_any" -eq 1 ] || say "  (none yet: write what the facts support, cite nothing, and say in notes/$_id.questions.md what you need)"
  _nv=$(for _k in $(sec '(.sources // [])[]'); do
    _st=$(awk -F'\t' -v k="$_k" '$1 == k { print $2; exit }' "$_rows")
    [ "$_st" = verified ] || printf '%s(%s) ' "$_k" "${_st:-no row}"
  done)
  [ -z "$_nv" ] || say "NOT YET VERIFIED (do not cite): $_nv"
  say ""
  say "READ (shared, read only): notes/facts.md  notes/glossary.md  refs.bib  REFERENCES.md"
  say "WRITE:                    sections/$_id.md   (pandoc markdown), figures in figures/ if you have any"
  say "ASK:                      notes/$_id.questions.md"
  say "HAND IN:                  thesis submit $SLUG $_id --as $SEAT"
  say "                          (it runs build-section, lint, cite-check, slop and readability; it refuses with the reasons)"
  say "GIVE UP:                  thesis release $SLUG $_id --as $SEAT"
  say ""
  say "RULES"
  awk -v id="$_id" -v role="role:$_role" '
    /^## / { on = ($2 == "common" || $2 == "style" || $2 == role); next }
    on { gsub(/@ID@/, id); print }' "$SHARE/lib/workorder.txt" | sed 's/^/  /'
  say ""
}

# ---------------------------------------------------------------- submit

cmd_submit() {
  _slug=
  _id=
  _as=
  while [ $# -gt 0 ]; do
    case "$1" in
      --as)
        [ $# -ge 2 ] || die "submit: --as needs a seat"
        _as=$2
        shift
        ;;
      -*) die "submit: unknown option $1" ;;
      *) if [ -z "$_slug" ]; then _slug=$1; elif [ -z "$_id" ]; then _id=$1; else die "submit: too many arguments"; fi ;;
    esac
    shift
  done
  [ -n "$_slug" ] && [ -n "$_id" ] || die "usage: thesis submit <slug> <id> [--as <seat>]"
  need_project "$_slug"
  need_section "$_id"
  SEAT=$(seat_name "$_as")
  _ci=$(claim_info "$_id")
  [ -n "$_ci" ] && [ "${_ci% *}" = "$SEAT" ] || die "$SLUG/$_id is not claimed by $SEAT: thesis fetch $SLUG $_id --as $SEAT"
  SF=$(section_file "$_id")
  plain_file "$SF" || die "$SLUG/$_id: write sections/$_id.md first"
  _reasons=
  _step() { # <name> <command...>
    _n=$1
    shift
    if "$@" >"$TMP/step.out" 2>&1; then
      say "  ok   $_n"
    else
      say "  FAIL $_n"
      sed 's/^/       /' "$TMP/step.out"
      _reasons="$_reasons $_n"
    fi
  }
  say "thesis submit: $SLUG/$_id by $SEAT"
  # Each gate runs in its own process: a die in it is a refusal, not an exit of the submit.
  _step lint "$SELF" lint "$SLUG" "$_id"
  _step build-section "$SELF" build-section "$SLUG" "$_id"
  _step cite-check "$SELF" cite-check "$SLUG" "$_id"
  _step slop "$SELF" slop "$SLUG" "$_id"
  _step readability "$SELF" readability "$SLUG" "$_id"
  if [ -n "$_reasons" ]; then
    log "submit $_id refused:$_reasons"
    die "$SLUG/$_id is not handed in. Gates that failed:$_reasons. Fix the text, then run thesis submit again."
  fi
  _sha=$(sha_of "$SF")
  state_put "$_id" '.status = "drafted" | .by = $by | .sha = $sha | .drafted = $iso | .round = (.round // 0) | del(.reviewed_sha, .report_ok)' --arg by "$SEAT" --arg sha "$_sha" --arg iso "$(now_iso)"
  rm -f "$(claim_file "$_id")"
  log "submit $_id by $SEAT: drafted (sha ${_sha%"${_sha#????????}"})"
  say "thesis: $SLUG/$_id is drafted. The reviewer takes it from here."
}

# ---------------------------------------------------------------- review-report, verdict

cmd_review_report() {
  [ $# -eq 2 ] || die "usage: thesis review-report <slug> <id|final>"
  need_project "$1"
  _id=$2
  mkdir -p "$P/review" "$P/state"
  if [ "$_id" = final ]; then
    _out=$P/review/final.gates.md
    {
      say "# Final review of $SLUG, $(now_iso)"
      say ""
      say "Gates that run on the whole work. A machine wrote this report; the reviewer reads and decides."
      say ""
      say "## cite-check (whole work)"
      say '```'
      "$SELF" cite-check "$SLUG" 2>&1 || say "(failed: exit $?)"
      say '```'
      say ""
      say "## status"
      say '```'
      "$SELF" status "$SLUG" 2>&1 || true
      say '```'
      say ""
      say "## ufrj-check (needs build/thesis.pdf from assemble)"
      say '```'
      "$SELF" ufrj-check "$SLUG" 2>&1 || say "(failed: exit $?)"
      say '```'
    } | atomic_write "$_out"
    say "thesis: wrote $_out"
    return 0
  fi
  need_section "$_id"
  SF=$(section_file "$SID")
  plain_file "$SF" || die "$SLUG/$SID: no sections/$SID.md"
  _out=$P/review/$SID.gates.md
  _allok=1
  _body=$TMP/report.md
  {
    say "# Review of $SLUG/$SID, $(now_iso)"
    say ""
    say "Section sha256 ${_sha:-$(sha_of "$SF")}"
    say "Written by $(state_get "$SID" '.by // "?"'), round $(state_get "$SID" '.round // 0'). The gates below are local rules; the reviewer's verdict is a decision."
    say ""
  } >"$_body"
  for _g in lint readability slop cite-check cite-score; do
    {
      say "## $_g"
      say '```'
    } >>"$_body"
    _rc=0
    case "$_g" in
      lint) "$SELF" lint "$SLUG" "$SID" >>"$_body" 2>&1 || _rc=$? ;;
      cite-check) "$SELF" cite-check "$SLUG" "$SID" >>"$_body" 2>&1 || _rc=$? ;;
      *) "$SELF" "$_g" "$SLUG" "$SID" >>"$_body" 2>&1 || _rc=$? ;;
    esac
    {
      say '```'
      say "result: $([ "$_rc" -eq 0 ] && echo PASS || echo "FAIL (exit $_rc)")"
      say ""
    } >>"$_body"
    [ "$_rc" -eq 0 ] || _allok=0
  done
  {
    say "## For the reviewer (by hand: no script can do these)"
    say "- Does each cited claim say what sources/<key>.md says? Read the passages."
    say "- Is it plain pt-BR a student of the course reads once? Is any fact invented?"
    say "- Does the text match the UFRJ part and the brief, and stay inside this section?"
    say ""
    say "Gates: $([ "$_allok" -eq 1 ] && echo "all PASS" || echo "at least one FAIL")."
  } >>"$_body"
  atomic_write "$_out" <"$_body"
  _sha=$(sha_of "$SF")
  state_put "$SID" '.reviewed_sha = $sha | .report_ok = ($ok == "1") | (if .status == "drafted" and $ok == "1" then .status = "linted" else . end)' --arg sha "$_sha" --arg ok "$_allok"
  log "review-report $SID: $([ "$_allok" -eq 1 ] && echo PASS || echo FAIL)"
  say "thesis: wrote $_out ($([ "$_allok" -eq 1 ] && echo "all gates PASS" || echo "a gate FAILED"))"
  [ "$_allok" -eq 1 ]
}

cmd_verdict() {
  _slug=
  _id=
  _dec=
  _by=
  _notef=
  while [ $# -gt 0 ]; do
    case "$1" in
      --by)
        [ $# -ge 2 ] || die "verdict: --by needs a seat"
        _by=$2
        shift
        ;;
      --note)
        [ $# -ge 2 ] || die "verdict: --note needs a file"
        _notef=$2
        shift
        ;;
      -*) die "verdict: unknown option $1" ;;
      *)
        if [ -z "$_slug" ]; then _slug=$1; elif [ -z "$_id" ]; then _id=$1; elif [ -z "$_dec" ]; then _dec=$1; else die "verdict: too many arguments"; fi
        ;;
    esac
    shift
  done
  [ -n "$_slug" ] && [ -n "$_id" ] && [ -n "$_by" ] || die "usage: thesis verdict <slug> <id> accept|revise --by <seat> [--note <file>]"
  case "$_dec" in accept | revise) ;; *) die "verdict: say accept or revise" ;; esac
  check_seat "$_by"
  need_project "$_slug"
  need_section "$_id"
  SEAT=$_by
  SF=$(section_file "$_id")
  plain_file "$SF" || die "$SLUG/$_id: no sections/$_id.md"
  _st=$(state_get "$_id" '.status // "todo"')
  case "$_st" in
    drafted | linted) ;;
    *) die "$SLUG/$_id is $_st: a verdict needs a drafted section (status drafted or linted)" ;;
  esac
  _writer=$(state_get "$_id" '.by // ""')
  [ "$_writer" != "$_by" ] || die "$SLUG/$_id: $_by wrote this section and may not judge it"
  _sha=$(sha_of "$SF")
  [ "$(state_get "$_id" '.sha')" = "$_sha" ] || die "$SLUG/$_id: sections/$_id.md changed after submit: the writer must submit again"
  if [ -n "$_notef" ]; then
    case "$_notef" in
      /* | *..*) die "verdict: --note must be a file inside the project (notes/ or review/), without .." ;;
    esac
    plain_file "$P/$_notef" || die "verdict: no note file $P/$_notef"
  fi
  _round=$(state_get "$_id" '.round // 0')
  if [ "$_dec" = accept ]; then
    plain_file "$P/review/$_id.review.md" || die "$SLUG/$_id: write review/$_id.review.md first (the reviewer's findings); thesis only writes review/$_id.gates.md"
    if [ "$(state_get "$_id" '.reviewed_sha')" != "$_sha" ]; then "$SELF" review-report "$SLUG" "$_id" >/dev/null 2>&1 || true; fi
    [ "$(state_get "$_id" '.reviewed_sha')" = "$_sha" ] || die "$SLUG/$_id: the gates did not run on the current text"
    [ "$(state_get "$_id" '.report_ok')" = true ] || die "$SLUG/$_id: a gate failed on the current text (review/$_id.gates.md): revise"
    state_put "$_id" '.status = "accepted" | .accepted_sha = $sha | .verdict_by = $by | .verdict_at = $iso' --arg sha "$_sha" --arg by "$_by" --arg iso "$(now_iso)"
    rm -f "$(claim_file "$_id")"
    log "verdict $_id accept by $_by (sha ${_sha%"${_sha#????????}"})"
  else
    _max=$(pn .limits.max_review_rounds)
    if [ "$_round" -ge "$_max" ]; then
      log "verdict $_id revise refused: round limit $_max"
      die "$SLUG/$_id has had $_round review rounds (the limit is $_max): ask the owner to decide. Nothing changed."
    fi
    _round=$((_round + 1))
    state_put "$_id" '.status = "revise" | .round = $round | .verdict_by = $by | .verdict_at = $iso | del(.reviewed_sha, .report_ok, .accepted_sha)' --argjson round "$_round" --arg by "$_by" --arg iso "$(now_iso)"
    # The claim goes back to the writer, so that the writer's next fetch resumes this section.
    mkdir -p "$P/claims"
    printf 'seat=%s\nepoch=%s\niso=%s\nsection=%s\n' "$_writer" "$(now_s)" "$(now_iso)" "$_id" >"$(claim_file "$_id")"
    log "verdict $_id revise by $_by (round $_round)"
  fi
  if [ -n "$_notef" ]; then cp "$P/$_notef" "$P/review/$_id.verdict.md"; else
    printf 'verdict: %s by %s at %s (round %s)\n' "$_dec" "$_by" "$(now_iso)" "$_round" >"$P/review/$_id.verdict.md"
  fi
  say "thesis: $SLUG/$_id: $_dec by $_by"
}
