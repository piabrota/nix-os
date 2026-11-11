# One beat as an ASS script (mode "ass") or as a plan for the other layers (mode "plan").
# Arguments: $sp $beat $shot $style $profile $hin $total $dur $last $mask $mode
#   $hin   seconds of pre-roll before the beat starts (the incoming transition's handle)
#   $total length of the clip in seconds: pre-roll + beat + post-roll
#   $mask  true: every colour is white, to measure what the script draws (`reel` textbox)
# The words on screen are the lines of $beat.text and nothing else: `visual.params` and the
# shot only steer the look. Every scene is a function of these arguments.
# Sizes: libass reads \fs as the height of the font's line cell, not of its em. The widths and
# line heights of a font are in the style (fonts.<role>.w, .lh), measured with libass.
include "common";

def W: $profile.video.width;
def H: $profile.video.height;
def REG:
  ({x0: (W * $profile.safe.side), x1: (W * (1 - $profile.safe.side)),
    y0: (H * $profile.safe.top), y1: (H * (1 - $profile.safe.bottom))}
   | . + {w: (.x1 - .x0), h: (.y1 - .y0), cx: ((.x0 + .x1) / 2), cy: ((.y0 + .y1) / 2)});
def MOT: ($style.motion + ($shot.motion // {}));
def LAY: ($shot.text_layout // {});
def PARAMS: (($beat.visual.params // {}) + ($shot.params // {}));
def ease_p: ({"linear": 1, "out_quad": 2, "out_cubic": 3, "out_quart": 4}[MOT.ease // "out_cubic"] // 3);
def eo($u): 1 - pow(1 - $u; ease_p);
def tscale: (LAY.scale // 1);
def cyb: REG.y0 + REG.h * (LAY.y // 0.5);
def PAL: ({main: "fg", emph: "accent_text", sub: "muted", bar: "accent"} + ($shot.palette // {}));
def col($role): if $mask then "&HFFFFFF&" else ($style.colors[PAL[$role]] | ass_color) end;
def fam($k): $style.fonts[$k].family;
def lines: ($beat.text // []);
def LOOPEND: ($last and ($sp.loop == true));
def fadeout: if LOOPEND then "\\fad(0,350)" else "" end;
def A($x): $hin + $x;

# Width of a string at \fs 1, from the font's table; size that makes it fit; line height of a size.
def cw($k; $c):
  $style.fonts[$k].w as $w
  | if $c == 32 then $w.space
    elif ($c >= 65 and $c <= 90) or ($c >= 192 and $c <= 222) then $w.upper
    elif $c >= 48 and $c <= 57 then $w.digit
    elif ($c >= 97 and $c <= 122) or ($c >= 223 and $c <= 255) then $w.lower
    else $w.other end;
def tw($k; $s): (($s | plain | explode | map(cw($k; .)) | add // 0) * (if $style.fonts[$k].bold then 1.06 else 1 end));
def fit($k; $s; $w; $cap): ([($cap * tscale), ($w / (([tw($k; $s), 0.01] | max) * 1.1))] | min | floor | [., 36] | max);
def fitall($k; $ss; $w; $cap): ($ss | map(fit($k; .; $w; $cap)) | min);
def lh($k; $size): $size * $style.fonts[$k].lh;
def step($n): if $n <= 1 then 0 else ([MOT.stagger, ((0.65 * $dur - MOT.enter_s) / ($n - 1))] | min | [., 0.05] | max) end;

def dlg($layer; $t0; $t1; $sty; $text):
  "Dialogue: \($layer),\($t0 | ass_t),\($t1 | ass_t),\($sty),,0,0,0,,\($text)";
def hold($layer; $t0; $sty; $tags; $text):
  dlg($layer; A($t0); $total; $sty; "{" + $tags + fadeout + "}" + $text);

# A line that comes in over $d seconds, from ($dx,$dy) away, sharpening and fading in.
def NSEG: 8;
def enter($layer; $sty; $x; $y; $dx; $dy; $tags; $text; $t0; $d):
  ([range(0; NSEG)]
   | map(. as $k
         | eo($k / NSEG) as $ea
         | eo(($k + 1) / NSEG) as $eb
         | dlg($layer; A($t0 + ($d * $k / NSEG)); A($t0 + ($d * ($k + 1) / NSEG)); $sty;
               "{\\an5\\move(\(($x + ($dx * (1 - $ea))) | r1),\(($y + ($dy * (1 - $ea))) | r1),\(($x + ($dx * (1 - $eb))) | r1),\(($y + ($dy * (1 - $eb))) | r1))\\alpha\($eb | ass_alpha)\\blur\((MOT.blur * (1 - $eb)) | r1)" + $tags + "}" + $text)))
  + [hold($layer; $t0 + $d; $sty; "\\an5\\pos(\($x | r1),\($y | r1))" + $tags; $text)];

# A line of text: runs in the main colour, emphasis in the accent.
def line_text_c($base): words_of | map(.runs | map("{\\1c\(if .e then col("emph") else $base end)}" + (.t | ass_escape)) | join("")) | join(" ");
def line_text: line_text_c(col("main"));

# Drawings (layer 0). The unit square is 100 x 100 and starts at 0: libass centres a drawing on
# its box, and a box with negative coordinates is read as starting at the origin.
def RECT: "m 0 0 l 100 0 100 100 0 100";
def DOT: "m 0 50 b 0 22 22 0 50 0 b 78 0 100 22 100 50 b 100 78 78 100 50 100 b 22 100 0 78 0 50";
# A bar that grows from its centre, sideways.
def bar($x; $y; $w; $h; $role; $t0; $d):
  dlg(0; A($t0); $total; "Default";
      "{\\an5\\pos(\($x | r1),\($y | r1))\\bord0\\shad0\\1c\(col($role))\\p1\\fscx0\\fscy\($h | r1)\\t(0,\(($d * 1000) | round),0.5,\\fscx\($w | r1))" + fadeout + "}" + RECT + "{\\p0}");
# A bar that grows down from its top.
def bar_v($x; $y; $w; $h; $role; $t0; $d):
  dlg(0; A($t0); $total; "Default";
      "{\\an8\\pos(\($x | r1),\($y | r1))\\bord0\\shad0\\1c\(col($role))\\p1\\fscx\($w | r1)\\fscy0\\t(0,\(($d * 1000) | round),0.5,\\fscy\($h | r1))" + fadeout + "}" + RECT + "{\\p0}");
def dot($x; $y; $d; $role; $t0):
  dlg(0; A($t0); $total; "Default";
      "{\\an5\\pos(\($x | r1),\($y | r1))\\bord0\\shad0\\1c\(col($role))\\p1\\fscx0\\fscy0\\t(0,200,0.5,\\fscx\(($d * 1.25) | r1)\\fscy\(($d * 1.25) | r1))\\t(200,380,\\fscx\($d | r1)\\fscy\($d | r1))" + fadeout + "}" + DOT + "{\\p0}");

def tstyle($s): "\\fs\($s | floor)\\bord0\\shad0";

# ---- scenes -------------------------------------------------------------------------------

# kinetic_text: words slam in one by one, the lines centred, a bar draws under them.
def kinetic_text:
  (lines | length) as $n
  | (lines | map(words_of)) as $ws
  | fitall("title"; lines; REG.w; 230) as $S
  | lh("title"; $S) as $lh
  | ($n * $lh) as $bh
  | ($ws | map(length) | add) as $nw
  | (if $nw <= 1 then 0 else ([MOT.stagger, ((0.65 * $dur - 0.3) / ($nw - 1))] | min | [., 0.04] | max) end) as $wstep
  | (reduce range(0; $n) as $i ({g: 0, ev: []};
       .g as $g0
       | .ev += [
           (lines[$i] | words_of) as $words
           | (cyb - ($bh / 2) + ($lh * ($i + 0.5))) as $y
           | ($words | to_entries | map(. as $we
               | (($g0 + $we.key) * $wstep * 1000 | round) as $ms
               | ("{\\alpha&HFF&\\blur\(MOT.blur)\\fscx\((MOT.pop * 112) | round)\\fscy\((MOT.pop * 112) | round)\\t(\($ms),\($ms + 120),\\alpha&H00&)\\t(\($ms),\($ms + 300),\\blur0\\fscx100\\fscy100)}"
                  + ($we.value.runs | map("{\\1c\(if .e then col("emph") else col("main") end)}" + (.t | ass_escape)) | join("")))) | join(" ")) as $body
           | dlg(1; A(0); $total; "Title"; "{\\an5\\pos(\(REG.cx | r1),\($y | r1))" + tstyle($S) + fadeout + "}" + $body)
         ]
       | .g += ($ws[$i] | length))
     | .ev)
  + [bar(REG.cx; (cyb + ($bh / 2) + 70); 260; 14; "bar"; (($nw - 1) * $wstep); 0.45)];

# title_card: title lines rise in; with params.subtitle the last line is a quieter subtitle.
def title_card:
  (lines | length) as $n
  | (if (PARAMS.subtitle // false) and $n >= 2 then 1 else 0 end) as $ns
  | (lines[0:($n - $ns)]) as $tl
  | (lines[($n - $ns):]) as $sl
  | fitall("title"; $tl; REG.w; 200) as $S
  | lh("title"; $S) as $lh
  | (if $ns == 1 then fit("text"; $sl[0]; REG.w; 72) else 0 end) as $SS
  | (($tl | length) * $lh) as $tb
  | (if $ns == 1 then 56 + lh("text"; $SS) else 0 end) as $sb
  | ($tb + 56 + $sb) as $tot
  | (cyb - ($tot / 2)) as $top
  | step($n) as $st
  | ([range(0; ($tl | length)) as $i
      | enter(1; "Title"; REG.cx; ($top + ($lh * ($i + 0.5))); 0; 56; tstyle($S); ($tl[$i] | line_text); ($i * $st); MOT.enter_s)] | add)
  + [bar(REG.cx; ($top + $tb + 40); 220; 14; "bar"; (($tl | length) * $st); 0.4)]
  + (if $ns == 1 then
       enter(1; "Body"; REG.cx; ($top + $tb + 96 + (lh("text"; $SS) / 2)); 0; 30; tstyle($SS); ($sl[0] | line_text_c(col("sub"))); (($tl | length) * $st + 0.15); MOT.enter_s)
     else [] end);

# big_number: line 1 is the number (it counts up when it is a number); the other lines label it.
def fmtn($x; $d; $sep):
  ($x * pow(10; $d) | round | tostring) as $s
  | ($s | if length <= $d then (("0" * ($d - length + 1)) + .) else . end) as $z
  | if $d == 0 then $z else ($z[0:(($z | length) - $d)] + $sep + $z[(($z | length) - $d):]) end;
def big_number:
  (lines[0] // "" | plain) as $num
  | (lines[1:]) as $lab
  | ($num | capture("^(?<pre>[^0-9]*)(?<n>[0-9]+(?:[.,][0-9]+)?)(?<suf>.*)$")?) as $cap
  | fit("title"; $num; REG.w; 760) as $S1
  | (if ($lab | length) > 0 then fitall("text"; $lab; REG.w; 66) else 0 end) as $S2
  | lh("text"; $S2) as $lh
  | ($S1 * 0.62) as $hn
  | (($lab | length) * $lh) as $hb
  | ($hn + (if $hb > 0 then 100 + $hb else 0 end)) as $tot
  | (cyb - ($tot / 2)) as $top
  | ($top + ($hn / 2)) as $ny
  | ([0.9, (0.5 * $dur)] | min) as $cd
  | ((($cd * 15) | floor) | [., 2] | max) as $K
  | (if $cap == null then [] else
       ($cap.n | if test(",") then "," else "." end) as $sep
       | ($cap.n | gsub(","; ".")) as $nn
       | ($nn | tonumber) as $v
       | ($nn | split(".") | if length > 1 then (.[1] | length) else 0 end) as $d
       | [range(0; $K) as $k
          | dlg(1; A($cd * $k / $K); A($cd * ($k + 1) / $K); "Title";
                "{\\an5\\pos(\(REG.cx | r1),\($ny | r1))" + tstyle($S1) + "\\1c\(col("emph"))}" + ($cap.pre | ass_escape) + fmtn($v * eo(($k + 0.5) / $K); $d; $sep) + ($cap.suf | ass_escape))]
     end) as $count
  | $count
  + [hold(1; (if $cap == null then 0 else $cd end); "Title";
          "\\an5\\pos(\(REG.cx | r1),\($ny | r1))" + tstyle($S1) + "\\1c\(col("emph"))" + (if $cap == null then "\\fscx110\\fscy110\\t(0,300,0.5,\\fscx100\\fscy100)" else "\\fscx108\\fscy108\\t(0,260,0.5,\\fscx100\\fscy100)" end);
          ($num | if $cap == null then line_text_c(col("emph")) else (($cap.pre | ass_escape) + $cap.n + ($cap.suf | ass_escape)) end))]
  + (if $hb > 0 then
       [bar(REG.cx; ($top + $hn + 40); 160; 10; "bar"; ($cd * 0.7); 0.35)]
       + ([range(0; ($lab | length)) as $i
           | enter(1; "Body"; REG.cx; ($top + $hn + 100 + ($lh * ($i + 0.5))); 0; 34; tstyle($S2); ($lab[$i] | line_text); ($cd * 0.7 + 0.2 + ($i * 0.15)); MOT.enter_s)] | add)
     else [] end);

# bullet_reveal: each line is a bullet, sliding in from the left.
def bullet_reveal:
  (lines | length) as $n
  | fitall("title"; lines; (REG.w - 80); 150) as $S
  | (lines | map(tw("title"; .) * $S) | max) as $mw
  | (REG.cx - (($mw + 70) / 2)) as $x0
  | ($S * 1.0) as $sp_
  | (cyb - (($n - 1) * $sp_ / 2)) as $y0
  | step($n) as $st
  | [range(0; $n) as $i
     | ($y0 + ($sp_ * $i)) as $y
     | dot(($x0 + 14); $y; 26; "bar"; ($i * $st)),
       enter(1; "Title"; ($x0 + 70 + ((tw("title"; lines[$i]) * $S) / 2)); $y; -70; 0; tstyle($S); (lines[$i] | line_text); ($i * $st); MOT.enter_s)[]];

# quote: a big quotation mark, then the lines fade in one after the other.
def quote:
  (lines | length) as $n
  | (if (PARAMS.attribution // false) and $n >= 2 then 1 else 0 end) as $na
  | (lines[0:($n - $na)]) as $ql
  | (lines[($n - $na):]) as $al
  | fitall("text"; $ql; REG.w; 100) as $S
  | lh("text"; $S) as $lh
  | (($ql | length) * $lh) as $qb
  | (if $na == 1 then 100 else 0 end) as $ab
  | ($qb + $ab + 190) as $tot
  | (cyb - ($tot / 2)) as $top
  | step($n) as $st
  | [dlg(1; A(0); $total; "Title";
         "{\\an5\\pos(\(REG.cx | r1),\(($top + 90) | r1))\\fs420\\bord0\\shad0\\1c\(col("bar"))\\alpha&HFF&\\t(0,300,\\alpha&H00&)" + fadeout + "}" + "\u201c")]
  + ([range(0; ($ql | length)) as $i
      | enter(1; "Body"; REG.cx; ($top + 220 + ($lh * ($i + 0.5))); 0; 30; tstyle($S); ($ql[$i] | line_text); (0.15 + ($i * $st)); MOT.enter_s)] | add)
  + (if $na == 1 then
       [bar((REG.cx - 200); ($top + 220 + $qb + 50); 60; 8; "bar"; (0.15 + (($ql | length) * $st)); 0.3)]
       + enter(1; "Body"; (REG.cx + 30); ($top + 220 + $qb + 50); 0; 20; tstyle(($S * 0.6)); ($al[0] | line_text_c(col("sub"))); (0.15 + (($ql | length) * $st)); MOT.enter_s)
     else [] end);

# split_compare: two panels with a line between. The first lines are the quiet panel, the rest the point.
def split_compare:
  (lines | length) as $n
  | ((PARAMS.split // (($n / 2) | ceil)) | [., 1, ($n - 1)] | sort | .[1]) as $k
  | (lines[0:$k]) as $top_l
  | (lines[$k:]) as $bot_l
  | (cyb - REG.cy) as $off
  | (REG.y0 + (REG.h * 0.25) + $off) as $yt
  | (REG.y0 + (REG.h * 0.75) + $off) as $yb
  | fitall("title"; $top_l; REG.w; 130) as $S1
  | fitall("title"; $bot_l; REG.w; 180) as $S2
  | lh("title"; $S1) as $l1
  | lh("title"; $S2) as $l2
  | ([MOT.stagger, 0.3] | max) as $g
  | ([range(0; ($top_l | length)) as $i
      | enter(1; "Title"; REG.cx; ($yt - ((($top_l | length) * $l1) / 2) + ($l1 * ($i + 0.5))); 0; 40; tstyle($S1); ($top_l[$i] | line_text_c(col("sub"))); ($i * 0.12); MOT.enter_s)] | add)
  + [bar(REG.cx; (($yt + $yb) / 2); 760; 8; "bar"; $g; 0.45)]
  + ([range(0; ($bot_l | length)) as $i
      | enter(1; "Title"; REG.cx; ($yb - ((($bot_l | length) * $l2) / 2) + ($l2 * ($i + 0.5))); 0; 40; tstyle($S2); ($bot_l[$i] | line_text); ($g + 0.35 + ($i * 0.12)); MOT.enter_s)] | add);

# timeline: lines are "when: label". A line grows down, a dot and a pair of lines come in for each.
def timeline:
  (lines | map(split(": ") | {when: .[0], label: (.[1:] | join(": "))})) as $it
  | ($it | length) as $n
  | ([280, ((REG.h - 100) / $n)] | min) as $sp_
  | (cyb - (($n - 1) * $sp_ / 2)) as $y0
  | (REG.w - 110) as $tw
  | fitall("title"; ($it | map(.when)); $tw; 150) as $S1
  | fitall("text"; ($it | map(.label)); $tw; 84) as $S2
  | ([($it | map(tw("title"; .when) * $S1) | max), ($it | map(tw("text"; .label) * $S2) | max)] | max) as $mw
  | (REG.cx - (($mw + 70) / 2)) as $lx
  | ($lx + 70) as $tx
  | step($n) as $st
  | [bar_v($lx; $y0; 8; (($n - 1) * $sp_); "sub"; 0; (0.65 * $dur))]
  + ([range(0; $n) as $i
      | ($y0 + ($sp_ * $i)) as $y
      | ($it[$i]) as $e
      | dot($lx; $y; 30; "bar"; ($i * $st)),
        enter(1; "Title"; ($tx + ((tw("title"; $e.when) * $S1) / 2)); ($y - ($S1 * 0.34)); 40; 0; tstyle($S1); ($e.when | line_text_c(col("emph"))); ($i * $st); MOT.enter_s)[],
        enter(1; "Body"; ($tx + ((tw("text"; $e.label) * $S2) / 2)); ($y + ($S1 * 0.42)); 40; 0; tstyle($S2); ($e.label | line_text); ($i * $st + 0.1); MOT.enter_s)[]
     ]);

# diagram_reveal: SVG layers come in one by one above (see the plan), a caption line for each below.
def DIAG_H: 560;
def diagram_reveal:
  (lines | length) as $n
  | (PARAMS.layers | length) as $nl
  | ([$n, $nl] | max) as $m
  | fitall("text"; lines; REG.w; 84) as $S
  | lh("text"; $S) as $lh
  | (cyb - REG.cy + REG.y0 + DIAG_H + 70) as $cy0
  | step($m) as $st
  | [range(0; $n) as $i
     | enter(1; "Body"; REG.cx; ($cy0 + ($lh * ($i + 0.5))); 0; 30; tstyle($S); (lines[$i] | line_text); (0.15 + ([$i, ($nl - 1)] | min) * $st + (if $i >= $nl then (($i - $nl + 1) * 0.2) else 0 end)); MOT.enter_s)] | add;

# outro_loop: the closing lines; the last one is the handle, with a bar. In a loop reel the picture
# fades out on the last beat, so the last frame is the empty sheet the first beat starts from.
def outro_loop:
  (lines | length) as $n
  | (if $n >= 2 then fitall("title"; lines[0:($n - 1)]; REG.w; 190) else 0 end) as $S
  | fit("title"; lines[$n - 1]; REG.w; 170) as $SH
  | lh("title"; $S) as $lh
  | lh("title"; $SH) as $lhh
  | ((($n - 1) * $lh) + $lhh + 70) as $tot
  | (cyb - ($tot / 2)) as $top
  | step($n) as $st
  | ([range(0; ($n - 1)) as $i
      | enter(1; "Title"; REG.cx; ($top + ($lh * ($i + 0.5))); 0; 50; tstyle($S); (lines[$i] | line_text); ($i * $st); MOT.enter_s)] | add)
  + enter(1; "Title"; REG.cx; ($top + (($n - 1) * $lh) + ($lhh / 2)); 0; 50; tstyle($SH); (lines[$n - 1] | line_text_c(col("emph"))); (($n - 1) * $st); MOT.enter_s)
  + [bar(REG.cx; ($top + (($n - 1) * $lh) + $lhh + 36); 220; 12; "bar"; (($n - 1) * $st + 0.1); 0.45)];

# ---- the script ---------------------------------------------------------------------------
def events:
  ($beat.visual.scene) as $s
  | if $s == "kinetic_text" then kinetic_text
    elif $s == "title_card" then title_card
    elif $s == "big_number" then big_number
    elif $s == "bullet_reveal" then bullet_reveal
    elif $s == "quote" then quote
    elif $s == "split_compare" then split_compare
    elif $s == "timeline" then timeline
    elif $s == "diagram_reveal" then diagram_reveal
    elif $s == "outro_loop" then outro_loop
    else error("unknown scene \($s)") end;

def header:
  ([
    "[Script Info]",
    "; beat \($beat.id), scene \($beat.visual.scene)",
    "ScriptType: v4.00+",
    "PlayResX: \(W)",
    "PlayResY: \(H)",
    "WrapStyle: 2",
    "ScaledBorderAndShadow: yes",
    "",
    "[V4+ Styles]",
    "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding",
    "Style: Default,\(fam("text")),60,\($style.colors.fg | ass_style_color),\($style.colors.fg | ass_style_color),\($style.colors.bg | ass_style_color),\($style.colors.bg | ass_style_color),0,0,0,0,100,100,0,0,1,0,0,5,0,0,0,1",
    "Style: Title,\(fam("title")),100,\($style.colors.fg | ass_style_color),\($style.colors.fg | ass_style_color),\($style.colors.bg | ass_style_color),\($style.colors.bg | ass_style_color),\(if $style.fonts.title.bold then -1 else 0 end),0,0,0,100,100,0,0,1,0,0,5,0,0,0,1",
    "Style: Body,\(fam("text")),60,\($style.colors.fg | ass_style_color),\($style.colors.fg | ass_style_color),\($style.colors.bg | ass_style_color),\($style.colors.bg | ass_style_color),\(if $style.fonts.text.bold then -1 else 0 end),0,0,0,100,100,0,0,1,0,0,5,0,0,0,1",
    "",
    "[Events]",
    "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text"
  ] | join("\n"));

def zoom: ($shot.camera.zoom // $style.motion.bg_zoom);
def plan:
  (PARAMS.layers // []) as $ls
  | {
      zoom: (if LOOPEND then [zoom[1], zoom[0]] else zoom end),
      grain: ($style.motion.grain),
      layers: ([$ls | to_entries[]
                | (.value | if type == "string" and test("\\Adirection/svg/[a-z0-9][a-z0-9_.-]*\\.svg\\z") then . else error("layer \(tojson): write direction/svg/<name>.svg") end) as $svg
                | {svg: $svg, at: (A(0.15 + (.key * step([($ls | length), (lines | length)] | max))))}] | map(. + {fade: 0.35})),
      diagram: {y0: (cyb - REG.cy + REG.y0), h: DIAG_H, w: (REG.w | floor)}
    };

if $mode == "plan" then plan | tojson
else header + "\n" + (events | join("\n")) + "\n" end
