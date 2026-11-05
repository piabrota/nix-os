# The screenplay lint. Input: screenplay.json. Arguments: $profile (profile.json), $styles (the
# names of the style files). Output: an array of findings {level, rule, beat, msg}. Level `error`
# blocks `reel approve`; `warn` does not. Every number comes from $profile.
def f($lvl; $rule; $beat; $msg): {level: $lvl, rule: $rule, beat: $beat, msg: $msg};
def e($rule; $beat; $msg): f("error"; $rule; $beat; $msg);
def w($rule; $beat; $msg): f("warn"; $rule; $beat; $msg);
def r3: (. * 1000 | round) / 1000;
def plain: gsub("\\*"; "");
def blank: type != "string" or (gsub("\\s"; "") | length == 0);
def nchars: [(.text // [])[] | select(type == "string") | plain | length] | add // 0;
def pad2: tostring | if length < 2 then "0" + . else . end;
def isnum: type == "number";

def req_str($k): if (.[$k] | blank) then e("fields"; null; "\($k) must be a non-empty string") else empty end;

# Control characters, and the line and paragraph separators of Unicode.
def ctl: explode | any(.[]; . < 32 or (. >= 127 and . <= 159) or . == 8232 or . == 8233);
# A symbol, an emoji or a joiner: the two fonts do not cover them (U+2600 and up, U+200D, U+FE0F).
def nofont: explode | any(.[]; . >= 9728 or . == 8205 or . == 65039);
def has_music: ((.music | objects | .preset) // "none") != "none"
  and ([.beats[]? | select(type == "object") | .sound | select(type == "object") | select((.silence // false) != true and (.music // "on") != "off")] | length) > 0;
def has_sfx: ([.beats[]? | select(type == "object") | .sound | select(type == "object") | (.sfx // []) | select(type == "array") | .[]] | length) > 0;
def top_checks:
  [
    (if .schema != "reels.screenplay/1" then e("schema"; null; "schema must be \"reels.screenplay/1\"") else empty end),
    (if (.slug | type) != "string" or ((.slug | test("\\A[a-z0-9][a-z0-9-]{0,40}\\z")) | not)
     then e("slug"; null; "slug: lowercase letters, digits and - only, 1 to 41 characters") else empty end),
    req_str("title"), req_str("logline"), req_str("audience"),
    (if ((.language // "") | type) != "string" or ((.language // "") | test("\\A[a-z]{2}(-[A-Za-z]{2,4})?\\z") | not)
     then e("language"; null; "language must be set, as a code like pt-BR or en") else empty end),
    (if ((.format | isnum) | not) or ((.format as $x | $profile.formats | index($x)) == null)
     then e("format"; null; "format must be one of \($profile.formats | map(tostring) | join(", ")) (seconds)") else empty end),
    (if (.loop | type) != "boolean" then e("loop"; null; "loop must be true or false") else empty end),
    (if (.look | type) != "object" or (.look.style | type) != "string"
     then e("look"; null; "look.style must name a style: \($styles | join(", "))")
     elif (.look.style as $ls | $styles | index($ls)) == null
     then e("look"; null; "unknown style \(.look.style): use \($styles | join(", "))") else empty end),
    (keys_unsorted[] | select(IN("schema", "slug", "title", "format", "logline", "audience", "language", "claims", "look", "music", "loop", "beats") | not)
     | w("keys"; null; "unknown top-level key: \(.)")),
    (if [.. | objects | select(has("vo"))] | length > 0 and ($profile.voice | not)
     then e("voice"; null; "vo (voice-over) is not enabled: profile.voice is false") else empty end),
    (if [.. | strings | select(test("\\bTODO\\b"))] | length > 0
     then e("placeholder"; null; "the file still has a TODO") else empty end),
    # What the file says reaches captions, a terminal and the outbox: no control character, no
    # string of a size that no reel needs.
    (if [.. | strings | select(ctl)] | length > 0
     then e("text"; null; "a string has a control character (a line break, a tab, an escape): one line is one string") else empty end),
    (if [.. | strings | select(length > 1000)] | length > 0
     then e("text"; null; "a string has more than 1000 characters") else empty end),
    (if [.. | strings | select(nofont)] | length > 0
     then w("text"; null; "a string has a symbol or an emoji that the fonts (Inter, Fjalla One) may not draw") else empty end),
    (if (.look | type) == "object" and (.look | has("palette")) then
       (if (.look.palette | type) != "object" then e("look"; null; "look.palette must be an object of colour overrides")
        else (.look.palette | to_entries[] | select((.key | test("\\A[a-z_]{1,20}\\z") | not) or ((.value | type) != "string") or ((.value | test("\\A#[0-9A-Fa-f]{6}\\z")) | not))
              | e("look"; null; "look.palette.\(.key): a colour name and a value like #RRGGBB"))
        end) else empty end),
    (if (.beats | type) == "array" and ((has_music or has_sfx) | not)
     then e("sound"; null; "the reel has no sound at all (no music, no effect): QA holds the loudness to a target, so it would never pass") else empty end),
    # claims
    (if (.claims | type) != "array" then e("claims"; null; "claims must be an array (it may be empty)")
     else (.claims | to_entries[] | .key as $i | .value as $c
       | (if ($c | type) != "object" then e("claims"; null; "claim \($i + 1) is not an object")
          else
            (if ($c.id | blank) then e("claims"; null; "claim \($i + 1) has no id") else empty end),
            (if ($c.text | blank) then e("claims"; null; "claim \($c.id // $i + 1) has no text") else empty end),
            (if ($c.source | blank) then e("claims"; null; "claim \($c.id // $i + 1) has no source: write a source or \"own\"") else empty end),
            (if ($profile.claim_status | index($c.status)) == null
             then e("claims"; null; "claim \($c.id // $i + 1): status must be one of \($profile.claim_status | join(", "))")
             elif $c.status == "needs-check" then e("claims"; null; "claim \($c.id // $i + 1) still needs a check: give a source or own")
             elif ($c.source == "own") != ($c.status == "own") then e("claims"; null; "claim \($c.id // $i + 1): status own goes with source own, and no other")
             else empty end)
          end))
     end),
    # music
    (if has("music") then
       (if (.music | type) != "object" or (.music.preset as $mp | $profile.music_presets | index($mp)) == null
        then e("music"; null; "music.preset must be one of \($profile.music_presets | join(", "))")
        elif .music.preset == "none" then empty
        elif ((.music.bpm | isnum) | not) or .music.bpm < 60 or .music.bpm > 160 then e("music"; null; "music.bpm must be a number from 60 to 160")
        elif ((.format * .music.bpm / 60) | . != floor) then w("music"; null; "music.bpm \(.music.bpm) does not give a whole number of beats in \(.format) s: the bed will not loop clean")
        else empty end)
     else empty end)
  ];

def beat_checks:
  . as $sp
  | ($sp.beats) as $beats
  | ($beats | length) as $n
  | [$beats | to_entries[] | .key as $i | .value as $b
     | ($b.id // ("#" + (($i + 1) | tostring))) as $id
     | (if ($b | type) != "object" then e("beat"; $id; "not an object")
        else
          ($b.t_in | isnum) as $okin | ($b.t_out | isnum) as $okout
          | ((try (($b.t_out - $b.t_in) | r3) catch 0) // 0) as $dur
          | ($b | nchars) as $nc
          | (($b.visual | objects | .scene) // "") as $scene
          | (
              (if $b.id != ("b" + (($i + 1) | pad2)) then e("ids"; $id; "id must be b\(($i + 1) | pad2) (b01.. in order)") else empty end),
              (if ($okin and $okout) | not then e("time"; $id; "t_in and t_out must be numbers (seconds)")
               else
                 (if $i == 0 and $b.t_in != 0 then e("time"; $id; "the first beat starts at 0, not \($b.t_in)") else empty end),
                 (if $i > 0 and ($b.t_in | r3) != ($beats[$i - 1].t_out | r3) then e("time"; $id; "gap or overlap: t_in \($b.t_in) but the beat before ends at \($beats[$i - 1].t_out)") else empty end),
                 (if $dur <= 0 then e("time"; $id; "t_out must be after t_in")
                  elif $dur < $profile.beat.min_s then e("length"; $id; "beat is \($dur) s: the minimum is \($profile.beat.min_s) s") else empty end),
                 (if $i == $n - 1 and ($b.t_out | r3) != $sp.format then e("total"; $id; "the beats end at \($b.t_out) s but the format is \($sp.format) s") else empty end)
               end),
              (if ($profile.roles | index($b.role)) == null then e("role"; $id; "role must be one of \($profile.roles | join(", "))") else empty end),
              (if $i == 0 and $b.role != "hook" then e("hook"; $id; "the first beat must have the role hook") else empty end),
              (if $i > 0 and $b.role == "hook" then e("hook"; $id; "only the first beat is the hook") else empty end),
              (if $i == 0 and $okout and $b.t_out > $profile.hook.max_t_out then e("hook"; $id; "the hook ends at \($b.t_out) s: it must end by \($profile.hook.max_t_out) s") else empty end),
              (if $i == 0 and ($b.text // []) == [] then w("hook"; $id; "the hook has no on-screen text: most people watch with the sound off") else empty end),
              (if $b.role == "cta" and $i != $n - 1 then e("cta"; $id; "a cta is allowed only in the last beat") else empty end),
              (if $b.role == "loop" and $i != $n - 1 then e("loop"; $id; "the role loop is allowed only in the last beat") else empty end),
              # visual
              (if ($b.visual | type) != "object" then e("visual"; $id; "visual must be an object: {describe, scene, params}")
               else
                 (if ($b.visual.describe | blank) then e("visual"; $id; "visual.describe: say in words what is on screen") else empty end),
                 (if ($profile.scenes | index($scene)) == null then e("scene"; $id; "visual.scene must be one of \($profile.scenes | join(", "))") else empty end),
                 (if ($b.visual | has("params")) and (($b.visual.params | type) != "object") then e("visual"; $id; "visual.params must be an object") else empty end)
               end),
              # text
              (if (($b | has("text")) | not) or (($b.text | type) != "array" or ([$b.text[] | type != "string"] | any))
               then e("text"; $id; "text must be an array of strings (use [] for no text)")
               else
                 (if ($b.text | length) > $profile.text.max_lines then e("text"; $id; "\($b.text | length) lines: at most \($profile.text.max_lines)") else empty end),
                 ($b.text | to_entries[] | select((.value | plain | length) > $profile.text.max_chars_per_line)
                  | e("text"; $id; "line \(.key + 1) has \(.value | plain | length) characters: at most \($profile.text.max_chars_per_line)")),
                 ($b.text | to_entries[] | select(.value | blank) | e("text"; $id; "line \(.key + 1) is empty")),
                 ($b.text | to_entries[] | select((.value | blank | not) and (.value | test("^\\s|\\s$"))) | e("text"; $id; "line \(.key + 1) has a space at its start or end")),
                 ($b.text | to_entries[] | select(((.value | [match("\\*"; "g")] | length) % 2) == 1) | e("text"; $id; "line \(.key + 1) has an odd number of * (emphasis marks come in pairs)")),
                 ($b.text | to_entries[] | select(.value | test("[{}\\\\]")) | e("text"; $id; "line \(.key + 1) has a brace or a backslash: the captions use them")),
                 (if $dur > 0 and ($nc / $dur) > $profile.text.max_cps then e("reading"; $id; "\($nc) characters in \($dur) s is \(($nc / $dur * 10 | round) / 10) per second: at most \($profile.text.max_cps)") else empty end)
               end),
              # scene rules that read the text
              (if ($b.text | type) == "array" then
                 (if $scene == "timeline" and ([$b.text[] | select(type == "string" and (contains(": ") | not))] | length) > 0 then e("scene"; $id; "timeline: every line is \"when: label\"") else empty end),
                 (if $scene == "split_compare" and ($b.text | length) < 2 then e("scene"; $id; "split_compare needs at least 2 lines") else empty end),
                 (if $scene == "bullet_reveal" and (($b.text | length) < 2) then e("scene"; $id; "bullet_reveal needs at least 2 lines") else empty end),
                 (if ($scene | IN("title_card", "big_number", "quote", "kinetic_text", "outro_loop", "diagram_reveal")) and ($b.text | length) < 1 then e("scene"; $id; "\($scene) needs at least 1 line of text") else empty end),
                 (if $scene == "big_number" and (($b.text[0] // "") | plain | length) > 8 then w("scene"; $id; "big_number: the first line is the number: 8 characters or fewer reads best") else empty end)
               else empty end),
              (if $scene == "diagram_reveal" then
                 (if ($b.visual.params.layers | type) != "array" or ($b.visual.params.layers | length) < 1 then e("scene"; $id; "diagram_reveal needs params.layers: a list of SVG files under direction/svg/")
                  else ($b.visual.params.layers[] | select((type != "string") or (test("\\Adirection/svg/[a-z0-9][a-z0-9_.-]*\\.svg\\z") | not)) | e("scene"; $id; "layer \(. | tojson): write direction/svg/<name>.svg"))
                  end) else empty end),
              (if $scene == "outro_loop" and $i != $n - 1 then e("scene"; $id; "outro_loop is for the last beat") else empty end),
              (if $i == $n - 1 and $sp.loop == true and $scene != "outro_loop" then e("loop"; $id; "loop is true: the last beat must use the scene outro_loop") else empty end),
              # sound
              (if (($b | has("sound")) | not) or (($b.sound | type) != "object") then e("sound"; $id; "sound must be an object: {music, sfx, silence}")
               else
                 (if ($b.sound | has("music")) and ($profile.music_levels | index($b.sound.music)) == null then e("sound"; $id; "sound.music must be one of \($profile.music_levels | join(", "))") else empty end),
                 (if ($b.sound.sfx // []) | type != "array" then e("sound"; $id; "sound.sfx must be an array of {name, at}")
                  else ($b.sound.sfx // [])[] | select(type != "object" or (. as $x | $profile.sfx | index($x.name)) == null or (.at | isnum | not) or .at < 0 or .at > $dur)
                   | e("sound"; $id; "sfx \(. | tojson): name one of \($profile.sfx | join(", ")) and at from 0 to \($dur) s") end),
                 (if (($b.sound.sfx // []) | type) == "array" and (($b.sound.sfx // []) | length) > $profile.sfx_per_beat then e("sound"; $id; "at most \($profile.sfx_per_beat) sound effects in a beat") else empty end),
                 (if ($b.sound.silence // false) == true and ((($b.sound.music // "off") != "off") or (($b.sound.sfx // []) | length) > 0)
                  then e("sound"; $id; "silence is true but the beat has music or sfx") else empty end)
               end),
              # transition
              (if ($profile.transitions | index($b.transition)) == null then e("transition"; $id; "transition must be one of \($profile.transitions | join(", "))")
               elif $i == 0 and $b.transition != "cut" then e("transition"; $id; "the first beat comes in with cut") else empty end),
              (if $b | has("transition_s") then
                 (if (($b.transition_s | isnum) | not) or $b.transition_s <= 0 or $b.transition_s > $profile.transition.max_s then e("transition"; $id; "transition_s must be a number above 0 and at most \($profile.transition.max_s) s")
                  elif $i > 0 and $okout and $okin and ($b.transition != "cut") and ($b.transition_s > ([$dur, ($beats[$i - 1].t_out - $beats[$i - 1].t_in)] | min) / 2) then e("transition"; $id; "transition_s \($b.transition_s) is more than half of an adjacent beat")
                  else empty end) else empty end),
              # claims
              (if ($b | has("claims")) then
                 (if ($b.claims | type) != "array" then e("claims"; $id; "claims must be an array of claim ids")
                  else $b.claims[] | . as $cid | select(([$sp.claims[]? | .id] | index($cid)) == null) | e("claims"; $id; "cites claim \(. | tojson), which does not exist") end) else empty end),
              (if ([($b.text // [])[] | select(type == "string" and test("[0-9]"))] | length) > 0 and (($b.claims // []) | length) == 0
               then w("claims"; $id; "a number is on screen but the beat cites no claim") else empty end),
              ($b | keys_unsorted[] | select(IN("id", "t_in", "t_out", "role", "visual", "text", "sound", "transition", "transition_s", "claims", "note") | not) | w("keys"; $id; "unknown beat key: \(.)"))
            )
        end)
  ]
  + [($sp.claims // [])[] | select(type == "object") | .id as $cid | select(([$beats[] | (.claims // [])[]] | index($cid)) == null)
     | w("claims"; null; "claim \(.id) is cited by no beat")];

def lint:
  top_checks
  + (if (.beats | type) != "array" or (.beats | length) == 0 then [e("beats"; null; "beats must be a non-empty array")]
     else beat_checks end);

# A file that the rules cannot read is an error: the lint fails closed.
if type != "object" then [e("schema"; null; "the file must hold one JSON object")]
else try lint catch [e("lint"; null; "the rules cannot read this file: \(.)")] end
