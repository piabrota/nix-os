//// Design C, "paths": the first page grown by one block. 无 (the README drawing) and the name stay;
//// below them, a listing of what answers on piabrota.art and where the rest lives. At /paths/.

import gleam/list
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import piabrota_site/data.{type Project}
import piabrota_site/parts

pub fn view() -> Element(msg) {
  let #(here, away) = list.partition(data.projects, is_here)
  html.main([attribute.class("column")], [
    // The drawing from docs/drawings/mu.svg, copied next to the page by default.nix.
    html.img([
      attribute.src("/mu.svg"),
      attribute.alt("无, mu, brushed in its four strokes"),
      attribute.width(150),
      attribute.height(150),
      attribute.class("mu"),
    ]),
    html.p([attribute.class("name")], [html.text(data.name)]),
    html.section(
      [attribute.class("terminal"), attribute.aria_label("listing")],
      [
        html.div([attribute.class("dots")], [
          html.span([], []),
          html.span([], []),
          html.span([], []),
        ]),
        block("ls piabrota.art/", here),
        block("ls elsewhere/", away),
      ],
    ),
    html.p([attribute.class("links")], [
      html.a([attribute.href("https://github.com/piabrota")], [
        html.text("github"),
      ]),
      html.text(" · "),
      html.a([attribute.href("https://opencollective.com/piabrota")], [
        html.text("open collective"),
      ]),
      html.text(" · "),
      html.a([attribute.href("https://github.com/sponsors/h0ffmann")], [
        html.text("sponsors"),
      ]),
    ]),
    parts.switcher("paths"),
  ])
}

fn is_here(p: Project) -> Bool {
  case p.where {
    "piabrota.art/" <> _ -> True
    _ -> False
  }
}

fn block(prompt: String, projects: List(Project)) -> Element(msg) {
  html.div([], [
    html.p([attribute.class("prompt")], [html.text("$ " <> prompt)]),
    html.ul(
      [],
      list.map(projects, fn(p) {
        html.li([], [
          case is_here(p) {
            True ->
              case p.href {
                "" ->
                  html.span([attribute.class("where")], [html.text(path(p))])
                href ->
                  html.a([attribute.class("where"), attribute.href(href)], [
                    html.text(path(p)),
                  ])
              }
            False -> parts.address(p)
          },
          html.span([attribute.class("who")], [html.text(p.name)]),
          html.span([attribute.class(parts.state_class(p.state))], [
            html.text(parts.state_name(p.state)),
          ]),
        ])
      }),
    ),
  ])
}

/// piabrota.art/nixos → /nixos
fn path(p: Project) -> String {
  case p.where {
    "piabrota.art" <> rest -> rest
    other -> other
  }
}
