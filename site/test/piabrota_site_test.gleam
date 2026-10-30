import gleam/string
import gleeunit
import piabrota_site/prerender

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn document_test() {
  let page = prerender.render()
  assert string.starts_with(string.lowercase(page), "<!doctype html>")
  assert string.contains(page, "<html lang=\"pt-BR\">")
  assert string.contains(page, "<title>piabrota</title>")
  assert string.contains(page, "href=\"style.css\"")
}

// The README links piabrota.art/nixos; site.nix redirects it, and the page links it too.
pub fn nixos_link_test() {
  assert string.contains(prerender.render(), "href=\"/nixos\"")
}

// 无 is marked as Chinese and kept out of machine translation.
pub fn mu_test() {
  let page = prerender.render()
  assert string.contains(page, "无")
  assert string.contains(page, "lang=\"zh-Hans\"")
  assert string.contains(page, "translate=\"no\"")
}

// Both palettes reach the browser bar.
pub fn theme_color_test() {
  let page = prerender.render()
  assert string.contains(page, "(prefers-color-scheme: light)")
  assert string.contains(page, "(prefers-color-scheme: dark)")
}

// Prerendered: no script, so the page works with JavaScript off.
pub fn no_script_test() {
  assert !string.contains(prerender.render(), "<script")
}
