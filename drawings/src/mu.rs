//! The nix-os drawing: 无 (*mu*, "no thing") brushed in its four strokes, in the standard order.
//! 无 is the other way to write the 無 of [pirsig](https://github.com/h0ffmann/pirsig)'s logo:
//! the simplified form, and an old variant that Japanese also knows.
//!
//! Each stroke is a brush line through hand-placed points with a width at each point: the two
//! horizontals stop firmly (*tome*), the falling stroke sweeps out to a point (*harai*), and the
//! last stroke bends right along the bottom and lifts in a hook. The stroke order follows
//! KanjiVG; the points are drawn here.

use crate::pen::{brush, Drawing, Mark, P};

/// A stroke in a 0–100 box: (x, y, brush width at that point).
type Stroke = &'static [(f64, f64, f64)];

/// The four strokes of 无, in writing order.
const MU: [Stroke; 4] = [
    // 1 ㇐ the short top horizontal, rising a little, stopped at the end
    &[
        (27.0, 30.0, 6.0),
        (31.0, 28.6, 4.8),
        (52.0, 26.8, 3.0),
        (72.0, 25.2, 3.2),
        (79.0, 24.8, 5.4),
        (80.5, 26.2, 6.0),
    ],
    // 2 ㇐ the long horizontal
    &[
        (11.5, 52.0, 7.0),
        (16.0, 50.8, 5.4),
        (45.0, 49.0, 3.4),
        (75.0, 47.4, 3.3),
        (92.0, 46.6, 5.4),
        (96.5, 48.0, 7.0),
    ],
    // 3 ㇒ the falling stroke, from the top horizontal down through the long one, swept out
    &[
        (50.5, 30.0, 7.0),
        (50.2, 37.0, 6.6),
        (48.2, 54.0, 5.8),
        (42.5, 70.0, 4.4),
        (32.0, 84.0, 2.8),
        (17.5, 94.5, 0.8),
    ],
    // 4 ㇟ down from the long horizontal, bent right along the bottom, lifted in a hook
    &[
        (60.5, 52.5, 7.0),
        (61.6, 57.0, 6.0),
        (61.8, 72.0, 5.2),
        (63.2, 84.0, 5.0),
        (68.5, 89.6, 4.6),
        (82.0, 90.6, 4.2),
        (91.0, 89.8, 5.4),
        (94.4, 86.6, 5.4),
        (95.4, 80.0, 2.4),
    ],
];

/// The canvas, square, with the kanji in its middle.
const SIDE: f64 = 240.0;
/// The kanji's box on the canvas: centre and scale of the 0–100 box.
const CENTRE: P = (SIDE / 2.0, SIDE / 2.0);
const SCALE: f64 = 2.2;
/// How heavy the brush is: the widths of [`MU`] times this.
const BRUSH: f64 = 2.2;

fn place((x, y): P) -> P {
    (
        (x - 54.0).mul_add(SCALE, CENTRE.0),
        (y - 60.0).mul_add(SCALE, CENTRE.1),
    )
}

#[must_use]
pub fn drawing() -> Drawing {
    let mut marks: Vec<Mark> = vec![];
    for s in MU {
        let pts: Vec<P> = s.iter().map(|&(x, y, _)| place((x, y))).collect();
        let widths: Vec<f64> = s.iter().map(|&(_, _, w)| w * BRUSH).collect();
        marks.extend(brush(&pts, &widths));
    }
    Drawing {
        w: SIDE,
        h: SIDE,
        label: "无 (mu, no thing) brushed in its four strokes, by @h0ffmann",
        desc: "Drawn from the Desmos expressions of mu.desmos.json: cubic Béziers through hand-placed points, each piece at its brush width.",
        marks,
    }
}

#[cfg(test)]
mod tests {
    use super::MU;

    #[test]
    fn mu_has_its_four_strokes_in_order() {
        assert_eq!(MU.len(), 4);
        let first = |s: &[(f64, f64, f64)]| s[0];
        let last = |s: &[(f64, f64, f64)]| s[s.len() - 1];
        // the two horizontals: short above long
        assert!(first(MU[0]).1 < first(MU[1]).1);
        assert!(last(MU[0]).0 - first(MU[0]).0 < last(MU[1]).0 - first(MU[1]).0);
        // the falling stroke crosses the long horizontal and ends low on the left
        assert!(first(MU[2]).1 < MU[1][2].1 && last(MU[2]).1 > MU[1][2].1);
        assert!(last(MU[2]).0 < first(MU[2]).0);
        // the last stroke ends to the right, above its lowest point: the hook
        let low = MU[3].iter().map(|p| p.1).fold(0.0, f64::max);
        assert!(last(MU[3]).0 > first(MU[3]).0 && last(MU[3]).1 < low);
    }
}
