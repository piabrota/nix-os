//// `gleam run -m piabrota_site/render/fabric_ja_jp`: design A in ja-JP, rendered at build time.

import gleam/io
import piabrota_site/page

pub fn main() -> Nil {
  io.println(page.fabric_in("ja-JP"))
}
