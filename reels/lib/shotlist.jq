# The default shotlist of a screenplay: one shot a beat, the look taken from the style.
# The creative director starts from it and changes what the picture needs. Input: screenplay.json.
# Arguments: $style, $hash (sha256 of screenplay.json).
{
  schema: "reels.shotlist/1",
  slug: .slug,
  screenplay_sha256: $hash,
  shots: [.beats[] | {
    beat: .id,
    scene: .visual.scene,
    kind: "flat",
    params: {},
    camera: {zoom: $style.motion.bg_zoom},
    motion: {ease: ($style.motion.ease), stagger: $style.motion.stagger, enter_s: $style.motion.enter_s, pop: $style.motion.pop, blur: $style.motion.blur},
    text_layout: {y: 0.5, scale: 1},
    palette: {main: "fg", emph: "accent_text", sub: "muted", bar: "accent"},
    transition: .transition,
    note: ""
  }]
}
