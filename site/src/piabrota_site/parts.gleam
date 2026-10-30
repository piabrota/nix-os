//// What the three pages share: the mark, a project's address, the switcher between the designs.

import gleam/int
import gleam/list
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/element/svg
import piabrota_site/data.{type Project, type State, Coming, Live, NoSite}

/// The three designs, each at its own path: A at the root, B and C below it.
pub const designs = [
  #("A", "fabric", "/"),
  #("B", "index", "/index/"),
  #("C", "paths", "/paths/"),
]

/// site.nix answers this path with a redirect to the repository.
pub const nixos = "/nixos"

/// The org's mark, as the profile shows it: an open green eye on red.
pub fn eye(size: Int) -> Element(msg) {
  let a = attribute.attribute
  html.svg(
    [
      a("viewBox", "0 0 100 100"),
      a("width", int.to_string(size)),
      a("height", int.to_string(size)),
      a("aria-hidden", "true"),
      attribute.class("eye"),
    ],
    [
      svg.rect([
        a("width", "100"),
        a("height", "100"),
        a("rx", "20"),
        a("fill", "#BC2318"),
      ]),
      svg.path([
        a("d", "M10 50 Q50 20 90 50 Q50 80 10 50Z"),
        a("fill", "#F7F3EA"),
      ]),
      svg.circle([
        a("cx", "50"),
        a("cy", "50"),
        a("r", "13"),
        a("fill", "#2E9E4F"),
      ]),
      svg.circle([
        a("cx", "50"),
        a("cy", "50"),
        a("r", "6"),
        a("fill", "#0B0D12"),
      ]),
    ],
  )
}

pub fn state_name(state: State) -> String {
  case state {
    Live -> "live"
    Coming -> "coming"
    NoSite -> "no site yet"
  }
}

pub fn state_class(state: State) -> String {
  case state {
    Live -> "live"
    Coming -> "coming"
    NoSite -> "none"
  }
}

/// The project's address, a link when there is somewhere to go.
pub fn address(p: Project) -> Element(msg) {
  case p.href {
    "" -> html.span([attribute.class("where")], [html.text(p.where)])
    href ->
      html.a([attribute.class("where"), attribute.href(href)], [
        html.text(p.where),
      ])
  }
}

/// The switcher at the foot of each page: the three designs, the current one marked.
pub fn switcher(current: String) -> Element(msg) {
  html.nav([attribute.class("designs"), attribute.aria_label("designs")], [
    html.span([], [html.text("designs:")]),
    ..list.map(designs, fn(d) {
      let #(letter, name, href) = d
      let current_attr = case name == current {
        True -> [attribute.aria_current("page")]
        False -> []
      }
      html.a([attribute.href(href), ..current_attr], [
        html.text(letter <> " · " <> name),
      ])
    })
  ])
}

/// The projects of one lane, in the profile's order.
pub fn in_lane(lane: String) -> List(Project) {
  list.filter(data.projects, fn(p) { p.lane == lane })
}
