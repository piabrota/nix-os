//// The page. It is prerendered and loads no JavaScript.

import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

pub const title = "piabrota"

pub const description = "piabrota.art"

/// site.nix answers this path with a redirect to the repository.
pub const nixos = "/nixos"

pub fn view() -> Element(msg) {
  html.main([], [
    // 无 (mu), the README drawing: Chinese, and never machine-translated.
    html.h1(
      [attribute.lang("zh-Hans"), attribute.attribute("translate", "no")],
      [html.text("无")],
    ),
    html.p([], [html.text(title)]),
    html.p([], [html.a([attribute.href(nixos)], [html.text("nix-os")])]),
  ])
}
