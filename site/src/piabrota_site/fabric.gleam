//// Design A, "fabric": the org as closed-source's page is built: the numbers, the tiles with their
//// tags, the anchors, and the sections in order. The tiles sit in the lanes of the profile's
//// "How it fits" figure. Served at /.

import gleam/int
import gleam/list
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import piabrota_site/community
import piabrota_site/data.{type Closed, type Project, type Service}
import piabrota_site/i18n
import piabrota_site/marks
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
      services(lang),
      html.section([attribute.class("wrap"), attribute.id("projects")], [
        parts.section_head(
          i18n.t(lang, "head.projects"),
          i18n.t(lang, "note.projects"),
        ),
        html.p([attribute.class("sub")], [
          html.text(i18n.t(lang, "sub.projects")),
        ]),
        ..list.append(
          list.map(data.lanes, fn(lane) {
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
          }),
          closed_lane(lang),
        )
      ]),
      ..community.sections(lang)
    ]),
    parts.foot("fabric", lang),
  ])
}

/// The projects that are not FOSS yet. Their tiles link nowhere: the repositories are private.
/// With none, there is no lane.
fn closed_lane(lang: String) -> List(Element(msg)) {
  case data.closed {
    [] -> []
    closed -> [
      html.div([attribute.class("lane")], [
        html.h3([], [
          html.text(i18n.t(lang, "closed.lane")),
          html.span([attribute.class("count")], [
            html.text(int.to_string(list.length(closed))),
          ]),
        ]),
        html.ul(
          [attribute.class("tiles")],
          list.map(closed, closed_tile(_, lang)),
        ),
      ]),
    ]
  }
}

fn closed_tile(p: Closed, lang: String) -> Element(msg) {
  html.li([attribute.class("tile"), attribute.data("name", p.name)], [
    html.div([attribute.class("tile-top")], [
      html.span(
        [attribute.class("project-logo glyph"), attribute.aria_hidden(True)],
        [html.text(p.glyph)],
      ),
      html.div([attribute.class("tile-tags")], [
        html.span([], [html.text(i18n.t(lang, "closed.tag"))]),
        html.span([], [html.text(p.lang)]),
      ]),
    ]),
    html.h4([], [html.text(p.name)]),
    html.p([attribute.class("blurb")], [
      html.text(i18n.fact(lang, "project." <> p.name, p.blurb)),
    ]),
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
      paper(p, lang),
      parts.commits(p, lang),
    ],
  )
}

/// The paper badge, "aiXiv 2611.01105", linked to its abstract page; nothing without a paper.
fn paper(p: Project, lang: String) -> Element(msg) {
  case string.split_once(p.paper, "/abs/") {
    Error(Nil) -> element.none()
    Ok(#(_, id)) ->
      html.a(
        [
          attribute.class("paper"),
          attribute.href(p.paper),
          attribute.title(i18n.t(lang, "paper.title")),
        ],
        [
          html.span([attribute.class("paper-label")], [html.text("aiXiv")]),
          html.text(" " <> id),
        ],
      )
  }
}

fn tile_href(p: Project) -> String {
  case p.href {
    "" -> p.repo
    href -> href
  }
}

/// What piabrota2 serves on its own names: one link card each, with its mark and whether it needs
/// the login.
fn services(lang: String) -> Element(msg) {
  html.section([attribute.class("wrap"), attribute.id("services")], [
    parts.section_head(
      i18n.t(lang, "head.services"),
      i18n.t(lang, "note.services"),
    ),
    html.ul(
      [attribute.class("services")],
      list.map(data.services, service(_, lang)),
    ),
  ])
}

fn service(s: Service, lang: String) -> Element(msg) {
  let mark = case marks.for(s.name, 52) {
    Ok(mark) -> mark
    Error(Nil) -> element.none()
  }
  html.li([attribute.class("service"), attribute.data("name", s.name)], [
    mark,
    html.div([attribute.class("service-body")], [
      html.h3([], [
        html.a(
          [
            attribute.class("tile-link"),
            attribute.href("https://" <> s.host <> "/"),
          ],
          [html.text(s.label)],
        ),
        html.span([attribute.class("access is-" <> s.access)], [
          html.text(i18n.t(lang, "access." <> s.access)),
        ]),
      ]),
      html.p([attribute.class("blurb")], [
        html.text(i18n.fact(lang, "service." <> s.name, s.blurb)),
      ]),
      html.span([attribute.class("host")], [html.text(s.host <> " ↗")]),
    ]),
  ])
}
