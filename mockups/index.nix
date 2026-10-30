# Mockup B, "index": an editorial list. Light, a large red wordmark, one numbered row a project,
# where it meets the web on the right (below, on a phone).
{ lib, s, data, where }:
w:
let
  inherit (lib) concatStrings length foldl' imap0;
  wide = w >= 900;
  pad = if wide then 64 else 20;
  inner = w - 2 * pad;
  fg = "#1B1B1B";
  muted = "#6B6B6B";
  rule = "#DEDBD2";
  red = "#BC2318";
  mono = "'JetBrains Mono', ui-monospace, monospace";
  heading = "'Fjalla One', 'Arial Narrow', Inter, sans-serif";
  stateLabel = st: { live = "live"; coming = "coming"; none = "no site yet"; }.${st};
  stateCol = st: { live = "#2E7D32"; coming = "#A86B00"; none = muted; }.${st};

  top = concatStrings [
    (s.eye pad 28 28)
    (s.text (pad + 40) 49 { fill = fg; font-size = 16; font-weight = 600; } data.org.name)
    (if wide then s.text (w - pad - s.width 14 "github.com/piabrota") 49 { fill = muted; font-size = 14; } "github.com/piabrota" else "")
  ];

  mark = if wide then 150 else 64;
  markY = 110 + mark;
  kTop = markY + 44;
  head = concatStrings [
    (s.text (pad - mark / 20) markY { fill = red; font-size = mark; font-family = heading; letter-spacing = -2; } (lib.toUpper data.org.name))
    (s.text pad kTop { fill = muted; font-size = if wide then 18 else 15; } data.org.kicker)
    (s.line pad (kTop + 36) (w - pad) (kTop + 36) { stroke = fg; stroke-width = 2; })
  ];

  # A row: number, name, blurb; the address, state and licence in a right column (wide) or below.
  colR = 300;
  textW = if wide then inner - 80 - colR - 40 else inner - 44;
  row = y: i: p:
    let
      bl = s.wrap (s.fit textW 15) p.blurb;
      bodyH = 44 + length bl * 22;
      tx = pad + (if wide then 80 else 44);
      rx = w - pad - colR;
      meta =
        if wide then [
          (s.text rx (y + 36) { fill = fg; font-size = 13; font-family = mono; } (where p))
          (s.text rx (y + 60) { fill = stateCol p.state; font-size = 13; } "${stateLabel p.state} · ${p.licence}")
        ] else [
          (s.text tx (y + bodyH + 28) { fill = fg; font-size = 12; font-family = mono; } (where p))
          (s.text tx (y + bodyH + 50) { fill = stateCol p.state; font-size = 12; } "${stateLabel p.state} · ${p.licence}")
        ];
      h = (if wide then lib.max bodyH 70 else bodyH + 62) + 24;
    in
    {
      inherit h;
      out = concatStrings ([
        (s.text pad (y + 36) { fill = muted; font-size = 13; font-family = mono; } (lib.fixedWidthNumber 2 (i + 1)))
        (s.text tx (y + 36) { fill = fg; font-size = if wide then 30 else 24; font-family = heading; } p.name)
        (s.lines tx (y + 66) 22 { fill = muted; font-size = 15; } bl)
      ] ++ meta ++ [ (s.line pad (y + h) (w - pad) (y + h) { stroke = rule; }) ]);
    };
  rows = foldl'
    (acc: ip: let r = row acc.y ip.i ip.p; in { y = acc.y + r.h; out = acc.out + r.out; })
    { y = kTop + 50; out = ""; }
    (imap0 (i: p: { inherit i p; }) data.projects);

  fTop = rows.y + 50;
  lede = s.wrap (s.fit (if wide then 640 else inner) 15) data.org.lede;
  footer = concatStrings [
    (s.lines pad fTop 22 { fill = muted; font-size = 15; } lede)
    (s.text pad (fTop + length lede * 22 + 24) { fill = fg; font-size = 13; } "Partnerships: ${data.org.contact}")
  ];
in
s.doc
{
  width = w;
  height = fTop + length lede * 22 + 70;
  title = "Mockup B, index: the piabrota.art homepage, ${toString w} px wide";
  bg = "#FAFAF7";
}
  (concatStrings [ top head rows.out footer ])
