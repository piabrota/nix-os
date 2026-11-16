//// `gleam run -m ww3_gpu_site/prerender_ja_jp > dist/ja-JP/index.html`: the page in Japanese,
//// from the same source as the English one (app.t).

import gleam/io
import ww3_gpu_site/prerender

pub fn main() -> Nil {
  io.println(prerender.render("ja-JP"))
}
