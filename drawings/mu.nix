# The nix-os drawing: 无 (*mu*, "no thing") brushed in its four strokes, in the standard order.
# 无 is the other way to write the 無 of pirsig's logo: the simplified form, and an old variant
# that Japanese also knows.
#
# Each stroke is a brush line through hand-placed points with a width at each point: the two
# horizontals stop firmly (*tome*), the falling stroke sweeps out to a point (*harai*), and the
# last stroke bends right along the bottom and lifts in a hook. The stroke order follows KanjiVG;
# the points are drawn here.
{ lib, pen }:
let
  # The four strokes of 无, in writing order, in a 0–100 box: [x y brush width at that point].
  strokes = [
    # 1 ㇐ the short top horizontal, rising a little, stopped at the end
    [
      [ 27.0 30.0 6.0 ]
      [ 31.0 28.6 4.8 ]
      [ 52.0 26.8 3.0 ]
      [ 72.0 25.2 3.2 ]
      [ 79.0 24.8 5.4 ]
      [ 80.5 26.2 6.0 ]
    ]
    # 2 ㇐ the long horizontal
    [
      [ 11.5 52.0 7.0 ]
      [ 16.0 50.8 5.4 ]
      [ 45.0 49.0 3.4 ]
      [ 75.0 47.4 3.3 ]
      [ 92.0 46.6 5.4 ]
      [ 96.5 48.0 7.0 ]
    ]
    # 3 ㇒ the falling stroke, from the top horizontal down through the long one, swept out
    [
      [ 50.5 30.0 7.0 ]
      [ 50.2 37.0 6.6 ]
      [ 48.2 54.0 5.8 ]
      [ 42.5 70.0 4.4 ]
      [ 32.0 84.0 2.8 ]
      [ 17.5 94.5 0.8 ]
    ]
    # 4 ㇟ down from the long horizontal, bent right along the bottom, lifted in a hook
    [
      [ 60.5 52.5 7.0 ]
      [ 61.6 57.0 6.0 ]
      [ 61.8 72.0 5.2 ]
      [ 63.2 84.0 5.0 ]
      [ 68.5 89.6 4.6 ]
      [ 82.0 90.6 4.2 ]
      [ 91.0 89.8 5.4 ]
      [ 94.4 86.6 5.4 ]
      [ 95.4 80.0 2.4 ]
    ]
  ];

  # The canvas, square, with the kanji in its middle: the 0–100 box scaled by `scale` about its
  # point (54, 60). The widths of `strokes` are times `weight`, how heavy the brush is.
  side = 240.0;
  scale = 2.2;
  weight = 2.2;
  place = p: [
    (pen.fma (builtins.elemAt p 0 - 54.0) scale (side / 2.0))
    (pen.fma (builtins.elemAt p 1 - 60.0) scale (side / 2.0))
  ];
in
{
  inherit strokes;

  drawing = pen.drawing {
    w = side;
    h = side;
    label = "无 (mu, no thing) brushed in its four strokes, by @h0ffmann";
    desc = "Drawn from the Desmos expressions of mu.desmos.json: cubic Béziers through hand-placed points, each piece at its brush width.";
    marks = lib.concatMap
      (s: pen.brush (map place s) (map (p: builtins.elemAt p 2 * weight) s))
      strokes;
  };
}
