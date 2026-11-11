# The background of a style as SVG, 1080x1920: a vertical gradient, a glow, a vignette.
# Input: the style. Arguments: $profile. Output: SVG text (jq -r).
include "common";
(.background // {}) as $bg
| ($profile.video.width) as $w
| ($profile.video.height) as $h
| (.colors[$bg.glow_color // "accent"]) as $gc
| ($bg.glow_opacity // 0) as $go
| ($bg.vignette // 0.4) as $vg
| "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\($w)\" height=\"\($h)\" viewBox=\"0 0 \($w) \($h)\">",
  "<defs>",
  "<linearGradient id=\"g\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\"><stop offset=\"0\" stop-color=\"\(.colors.bg)\"/><stop offset=\"1\" stop-color=\"\(.colors.surface)\"/></linearGradient>",
  "<radialGradient id=\"glow\" gradientUnits=\"userSpaceOnUse\" cx=\"\(($bg.glow_x // 0.5) * $w)\" cy=\"\(($bg.glow_y // 0.5) * $h)\" r=\"\(($bg.glow_r // 0.6) * $w)\"><stop offset=\"0\" stop-color=\"\($gc)\" stop-opacity=\"\($go)\"/><stop offset=\"1\" stop-color=\"\($gc)\" stop-opacity=\"0\"/></radialGradient>",
  "<radialGradient id=\"vig\" cx=\"0.5\" cy=\"0.5\" r=\"0.75\"><stop offset=\"0.55\" stop-color=\"#000\" stop-opacity=\"0\"/><stop offset=\"1\" stop-color=\"#000\" stop-opacity=\"\($vg)\"/></radialGradient>",
  "</defs>",
  "<rect width=\"\($w)\" height=\"\($h)\" fill=\"url(#g)\"/>",
  "<rect width=\"\($w)\" height=\"\($h)\" fill=\"url(#glow)\"/>",
  "<rect width=\"\($w)\" height=\"\($h)\" fill=\"url(#vig)\"/>",
  "</svg>"
