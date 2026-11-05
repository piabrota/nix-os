# The frame plan of a reel. Input: screenplay.json. Arguments: $profile. Output: one object a beat:
#   S, E      first frame of the beat and the frame after its last
#   hin, hout frames of handle before and after the beat: the part of a transition that this beat's
#             clip has to cover. A cut is a one-frame blend: hin 1, hout 0 on its sides.
#   frames    length of the clip: hin + (E - S) + hout
#   dq        frames of the transition into this beat (0 for the first beat)
#   offset    seconds where the xfade into this beat starts, on the stream of the beats before it
# The beats are cut at round(t * fps), so the reel has exactly format * fps frames, whatever the
# decimals of the screenplay. The fade of a boundary is centred on it: half in each clip.
include "common";

($profile.video.fps) as $fps
| (.beats | length) as $n
| [.beats[]
   | (.transition // "cut") as $tr
   | ((.transition_s // $profile.transition.default_s) * $fps | round) as $q
   | (if $tr == "cut" then 1 else ([$q, 2] | max | if . % 2 == 1 then . + 1 else . end) end) as $dq
   | {id, tr: $tr, S: ((.t_in * $fps) | round), E: ((.t_out * $fps) | round), dq: $dq, a: (if $tr == "cut" then 1 else ($dq / 2) end)}] as $b
| [range(0; $n) as $i
   | $b[$i] as $x
   | (if $i == 0 then 0 else $x.a end) as $hin
   | (if $i == $n - 1 then 0 else ($b[$i + 1].dq - $b[$i + 1].a) end) as $hout
   | {id: $x.id, tr: $x.tr, S: $x.S, E: $x.E, hin: $hin, hout: $hout,
      frames: ($hin + ($x.E - $x.S) + $hout),
      dq: (if $i == 0 then 0 else $x.dq end),
      offset: (if $i == 0 then null else (($x.S - $x.a) / $fps) end)}]
