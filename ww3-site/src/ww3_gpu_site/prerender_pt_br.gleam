//// `gleam run -m ww3_gpu_site/prerender_pt_br > dist/pt-BR/index.html`: the page in Brazilian
//// Portuguese, from the same source as the English one (app.t).

import gleam/io
import ww3_gpu_site/prerender

pub fn main() -> Nil {
  io.println(prerender.render("pt-BR"))
}
