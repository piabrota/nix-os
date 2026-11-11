# Helpers shared by the jq programs of the toolkit (colour, time, contrast, text runs).

def r1: (. * 10 | round) / 10;
def r2: (. * 100 | round) / 100;
def r3: (. * 1000 | round) / 1000;
def plain: gsub("\\*"; "");

# ---- colour -------------------------------------------------------------------------------
def hexdig: if . >= 97 then . - 87 elif . >= 65 then . - 55 else . - 48 end;
def hex2rgb: ltrimstr("#") | [.[0:2], .[2:4], .[4:6]] | map(explode | map(hexdig) | .[0] * 16 + .[1]);
def hex2: ((. / 16 | floor) as $a | (. % 16) as $b | "0123456789ABCDEF"[$a:$a + 1] + "0123456789ABCDEF"[$b:$b + 1]);
# "&HBBGGRR&" for an override tag; "&H00BBGGRR" for a style line.
def ass_color: hex2rgb | reverse | map(hex2) | join("") | "&H" + . + "&";
def ass_style_color: hex2rgb | reverse | map(hex2) | join("") | "&H00" + .;
def lin: . / 255 | if . <= 0.03928 then . / 12.92 else pow((. + 0.055) / 1.055; 2.4) end;
def lum: hex2rgb | map(lin) | (0.2126 * .[0]) + (0.7152 * .[1]) + (0.0722 * .[2]);
def contrast($a; $b): ($a | lum) as $x | ($b | lum) as $y | (([$x, $y] | max) + 0.05) / (([$x, $y] | min) + 0.05);
# alpha tag value: opacity 0..1 -> "&HXX&"
def ass_alpha: (1 - (. | if . < 0 then 0 elif . > 1 then 1 else . end)) * 255 | round | hex2 | "&H" + . + "&";

# ---- time ---------------------------------------------------------------------------------
def pad2: tostring | if length < 2 then "0" + . else . end;
def ass_t:
  (. * 100 | round) as $cs
  | ($cs / 360000 | floor) as $h
  | (($cs % 360000) / 6000 | floor) as $m
  | (($cs % 6000) / 100 | floor) as $s
  | ($cs % 100) as $c
  | "\($h):\($m | pad2):\($s | pad2).\($c | pad2)";

# ---- text runs ----------------------------------------------------------------------------
# A line with *emphasis* becomes runs {t, e}; words are lists of runs, glued where no space is between.
def runs_of: split("*") | to_entries | map({t: .value, e: (.key % 2 == 1)} | select(.t != ""));
def words_of:
  reduce (runs_of[]) as $r ([];
    ($r.t | split(" ")) as $parts
    | reduce range(0; $parts | length) as $i (.;
        $parts[$i] as $p
        | if $p == "" then (if length > 0 then .[-1].closed = true else . end)
          else
            (if $i == 0 and length > 0 and (.[-1].closed | not)
             then .[-1].runs += [{t: $p, e: $r.e}]
             else . + [{runs: [{t: $p, e: $r.e}], closed: false}] end)
            | (if $i < (($parts | length) - 1) then .[-1].closed = true else . end)
          end))
  | map({runs});
# The one place where words become Dialogue text. libass reads { } as an override block and \ as a
# command; a line break would end the Dialogue line and start another line of the script. None of
# them gets through: braces become parentheses, \ becomes /, control characters become a space.
def ass_escape:
  gsub("\\{"; "(") | gsub("\\}"; ")") | gsub("\\\\"; "/")
  | explode | map(if . < 32 or (. >= 127 and . <= 159) or . == 8232 or . == 8233 then 32 else . end) | implode;
