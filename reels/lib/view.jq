# The screenplay as an A/V script: one block a beat, picture on the left, text and sound on the right.
# A view only: nothing reads it back. Input: screenplay.json. Output: plain text (use jq -r).
include "common";

def padr($n): if length >= $n then . else . + (" " * ($n - length)) end;
def wrap($w):
  if . == "" then [""] else
    (split(" ") | reduce .[] as $word ([""];
       if (.[-1] | length) == 0 then .[-1] = $word
       elif ((.[-1] | length) + 1 + ($word | length)) <= $w then .[-1] += (" " + $word)
       else . + [$word] end))
  end;
def sec: (. * 10 | round) / 10 | tostring | if test("\\.") then . else . + ".0" end;
def sound_lines:
  (.sound // {}) as $s
  | (if ($s.silence // false) then ["(silence)"]
     else
       [(if ($s.music // "") != "" then "music: \($s.music)" else empty end)]
       + [($s.sfx // [])[] | "sfx: \(.name) at \(.at | sec) s"]
     end);

def block($lw; $rw):
  . as $b
  | (($b.visual.describe // "") | wrap($lw)) as $pic
  | ([($b.text // [])[] | plain] | map(wrap($rw)) | add // ["(no text)"]) as $txt
  | ($b | sound_lines) as $snd
  | ($txt + [""] + $snd) as $right
  | ([($pic | length), ($right | length)] | max) as $n
  | "\($b.id)  \($b.t_in | sec) - \($b.t_out | sec) s  \($b.role | ascii_upcase)  [\($b.visual.scene // "?")]  in: \($b.transition // "cut")"
    + (if ($b.note // "") != "" then "\n    note: \($b.note)" else "" end)
    + "\n"
    + ([range(0; $n) | "    " + (($pic[.] // "") | padr($lw)) + "  |  " + ($right[.] // "")] | join("\n"));

(.beats // []) as $beats
| "\(.title)  (\(.slug), \(.format) s, \(.language), \(if .loop then "loops" else "no loop" end))",
  "logline:  \(.logline)",
  "audience: \(.audience)",
  "look:     \(.look.style // "?")    music: \(.music.preset // "none")\(if .music.bpm then " \(.music.bpm) bpm" else "" end)",
  "",
  "    PICTURE" + (" " * 41) + "|  TEXT, SOUND",
  ("-" * 100),
  ($beats[] | block(44; 44), ""),
  (if (.claims // []) | length > 0 then
     "CLAIMS",
     ((.claims // [])[] | "  \(.id)  [\(.status)]  \(.text)  (source: \(.source))")
   else empty end)
