//// `gleam run -m piabrota_site/render/fabric_zh_cn`: design A in zh-CN, rendered at build time.

import gleam/io
import piabrota_site/page

pub fn main() -> Nil {
  io.println(page.fabric_in("zh-CN"))
}
