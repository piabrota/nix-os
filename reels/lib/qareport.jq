# The QA report. Input: the ffprobe JSON of reel.mp4 (-show_format -show_streams).
# Arguments: $profile, $slug, $fmt, $loud (loudnorm measurement, or null when the file has no audio),
# $moov and $mdat (byte offset of the two top-level boxes, -1 when missing), $beats (the measured
# beats), $hook (the frame at qa.hook_probe_s), $reel_sha, $sp_sha (the approved screenplay),
# $render_sha and $render_reel (the screenplay and the file that render.json names: what `reel
# render` wrote). Output: qa.json. `pass` is true only when every check and every beat passes.
# Every number is read from the file; a field that is missing makes its check fail, not the report.

def chk($name; $ok; $got; $want): {name: $name, pass: $ok, got: $got, want: $want};
# loudnorm prints "-inf" for digital silence: that is a very low number, not a parse error.
def num: if type == "number" then . elif . == "-inf" then -99 elif . == "inf" then 99 else (try tonumber catch null) end;
def nz($x): if $x == null then 0 else $x end;

((.streams // []) | map(select(.codec_type == "video"))) as $vs
| ((.streams // []) | map(select(.codec_type == "audio"))) as $as
| ($vs | first // {}) as $v
| ($as | first // {}) as $a
| (.format // {}) as $f
| ($profile.video) as $pv
| ($profile.audio) as $pa
| (($f.duration // "0") | tonumber) as $dur
| (if $loud == null then null else ($loud.input_i | num) end) as $lufs
| (if $loud == null then null else ($loud.input_tp | num) end) as $tp
| ((($a.duration // "0") | tonumber)) as $adur
| [
    chk("container"; (($f.format_name // "") | contains("mp4")); $f.format_name; "mp4"),
    chk("streams"; (($vs | length) == 1 and ($as | length) == 1); "\($vs | length) video, \($as | length) audio"; "1 video, 1 audio"),
    chk("video codec"; $v.codec_name == $pv.codec; $v.codec_name; $pv.codec),
    chk("size"; ($v.width == $pv.width and $v.height == $pv.height); "\($v.width)x\($v.height)"; "\($pv.width)x\($pv.height)"),
    chk("pixel aspect"; ($v.sample_aspect_ratio // "1:1") == "1:1"; ($v.sample_aspect_ratio // "1:1"); "1:1"),
    chk("pixel format"; $v.pix_fmt == $pv.pix_fmt; $v.pix_fmt; $pv.pix_fmt),
    chk("frame rate"; $v.r_frame_rate == "\($pv.fps)/1"; $v.r_frame_rate; "\($pv.fps)/1"),
    chk("frames"; (($v.nb_frames // "0") | tonumber) == ($fmt * $pv.fps); $v.nb_frames; ($fmt * $pv.fps)),
    chk("duration"; (($dur - $fmt) | fabs) <= $profile.qa.duration_tolerance_s; $dur; "\($fmt) +- \($profile.qa.duration_tolerance_s)"),
    chk("audio codec"; $a.codec_name == $pa.codec; ($a.codec_name // "none"); $pa.codec),
    chk("audio rate"; (($a.sample_rate // "0") | tonumber) == $pa.rate; ($a.sample_rate // "none"); $pa.rate),
    chk("audio channels"; $a.channels == $pa.channels; ($a.channels // "none"); $pa.channels),
    chk("audio length"; (($adur - $fmt) | fabs) <= $profile.qa.audio_tolerance_s; $adur; "\($fmt) +- \($profile.qa.audio_tolerance_s)"),
    chk("faststart (moov before mdat)"; ($moov >= 0 and $mdat >= 0 and $moov < $mdat); "moov at \($moov), mdat at \($mdat)"; "moov first"),
    chk("loudness (LUFS)"; ($lufs != null and (($lufs - $pa.target_lufs) | fabs) <= $pa.lufs_tolerance); ($lufs // "no audio"); "\($pa.target_lufs) +- \($pa.lufs_tolerance)"),
    chk("true peak (dBTP)"; ($tp != null and $tp <= ($pa.true_peak + $pa.true_peak_slack)); ($tp // "no audio"); "at most \($pa.true_peak + $pa.true_peak_slack)"),
    chk("made from the approved screenplay"; $render_sha == $sp_sha; ($render_sha[0:8] | if . == "" then "no render.json" else . end); $sp_sha[0:8]),
    chk("is the file that reel render wrote"; $render_reel == $reel_sha; ($render_reel[0:8] | if . == "" then "no render.json" else . end); $reel_sha[0:8]),
    chk("hook picture at \($profile.qa.hook_probe_s) s"; $hook != "none"; $hook; "something drawn")
  ] as $checks
| ($beats | map(select(.pass | not))) as $badbeats
| {
    schema: "reels.qa/1",
    slug: $slug,
    format: $fmt,
    pass: (($checks | all(.pass)) and ($badbeats | length) == 0),
    reel_sha256: $reel_sha,
    screenplay_sha256: $sp_sha,
    facts: {
      bytes: (($f.size // "0") | tonumber),
      duration_s: $dur,
      size: "\($v.width)x\($v.height)",
      fps: $v.r_frame_rate,
      video: "\($v.codec_name) \($v.profile // "") \($v.pix_fmt)",
      audio: "\($a.codec_name) \($a.sample_rate) Hz \($a.channels) ch",
      bit_rate: (($f.bit_rate // "0") | tonumber)
    },
    loudness: {lufs: $lufs, true_peak_dbtp: $tp, lra: (if $loud == null then null else ($loud.input_lra | num) end)},
    checks: $checks,
    beats: $beats,
    failures: (
      [$checks[] | select(.pass | not) | "\(.name): got \(.got), want \(.want)"]
      + [$badbeats[] | .id as $id | .problems[] | "beat \($id): \(.)"])
  }
