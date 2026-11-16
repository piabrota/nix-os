//// `gleam run -m ww3_gpu_site/prerender_lineage_pt_br > dist/pt-BR/lineage/index.html`.

import gleam/io
import ww3_gpu_site/prerender_lineage

pub fn main() -> Nil {
  io.println(prerender_lineage.render("pt-BR"))
}
