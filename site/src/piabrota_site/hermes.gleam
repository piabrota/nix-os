//// /hermes: Hermes Agent as nix-os runs it. The YAML is site/hermes.nix's, written from the
//// evaluated hermes.nix at build time, so the page follows every change to it. English only.

import gleam/list
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import piabrota_site/data
import piabrota_site/marks
import piabrota_site/parts

pub const module = "https://github.com/piabrota/nix-os/blob/main/hermes.nix"

pub const doc = "https://github.com/piabrota/nix-os/blob/main/docs/HERMES.md"

pub fn view() -> Element(msg) {
  html.div([], [
    parts.top("hermes", "en", [
      html.div([], [
        parts.eyebrow("piabrota.art · think and write"),
        html.h1([], [
          html.text("hermes "),
          html.span([], [html.text("· on nix-os")]),
        ]),
        html.p([attribute.class("lede")], [
          html.text(
            "Nous Research's Hermes Agent runs on KVM 4, the second VPS, as one systemd unit, with Claude through the owner's subscription. Below is its configuration as Hermes reads it, in YAML, written from hermes.nix when the site is built.",
          ),
        ]),
        facts(),
        html.div([attribute.class("actions")], [
          parts.button("#config", "Read the config ↓", True),
          parts.button(module, "hermes.nix ↗", False),
          parts.button(doc, "docs/HERMES.md ↗", False),
          parts.button("/hosts", "Which host →", False),
        ]),
      ]),
      html.figure([attribute.class("drawing")], [
        marks.hermes(176),
        html.figcaption([], [html.text("the hermes mark · the messenger")]),
      ]),
    ]),
    html.main([], case data.hermes_config {
      "" -> [
        html.section([attribute.class("wrap")], [
          html.p([attribute.class("sub")], [
            html.text("Hermes is off on this system."),
          ]),
        ]),
      ]
      config -> [
        html.section([attribute.class("wrap"), attribute.id("config")], [
          parts.section_head("config.yaml", "from hermes.nix"),
          html.p([attribute.class("sub")], [
            html.text(
              "The keys nix-os owns. On every activation they are merged into /var/lib/hermes/.hermes/config.yaml, which also keeps the keys Hermes writes itself.",
            ),
          ]),
          terminal("/var/lib/hermes/.hermes/config.yaml", config),
        ]),
        html.section([attribute.class("wrap"), attribute.id("unit")], [
          parts.section_head("The unit", "how nix-os runs it"),
          html.p([attribute.class("sub")], [
            html.text(
              "The package, its limits, and what is installed beside the config. A merge to main deploys it.",
            ),
          ]),
          terminal("hermes-agent.service", data.hermes_service),
          html.p([attribute.class("sub")], [
            html.a([attribute.href(data.hermes_upstream)], [
              html.text("The upstream commit the flake pins ↗"),
            ]),
          ]),
        ]),
        html.section([attribute.class("wrap"), attribute.id("secrets")], [
          parts.section_head("Not shown", "secrets"),
          html.p([attribute.class("sub")], [
            html.text(
              "The Claude token, the chat platforms' tokens and the allowed users live only on the box, in a root-only file that Nix never reads. A key that names a token, a key, a secret, a password or allowed users is dropped before the page is built, and the build stops if one gets through.",
            ),
          ]),
        ]),
      ]
    }),
    parts.foot("hermes", "en"),
  ])
}

/// The hero's facts, from site/hermes.nix.
fn facts() -> Element(msg) {
  html.dl([attribute.class("metrics hermes-facts")], {
    use #(label, value) <- list.map(data.hermes_facts)
    html.div([], [
      html.dt([], [html.text(label)]),
      html.dd([], [html.text(value)]),
    ])
  })
}

fn terminal(title: String, text: String) -> Element(msg) {
  html.div([attribute.class("terminal")], [
    html.div([attribute.class("term-bar")], [
      html.span([attribute.class("dots")], [
        html.i([], []),
        html.i([], []),
        html.i([], []),
      ]),
      html.span([], [html.text(title)]),
    ]),
    html.pre([attribute.class("yaml")], [html.code([], [html.text(text)])]),
  ])
}
