//// `gleam run -m piabrota_site/render/fabric_pt_br`: design A in pt-BR, rendered at build time.

import gleam/io
import piabrota_site/page

pub fn main() -> Nil {
  io.println(page.fabric_in("pt-BR"))
}
