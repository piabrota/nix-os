//// Design B, "index": an editorial list. Light, a large red wordmark, one numbered row a
//// project, its address, state and licence beside it. Served at /index/.

import gleam/int
import gleam/list
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import piabrota_site/data.{type Project}
import piabrota_site/parts

pub fn view() -> Element(msg) {
  html.div([attribute.class("page")], [
    html.header([attribute.class("top")], [
      html.a([attribute.class("brand"), attribute.href("/")], [
        parts.eye(28),
        html.span([], [html.text(data.name)]),
      ]),
      html.a([attribute.href("https://github.com/piabrota")], [
        html.text("github.com/piabrota"),
      ]),
    ]),
    html.main([], [
      html.h1([attribute.class("wordmark")], [
        html.text(string.uppercase(data.name)),
      ]),
      html.p([attribute.class("kicker")], [html.text(data.kicker)]),
      html.ol(
        [attribute.class("rows")],
        list.index_map(data.projects, fn(p, i) { row(p, i + 1) }),
      ),
    ]),
    html.footer([], [
      html.p([], [html.text(data.lede)]),
      html.p([], [html.text("Partnerships: " <> data.contact)]),
      parts.switcher("index"),
    ]),
  ])
}

fn row(p: Project, n: Int) -> Element(msg) {
  html.li([], [
    html.span([attribute.class("n")], [
      html.text(string.pad_start(int.to_string(n), 2, "0")),
    ]),
    html.div([attribute.class("body")], [
      html.h2([], [html.text(p.name)]),
      html.p([], [html.text(p.blurb)]),
    ]),
    html.div([attribute.class("side")], [
      parts.address(p),
      html.p([attribute.class(parts.state_class(p.state))], [
        html.text(parts.state_name(p.state) <> " · " <> p.licence),
      ]),
    ]),
  ])
}
