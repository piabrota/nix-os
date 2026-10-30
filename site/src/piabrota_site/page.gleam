//// The HTML document around the page.

import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import piabrota_site/app

/// The browser bar follows the page's light or dark palette (static/style.css).
const light = "#fafaf7"

const dark = "#141414"

pub fn document(body: Element(msg)) -> Element(msg) {
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
  html.html([attribute.lang("pt-BR")], [
    html.head([], [
      html.meta([attribute.charset("utf-8")]),
      meta("viewport", "width=device-width, initial-scale=1"),
      html.title([], app.title),
      meta("description", app.description),
      theme(light, "light"),
      theme(dark, "dark"),
      // No favicon: an empty one stops the browser asking for /favicon.ico.
      html.link([attribute.rel("icon"), attribute.href("data:,")]),
      html.link([attribute.rel("stylesheet"), attribute.href("style.css")]),
    ]),
    html.body([], [body]),
  ])
}
