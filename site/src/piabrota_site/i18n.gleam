//// The site's languages. The strings live in site/locale/<lang>.json; site/data.nix compiles them
//// into data.locale. English is the source: another language falls back to it.

import piabrota_site/data

pub const english = "en"

/// Each language: its code, its name in its own words, and the page of design A.
pub const languages = [
  #("en", "English", "/"),
  #("pt-BR", "Português", "/pt-BR/"),
  #("zh-CN", "简体中文", "/zh-CN/"),
  #("ja-JP", "日本語", "/ja-JP/"),
]

/// A word of the page.
pub fn t(lang: String, key: String) -> String {
  case data.locale(lang, key) {
    "" -> data.locale(english, key)
    text -> text
  }
}

/// A fact of mockups/data.nix: `source` in English, the locale's words elsewhere.
pub fn fact(lang: String, key: String, source: String) -> String {
  case data.locale(lang, key) {
    "" -> source
    text -> text
  }
}
