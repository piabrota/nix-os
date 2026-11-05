# qa.sh: the checks of the finished file, the contact sheet, the hand-over to the outbox.
# Sourced by `reel`. QA never looks at the shotlist: it measures the MP4 against the profile and
# the approved screenplay, so a wrong scene cannot hide behind its own plan. Every number of
# qa.json is read from the file itself, never from render.json or from an earlier QA.
# shellcheck shell=sh

# bbox_of <file>: the box that a `bbox` filter printed, "x1 y1 x2 y2", or "none".
bbox_of() {
  _x1='' _y1='' _x2='' _y2=''
  while IFS='=' read -r _k _v; do
    case "$_k" in
      lavfi.bbox.x1) _x1=$_v ;;
      lavfi.bbox.y1) _y1=$_v ;;
      lavfi.bbox.x2) _x2=$_v ;;
      lavfi.bbox.y2) _y2=$_v ;;
    esac
  done <"$1"
  if [ -z "$_x1" ]; then echo none; else echo "$_x1 $_y1 $_x2 $_y2"; fi
}

# measure_frame <png>: sets MBOX (the box of what the frame draws, from its edges: the picture
# minus a blurred copy of itself) and MRANGE (the luminance range inside that box, 0 for none).
# The background is a smooth gradient, so only text, shapes and drawings leave edges.
measure_frame() {
  _bb=$TMP/qa-bbox.txt
  : >"$_bb"
  ff -i "$1" -vf "split[a][b];[b]gblur=sigma=3[bl];[a][bl]blend=all_mode=difference,format=gray,bbox=min_val=$(pnum .qa.edge_min),metadata=mode=print:file=$_bb" \
    -frames:v 1 -f null - || die "cannot measure $1"
  MBOX=$(bbox_of "$_bb")
  MRANGE=0
  [ "$MBOX" != none ] || return 0
  read -r _bx1 _by1 _bx2 _by2 <<EOF
$MBOX
EOF
  _st=$TMP/qa-stats.txt
  : >"$_st"
  ff -i "$1" -vf "crop=$((_bx2 - _bx1 + 1)):$((_by2 - _by1 + 1)):$_bx1:$_by1,format=gray,signalstats,metadata=mode=print:file=$_st" \
    -frames:v 1 -f null - || die "cannot measure the contrast of $1"
  _lo=0 _hi=0
  while IFS='=' read -r _k _v; do
    case "$_k" in
      lavfi.signalstats.YMIN) _lo=$_v ;;
      lavfi.signalstats.YMAX) _hi=$_v ;;
    esac
  done <"$_st"
  MRANGE=$((_hi - _lo))
}

# frame_at <mp4> <seconds> <out.png>
frame_at() {
  rm -f "$3" "$3.part.png"
  ff -ss "$2" -i "$1" -frames:v 1 -f image2 -update 1 "$3.part.png" || die "cannot take the frame at $2 s"
  # past the end of the file ffmpeg writes nothing and says nothing
  [ -f "$3.part.png" ] || return 1
  mv -f "$3.part.png" "$3"
}

# mp4_boxes <file>: "moov-offset mdat-offset" of the top-level boxes, -1 for a missing one. Reads
# the box headers only: size (4 bytes, or 8 after size 1) and type, so a file whose index is at the
# end (no +faststart) shows moov after mdat.
mp4_boxes() {
  _total=$(wc -c <"$1" | tr -d ' ')
  _off=0
  _moov=-1
  _mdat=-1
  while [ "$_off" -lt "$_total" ]; do
    _a='' _b='' _c='' _d='' _e='' _f='' _g='' _h='' _i='' _j='' _k='' _l='' _m='' _n='' _o='' _p=''
    read -r _a _b _c _d _e _f _g _h _i _j _k _l _m _n _o _p <<EOF
$(od -An -tx1 -v -N16 -j "$_off" "$1")
EOF
    [ -n "$_h" ] || break
    _len=$((0x$_a$_b$_c$_d))
    if [ "$_len" -eq 1 ]; then
      [ -n "$_p" ] || break
      _len=$((0x$_i$_j$_k$_l$_m$_n$_o$_p))
    fi
    case "$_e$_f$_g$_h" in
      6d6f6f76) [ "$_moov" -ge 0 ] || _moov=$_off ;;
      6d646174) [ "$_mdat" -ge 0 ] || _mdat=$_off ;;
    esac
    [ "$_len" -ge 8 ] || break
    _off=$((_off + _len))
  done
  echo "$_moov $_mdat"
}

# measure_loudness <mp4>: the loudnorm measurement of the audio as JSON, or null when the file has
# no audio stream.
measure_loudness() {
  if [ -z "$(timeout -k 5 60 ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$1")" ]; then
    echo null
    return 0
  fi
  ffl -i "$1" -vn \
    -af "loudnorm=I=$(pnum .audio.target_lufs):TP=$(pnum .audio.true_peak):LRA=11:print_format=json" -f null - 2>"$TMP/qa-ln.txt" || die "loudness measurement failed"
  jq -Rs 'capture("(?<j>\\{[^}]*\\})").j | fromjson' <"$TMP/qa-ln.txt" || die "cannot read the loudness measurement"
}

# qa_plan: the probe line of each beat (qaplan.jq): id, probe second, start second, has text.
qa_plan() {
  printf '%s' "$TL" | jq -r -L "$LIB" --argjson profile "$PJ" --argjson sp "$SPJ" -f "$LIB/qaplan.jq"
}

# qa_extract <mp4> <qa folder>: a frame at the probe and at the start of every beat, into the
# folder as bNN.png and bNN-start.png. The hook frame at qa.hook_probe_s is hook.png.
qa_extract() {
  mkdir -p "$2"
  frame_at "$1" "$(pnum .qa.hook_probe_s)" "$2/hook.png" || :
  while IFS="$TAB" read -r _id _probe _start _txt; do
    frame_at "$1" "$_probe" "$2/$_id.png" || note "no frame at $_probe s: the file is shorter than the screenplay"
    frame_at "$1" "$_start" "$2/$_id-start.png" || :
  done <<EOF
$(qa_plan)
EOF
}

cmd_qa() {
  [ $# -eq 1 ] || die "usage: reel qa <slug>"
  _slug=$1
  load_project "$_slug"
  _rd=$(out_dir "$_slug")
  _mp4=$_rd/reel.mp4
  # An old report is void the moment QA starts: a QA that dies halfway leaves none.
  rm -f "$_rd/qa.json" "$_rd/qa.json.part"
  plain_file "$_mp4" || die "no reel to check: $_mp4 (reel render $_slug)"
  _qd=$_rd/qa
  _probe_json=$(timeout -k 5 60 ffprobe -v error -print_format json -show_format -show_streams "$_mp4") || die "ffprobe cannot read $_mp4: it is not a video file"
  qa_extract "$_mp4" "$_qd"

  _safe=$(safe_rect)
  _slack=$(pnum .qa.safe_slack_px)
  _minrange=$(pnum .qa.min_text_range)
  : >"$TMP/qa-beats.jsonl"
  while IFS="$TAB" read -r _id _probe _start _txt; do
    if [ -f "$_qd/$_id.png" ]; then measure_frame "$_qd/$_id.png"; else MBOX=missing MRANGE=0; fi
    jq -n -c --arg id "$_id" --argjson probe "$_probe" --arg box "$MBOX" --argjson range "$MRANGE" --argjson text "$_txt" \
      --arg safe "$_safe" --argjson slack "$_slack" --argjson minrange "$_minrange" '
      ($safe | split(" ") | map(tonumber)) as $s
      | ($box | if . == "none" or . == "missing" then null else split(" ") | map(tonumber) end) as $b
      | [ (if $box == "missing" then "no frame at \($probe) s: reel.mp4 is shorter than the screenplay" else empty end),
          (if $text == 1 and $b == null and $box != "missing" then "the screenplay has text but the frame at \($probe) s draws nothing" else empty end),
          (if $b != null and ($b[0] < $s[0] - $slack or $b[1] < $s[1] - $slack or $b[2] > $s[2] + $slack or $b[3] > $s[3] + $slack)
           then "the picture at \($probe) s leaves the safe area: drawn \($box), safe \($safe) (x1 y1 x2 y2, slack \($slack) px)" else empty end),
          (if $text == 1 and $b != null and $range < $minrange then "low contrast at \($probe) s: luminance range \($range), at least \($minrange) wanted" else empty end)
        ] as $p
      | {id: $id, probe_s: $probe, frame: "qa/\($id).png", has_text: ($text == 1), drawn: $box, luminance_range: $range, problems: $p, pass: ($p | length == 0)}' >>"$TMP/qa-beats.jsonl"
  done <<EOF
$(qa_plan)
EOF
  if [ -f "$_qd/hook.png" ]; then measure_frame "$_qd/hook.png"; else MBOX=none; fi
  _hook=$MBOX

  read -r _moov _mdat <<EOF
$(mp4_boxes "$_mp4")
EOF
  _loud=$(measure_loudness "$_mp4")
  _fmt=$(printf '%s' "$SPJ" | jq -r '.format')
  # What render.json says about the file: a claim to check, not a fact. The report carries the file's
  # own hash; the two checks "made from the approved screenplay" and "is the file that reel render
  # wrote" fail when render.json is missing or does not match.
  _render_sha=
  _render_reel=
  if plain_file "$_rd/render.json"; then
    _render_sha=$(jq -r '.screenplay_sha256 // ""' "$_rd/render.json" 2>/dev/null) || _render_sha=
    _render_reel=$(jq -r '.reel_sha256 // ""' "$_rd/render.json" 2>/dev/null) || _render_reel=
  fi

  printf '%s' "$_probe_json" | jq -L "$LIB" \
    --argjson profile "$PJ" --arg slug "$_slug" --argjson fmt "$_fmt" --argjson loud "$_loud" \
    --argjson moov "$_moov" --argjson mdat "$_mdat" --slurpfile beats "$TMP/qa-beats.jsonl" --arg hook "$_hook" \
    --arg reel_sha "$(sha_of "$_mp4")" --arg sp_sha "$APPROVED_HASH" --arg render_sha "$_render_sha" --arg render_reel "$_render_reel" \
    -f "$LIB/qareport.jq" >"$_rd/qa.json.part" || die "cannot write the QA report"
  mv -f "$_rd/qa.json.part" "$_rd/qa.json"
  jq -r '.checks[] | "\(if .pass then "pass" else "FAIL" end)  \(.name): \(.got)"' "$_rd/qa.json"
  jq -r '.beats[] | "\(if .pass then "pass" else "FAIL" end)  beat \(.id) at \(.probe_s) s: drawn \(.drawn), luminance range \(.luminance_range)"' "$_rd/qa.json"
  jq -r '.failures[] | "  -> \(.)"' "$_rd/qa.json"
  if jq -e .pass "$_rd/qa.json" >/dev/null; then
    say "qa: PASS ($_rd/qa.json, frames in $_qd)"
  else
    say "qa: FAIL ($_rd/qa.json)"
    return 1
  fi
}

# require_fresh_reel <slug>: sets RD. reel.mp4 must be the file that `reel render` wrote for the
# screenplay that is approved now: render.json names both, by hash.
require_fresh_reel() {
  RD=$(out_dir "$1")
  plain_file "$RD/reel.mp4" || die "no reel: $RD/reel.mp4 (reel render $1)"
  plain_file "$RD/render.json" || die "no render.json: reel.mp4 was not made by reel render $1"
  [ "$(jq -r '.screenplay_sha256 // ""' "$RD/render.json" 2>/dev/null)" = "$APPROVED_HASH" ] || die "reel.mp4 was made from another screenplay: reel render $1 again"
  [ "$(jq -r '.reel_sha256 // ""' "$RD/render.json" 2>/dev/null)" = "$(sha_of "$RD/reel.mp4")" ] || die "reel.mp4 is not the file that reel render wrote: reel render $1 again"
}

# no_links <folder>: succeeds when nothing in the folder tree is a symbolic link.
no_links() {
  for _ne in "$1"/* "$1"/.[!.]*; do
    if [ -L "$_ne" ]; then return 1; fi
    if [ -d "$_ne" ]; then no_links "$_ne" || return 1; fi
  done
}

# contact_sheet: all the beat frames in one PNG, in order, 270 px wide, four to a row.
cmd_contact_sheet() {
  [ $# -eq 1 ] || die "usage: reel contact-sheet <slug>"
  _slug=$1
  load_project "$_slug"
  require_fresh_reel "$_slug"
  _rd=$RD
  qa_extract "$_rd/reel.mp4" "$_rd/qa"
  _n=$(printf '%s' "$TL" | jq 'length')
  for _id in $(printf '%s' "$TL" | jq -r '.[].id'); do
    [ -f "$_rd/qa/$_id.png" ] || die "no frame for beat $_id: reel.mp4 is shorter than the screenplay"
  done
  _cols=4
  [ "$_n" -ge "$_cols" ] || _cols=$_n
  _rows=$(((_n + _cols - 1) / _cols))
  rm -f "$_rd/qa/contact-sheet.png.part.png"
  ff -framerate 1 -i "$_rd/qa/b%02d.png" \
    -vf "scale=270:-2,tile=${_cols}x${_rows}:padding=8:margin=8:color=0x222222" -frames:v 1 -f image2 -update 1 "$_rd/qa/contact-sheet.png.part.png" || die "cannot make the contact sheet"
  mv -f "$_rd/qa/contact-sheet.png.part.png" "$_rd/qa/contact-sheet.png"
  say "contact sheet: $_rd/qa/contact-sheet.png ($_n beats)"
}

# publish <slug> [--replace]: the finished reel to the outbox, where Hermes reads it. Needs a QA
# report that passed, made for this very file and this very screenplay: the hashes in qa.json are
# compared with the file and the approval as they are now (a report older than either does not
# match). One folder a slug, written under a hidden name and moved in with one rename; an existing
# folder is kept unless --replace says to swap it, and no other slug is ever touched.
cmd_publish() {
  [ $# -ge 1 ] && [ $# -le 2 ] || die "usage: reel publish <slug> [--replace]"
  _slug=$1
  _replace=0
  case "${2:-}" in
    '') ;;
    --replace) _replace=1 ;;
    *) die "unknown option: $2" ;;
  esac
  require_approved "$_slug"
  require_fresh_reel "$_slug"
  _rd=$RD
  plain_file "$_rd/qa.json" || die "no QA report: run reel qa $_slug first"
  jq -e '.schema == "reels.qa/1" and .pass == true and ([.checks[].pass] | all) and ([.beats[].pass] | all) and (.failures | length == 0)' "$_rd/qa.json" >/dev/null 2>&1 ||
    die "the QA of $_slug did not pass: fix it, render and run reel qa again"
  [ "$(jq -r .reel_sha256 "$_rd/qa.json")" = "$(sha_of "$_rd/reel.mp4")" ] || die "reel.mp4 changed after its QA: run reel qa $_slug again"
  [ "$(jq -r .screenplay_sha256 "$_rd/qa.json")" = "$APPROVED_HASH" ] || die "the QA is of another screenplay: render and run reel qa again"
  if [ -d "$PROJ/review" ]; then no_links "$PROJ/review" || die "review/ has a symbolic link: publish copies files, not links"; fi
  _dest=$OUTBOX/$_slug
  if { [ -e "$_dest" ] || [ -L "$_dest" ]; } && [ "$_replace" -eq 0 ]; then
    die "$_dest exists: use --replace to swap it (only this slug is touched)"
  fi
  mkdir -p "$OUTBOX" || die "cannot make $OUTBOX"
  # Staged inside the outbox, so the files take the folder's default ACL, and moved in with one rename.
  _stage=$OUTBOX/.$_slug.part
  _old=$OUTBOX/.$_slug.old
  rm -rf "$_stage" "$_old"
  mkdir "$_stage" || die "cannot write to $OUTBOX"
  cp "$_rd/reel.mp4" "$_rd/qa.json" "$SP" "$PROJ/screenplay.approved" "$_stage/" || {
    rm -rf "$_stage"
    die "copy failed"
  }
  if [ -d "$PROJ/review" ]; then
    cp -R "$PROJ/review" "$_stage/review" || {
      rm -rf "$_stage"
      die "copy of review failed"
    }
  fi
  # The unit's UMask is 077, and a default ACL does not lift it on this box's ext4 (tested): Hermes
  # reads through the group of the folder, so the group gets its read bit here, not from the umask.
  chmod -R g+rX "$_stage" || {
    rm -rf "$_stage"
    die "cannot set the mode of the files"
  }
  if [ -e "$_dest" ] || [ -L "$_dest" ]; then
    mv "$_dest" "$_old" || {
      rm -rf "$_stage"
      die "cannot move the old folder aside"
    }
  fi
  mv "$_stage" "$_dest" || {
    [ ! -e "$_old" ] || mv "$_old" "$_dest"
    rm -rf "$_stage"
    die "cannot move the folder into place"
  }
  rm -rf "$_old"
  say "published: $_dest ($(wc -c <"$_dest/reel.mp4" | tr -d ' ') bytes)"
}
