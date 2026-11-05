# Where QA looks. Input: the frame plan of the reel (timeline.jq). Arguments: $profile, $sp.
# Output: one tab-separated line a beat: id, probe second, start second, 1 when the beat has text.
# The probe is at qa.probe_frac of the beat, moved clear of the two transitions that overlap it, so
# the frame shows the beat and not a blend. The start is the first frame of the beat: the boundary.
include "common";

($profile.video.fps) as $fps
| ($profile.qa.probe_frac) as $pf
| . as $tl
| range(0; length) as $i
| $tl[$i] as $t
| ($tl[$i + 1].hin // 0) as $aout
| ($t.S + $t.hin + 1) as $lo
| ($t.E - $aout - 2) as $hi
| ($t.S + (($t.E - $t.S) * $pf | round)) as $want
| (if $lo > $hi then $want elif $want < $lo then $lo elif $want > $hi then $hi else $want end) as $p
| [$t.id, ($p / $fps | r3), ($t.S / $fps | r3), (if (($sp.beats[$i].text // []) | length) > 0 then 1 else 0 end)]
| @tsv
