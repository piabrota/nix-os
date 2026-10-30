//// `gleam run -m piabrota_site/prerender > dist/index.html`: the whole page, rendered once at
//// build time (default.nix). The VPS serves the result; it runs no Gleam and no node.

import gleam/io
import lustre/element
import piabrota_site/app
import piabrota_site/page

pub fn render() -> String {
  app.view()
  |> page.document
  |> element.to_document_string
}

pub fn main() -> Nil {
  io.println(render())
}
