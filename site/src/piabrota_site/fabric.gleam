//// Design A, "fabric": the org as closed-source's page is built: the numbers, the tiles with their
//// tags, the anchors, and the sections in order. The tiles sit in the lanes of the profile's
//// "How it fits" figure. Served at /.

import gleam/int
import gleam/list
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import piabrota_site/community
import piabrota_site/data.{type Project}
import piabrota_site/parts

pub fn view() -> Element(msg) {
  html.div([], [
    parts.top("fabric", [
      html.div([], [
        parts.eyebrow(data.kicker),
        html.h1([], [
          html.text("Open software, "),
          html.span([], [html.text("made in Rio de Janeiro.")]),
        ]),
        html.p([attribute.class("lede")], [html.text(data.lede)]),
        parts.metrics(),
        parts.status(),
        parts.buttons(#("#projects", "See the projects ↓")),
      ]),
      html.figure([attribute.class("drawing")], [
        parts.eye(176),
        html.figcaption([], [html.text("the piabrota mark")]),
      ]),
    ]),
    html.main([], [
      html.section([attribute.class("wrap"), attribute.id("projects")], [
        parts.section_head("Projects", "from piabrota/.github"),
        html.p([attribute.class("sub")], [
          html.text(
            "Each lane is a kind of work. Click a tile to open the project's site, or its repository when it has no site yet.",
          ),
        ]),
        ..list.map(data.lanes, fn(lane) {
          let projects = parts.in_lane(lane.id)
          html.div([attribute.class("lane")], [
            html.h3([], [
              html.text(lane.label),
              html.span([attribute.class("count")], [
                html.text(int.to_string(list.length(projects))),
              ]),
            ]),
            html.ul([attribute.class("tiles")], list.map(projects, tile)),
          ])
        })
      ]),
      ..community.sections()
    ]),
    parts.foot("fabric"),
  ])
}

/// A tile: the tags, the name, the blurb. The name's link covers the whole tile, as on
/// closed-source; `tile_href` always has somewhere to go.
fn tile(p: Project) -> Element(msg) {
  html.li(
    [
      attribute.class("tile"),
      attribute.data("state", parts.state_class(p.state)),
      attribute.data("name", p.name),
    ],
    [
      html.div([attribute.class("tile-tags")], [
        parts.pill(p.state),
        html.span([], [html.text(p.lang)]),
        html.span([], [html.text(p.origin)]),
      ]),
      html.h4([], [
        html.a([attribute.class("tile-link"), attribute.href(tile_href(p))], [
          html.text(p.name),
        ]),
      ]),
      html.p([attribute.class("blurb")], [html.text(p.blurb)]),
      html.span([attribute.class("meta")], [
        html.text(p.licence <> " · " <> p.where),
      ]),
    ],
  )
}

fn tile_href(p: Project) -> String {
  case p.href {
    "" -> p.repo
    href -> href
  }
}
