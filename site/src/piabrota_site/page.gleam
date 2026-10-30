//// The HTML document around a page, and the three pages as documents.

import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import piabrota_site/data
import piabrota_site/fabric as fabric_page
import piabrota_site/index as index_page
import piabrota_site/paths as paths_page

/// Design A at the root.
pub fn fabric() -> String {
  document("fabric", "#0B0D12", fabric_page.view())
}

/// Design B at /index/.
pub fn index() -> String {
  document("index", "#FAFAF7", index_page.view())
}

/// Design C at /paths/.
pub fn paths() -> String {
  document("paths", "#FAFAF7", paths_page.view())
}

/// `design` names the body's class in style.css; `bar` colours the browser bar.
fn document(design: String, bar: String, body: Element(msg)) -> String {
  let meta = fn(name, value) {
    html.meta([attribute.name(name), attribute.content(value)])
  }
  html.html([attribute.lang("en")], [
    html.head([], [
      html.meta([attribute.charset("utf-8")]),
      meta("viewport", "width=device-width, initial-scale=1"),
      html.title([], data.name),
      meta("description", data.name <> ": " <> data.kicker),
      meta("theme-color", bar),
      // No favicon: an empty one stops the browser asking for /favicon.ico.
      html.link([attribute.rel("icon"), attribute.href("data:,")]),
      html.link([attribute.rel("stylesheet"), attribute.href("/style.css")]),
    ]),
    html.body([attribute.class(design)], [body]),
  ])
  |> element.to_document_string
}
