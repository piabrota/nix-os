//// Design A, "fabric": the org profile as a page. The projects as cards in the lanes of the
//// profile's "How it fits" figure, each with its state on its edge. Served at /.

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
            "Each lane is a kind of work. The edge of a card says where the project stands.",
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
            html.ul([attribute.class("cards")], list.map(projects, card)),
          ])
        })
      ]),
      ..community.sections()
    ]),
    parts.foot("fabric"),
  ])
}

fn card(p: Project) -> Element(msg) {
  html.li(
    [
      attribute.class("card"),
      attribute.data("state", parts.state_class(p.state)),
    ],
    [
      html.div([attribute.class("card-head")], [
        html.h4([], [html.text(p.name)]),
        parts.pill(p.state),
      ]),
      html.p([attribute.class("blurb")], [html.text(p.blurb)]),
      html.div([attribute.class("card-foot")], [
        html.span([attribute.class("meta")], [
          html.text(p.lang <> " · " <> p.licence),
        ]),
        parts.address(p),
      ]),
    ],
  )
}
