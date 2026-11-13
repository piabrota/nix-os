//// Design B, "index": the wordmark, then the project tiles and the rest with nothing before them.
//// Served at /index/.

import gleam/int
import gleam/list
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import piabrota_site/community
import piabrota_site/data
import piabrota_site/parts

pub fn view() -> Element(msg) {
  html.div([], [
    parts.top("index", "en", [
      html.div([], [
        parts.eyebrow(
          "index · " <> int.to_string(list.length(data.projects)) <> " projects",
        ),
        html.h1([attribute.class("wordmark")], [
          html.text(string.uppercase(data.name)),
        ]),
        html.p([attribute.class("lede")], [html.text(data.lede)]),
        parts.metrics("en"),
        parts.status("en"),
        parts.buttons(#("#projects", "See the projects ↓"), "en"),
      ]),
    ]),
    html.main([], [community.projects("en"), ..community.sections("en")]),
    parts.foot("index", "en"),
  ])
}
