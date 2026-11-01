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
import piabrota_site/i18n
import piabrota_site/parts

pub fn view(lang: String) -> Element(msg) {
  html.div([], [
    parts.top("fabric", lang, [
      html.div([], [
        parts.eyebrow(i18n.fact(lang, "org.kicker", data.kicker)),
        html.h1([], [
          html.text(i18n.t(lang, "hero.line1")),
          html.span([], [html.text(i18n.t(lang, "hero.line2"))]),
        ]),
        html.p([attribute.class("lede")], [
          html.text(i18n.fact(lang, "org.lede", data.lede)),
        ]),
        parts.metrics(lang),
        parts.status(lang),
        parts.buttons(#("#projects", i18n.t(lang, "hero.cta")), lang),
      ]),
      html.figure([attribute.class("drawing")], [
        parts.eye(176),
        html.figcaption([], [html.text(i18n.t(lang, "hero.mark"))]),
      ]),
    ]),
    html.main([], [
      html.section([attribute.class("wrap"), attribute.id("projects")], [
        parts.section_head(
          i18n.t(lang, "head.projects"),
          i18n.t(lang, "note.projects"),
        ),
        html.p([attribute.class("sub")], [
          html.text(i18n.t(lang, "sub.projects")),
        ]),
        ..list.map(data.lanes, fn(lane) {
          let projects = parts.in_lane(lane.id)
          html.div([attribute.class("lane")], [
            html.h3([], [
              html.text(i18n.fact(lang, "lane." <> lane.id, lane.label)),
              html.span([attribute.class("count")], [
                html.text(int.to_string(list.length(projects))),
              ]),
            ]),
            html.ul(
              [attribute.class("tiles")],
              list.map(projects, tile(_, lang)),
            ),
          ])
        })
      ]),
      ..community.sections(lang)
    ]),
    parts.foot("fabric", lang),
  ])
}

/// A tile: the tags, the name, the blurb. The name's link covers the whole tile, as on
/// closed-source; `tile_href` always has somewhere to go.
fn tile(p: Project, lang: String) -> Element(msg) {
  html.li(
    [
      attribute.class("tile"),
      attribute.data("state", parts.state_class(p.state)),
      attribute.data("name", p.name),
    ],
    [
      html.div([attribute.class("tile-top")], [
        parts.logo(p),
        html.div([attribute.class("tile-tags")], [
          parts.pill(p.state, lang),
          html.span([], [html.text(p.lang)]),
          html.span([], [html.text(i18n.t(lang, "origin." <> p.origin))]),
        ]),
      ]),
      html.h4([], [
        html.a([attribute.class("tile-link"), attribute.href(tile_href(p))], [
          html.text(p.name),
        ]),
      ]),
      html.p([attribute.class("blurb")], [
        html.text(i18n.fact(lang, "project." <> p.name, p.blurb)),
      ]),
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
