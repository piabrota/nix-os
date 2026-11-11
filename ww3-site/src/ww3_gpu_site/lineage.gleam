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
  app.frame(l, "../", [
    html.header([], [html.h1([], [html.text(t(l, "lineage"))])]),
    html.div([attribute.class("content")], [
      html.p([], [
        html.text(t(
          l,
          "the works this one descends from or runs beside, on one line of time: the wave models, the ocean model, the weather models, the ports of models to other machines, and the releases of this work and its sister port in rust.",
        )),
      ]),
      html.section([attribute.id("lineage")], [
        html.h2([], [html.text(t(l, "the timeline"))]),
        html.p([], [
          html.text(t(
            l,
            "each date is only as precise as its source; a planned event is marked so.",
          )),
        ]),
        html.ul(
          [attribute.class("records")],
          list.map(content.events, event(l, _)),
        ),
      ]),
    ]),
    html.footer([attribute.class("foot")], [
      html.p([], [
        html.text(
          t(l, "every fact on this page was read from the repository at") <> " ",
        ),
        html.a([attribute.href(app.repo <> "/commit/" <> content.revision)], [
          html.text(content.revision),
        ]),
        html.text("."),
      ]),
      app.credit(l),
    ]),
  ])
}

fn event(l: String, e: Event) -> Element(msg) {
  let planned = case e.status {
    "planned" -> " (" <> t(l, "planned") <> ")"
    _ -> ""
  }
  html.li([], [
    html.text(string.lowercase(e.line) <> ": "),
    html.a([attribute.href(e.url)], [html.text(e.name)]),
    html.text(planned),
    html.span([attribute.class("date")], [html.text(e.date)]),
    html.br([]),
    html.small([], [html.text(e.what <> " · " <> e.source)]),
  ])
}
