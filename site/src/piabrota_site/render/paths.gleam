//// `gleam run -m piabrota_site/render/paths`: the paths page, rendered once at build time
//// (default.nix). The VPS serves the result; it runs no Gleam and no node.

import gleam/io
import piabrota_site/page

pub fn main() -> Nil {
  io.println(page.paths())
}
