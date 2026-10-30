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
  document("fabric", "piabrota", fabric_page.view())
}

/// Design B at /index/.
pub fn index() -> String {
  document("index", "piabrota · index", index_page.view())
}

/// Design C at /paths/.
pub fn paths() -> String {
  document("paths", "piabrota · paths", paths_page.view())
}

/// `design` names the body's class in style.css. The fonts are the sister sites' (picasso,
/// gramatico, closed-source), from Google Fonts; the system fonts stand in until they load.
fn document(design: String, title: String, body: Element(msg)) -> String {
  let meta = fn(name, value) {
    html.meta([attribute.name(name), attribute.content(value)])
  }
  let theme = fn(colour, scheme) {
    html.meta([
      attribute.name("theme-color"),
      attribute.content(colour),
      attribute.attribute("media", "(prefers-color-scheme: " <> scheme <> ")"),
    ])
  }
  html.html([attribute.lang("en")], [
    html.head([], [
      html.meta([attribute.charset("utf-8")]),
      meta("viewport", "width=device-width, initial-scale=1"),
      html.title([], title),
      meta("description", data.name <> ": " <> data.kicker <> ". " <> data.lede),
      theme("#0B0D12", "dark"),
      theme("#FFFFFF", "light"),
      // No favicon: an empty one stops the browser asking for /favicon.ico.
      html.link([attribute.rel("icon"), attribute.href("data:,")]),
      html.link([
        attribute.rel("preconnect"),
        attribute.href("https://fonts.googleapis.com"),
      ]),
      html.link([
        attribute.rel("preconnect"),
        attribute.href("https://fonts.gstatic.com"),
        attribute.crossorigin(""),
      ]),
      html.link([
        attribute.rel("stylesheet"),
        attribute.href(
          "https://fonts.googleapis.com/css2?family=Fjalla+One&family=Inter:wght@400;600&family=JetBrains+Mono&display=swap",
        ),
      ]),
      html.link([attribute.rel("stylesheet"), attribute.href("/style.css")]),
      ..analytics(data.analytics_id)
    ]),
    html.body([attribute.class(design)], [body]),
  ])
  |> element.to_document_string
}

/// Google's tag (gtag.js) for a GA4 measurement ID, or nothing when the ID is "": then the page
/// loads no script at all. The ID comes from piabrota.site.analytics.measurementId (site.nix).
pub fn analytics(id: String) -> List(Element(msg)) {
  case id {
    "" -> []
    id -> [
      html.script(
        [
          attribute.attribute("async", ""),
          attribute.src("https://www.googletagmanager.com/gtag/js?id=" <> id),
        ],
        "",
      ),
      html.script(
        [],
        "window.dataLayer = window.dataLayer || [];\nfunction gtag(){dataLayer.push(arguments);}\ngtag('js', new Date());\ngtag('config', '"
          <> id
          <> "');",
      ),
    ]
  }
}
