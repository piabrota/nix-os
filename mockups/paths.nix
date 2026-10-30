# Mockup C, "paths": today's page grown by one block. 无 (the README drawing, from drawings/) and
# the name stay; below them, a listing of what answers on piabrota.art and where the rest lives.
{ lib, s, data, where, mu }:
w:
let
  inherit (lib) concatStrings filter length foldl';
  wide = w >= 900;
  col = if wide then 620 else w - 40;
  x0 = (w - col) / 2;
  cx = w / 2;
  fg = "#1B1B1B";
  muted = "#6B6B6B";
  link = "#1682D4";
  term = "#141414";
  tfg = "#ECECEC";
  tmuted = "#9A9A9A";
  mono = "'JetBrains Mono', ui-monospace, monospace";
  stateCol = st: { live = "#4CC38A"; coming = "#E3B341"; none = tmuted; }.${st};

  muSize = if wide then 150 else 110;
  muY = if wide then 70 else 40;
  # The drawing's own SVG, placed and sized; its colours are pinned in `defs` below.
  drawing = builtins.replaceStrings
    [ ''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 240" width="240" height="240"'' ]
    [ ''<svg x="${toString (cx - muSize / 2)}" y="${toString muY}" viewBox="0 0 240 240" width="${toString muSize}" height="${toString muSize}"'' ]
    mu;
  nameY = muY + muSize + 40;

  # The listing: a terminal card, one entry a project.
  here = filter (p: p ? path) data.projects;
  away = filter (p: !(p ? path)) data.projects;
  lead = 22;
  entryH = if wide then lead else 2 * lead + 4;
  entry = y: p:
    if wide then
      concatStrings [
        (s.text (x0 + 24) y { fill = tfg; } (p.path or (where p)))
        (s.text (x0 + 24 + 320) y { fill = tmuted; } p.name)
        (s.text (x0 + col - 24 - s.width 13 p.state) y { fill = stateCol p.state; } p.state)
      ] else
      concatStrings [
        (s.text (x0 + 16) y { fill = tfg; } (p.path or (where p)))
        (s.el "text" { x = x0 + 32; y = y + lead; fill = tmuted; } [
          (s.esc "${p.name} · ")
          (s.el "tspan" { fill = stateCol p.state; } [ p.state ])
        ])
      ];
  block = y: prompt: ps: {
    h = lead + 10 + length ps * entryH + 18;
    out = s.text (x0 + (if wide then 24 else 16)) y { fill = tmuted; } "$ ${prompt}"
      + (foldl' (acc: p: { y = acc.y + entryH; out = acc.out + entry acc.y p; }) { y = y + lead + 10; out = ""; } ps).out;
  };
  tTop = nameY + 50;
  b1 = block (tTop + 56) "ls piabrota.art/" here;
  b2 = block (tTop + 56 + b1.h) "ls elsewhere/" away;
  tH = 56 + b1.h + b2.h;
  terminal = concatStrings [
    (s.rect { x = x0; y = tTop; width = col; height = tH; rx = 12; fill = term; })
    (concatStrings (lib.imap0 (i: c: s.leaf "circle" { cx = x0 + 22 + i * 18; cy = tTop + 20; r = 5; fill = c; }) [ "#BC2318" "#E3B341" "#2E9E4F" ]))
    (s.g { font-family = mono; font-size = 13; } [ b1.out b2.out ])
  ];

  lTop = tTop + tH + 44;
  linksText = "github · open collective · sponsors";
in
s.doc
{
  width = w;
  height = lTop + 70;
  title = "Mockup C, paths: the piabrota.art homepage, ${toString w} px wide";
  bg = "#FAFAF7";
  defs = "<style>.l{stroke:${fg}!important}.d{fill:${fg}!important}</style>";
}
  (concatStrings [
    drawing
    (s.text cx nameY { fill = muted; font-size = 18; text-anchor = "middle"; } data.org.name)
    terminal
    (s.text cx lTop { fill = link; font-size = 16; text-anchor = "middle"; text-decoration = "underline"; } linksText)
  ])
