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

fn escaped(s: String) -> String {
  s
  |> string.replace("&", "&amp;")
  |> string.replace("'", "&#39;")
  |> string.replace("<", "&lt;")
  |> string.replace(">", "&gt;")
  |> string.replace("\"", "&quot;")
}

const sections = [
  "research", "numbers", "tools", "figures", "port", "decisions", "designs",
  "cite",
]

// One source, four pages: each sentence is a key of site/locales/<lang>.json.
pub fn a_sentence_is_read_by_its_key_test() {
  assert app.t("en", "links.repository") == "the repository"
  assert app.t("pt-BR", "links.repository") == "o repositório"
  assert app.t("ja-JP", "lineage.title") == "系譜"
  assert app.t("zh-CN", "lineage.title") == "谱系"
  assert app.t("pt-BR", "no.such.key") == "no.such.key"
}

pub fn the_page_in_each_language_test() {
  list.each(app.languages, fn(language) {
    let #(code, name, folder) = language
    let page = prerender.render(code)
    assert string.contains(page, "<html lang=\"" <> code <> "\">")
    assert string.contains(page, "https://wave.piabrota.art/" <> folder)
    // The language of the page is named and is not a link; the others are links.
    assert string.contains(
      page,
      "<strong lang=\"" <> code <> "\">" <> name <> "</strong>",
    )
    list.each(sections, fn(id) {
      assert string.contains(page, "id=\"" <> id <> "\"")
    })
  })
  let pt = prerender.render("pt-BR")
  assert string.contains(pt, "ferramentas usadas")
  // The files of the site are one level up from /pt-BR/; the anchors stay on the page.
  assert string.contains(pt, "href=\"../style.css\"")
  assert string.contains(pt, "src=\"../archify/")
  assert string.contains(pt, "href=\"#research\"")
}

// Each page links to the three others, named in their own languages.
pub fn the_pages_link_each_other_test() {
  let en = html()
  assert string.contains(en, "href=\"pt-BR/\" hreflang=\"pt-BR\"")
  assert string.contains(en, "href=\"zh-CN/\" hreflang=\"zh-CN\"")
  assert string.contains(en, "href=\"ja-JP/\" hreflang=\"ja-JP\"")
  let ja = prerender.render("ja-JP")
  assert string.contains(ja, "href=\"../\" hreflang=\"en\"")
  assert string.contains(ja, "href=\"../pt-BR/\" hreflang=\"pt-BR\"")
}

// A page no native reader has checked says so; the English and Portuguese pages do not.
pub fn the_banner_test() {
  assert string.contains(prerender.render("zh-CN"), "class=\"banner\"")
  assert string.contains(prerender.render("ja-JP"), "class=\"banner\"")
  assert !string.contains(html(), "class=\"banner\"")
  assert !string.contains(prerender.render("pt-BR"), "class=\"banner\"")
}

// The side column comes before the text, so it is on the left, and a checkbox folds it.
pub fn the_side_column_is_on_the_left_and_folds_test() {
  let page = html()
  let assert Ok(#(before, _)) = string.split_once(page, "<div class=\"main\">")
  assert string.contains(before, "id=\"side-toggle\"")
  assert string.contains(
    before,
    "<label class=\"toggle-label\" for=\"side-toggle\"",
  )
  assert string.contains(before, "<nav>")
}

pub fn every_section_test() {
  let page = html()
  list.each(sections, fn(id) {
    assert string.contains(page, "id=\"" <> id <> "\"")
  })
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

// The publishers: Zenodo by its DOI, the aiXiv record, and arXiv as pending until .zenodo.json
// lists one.
pub fn the_publishers_test() {
  let page = html()
  assert string.contains(page, app.t("en", "side.publishers"))
  assert content.aixiv == "https://aixiv.online/abs/2611.01104"
  assert string.contains(page, "href=\"https://aixiv.online/abs/2611.01104\"")
  case content.arxiv {
    "" -> {
      assert string.contains(
        page,
        "arXiv: " <> app.t("en", "publishers.pending"),
      )
      Nil
    }
    url -> {
      assert string.contains(page, "href=\"" <> url <> "\"")
      Nil
    }
  }
}

pub fn no_script_test() {
  assert !string.contains(html(), "<script")
}

// The number of commits is on the page when the build knows it.
pub fn the_commits_test() {
  case content.commits {
    "" -> Nil
    n -> {
      assert string.contains(html(), n <> " commits")
      Nil
    }
  }
}

// Every tool of the reference toolchain is a row of the table.
pub fn every_tool_test() {
  let page = html()
  assert content.tools != []
  assert list.any(content.tools, fn(t) { string.starts_with(t.version, "5.") })
  list.each(content.tools, fn(t) {
    assert string.contains(page, "<td>" <> escaped(t.name) <> "</td>")
  })
}

// Every Archify figure is its committed PNG, with its question and a link to its PDF; the image
// carries no class and no style, so the page never dresses it.
pub fn every_figure_test() {
  let page = html()
  assert content.figures != []
  list.each(content.figures, fn(f) {
    assert string.contains(page, "src=\"archify/" <> f.slug <> ".png\"")
    assert string.contains(page, "docs/archify/" <> f.slug <> ".pdf")
    // A click on the picture opens its HTML page.
    assert string.contains(
      page,
      "<a href=\"" <> app.figures_site <> f.slug <> "/\"><img",
    )
    // Its drawn size, so the page never shrinks it to the text column.
    assert f.width != "" && f.height != ""
    assert string.contains(page, "width=\"" <> f.width <> "\"")
    // A drawing with no row in docs/archify/README.md is captioned with its name.
    let caption = case f.question {
      "" -> f.slug
      q -> q
    }
    assert string.contains(page, "<figcaption>" <> escaped(caption) <> " ")
  })
  assert !string.contains(page, "<img class")
  assert !string.contains(page, "style=")
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
  assert app.times(34.5066) == "34.5x"
  assert app.times(0.7008) == "0.7x"
  assert app.times(531.06) == "531x"
}

pub fn the_global_numbers_and_each_record_are_on_the_page_test() {
  let page = html()
  assert list.length(content.stats) == 7
  list.each(content.stats, fn(s) {
    assert string.contains(page, s.share <> " " <> s.name)
  })
  list.each(content.reports, fn(r) {
    case list.any(content.benches, fn(b) { b.report == r.name }) {
      True -> {
        assert string.contains(page, escaped(r.regtested))
        Nil
      }
      False -> Nil
    }
  })
}

// The look follows reasonablypolymorphic.com, and the page says so and names its author.
pub fn the_template_is_credited_test() {
  let page = html()
  assert string.contains(page, "href=\"https://reasonablypolymorphic.com/\"")
  assert string.contains(page, "href=\"https://github.com/isovector\"")
  assert string.contains(page, "Sandy Maguire")
  assert string.contains(
    prerender_lineage.render("en"),
    "href=\"https://github.com/isovector\"",
  )
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
  assert string.contains(page, "(planned)")
  assert string.contains(page, "href=\"../style.css\"")
  assert string.contains(page, "https://wave.piabrota.art/lineage/")
  assert string.contains(page, "href=\"../pt-BR/lineage/\" hreflang=\"pt-BR\"")
  assert string.contains(page, "href=\"../ja-JP/lineage/\" hreflang=\"ja-JP\"")
  assert string.contains(html(), "href=\"lineage/\"")
  let pt = prerender_lineage.render("pt-BR")
  assert string.contains(pt, "<html lang=\"pt-BR\">")
  assert string.contains(pt, "linhagem")
  assert string.contains(pt, "href=\"../../style.css\"")
  assert string.contains(pt, "href=\"../../lineage/\" hreflang=\"en\"")
  assert string.contains(pt, "https://wave.piabrota.art/pt-BR/lineage/")
}

// The side column lists five repositories of each of the three organizations.
pub fn the_repositories_test() {
  let page = html()
  list.each(["piabrota", "marola-dev", "ouroboric-dev"], fn(org) {
    let rows = list.filter(content.repos, fn(r) { r.org == org })
    assert list.length(rows) == 5
    list.each(rows, fn(r) {
      assert string.contains(
        page,
        "href=\"https://github.com/" <> org <> "/" <> r.name <> "\"",
      )
    })
  })
}

// Each organization has its logo, loaded from its owner and never a file of this site.
pub fn the_logos_test() {
  let page = html()
  assert list.length(app.logos) == 3
  list.each(app.logos, fn(logo) {
    let #(org, picture) = logo
    assert string.starts_with(picture, "https://")
    assert string.contains(
      page,
      "<a href=\"https://github.com/"
        <> org
        <> "\"><img alt height=\"28\" src=\""
        <> escaped(picture)
        <> "\">"
        <> org
        <> "</a>",
    )
  })
}

// The side column opens with the logo of ww3-gpu, the wave of the favicon, on every page.
pub fn the_logo_of_the_site_test() {
  assert string.contains(html(), "src=\"favicon.svg\" width=\"72\"")
  assert string.contains(
    prerender.render("pt-BR"),
    "src=\"../favicon.svg\" width=\"72\"",
  )
  assert string.contains(
    prerender_lineage.render("pt-BR"),
    "src=\"../../favicon.svg\" width=\"72\"",
  )
}
