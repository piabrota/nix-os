# A few SVG helpers for the mockups. Every coordinate is an integer, so the output is stable.
{ lib }:
let
  inherit (lib) concatStrings mapAttrsToList splitString foldl' stringLength;
in
rec {
  esc = builtins.replaceStrings [ "&" "<" ">" "\"" ] [ "&amp;" "&lt;" "&gt;" "&quot;" ];

  attrs = as: concatStrings (mapAttrsToList (k: v: " ${k}=\"${esc (toString v)}\"") as);

  el = name: as: children: "<${name}${attrs as}>${concatStrings children}</${name}>";
  leaf = name: as: "<${name}${attrs as}/>";

  rect = leaf "rect";
  line = x1: y1: x2: y2: as: leaf "line" ({ inherit x1 y1 x2 y2; } // as);
  text = x: y: as: s: el "text" ({ inherit x y; } // as) [ (esc s) ];
  g = el "g";

  # Greedy word wrap at `n` characters a line.
  wrap = n: s:
    foldl'
      (acc: w:
        if acc == [ ] then [ w ]
        else
          let last = lib.last acc; in
          if stringLength last + 1 + stringLength w <= n
          then lib.init acc ++ [ "${last} ${w}" ]
          else acc ++ [ w ])
      [ ]
      (splitString " " s);

  # Lines of text from (x, y), `lead` pixels apart.
  lines = x: y: lead: as: ls: concatStrings (lib.imap0 (i: l: text x (y + i * lead) as l) ls);

  # About how many characters of a sans font at `size` fit in `width` pixels.
  fit = width: size: width * 100 / (54 * size);

  # Roughly how wide a string is at `size`, for chips and right-aligned text.
  width = size: s: stringLength s * size * 56 / 100;

  # The org's mark, as the profile shows it: an open green eye on red, `s` pixels square.
  eye = x: y: s:
    let
      cx = x + s / 2;
      cy = y + s / 2;
      w = s * 40 / 100;
      h = s * 30 / 100;
    in
    g { } [
      (rect { inherit x y; width = s; height = s; rx = s / 5; fill = "#BC2318"; })
      (leaf "path" {
        d = "M${toString (cx - w)} ${toString cy} Q${toString cx} ${toString (cy - h)} ${toString (cx + w)} ${toString cy} Q${toString cx} ${toString (cy + h)} ${toString (cx - w)} ${toString cy}Z";
        fill = "#F7F3EA";
      })
      (leaf "circle" { inherit cx cy; r = s * 13 / 100; fill = "#2E9E4F"; })
      (leaf "circle" { inherit cx cy; r = s * 6 / 100; fill = "#0B0D12"; })
    ];

  doc = { width, height, title, bg, font ? "Inter, system-ui, -apple-system, 'Segoe UI', sans-serif", defs ? "" }: body:
    ''<svg xmlns="http://www.w3.org/2000/svg" width="${toString width}" height="${toString height}" viewBox="0 0 ${toString width} ${toString height}" font-family="${esc font}" role="img" aria-label="${esc title}">
<title>${esc title}</title>
<defs>${defs}</defs>
${rect { x = 0; y = 0; inherit width height; fill = bg; }}
${body}
</svg>
'';
}
