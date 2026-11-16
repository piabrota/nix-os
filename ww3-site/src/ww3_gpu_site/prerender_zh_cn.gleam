//// `gleam run -m ww3_gpu_site/prerender_zh_cn > dist/zh-CN/index.html`: the page in Simplified Chinese,
//// from the same source as the English one (app.t).

import gleam/io
import ww3_gpu_site/prerender

pub fn main() -> Nil {
  io.println(prerender.render("zh-CN"))
}
