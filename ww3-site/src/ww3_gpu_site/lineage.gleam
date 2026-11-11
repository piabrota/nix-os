//// The lineage page, /lineage/ and /pt-BR/lineage/: the works this one descends from or runs
//// beside, and its own releases, done and planned, on one line of time. Every event is a row of
//// site/data/lineage.tsv, read by site/content; nothing about a work is typed here (DESIGN.md,
//// "The lineage"). Prerendered by ww3_gpu_site/prerender_lineage; it needs no JavaScript.

import gleam/list
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import ww3_gpu_site/app.{t}
import ww3_gpu_site/content.{type Event}

pub fn view(l: String) -> Element(msg) {
  html.main([], [
    html.header([attribute.class("cover wrap")], [
      html.p([attribute.class("kicker")], [html.text("h0ffmann / ww3-gpu")]),
      html.h1([], [html.text(t(l, "lineage"))]),
      html.p([attribute.class("lede")], [
        html.text(t(
          l,
          "the works this one descends from or runs beside, on one line of time: the wave models, the ocean model, the weather models, the ports of models to other machines, and the releases of this work and its sister port in rust.",
        )),
      ]),
      html.nav([attribute.class("jump")], [
        html.a([attribute.href("../")], [html.text(t(l, "the front page"))]),
        html.a([attribute.href("#lineage")], [html.text(t(l, "the timeline"))]),
        other_language(l),
      ]),
    ]),
    html.section([attribute.id("lineage"), attribute.class("wrap")], [
      html.h2([], [html.text(t(l, "the timeline"))]),
      html.p([attribute.class("lede")], [
        html.text(t(l, "a dot in the blue light is a model;")),
        html.text(" "),
        html.text(t(
          l,
          "one in the amber light is a port, a model moved to other hardware or another language.",
        )),
        html.text(" "),
        html.text(t(
          l,
          "a hollow dot is planned, not done. each date is only as precise as its source.",
        )),
      ]),
      html.ol(
        [attribute.class("timeline")],
        list.map(content.events, event(l, _)),
      ),
    ]),
    html.footer([attribute.class("wrap foot")], [
      html.p([], [
        html.text(
          t(l, "every fact on this page was read from the repository at") <> " ",
        ),
        html.a([attribute.href(app.repo <> "/commit/" <> content.revision)], [
          html.text(content.revision),
        ]),
        html.text(". "),
        html.text(t(
          l,
          "to track a new work, add a row to site/data/lineage.tsv, with its date and its source.",
        )),
      ]),
    ]),
  ])
}

fn event(l: String, e: Event) -> Element(msg) {
  let planned = case e.status {
    "planned" -> [
      html.text(" "),
      html.span([attribute.class("chip code")], [html.text(t(l, "planned"))]),
    ]
    _ -> []
  }
  html.li([attribute.class("event " <> e.kind <> " " <> e.status)], [
    html.span([attribute.class("date")], [html.text(e.date)]),
    html.p([attribute.class("what")], [
      html.span([attribute.class("line")], [
        html.text(string.lowercase(e.line)),
      ]),
      html.text(" "),
      html.a([attribute.href(e.url)], [html.text(e.name)]),
      ..planned
    ]),
    html.p([attribute.class("aff")], [html.text(e.what)]),
    html.p([attribute.class("source")], [html.text(e.source)]),
  ])
}

/// The lineage in the other language, named in that language.
fn other_language(l: String) -> Element(msg) {
  let #(href, lang, name) = case l {
    "pt-BR" -> #("../../lineage/", "en", "english")
    _ -> #("../pt-BR/lineage/", "pt-BR", "português")
  }
  html.a(
    [
      attribute.href(href),
      attribute.attribute("hreflang", lang),
      attribute.attribute("lang", lang),
    ],
    [html.text(name)],
  )
}
