//// Design C, "paths": the first page grown up. 无 (the README drawing) beside the name, and a
//// terminal listing of what answers on piabrota.art and where the rest lives. Served at /paths/.

import gleam/list
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import piabrota_site/community
import piabrota_site/data.{type Project}
import piabrota_site/parts

pub fn view() -> Element(msg) {
  let #(here, away) = list.partition(data.projects, is_here)
  html.div([], [
    parts.top("paths", [
      html.div([], [
        parts.eyebrow("piabrota.art · " <> data.kicker),
        html.h1([], [
          html.text(data.name <> " "),
          html.span([], [html.text("· what answers where")]),
        ]),
        html.p([attribute.class("lede")], [
          html.text(
            "Some projects answer here, on a path of piabrota.art; the rest live on their own sites or in their repositories.",
          ),
        ]),
        parts.status(),
        parts.buttons(#("#ls", "List the paths ↓")),
      ]),
      // The drawing from docs/drawings/mu.svg, copied next to the page by default.nix.
      html.figure([attribute.class("drawing")], [
        html.img([
          attribute.src("/mu.svg"),
          attribute.alt("无, mu, brushed in its four strokes"),
          attribute.width(200),
          attribute.height(200),
        ]),
        html.figcaption([], [html.text("无 · mu, no thing")]),
      ]),
    ]),
    html.main([], [
      html.section([attribute.class("wrap"), attribute.id("ls")], [
        parts.section_head("Paths", "ls, two places"),
        html.div(
          [attribute.class("terminal"), attribute.aria_label("Listing")],
          [
            html.div([attribute.class("term-bar")], [
              html.span([attribute.class("dots")], [
                html.i([], []),
                html.i([], []),
                html.i([], []),
              ]),
              html.span([], [html.text("piabrota.art — ls")]),
            ]),
            block("ls piabrota.art/", here),
            block("ls elsewhere/", away),
          ],
        ),
      ]),
      ..community.sections()
    ]),
    parts.foot("paths"),
  ])
}

fn is_here(p: Project) -> Bool {
  case p.where {
    "piabrota.art/" <> _ -> True
    _ -> False
  }
}

fn block(prompt: String, projects: List(Project)) -> Element(msg) {
  html.div([attribute.class("term-block")], [
    html.p([attribute.class("prompt")], [
      html.span([], [html.text("$ ")]),
      html.text(prompt),
    ]),
    html.ul([], {
      use p <- list.map(projects)
      html.li([attribute.data("state", parts.state_class(p.state))], [
        case is_here(p), p.href {
          True, "" ->
            html.span([attribute.class("where")], [html.text(path(p))])
          True, href ->
            html.a([attribute.class("where"), attribute.href(href)], [
              html.text(path(p)),
            ])
          False, _ -> parts.address(p)
        },
        html.span([attribute.class("who")], [html.text(p.name)]),
        parts.pill(p.state),
      ])
    }),
  ])
}

/// piabrota.art/nixos → /nixos
fn path(p: Project) -> String {
  case p.where {
    "piabrota.art" <> rest -> rest
    other -> other
  }
}
