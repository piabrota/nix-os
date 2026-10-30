//// Design B, "index": every project in one table, ranked by the profile's order, picasso's
//// standings table in piabrota's colours. Served at /index/.

import gleam/int
import gleam/list
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import piabrota_site/community
import piabrota_site/data.{type Project}
import piabrota_site/parts

pub fn view() -> Element(msg) {
  html.div([], [
    parts.top("index", [
      html.div([], [
        parts.eyebrow(
          "index · " <> int.to_string(list.length(data.projects)) <> " projects",
        ),
        html.h1([attribute.class("wordmark")], [
          html.text(string.uppercase(data.name)),
        ]),
        html.p([attribute.class("lede")], [html.text(data.lede)]),
        parts.status(),
        parts.buttons(#("#all", "Read the index ↓")),
      ]),
    ]),
    html.main([], [
      html.section([attribute.class("wrap"), attribute.id("all")], [
        parts.section_head("Every project", data.kicker),
        html.div([attribute.class("table-scroll")], [
          html.table([attribute.class("repos")], [
            html.thead([], [
              html.tr([], [
                html.th([attribute.class("num")], [html.text("#")]),
                html.th([], [html.text("Project")]),
                html.th([], [html.text("Where")]),
                html.th([attribute.class("opt")], [html.text("Licence")]),
                html.th([], [html.text("State")]),
              ]),
            ]),
            html.tbody([], list.index_map(data.projects, row)),
          ]),
        ]),
      ]),
      ..community.sections()
    ]),
    parts.foot("index"),
  ])
}

fn row(p: Project, i: Int) -> Element(msg) {
  html.tr([attribute.data("state", parts.state_class(p.state))], [
    html.td([attribute.class("num rank")], [
      html.text(string.pad_start(int.to_string(i + 1), 2, "0")),
    ]),
    html.td([], [
      html.div([attribute.class("name")], [html.text(p.name)]),
      html.div([attribute.class("desc")], [html.text(p.blurb)]),
    ]),
    html.td([], [parts.address(p)]),
    html.td([attribute.class("opt when")], [
      html.text(p.lang <> " · " <> p.licence),
    ]),
    html.td([], [parts.pill(p.state)]),
  ])
}
