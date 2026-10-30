# Mockup A, "fabric": the org profile as a page. Dark, the logo's red, the projects as cards in
# the lanes of the profile's "How it fits" figure, each card saying where it meets the web.
{ lib, s, data, where }:
w:
let
  inherit (lib) concatStrings filter length foldl' imap0 max;
  wide = w >= 900;
  pad = if wide then 64 else 20;
  inner = w - 2 * pad;
  fg = "#EDEFF3";
  muted = "#9AA3B2";
  card = "#14171F";
  border = "#2A303C";
  red = "#BC2318";
  stateCol = st: { live = "#2E9E4F"; coming = "#D9A21B"; none = "#5B6474"; }.${st};
  heading = "'Fjalla One', 'Arial Narrow', Inter, sans-serif";

  # Navigation: the mark and the name, the profile's sections on the right.
  links =
    let
      gap = 28;
      widths = map (s.width 15) data.org.links;
      total = foldl' (a: b: a + b) 0 widths + gap * (length widths - 1);
    in
    (foldl'
      (acc: l: { x = acc.x + s.width 15 l + gap; out = acc.out + s.text acc.x 52 { fill = muted; font-size = 15; } l; })
      { x = w - pad - total; out = ""; }
      data.org.links).out;
  nav = concatStrings [
    (s.eye pad 26 36)
    (s.text (pad + 50) 52 { fill = fg; font-size = 22; font-family = heading; } data.org.name)
    (if wide then links else s.text (w - pad - 22) 52 { fill = muted; font-size = 22; } "≡")
  ];

  # The hero: kicker, headline, lede, three pills.
  hSize = if wide then 60 else 36;
  hLines = s.wrap (s.fit (if wide then 820 else inner) hSize) data.org.headline;
  hTop = 150;
  lSize = if wide then 19 else 16;
  lLines = s.wrap (s.fit (if wide then 680 else inner) lSize) data.org.lede;
  lTop = hTop + 24 + hSize + (length hLines - 1) * hSize * 112 / 100 + lSize + 30;
  pTop = lTop + (length lLines - 1) * lSize * 155 / 100 + 34;
  pill = x: y: label: s.g { } [
    (s.rect { inherit x y; width = s.width 13 label + 28; height = 30; rx = 15; fill = "none"; stroke = border; })
    (s.text (x + 14) (y + 20) { fill = fg; font-size = 13; } label)
  ];
  # The pills wrap to a new row at the right edge.
  pillRows = foldl'
    (acc: l:
      let
        pw = s.width 13 l + 28;
        next = acc.x + pw > w - pad;
        x = if next then pad else acc.x;
        y = if next then acc.y + 40 else acc.y;
      in
      { x = x + pw + 12; inherit y; out = acc.out + pill x y l; })
    { x = pad; y = pTop; out = ""; }
    [ "FOSS" "Rust first" "MPL-2.0" "made in Rio" ];
  pills = pillRows.out;
  hero = concatStrings [
    (s.text pad hTop { fill = red; font-size = 13; letter-spacing = 2; font-weight = 600; } (lib.toUpper data.org.kicker))
    (s.lines pad (hTop + 24 + hSize) (hSize * 112 / 100) { fill = fg; font-size = hSize; font-family = heading; } hLines)
    (s.lines pad lTop (lSize * 155 / 100) { fill = muted; font-size = lSize; } lLines)
    pills
  ];

  # The cards: every card as tall as the one with the longest blurb.
  cols = if wide then 3 else 1;
  gapC = 20;
  cardW = (inner - (cols - 1) * gapC) / cols;
  bSize = 14;
  blurb = p: s.wrap (s.fit (cardW - 40) bSize) p.blurb;
  cardH = 150 + 20 * foldl' max 0 (map (p: length (blurb p)) data.projects) - 20;
  oneCard = x: y: p: s.g { } [
    (s.rect { inherit x y; width = cardW; height = cardH; rx = 10; fill = card; stroke = border; })
    (s.text (x + 20) (y + 38) { fill = fg; font-size = 21; font-family = heading; } p.name)
    (s.text (x + 20) (y + 60) { fill = muted; font-size = 12; } "${p.lang} · ${p.licence}")
    (s.lines (x + 20) (y + 90) 20 { fill = muted; font-size = bSize; } (blurb p))
    (s.leaf "circle" { cx = x + 26; cy = y + cardH - 26; r = 5; fill = stateCol p.state; })
    (s.text (x + 40) (y + cardH - 21) { fill = fg; font-size = 12; font-family = "'JetBrains Mono', ui-monospace, monospace"; } (where p))
  ];
  laneBlock = top: lane:
    let
      ps = filter (p: p.lane == lane.id) data.projects;
      rows = (length ps + cols - 1) / cols;
      grid = concatStrings (imap0
        (i: p: oneCard (pad + lib.mod i cols * (cardW + gapC)) (top + 22 + i / cols * (cardH + gapC)) p)
        ps);
    in
    {
      out = s.text pad top { fill = muted; font-size = 12; letter-spacing = 2; font-weight = 600; } (lib.toUpper lane.label) + grid;
      height = 22 + rows * (cardH + gapC) + 24;
    };
  prTop = pillRows.y + 110;
  projects = foldl'
    (acc: lane: let b = laneBlock acc.y lane; in { y = acc.y + b.height; out = acc.out + b.out; })
    { y = prTop + 48; out = s.text pad prTop { fill = fg; font-size = 30; font-family = heading; } "Projects"; }
    data.lanes;

  fTop = projects.y + 20;
  footer = concatStrings [
    (s.line pad fTop (w - pad) fTop { stroke = border; })
    (s.text pad (fTop + 40) { fill = muted; font-size = 13; } "piabrota.art is served by nix-os, from /nix/store.")
    (s.text pad (fTop + 64) { fill = muted; font-size = 13; } "Partnerships: ${data.org.contact}")
  ];
  height = fTop + 100;
in
s.doc
{
  width = w;
  inherit height;
  title = "Mockup A, fabric: the piabrota.art homepage, ${toString w} px wide";
  bg = "#0B0D12";
  defs = ''<radialGradient id="glow" cx="10%" cy="0%" r="70%"><stop offset="0" stop-color="${red}" stop-opacity="0.28"/><stop offset="1" stop-color="${red}" stop-opacity="0"/></radialGradient>'';
}
  (concatStrings [
    (s.rect { x = 0; y = 0; width = w; height = 520; fill = "url(#glow)"; })
    nav
    hero
    projects.out
    footer
  ])
