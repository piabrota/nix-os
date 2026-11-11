//// `gleam run -m ww3_gpu_site/prerender_lineage > dist/lineage/index.html`: the lineage page in
//// English. ww3_gpu_site/prerender_lineage_pt_br writes it in Brazilian Portuguese.

import gleam/io
import lustre/element
import ww3_gpu_site/app
import ww3_gpu_site/lineage
import ww3_gpu_site/page

pub fn render(l: String) -> String {
  lineage.view(l)
  |> page.document_at(
    l,
    "lineage/",
    "ww3-gpu: " <> app.t(l, "lineage"),
    app.t(
      l,
      "the works ww3-gpu descends from or runs beside, and its releases, on one line of time.",
    ),
    _,
  )
  |> element.to_document_string
}

pub fn main() -> Nil {
  io.println(render("en"))
}
