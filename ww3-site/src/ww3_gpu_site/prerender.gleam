//// `gleam run -m ww3_gpu_site/prerender > dist/index.html`: the whole page in English, rendered
//// once at build time. It needs no JavaScript. ww3_gpu_site/prerender_pt_br writes the same page
//// in Brazilian Portuguese, for /pt-BR/.

import gleam/io
import lustre/element
import ww3_gpu_site/app
import ww3_gpu_site/page

pub fn render(l: String) -> String {
  app.view(l)
  |> page.document(l, _)
  |> element.to_document_string
}

pub fn main() -> Nil {
  io.println(render("en"))
}
