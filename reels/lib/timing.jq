# The table read: reading speed and hold time of every beat. Input: screenplay.json.
# Arguments: $profile. Output: plain text (jq -r). A beat is `FAST` when it needs more reading
# time than it has, `TIGHT` when less than 0.4 s is left to hold the text after it is read.
include "common";

def padr($n): if length >= $n then . else . + (" " * ($n - length)) end;
def padl($n): if length >= $n then . else (" " * ($n - length)) + . end;
def f1: (. * 10 | round) / 10 | tostring | if test("\\.") then . else . + ".0" end;

($profile.text.max_cps) as $cps
| [(.beats // [])[]
   | ((.t_out - .t_in) | r3) as $d
   | ([(.text // [])[] | plain | length] | add // 0) as $c
   | ($c / $cps) as $need
   | {id, role, dur: $d, chars: $c,
      cps: (if $d > 0 then ($c / $d) else 0 end),
      need: $need,
      hold: ($d - $need),
      flag: (if $c == 0 then "no text"
             elif ($d > 0 and ($c / $d) > $cps) then "FAST"
             elif ($d - $need) < 0.4 then "TIGHT"
             else "" end)}] as $rows
| ($rows | map(select(.chars > 0)) | sort_by([-.cps, .hold]) | first // null) as $worst
| "TABLE READ  (reading speed limit \($cps) characters per second)",
  "",
  (["beat", "role", "length", "chars", "cps", "needs", "hold", "flag"] | [(.[0] | padr(5)), (.[1] | padr(8)), (.[2] | padl(7)), (.[3] | padl(6)), (.[4] | padl(6)), (.[5] | padl(7)), (.[6] | padl(7)), .[7]] | join("  ")),
  ($rows[] | [(.id | padr(5)), (.role | padr(8)), ((.dur | f1) + " s" | padl(7)), (.chars | tostring | padl(6)), (.cps | f1 | padl(6)), ((.need | f1) + " s" | padl(7)), ((.hold | f1) + " s" | padl(7)), .flag] | join("  ")),
  "",
  (if $worst == null then "no text on screen"
   else "worst beat: \($worst.id)  \($worst.cps | f1) cps, \($worst.hold | f1) s to hold after reading" end),
  "total: \($rows | map(.dur) | add | f1) s, \($rows | map(.chars) | add) characters, \(($rows | map(.chars) | add) / ($rows | map(.dur) | add) | f1) cps on average",
  (if ($rows | map(select(.flag == "FAST")) | length) > 0 then "result: FAIL (\($rows | map(select(.flag == "FAST") | .id) | join(", ")) too fast)"
   elif ($rows | map(select(.flag == "TIGHT")) | length) > 0 then "result: OK, tight beats: \($rows | map(select(.flag == "TIGHT") | .id) | join(", "))"
   else "result: OK" end)
