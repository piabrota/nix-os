import gleam/list
import gleam/string
import gleeunit
import piabrota_site/data
import piabrota_site/page

pub fn main() -> Nil {
  gleeunit.main()
}

fn pages() -> List(#(String, String)) {
  [
    #("fabric", page.fabric()),
    #("index", page.index()),
    #("paths", page.paths()),
  ]
}

pub fn documents_test() {
  list.each(pages(), fn(p) {
    let #(design, html) = p
    assert string.starts_with(string.lowercase(html), "<!doctype html>")
    assert string.contains(html, "<html lang=\"en\">")
    assert string.contains(html, "<body class=\"" <> design <> "\">")
    assert string.contains(html, "href=\"/style.css\"")
  })
}

// Every page names every project of the org profile, and says what it is or where it meets the web.
pub fn every_project_test() {
  assert data.projects != []
  list.each(pages(), fn(p) {
    list.each(data.projects, fn(project) {
      assert string.contains(p.1, project.name)
      // Design C lists a path here without the domain: /nixos for piabrota.art/nixos.
      assert string.contains(p.1, project.blurb)
        || string.contains(p.1, project.where)
        || string.contains(
          p.1,
          string.replace(project.where, "piabrota.art", ""),
        )
    })
  })
}

// Every page links the other two, and marks itself as the current one.
pub fn switcher_test() {
  list.each(pages(), fn(p) {
    let #(design, html) = p
    assert string.contains(html, "href=\"/\"")
    assert string.contains(html, "href=\"/index/\"")
    assert string.contains(html, "href=\"/paths/\"")
    assert string.contains(html, "aria-current=\"page\"")
    assert string.contains(html, "· " <> design <> "</a>")
  })
}

// The README links piabrota.art/nixos; site.nix redirects it, and the pages link it.
pub fn nixos_link_test() {
  assert string.contains(page.fabric(), "href=\"/nixos\"")
  assert string.contains(page.paths(), "href=\"/nixos\"")
}

// A path here that is not live yet is no link at all: never a 404, never a link elsewhere.
pub fn no_dead_path_test() {
  list.each(pages(), fn(p) {
    assert !string.contains(p.1, "href=\"/pirsig\"")
    assert !string.contains(p.1, "href=\"/alerts\"")
  })
}

// Design C keeps the drawing.
pub fn mu_test() {
  assert string.contains(page.paths(), "src=\"/mu.svg\"")
}

// Prerendered: no script, so every page works with JavaScript off.
pub fn no_script_test() {
  list.each(pages(), fn(p) {
    assert !string.contains(p.1, "<script")
  })
}
