//// Design A, "fabric": the org profile as a page. Dark, the logo's red, the projects as cards in
//// the lanes of the profile's "How it fits" figure. Served at /.

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
        parts.eye(36),
        html.span([], [html.text(data.name)]),
      ]),
    ]),
    html.main([], [
      html.section([attribute.class("hero")], [
        html.p([attribute.class("kicker")], [
          html.text(string.uppercase(data.kicker)),
        ]),
        html.h1([], [html.text(data.headline)]),
        html.p([attribute.class("lede")], [html.text(data.lede)]),
        html.ul(
          [attribute.class("pills")],
          list.map(["FOSS", "Rust first", "MPL-2.0", "made in Rio"], fn(p) {
            html.li([], [html.text(p)])
          }),
        ),
      ]),
      html.section([attribute.id("projects")], [
        html.h2([], [html.text("Projects")]),
        ..list.map(data.lanes, fn(lane) {
          html.section([attribute.class("lane")], [
            html.h3([], [html.text(lane.label)]),
            html.div(
              [attribute.class("cards")],
              list.map(parts.in_lane(lane.id), card),
            ),
          ])
        })
      ]),
    ]),
    html.footer([], [
      html.p([], [
        html.text("piabrota.art is served by "),
        html.a([attribute.href(parts.nixos)], [html.text("nix-os")]),
        html.text(", from /nix/store."),
      ]),
      html.p([], [html.text("Partnerships: " <> data.contact)]),
      parts.switcher("fabric"),
    ]),
  ])
}

fn card(p: Project) -> Element(msg) {
  html.article([attribute.class("card")], [
    html.h4([], [html.text(p.name)]),
    html.p([attribute.class("meta")], [html.text(p.lang <> " · " <> p.licence)]),
    html.p([attribute.class("blurb")], [html.text(p.blurb)]),
    html.p([attribute.class("at " <> parts.state_class(p.state))], [
      html.span([attribute.class("dot")], []),
      parts.address(p),
    ]),
  ])
}
