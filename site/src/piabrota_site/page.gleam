//// The HTML document around a page, and the pages as documents.

import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import piabrota_site/data
import piabrota_site/fabric as fabric_page
import piabrota_site/hermes as hermes_page
import piabrota_site/hosts as hosts_page
import piabrota_site/i18n
import piabrota_site/index as index_page
import piabrota_site/paths as paths_page

/// Design A at the root.
pub fn fabric() -> String {
  fabric_in("en")
}

/// Design A in a language: English at the root, the others at /<lang>/.
pub fn fabric_in(lang: String) -> String {
  let path = case lang {
    "en" -> "/"
    _ -> "/" <> lang <> "/"
  }
  document("fabric", lang, path, "piabrota", fabric_page.view(lang))
}

/// Design B at /index/.
pub fn index() -> String {
  document("index", "en", "/index/", "piabrota · index", index_page.view())
}

/// Design C at /paths/.
pub fn paths() -> String {
  document("paths", "en", "/paths/", "piabrota · paths", paths_page.view())
}

/// Hermes's configuration at /hermes/.
pub fn hermes() -> String {
  document("hermes", "en", "/hermes/", "piabrota · hermes", hermes_page.view())
}

/// What each of the two VPSs runs, at /hosts/.
pub fn hosts() -> String {
  document("hosts", "en", "/hosts/", "piabrota · hosts", hosts_page.view())
}

/// Where the pages live (site.nix's `domain`). Link previews need absolute https addresses.
pub const origin = "https://www.piabrota.art"

/// The link preview, 1200x627 (1.91:1), drawn from og/og.svg by default.nix. LinkedIn takes the
/// apple-touch-icon (180 px) when a page names no og:image, and shows it blurred.
pub const og_image = "/og.png"

const og_alt =
  "The piabrota eye, red and green, beside the words: piabrota, open software, made in Rio de Janeiro."

fn og_locale(lang: String) -> String {
  case lang {
    "pt-BR" -> "pt_BR"
    "zh-CN" -> "zh_CN"
    "ja-JP" -> "ja_JP"
    _ -> "en_US"
  }
}

/// `design` names the body's class in style.css. The fonts are the sister sites' (picasso,
/// gramatico, closed-source), from Google Fonts; the system fonts stand in until they load.
fn document(
  design: String,
  lang: String,
  path: String,
  title: String,
  body: Element(msg),
) -> String {
  let meta = fn(name, value) {
    html.meta([attribute.name(name), attribute.content(value)])
  }
  let property = fn(name, value) {
    html.meta([attribute.attribute("property", name), attribute.content(value)])
  }
  let description =
    data.name
    <> ": "
    <> i18n.fact(lang, "org.kicker", data.kicker)
    <> ". "
    <> i18n.fact(lang, "org.lede", data.lede)
  // "piabrota" alone says little in a link preview: design A adds the kicker.
  let share_title = case design {
    "fabric" -> data.name <> " · " <> i18n.fact(lang, "org.kicker", data.kicker)
    _ -> title
  }
  let theme = fn(colour, scheme) {
    html.meta([
      attribute.name("theme-color"),
      attribute.content(colour),
      attribute.attribute("media", "(prefers-color-scheme: " <> scheme <> ")"),
    ])
  }
  html.html([attribute.lang(lang)], [
    html.head([], [
      html.meta([attribute.charset("utf-8")]),
      meta("viewport", "width=device-width, initial-scale=1"),
      html.title([], title),
      meta("description", description),
      // Both schemes, so the browser paints the right canvas before style.css arrives.
      meta("color-scheme", "dark light"),
      theme("#0B0D12", "dark"),
      theme("#FFFFFF", "light"),
      html.link([attribute.rel("canonical"), attribute.href(origin <> path)]),
      property("og:type", "website"),
      property("og:site_name", data.name),
      property("og:locale", og_locale(lang)),
      property("og:url", origin <> path),
      property("og:title", share_title),
      property("og:description", description),
      property("og:image", origin <> og_image),
      property("og:image:secure_url", origin <> og_image),
      property("og:image:type", "image/png"),
      property("og:image:width", "1200"),
      property("og:image:height", "627"),
      property("og:image:alt", og_alt),
      meta("twitter:card", "summary_large_image"),
      meta("twitter:title", share_title),
      meta("twitter:description", description),
      meta("twitter:image", origin <> og_image),
      meta("twitter:image:alt", og_alt),
      // The org's mark is the icon of every site under piabrota.art (favicon/, favicon.nix).
      html.link([
        attribute.rel("icon"),
        attribute.attribute("type", "image/svg+xml"),
        attribute.href("/favicon.svg"),
      ]),
      html.link([
        attribute.rel("icon"),
        attribute.href("/favicon.ico"),
        attribute.attribute("sizes", "48x48"),
      ]),
      html.link([
        attribute.rel("apple-touch-icon"),
        attribute.href("/apple-touch-icon.png"),
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
