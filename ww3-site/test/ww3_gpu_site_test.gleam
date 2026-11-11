import gleam/list
import gleam/string
import gleeunit
import ww3_gpu_site/app
import ww3_gpu_site/content
import ww3_gpu_site/prerender
import ww3_gpu_site/prerender_lineage

pub fn main() -> Nil {
  gleeunit.main()
}

fn html() -> String {
  prerender.render("en")
}

// One source, two pages: the Portuguese one is the same page, every sentence looked up by its
// English in site/data/translations/pt-BR.tsv (h0ffmann/h0ffmann#86).
pub fn a_sentence_is_translated_by_its_source_test() {
  assert app.t("pt-BR", "the repository") == "o repositório"
  assert app.t("en", "the repository") == "the repository"
  assert app.t("pt-BR", "a sentence with no row") == "a sentence with no row"
}

pub fn the_page_in_portuguese_test() {
  let pt = prerender.render("pt-BR")
  assert string.contains(pt, "<html lang=\"pt-BR\">")
  assert string.contains(pt, "o segundo cérebro")
  // The files of the site are one level up from /pt-BR/; the anchors stay on the page.
  assert string.contains(pt, "href=\"../andamento/\"")
  assert string.contains(pt, "href=\"../style.css\"")
  assert string.contains(pt, "href=\"#about\"")
  assert string.contains(pt, "https://h0ffmann.github.io/ww3-gpu/pt-BR/")
  // Every section and every fact is there, as on the English page.
  list.each(["about", "decisions", "port", "cite"], fn(id) {
    assert string.contains(pt, "id=\"" <> id <> "\"")
  })
}

// Each page links to the other, named in the other's language.
pub fn the_two_pages_link_each_other_test() {
  assert string.contains(html(), "href=\"pt-BR/\" hreflang=\"pt-BR\"")
  assert string.contains(
    prerender.render("pt-BR"),
    "href=\"../\" hreflang=\"en\"",
  )
  assert string.contains(html(), "<html lang=\"en\">")
}

pub fn every_section_test() {
  let page = html()
  list.each(
    [
      "about",
      "decisions",
      "designs",
      "port",
      "chaceon",
      "brain",
      "cite",
      "related",
    ],
    fn(id) {
      assert string.contains(page, "id=\"" <> id <> "\"")
    },
  )
}

pub fn every_record_test() {
  let page = html()
  list.each(list.append(content.adrs, content.wfips), fn(r) {
    assert string.contains(page, r.file)
  })
}

pub fn the_doi_test() {
  assert content.doi == "10.5281/zenodo.23221351"
  assert string.contains(html(), "https://doi.org/10.5281/zenodo.23221351")
}

pub fn related_authors_test() {
  let page = html()
  // Guimarães P.V. comes from .zenodo.json, with his ORCID; Fabio Akita from site/data/related.tsv.
  assert string.contains(page, "https://orcid.org/0000-0002-1686-4722")
  assert string.contains(page, "https://github.com/akitaonrails")
  assert string.contains(page, "legendary br dev")
}

pub fn no_script_test() {
  assert !string.contains(html(), "<script")
}

pub fn every_benchmark_number_test() {
  let page = html()
  assert content.reports != []
  assert content.benches != []
  list.each(content.reports, fn(r) {
    assert string.contains(page, r.file)
  })
  list.each(content.benches, fn(b) {
    assert string.contains(
      page,
      b.value <> " " <> b.unit <> " against " <> b.baseline,
    )
    assert string.contains(page, app.times(app.speedup(b)))
  })
}

pub fn a_slower_step_is_never_green_test() {
  assert app.shade(0.7) == "slower"
  assert app.shade(1.0) == "g1"
  assert app.shade(4.35) == "g2"
  assert app.shade(34.5) == "g3"
  assert app.shade(531.0) == "g4"
  assert app.times(34.5066) == "34.5x"
  assert app.times(0.7008) == "0.7x"
  assert app.times(531.06) == "531x"
}

pub fn the_global_numbers_and_each_record_are_on_the_page_test() {
  let page = html()
  // Translated, ported, regtested: each of the run time and of the lines, then the C++ size.
  assert list.length(content.stats) == 7
  assert list.any(content.stats, fn(s) {
    s.name == "of the run time, regtested"
  })
  list.each(content.stats, fn(s) {
    assert string.contains(page, s.name)
    assert string.contains(page, ">" <> s.share <> "<")
    assert string.contains(page, ">" <> s.count <> "<")
  })
  list.each(content.reports, fn(r) {
    assert r.regtested != ""
    assert string.contains(page, string.replace(r.regtested, "'", "&#39;"))
  })
}

// The sister port in Rust: its repository is linked from the cover and from its section, and
// each fact about it links to the file of chaceon that states it (site/data/related.tsv).
pub fn the_rust_port_test() {
  let page = html()
  assert string.contains(page, "href=\"https://github.com/h0ffmann/chaceon\"")
  assert string.contains(page, "the port in rust: chaceon")
  assert string.contains(page, "nothing has run on a real GPU")
  let facts = list.filter(content.links, fn(l) { l.kind == "chaceon" })
  assert facts != []
  list.each(facts, fn(l) {
    assert string.contains(page, l.url)
  })
}

// The lineage: every row of site/data/lineage.tsv is on the page, oldest first, with its link;
// a planned row says so; the front page links to it and the two languages link each other.
pub fn the_lineage_test() {
  let page = prerender_lineage.render("en")
  assert string.contains(page, "id=\"lineage\"")
  assert content.events != []
  list.each(content.events, fn(e) {
    assert string.contains(page, e.date)
    assert string.contains(page, string.replace(e.url, "&", "&amp;"))
  })
  let dates = list.map(content.events, fn(e) { e.date })
  assert dates == list.sort(dates, string.compare)
  assert list.any(content.events, fn(e) { e.status == "planned" })
  assert string.contains(page, "event port planned")
  assert string.contains(page, ">planned<")
  assert string.contains(page, "href=\"../style.css\"")
  assert string.contains(page, "https://h0ffmann.github.io/ww3-gpu/lineage/")
  assert string.contains(page, "href=\"../pt-BR/lineage/\" hreflang=\"pt-BR\"")
  assert string.contains(html(), "href=\"lineage/\"")
  let pt = prerender_lineage.render("pt-BR")
  assert string.contains(pt, "<html lang=\"pt-BR\">")
  assert string.contains(pt, "linhagem")
  assert string.contains(pt, "href=\"../../style.css\"")
  assert string.contains(pt, "href=\"../../lineage/\" hreflang=\"en\"")
  assert string.contains(
    pt,
    "https://h0ffmann.github.io/ww3-gpu/pt-BR/lineage/",
  )
}
