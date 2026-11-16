//// Design A, "fabric": the org as closed-source's page is built: the numbers, the tiles with their
//// tags, the anchors, and the sections in order. The tiles sit in the lanes of the profile's
//// "How it fits" figure. Served at /.

import gleam/list
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import piabrota_site/community
import piabrota_site/data.{type Service}
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
      community.projects(lang),
      ..community.sections(lang)
    ]),
    parts.foot("fabric", lang),
  ])
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
