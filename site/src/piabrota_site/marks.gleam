//// The marks of what piabrota runs but has no repository logo for: Hermes, OpenRig, the metrics
//// page, the room, its grid view and the proof pages. Each is the piabrota mark's square (red, radius 22) with one cream drawing,
//// in the mark's own colours only (site/DESIGN.md, "Marks"). Inline, so no file is stored.

import gleam/float
import gleam/int
import gleam/list
import lustre/attribute.{type Attribute}
import lustre/element.{type Element}
import lustre/element/html
import lustre/element/svg

const cream = "#F7F3EA"

const ink = "#0B0D12"

/// The mark of a name, if it has one here.
pub fn for(name: String, size: Int) -> Result(Element(msg), Nil) {
  case name {
    "hermes" -> Ok(hermes(size))
    "openrig" -> Ok(openrig(size))
    "metrics" -> Ok(metrics(size))
    "room" -> Ok(room(size))
    "proof" -> Ok(proof(size))
    "grid" -> Ok(grid(size))
    _ -> Error(Nil)
  }
}

/// A caduceus: the staff, two snakes that meet under the wings, two swept wings.
pub fn hermes(size: Int) -> Element(msg) {
  frame("hermes", size, [
    stroke("M50 30 V86", 6.0),
    stroke(
      "M50 81 C33 76 33 66 50 61 C67 56 67 46 50 42 C44 41 41 39 40 36",
      4.5,
    ),
    stroke(
      "M50 81 C67 76 67 66 50 61 C33 56 33 46 50 42 C56 41 59 39 60 36",
      4.5,
    ),
    dot(50, 21, 6, cream),
    dot(39, 35, 4, cream),
    dot(61, 35, 4, cream),
    fill(
      "M44 28 C36 19 24 15 10 17 L18 22 L12 25 L22 28 L17 31 C27 33 36 32 44 31Z",
    ),
    fill(
      "M56 28 C64 19 76 15 90 17 L82 22 L88 25 L78 28 L83 31 C73 33 64 32 56 31Z",
    ),
  ])
}

/// A rig: three seats tied to the daemon in the middle.
pub fn openrig(size: Int) -> Element(msg) {
  frame("openrig", size, [
    stroke("M50 50 L50 22 M50 50 L25 68 M50 50 L75 68", 5.0),
    dot(50, 22, 10, cream),
    dot(25, 68, 10, cream),
    dot(75, 68, 10, cream),
    dot(50, 50, 13, cream),
    dot(50, 50, 6, ink),
  ])
}

/// Three bars that rise: memory, vCPU, processes.
pub fn metrics(size: Int) -> Element(msg) {
  frame("metrics", size, [
    bar(20, 58, 22),
    bar(43, 42, 38),
    bar(66, 22, 58),
  ])
}

/// A room seen from its open side: the walls in perspective, and a window on the sea.
pub fn room(size: Int) -> Element(msg) {
  frame("room", size, [
    stroke("M18 18 H82 V82 H18 Z", 5.0),
    stroke("M18 82 L36 64 M82 82 L64 64 M18 18 L36 36 M82 18 L64 36", 5.0),
    svg.rect([
      a("x", "36"),
      a("y", "36"),
      a("width", "28"),
      a("height", "28"),
      a("fill", ink),
      a("stroke", cream),
      a("stroke-width", "4"),
    ]),
    stroke("M39 55 C44 51 48 51 51 54 C54 57 58 57 62 53", 3.0),
    dot(56, 44, 3, cream),
  ])
}

/// ▲ grid: a triangle cut into four, the mesh the coast is drawn on.
pub fn grid(size: Int) -> Element(msg) {
  frame("grid", size, [
    stroke("M50 18 L84 80 H16 Z", 6.0),
    stroke("M33 49 H67 L50 80 Z", 4.0),
  ])
}

/// ∀, for all: the glyph that h0ffmann/proof's README opens with.
pub fn proof(size: Int) -> Element(msg) {
  frame("proof", size, [
    stroke("M24 22 L50 80 L76 22", 7.0),
    stroke("M34 44 H66", 7.0),
  ])
}

fn frame(name: String, size: Int, drawing: List(Element(msg))) -> Element(msg) {
  html.svg(
    [
      a("viewBox", "0 0 100 100"),
      a("width", int.to_string(size)),
      a("height", int.to_string(size)),
      a("aria-hidden", "true"),
      attribute.class("logo-mark logo-mark-" <> name),
    ],
    list.prepend(
      drawing,
      svg.rect([
        a("width", "100"),
        a("height", "100"),
        a("rx", "22"),
        a("fill", "#BC2318"),
      ]),
    ),
  )
}

fn stroke(d: String, width: Float) -> Element(msg) {
  svg.path([
    a("d", d),
    a("fill", "none"),
    a("stroke", cream),
    a("stroke-width", float.to_string(width)),
    a("stroke-linecap", "round"),
    a("stroke-linejoin", "round"),
  ])
}

fn fill(d: String) -> Element(msg) {
  svg.path([a("d", d), a("fill", cream)])
}

fn dot(x: Int, y: Int, r: Int, colour: String) -> Element(msg) {
  svg.circle([
    a("cx", int.to_string(x)),
    a("cy", int.to_string(y)),
    a("r", int.to_string(r)),
    a("fill", colour),
  ])
}

fn bar(x: Int, y: Int, h: Int) -> Element(msg) {
  svg.rect([
    a("x", int.to_string(x)),
    a("y", int.to_string(y)),
    a("width", "14"),
    a("height", int.to_string(h)),
    a("rx", "3"),
    a("fill", cream),
  ])
}

fn a(name: String, value: String) -> Attribute(msg) {
  attribute.attribute(name, value)
}
