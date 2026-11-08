# The lint of direction/shotlist.json. Input: the shotlist. Arguments: $sp (screenplay), $style,
# $profile, $hash (sha256 of screenplay.json). Output: findings {level, rule, beat, msg}.
include "common";
def f($lvl; $rule; $beat; $msg): {level: $lvl, rule: $rule, beat: $beat, msg: $msg};
def e($rule; $beat; $msg): f("error"; $rule; $beat; $msg);
def isnum: type == "number";
def inrange($lo; $hi): isnum and . >= $lo and . <= $hi;

[
  (if .schema != "reels.shotlist/1" then e("schema"; null; "schema must be \"reels.shotlist/1\"") else empty end),
  (if .slug != $sp.slug then e("slug"; null; "slug \(.slug) is not the screenplay's \($sp.slug)") else empty end),
  (if .screenplay_sha256 != $hash then e("stale"; null; "the shotlist was made for another version of screenplay.json: the creative director redoes it") else empty end),
  (if (.shots | type) != "array" then e("shots"; null; "shots must be an array")
   else
     (if ([.shots[].beat] != [$sp.beats[].id]) then e("shots"; null; "one shot for each beat, in order: \([$sp.beats[].id] | join(", "))") else empty end),
     (.shots[] | . as $s
      | ($sp.beats | map(select(.id == $s.beat)) | first) as $b
      | select($b != null)
      | (
          (if $s.scene != $b.visual.scene then e("scene"; $s.beat; "scene \($s.scene) is not the screenplay's \($b.visual.scene): only the screenplay changes the scene") else empty end),
          (if ($s | has("transition")) and $s.transition != $b.transition then e("transition"; $s.beat; "transition \($s.transition) is not the screenplay's \($b.transition)") else empty end),
          (if ($s | has("kind")) and (["flat", "3d"] | index($s.kind)) == null then e("kind"; $s.beat; "kind is flat or 3d") else empty end),
          (if ($s.kind // "flat") == "3d" and ($s.frames // null) != ("frames/" + $s.beat)
           then e("frames"; $s.beat; "a 3d shot has \"frames\": \"frames/\($s.beat)\", the PNG sequence that reel blender \($sp.slug) \($s.beat) writes") else empty end),
          (if ($s.kind // "flat") != "3d" and ($s | has("frames")) then e("frames"; $s.beat; "frames is for a shot of kind 3d only") else empty end),
          (if ($s.kind // "flat") == "3d" and ((($b.t_out - $b.t_in) * $profile.blender.fps | ceil) > $profile.blender.max_frames)
           then f("warn"; "frames"; $s.beat; "the beat is longer than blender.max_frames (\($profile.blender.max_frames)) at \($profile.blender.fps) fps: the last frame is held") else empty end),
          (if ($s.camera.zoom // null) != null and ((($s.camera.zoom | type) != "array") or ($s.camera.zoom | length) != 2 or ([$s.camera.zoom[] | inrange(1; 1.3)] | all | not)) then e("camera"; $s.beat; "camera.zoom is [from, to], each from 1.0 to 1.3") else empty end),
          (if ($s.motion.ease // null) != null and ((["linear", "out_quad", "out_cubic", "out_quart"] | index($s.motion.ease)) == null) then e("motion"; $s.beat; "motion.ease is linear, out_quad, out_cubic or out_quart") else empty end),
          (if ($s.motion.stagger // null) != null and (($s.motion.stagger | inrange(0.04; 0.4)) | not) then e("motion"; $s.beat; "motion.stagger from 0.04 to 0.4 s") else empty end),
          (if ($s.motion.enter_s // null) != null and (($s.motion.enter_s | inrange(0.2; 1)) | not) then e("motion"; $s.beat; "motion.enter_s from 0.2 to 1 s") else empty end),
          (if ($s.motion.pop // null) != null and (($s.motion.pop | inrange(1; 1.2)) | not) then e("motion"; $s.beat; "motion.pop from 1 to 1.2") else empty end),
          (if ($s.motion.blur // null) != null and (($s.motion.blur | inrange(0; 20)) | not) then e("motion"; $s.beat; "motion.blur from 0 to 20") else empty end),
          (if ($s.text_layout.y // null) != null and (($s.text_layout.y | inrange(0.3; 0.7)) | not) then e("layout"; $s.beat; "text_layout.y from 0.3 to 0.7 (a fraction of the safe area)") else empty end),
          (if ($s.text_layout.scale // null) != null and (($s.text_layout.scale | inrange(0.6; 1.2)) | not) then e("layout"; $s.beat; "text_layout.scale from 0.6 to 1.2") else empty end),
          (if (($s.params | objects | .layers) // null) != null and (($s.params.layers | type) != "array" or ([$s.params.layers[] | (type != "string") or ((test("\\Adirection/svg/[a-z0-9][a-z0-9_.-]*\\.svg\\z")) | not)] | any))
           then e("params"; $s.beat; "params.layers: a list of direction/svg/<name>.svg") else empty end),
          (($s.palette // {}) | to_entries[]
           | select(.key | IN("main", "emph", "sub", "bar"))
           | .key as $role | .value as $tok
           | if ($style.colors[$tok] // null) == null then e("palette"; $s.beat; "palette.\($role): \($tok) is not a colour of the style (\($style.colors | keys | join(", ")))")
             elif $role != "bar" and contrast($style.colors[$tok]; $style.colors.bg) < 4.5 then e("contrast"; $s.beat; "palette.\($role) = \($tok): contrast \(contrast($style.colors[$tok]; $style.colors.bg) | r1) to the background, at least 4.5 is needed")
             elif $role == "bar" and contrast($style.colors[$tok]; $style.colors.bg) < 1.5 then e("contrast"; $s.beat; "palette.bar = \($tok) is almost the colour of the background")
             else empty end)
        ))
   end)
]
