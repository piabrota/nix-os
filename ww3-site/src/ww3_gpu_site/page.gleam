//// The HTML document around the page, in language `l` (app.t).

import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import ww3_gpu_site/app

/// Where the site is published. A link preview needs whole addresses.
pub const address = "https://wave.piabrota.art/"

/// The address of the page in language `l`: the English one at the root, the other under its
/// language's name.
pub fn address_of(l: String) -> String {
  case l {
    "en" -> address
    _ -> address <> l <> "/"
  }
}

pub fn document(l: String, body: Element(msg)) -> Element(msg) {
  let title = "ww3-gpu: " <> app.t(l, "page.title")
  let description = app.t(l, "page.description")
  document_at(l, "", title, description, body)
}

/// The document of a page at `path` under the page of language `l` ("" for the front page,
/// "lineage/" for the lineage), with its own title and description.
pub fn document_at(
  l: String,
  path: String,
  title: String,
  description: String,
  body: Element(msg),
) -> Element(msg) {
  let root = case path {
    "" -> app.up(l)
    _ -> "../" <> app.up(l)
  }
  let meta = fn(name, value) {
    html.meta([attribute.name(name), attribute.content(value)])
  }
  let property = fn(name, value) {
    html.meta([attribute.attribute("property", name), attribute.content(value)])
  }
  let stylesheet = fn(href) {
    html.link([attribute.rel("stylesheet"), attribute.href(href)])
  }
  let alternate = fn(lang) {
    html.link([
      attribute.rel("alternate"),
      attribute.attribute("hreflang", lang),
      attribute.href(address_of(lang) <> path),
    ])
  }
  html.html([attribute.lang(l)], [
    html.head([], [
      html.meta([attribute.charset("utf-8")]),
      meta("viewport", "width=device-width, initial-scale=1"),
      html.title([], title),
      meta("description", description),
      meta("author", "Matheus Hoffmann"),
      html.link([
        attribute.rel("canonical"),
        attribute.href(address_of(l) <> path),
      ]),
      alternate("en"),
      alternate("pt-BR"),
      alternate("zh-CN"),
      alternate("ja-JP"),
      property("og:title", title),
      property("og:description", description),
      property("og:type", "website"),
      property("og:url", address_of(l) <> path),
      html.link([
        attribute.rel("icon"),
        attribute.href(root <> "favicon.svg"),
        attribute.type_("image/svg+xml"),
      ]),
      html.link([
        attribute.rel("preconnect"),
        attribute.href("https://fonts.googleapis.com"),
      ]),
      html.link([
        attribute.rel("preconnect"),
        attribute.href("https://fonts.gstatic.com"),
        attribute.crossorigin(""),
      ]),
      stylesheet(
        "https://fonts.googleapis.com/css2?family=Amiri:wght@400;700&family=Mulish:wght@400;700&display=swap",
      ),
      stylesheet(root <> "style.css"),
    ]),
    html.body([], [body]),
  ])
}
