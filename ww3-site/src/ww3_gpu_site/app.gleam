//// The page. Every fact it shows comes from `content`, which site/content writes from the files of
//// ww3-gpu at the pinned commit; the sentences around the facts are written here, in lower case.
//// The page is plain: the research, its numbers, its tools, its figures and its records, with no
//// colour of its own. The Archify figures are the PNGs committed in ww3-gpu, shown as they are.
//// The look follows reasonablypolymorphic.com (Sandy Maguire, github.com/isovector): a text column
//// and a dark side column. It is prerendered and needs no JavaScript.
////
//// It is written once and built in four languages: at / in English, and at /pt-BR/, /zh-CN/ and
//// /ja-JP/. Each sentence goes through `t(l, "key")`, which reads it from
//// site/locales/<l>.json; site/content fails the build when a language lacks a key, or has a key
//// the page does not ask for.

import gleam/float
import gleam/int
import gleam/list
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import ww3_gpu_site/content.{
  type Bench, type Figure, type Person, type Record, type Report, type Stat,
  type Tool,
}

pub const repo = "https://github.com/h0ffmann/ww3-gpu"

const blob = "https://github.com/h0ffmann/ww3-gpu/blob/main/"

/// The site whose look this one follows, and its author's GitHub.
pub const template = "https://reasonablypolymorphic.com/"

/// Where ww3-gpu publishes each drawing as an interactive Archify page (its pages.yml). Archify
/// checks a drawing against the Git history of ww3-gpu, which the build here does not have, so
/// the pages are linked there and not built again.
pub const figures_site = "https://h0ffmann.github.io/ww3-gpu/figures/"

pub const template_author = "https://github.com/isovector"

/// The languages of the site: the code, the name in that language, and the folder of its pages
/// under the root ("" for English).
pub const languages = [
  #("en", "english", ""),
  #("pt-BR", "português", "pt-BR/"),
  #("zh-CN", "简体中文", "zh-CN/"),
  #("ja-JP", "日本語", "ja-JP/"),
]

/// The sentence of key `key` in language `l` (site/locales/<l>.json). A sentence that the
/// language lacks is shown in English, and a key that no file has is shown as it is; the build
/// has already failed for both.
pub fn t(l: String, key: String) -> String {
  let find = fn(lang) {
    case list.key_find(content.locales, lang) {
      Ok(pairs) -> list.key_find(pairs, key)
      Error(_) -> Error(Nil)
    }
  }
  case find(l), find("en") {
    Ok(text), _ -> text
    _, Ok(text) -> text
    _, _ -> key
  }
}

/// The way from the page to the root of the site: the style and the figures sit next to the
/// English page, one level up from the folder of each other language.
pub fn up(l: String) -> String {
  case l {
    "en" -> ""
    _ -> "../"
  }
}

pub fn view(l: String) -> Element(msg) {
  frame(l, "", [
    html.header([], [html.h1([], [html.text("ww3-gpu")])]),
    meta(l),
    html.div([attribute.class("content")], [
      research(l),
      numbers(l),
      tools(l),
      figures(l),
      port(l),
      records(
        "decisions",
        t(l, "decisions.title"),
        t(l, "decisions.about"),
        content.adrs,
      ),
      records(
        "designs",
        t(l, "designs.title"),
        t(l, "designs.about"),
        content.wfips,
      ),
      cite(l),
    ]),
    footer(l),
  ])
}

// ---- the frame: the text column and the side column -------------------------------------------

/// The page around `children`: the article, then the side column. `home` is the way from this
/// page to the front page of its language ("" on the front page, "../" on the lineage).
pub fn frame(
  l: String,
  home: String,
  children: List(Element(msg)),
) -> Element(msg) {
  // The side column is on the left. A checkbox before it, with no JavaScript, hides and shows it:
  // its label is the button at the top of the column (style.css). On a wide screen the column is
  // open until the reader closes it; on a phone it is closed until the reader opens it.
  html.div([attribute.class("page")], [
    html.input([
      attribute.type_("checkbox"),
      attribute.id("side-toggle"),
      attribute.class("toggle"),
      attribute.aria_label(t(l, "side.toggle")),
    ]),
    side(l, home),
    html.div([attribute.class("main")], [
      html.article([], list.append(banner(l), children)),
    ]),
  ])
}

/// The notice of a page that no native reader has checked yet; nothing in the other languages.
fn banner(l: String) -> List(Element(msg)) {
  case t(l, "banner") {
    "" -> []
    text -> [html.p([attribute.class("banner")], [html.text(text)])]
  }
}

fn side(l: String, home: String) -> Element(msg) {
  let item = fn(href, text) { html.li([], [a(href, text)]) }
  html.nav([], [
    html.label(
      [
        attribute.for("side-toggle"),
        attribute.class("toggle-label"),
        attribute.title(t(l, "side.toggle")),
      ],
      [html.text("☰")],
    ),
    html.p([attribute.class("brand")], [
      html.a([attribute.href(home <> "./")], [
        html.img([
          attribute.src(up(l) <> home <> "favicon.svg"),
          attribute.alt(""),
          attribute.width(72),
          attribute.height(72),
        ]),
        html.text("ww3"),
        html.br([]),
        html.text("gpu"),
      ]),
    ]),
    html.p([], [html.text(t(l, "side.about"))]),
    html.h2([], [html.text(t(l, "side.languages"))]),
    html.ul([], list.map(languages, language_item(l, home, _))),
    html.h2([], [html.text(t(l, "side.links"))]),
    html.ul([], [
      item(repo, t(l, "links.repository")),
      item(home <> "lineage/", t(l, "lineage.title")),
    ]),
    html.h2([], [html.text(t(l, "side.publishers"))]),
    html.ul([], publishers(l)),
    html.h2([], [html.text(t(l, "side.on_this_page"))]),
    html.ul([], [
      item(home <> "#research", t(l, "research.title")),
      item(home <> "#numbers", t(l, "numbers.title")),
      item(home <> "#tools", t(l, "tools.title")),
      item(home <> "#figures", t(l, "figures.title")),
      item(home <> "#port", t(l, "port.title")),
      item(home <> "#decisions", t(l, "decisions.title")),
      item(home <> "#designs", t(l, "designs.title")),
      item(home <> "#cite", t(l, "cite.title")),
    ]),
    ..list.flat_map(logos, fn(logo) {
      let #(org, picture) = logo
      [
        html.h2([attribute.class("org")], [
          html.a([attribute.href("https://github.com/" <> org)], [
            html.img([
              attribute.src(picture),
              attribute.alt(""),
              attribute.height(28),
            ]),
            html.text(org),
          ]),
        ]),
        html.ul(
          [],
          content.repos
            |> list.filter(fn(r) { r.org == org })
            |> list.map(fn(r) {
              item("https://github.com/" <> r.org <> "/" <> r.name, r.name)
            }),
        ),
      ]
    })
  ])
}

/// The three organizations of the side column, each with its logo. A logo is a trademark and is
/// never a file here: it loads from its owner's repository at a pinned commit (the ouroboric one
/// is the drawing for a dark ground), and piabrota's is its GitHub picture.
pub const logos = [
  #("piabrota", "https://avatars.githubusercontent.com/piabrota?s=128"),
  #(
    "marola-dev",
    "https://raw.githubusercontent.com/marola-dev/marola/19fdf0df9533aa22f25ae3024ab2abf61de73dab/docs/assets/logo-v2/marola-logo-v2.svg",
  ),
  #(
    "ouroboric-dev",
    "https://raw.githubusercontent.com/ouroboric-dev/ouroboric/4ab80ed2486a5e0ab0ade13e5089c2a4acdb4216/docs/7-branding/identity/logo/ouroboric-logo-horizontal-dark.svg",
  ),
]

/// One language of the side column: the same page in that language, named in that language; the
/// language of this page is text, not a link. `home` is "" on the front page and "../" on the
/// lineage.
fn language_item(
  l: String,
  home: String,
  language: #(String, String, String),
) -> Element(msg) {
  let #(code, name, folder) = language
  let page = case home {
    "" -> ""
    _ -> "lineage/"
  }
  let href = case home <> up(l) <> folder <> page {
    "" -> "./"
    path -> path
  }
  html.li([], [
    case code == l {
      True ->
        html.strong([attribute.attribute("lang", code)], [html.text(name)])
      False ->
        html.a(
          [
            attribute.href(href),
            attribute.attribute("hreflang", code),
            attribute.attribute("lang", code),
          ],
          [html.text(name)],
        )
    },
  ])
}

/// The line under the title: the commits and the commit the page was read at.
fn meta(l: String) -> Element(msg) {
  let count = case content.commits {
    "" -> []
    n -> [html.text(n <> " " <> t(l, "numbers.commits") <> " · ")]
  }
  html.p([attribute.class("meta")], [
    html.text(string.lowercase(content.site_title) <> " · "),
    ..list.append(count, [
      html.text(t(l, "meta.read_at") <> " "),
      html.a([attribute.href(repo <> "/commit/" <> content.revision)], [
        html.text(content.revision),
      ]),
    ])
  ])
}

fn footer(l: String) -> Element(msg) {
  html.footer([attribute.class("foot")], [
    html.p([], [
      html.text(t(l, "foot.read_at") <> " "),
      html.a([attribute.href(repo <> "/commit/" <> content.revision)], [
        html.text(content.revision),
      ]),
      html.text(". " <> t(l, "foot.trademark")),
    ]),
    credit(l),
  ])
}

/// The credit of the look, in the foot of every page.
pub fn credit(l: String) -> Element(msg) {
  html.p([], [
    html.text(t(l, "foot.look") <> " "),
    a(template, "reasonablypolymorphic.com"),
    html.text(", " <> t(l, "foot.by") <> " ("),
    a(template_author, "@isovector"),
    html.text("), " <> t(l, "foot.thanks")),
  ])
}

// ---- the sections ------------------------------------------------------------------------------

fn a(href: String, text: String) -> Element(msg) {
  html.a([attribute.href(href)], [html.text(text)])
}

fn section(id: String, title: String, children: List(Element(msg))) {
  html.section([attribute.id(id)], [html.h2([], [html.text(title)]), ..children])
}

fn p(text: String) -> Element(msg) {
  html.p([], [html.text(text)])
}

fn research(l: String) -> Element(msg) {
  section("research", t(l, "research.title"), [
    p(t(l, "research.lede")),
    p(t(l, "research.method")),
  ])
}

fn count_item(n: Int, label: String) -> Element(msg) {
  html.li([], [html.text(int.to_string(n) <> " " <> label)])
}

fn stat(s: Stat) -> Element(msg) {
  html.li([], [
    html.text(s.share <> " " <> s.name <> " (" <> s.count <> ")"),
  ])
}

fn numbers(l: String) -> Element(msg) {
  let commits = case content.commits {
    "" -> []
    n -> [html.li([], [html.text(n <> " " <> t(l, "numbers.commits"))])]
  }
  section("numbers", t(l, "numbers.title"), [
    html.ul(
      [],
      list.append(commits, [
        count_item(list.length(content.adrs), t(l, "numbers.adrs")),
        count_item(list.length(content.wfips), t(l, "numbers.wfips")),
        count_item(list.length(content.notes), t(l, "numbers.notes")),
        count_item(list.length(content.figures), t(l, "figures.title")),
        count_item(list.length(content.reports), t(l, "numbers.reports")),
      ]),
    ),
    p(t(l, "numbers.score")),
    html.ul([], list.map(content.stats, stat)),
  ])
}

fn tool_row(tool: Tool) -> Element(msg) {
  html.tr([], [
    html.td([], [html.text(tool.name)]),
    html.td([], [html.text(tool.version)]),
  ])
}

fn tools(l: String) -> Element(msg) {
  section("tools", t(l, "tools.title"), [
    p(t(l, "tools.about")),
    html.table([], [
      html.thead([], [
        html.tr([], [
          html.th([], [html.text(t(l, "tools.tool"))]),
          html.th([], [html.text(t(l, "tools.version"))]),
        ]),
      ]),
      html.tbody([], list.map(content.tools, tool_row)),
    ]),
  ])
}

/// One Archify figure: the PNG as it is, at the size it was drawn at (its `width` and `height`),
/// never shrunk to the text column; the style sheet scales it down only to the room beside the
/// side column. It links to itself, and under it are its question and its PDF.
fn figure(l: String, f: Figure) -> Element(msg) {
  let png = up(l) <> "archify/" <> f.slug <> ".png"
  let caption = case f.question {
    "" -> f.slug
    q -> q
  }
  let page = figures_site <> f.slug <> "/"
  html.figure([attribute.id(f.slug)], [
    html.div([attribute.class("drawing")], [
      html.a([attribute.href(page)], [
        html.img([
          attribute.src(png),
          attribute.alt(caption),
          attribute.attribute("width", f.width),
          attribute.attribute("height", f.height),
          attribute.attribute("loading", "lazy"),
        ]),
      ]),
    ]),
    html.figcaption([], [
      html.text(caption <> " "),
      a(page, t(l, "figures.page")),
      html.text(" · "),
      a(png, "png"),
      html.text(" · "),
      a(blob <> "docs/archify/" <> f.slug <> ".pdf", "pdf"),
    ]),
  ])
}

fn figures(l: String) -> Element(msg) {
  section("figures", t(l, "figures.title"), [
    p(t(l, "figures.about")),
    ..list.map(content.figures, figure(l, _))
  ])
}

// ---- the port, measured ----------------------------------------------------------------------
// Each bench row of kokkos/port_report/*_KOKKOS.md is one step; its speed-up is baseline / value.

fn number(s: String) -> Float {
  case float.parse(s) {
    Ok(x) -> x
    Error(_) ->
      case int.parse(s) {
        Ok(n) -> int.to_float(n)
        Error(_) -> 0.0
      }
  }
}

pub fn speedup(b: Bench) -> Float {
  let v = number(b.value)
  case v >. 0.0 {
    True -> number(b.baseline) /. v
    False -> 0.0
  }
}

/// "34.5x" or "531x" or "0.70x": two significant decimals below 10, one below 100, none above.
pub fn times(x: Float) -> String {
  let digits = case x <. 10.0, x <. 100.0 {
    True, _ -> 2
    False, True -> 1
    False, False -> 0
  }
  let shown = case digits {
    0 -> int.to_string(float.round(x))
    _ -> float.to_string(float.to_precision(x, digits))
  }
  shown <> "x"
}

fn step(l: String, b: Bench) -> Element(msg) {
  let x = speedup(b)
  let td = fn(text) { html.td([], [html.text(text)]) }
  html.tr([], [
    td(b.step),
    td(b.date),
    td(b.what <> " · " <> b.backend),
    td(case x <. 1.0 {
      True -> times(x) <> " " <> t(l, "port.slower")
      False -> times(x)
    }),
    td(
      b.value
      <> " "
      <> b.unit
      <> " "
      <> t(l, "port.against")
      <> " "
      <> b.baseline
      <> " "
      <> b.unit,
    ),
  ])
}

fn report(l: String, r: Report, rows: List(Bench)) -> Element(msg) {
  let regtested = case r.regtested {
    "" -> t(l, "port.no_record")
    v -> v
  }
  html.div([attribute.class("report")], [
    html.h3([], [a(blob <> r.file, r.name)]),
    p(r.status <> ". " <> t(l, "port.regtested") <> ": " <> regtested),
    html.table([], [
      html.thead([], [
        html.tr(
          [],
          list.map(
            [
              t(l, "port.step"),
              t(l, "port.date"),
              t(l, "port.what"),
              t(l, "port.speedup"),
              t(l, "port.measured"),
            ],
            fn(h) { html.th([], [html.text(h)]) },
          ),
        ),
      ]),
      html.tbody([], list.map(rows, step(l, _))),
    ]),
  ])
}

/// The reports with a benchmark get their table; the others are one paragraph of links, since
/// each of them says in its file why it has no number yet.
fn port(l: String) -> Element(msg) {
  let with_rows =
    list.map(content.reports, fn(r) {
      #(r, list.filter(content.benches, fn(b) { b.report == r.name }))
    })
  let #(measured, others) = list.partition(with_rows, fn(pair) { pair.1 != [] })
  let other_links =
    others
    |> list.map(fn(pair) {
      let r = pair.0
      a(blob <> r.file, r.name)
    })
    |> list.intersperse(html.text(", "))
  section("port", t(l, "port.title"), [
    p(t(l, "port.about")),
    ..list.append(list.map(measured, fn(pair) { report(l, pair.0, pair.1) }), [
      html.h3([], [
        html.text(
          int.to_string(list.length(others)) <> " " <> t(l, "port.others"),
        ),
      ]),
      html.p([attribute.class("others")], other_links),
    ])
  ])
}

fn records(
  id: String,
  title: String,
  about: String,
  rows: List(Record),
) -> Element(msg) {
  section(id, title, [
    p(about),
    html.ul(
      [attribute.class("records")],
      list.map(rows, fn(r) {
        html.li([], [
          html.a([attribute.href(blob <> r.file)], [
            html.text(r.id <> ": " <> r.title),
          ]),
          html.text(" (" <> string.lowercase(r.status) <> ")"),
          html.span([attribute.class("date")], [html.text(r.date)]),
        ])
      }),
    ),
  ])
}

fn orcid(p: Person) -> List(Element(msg)) {
  case p.orcid {
    "" -> []
    id -> [html.text(" · "), a("https://orcid.org/" <> id, "ORCID " <> id)]
  }
}

fn person(p: Person) -> Element(msg) {
  let role = case p.kind {
    "" -> p.role
    kind -> p.role <> ", " <> string.lowercase(kind)
  }
  html.li([], [
    html.strong([], [html.text(p.name)]),
    html.text(" (" <> role <> "), " <> p.affiliation),
    ..orcid(p)
  ])
}

/// Where the work is published: the Zenodo record by its concept DOI, then the preprint's aiXiv
/// and arXiv records, each read from .zenodo.json; one it does not list yet is shown as pending,
/// with no link.
fn publishers(l: String) -> List(Element(msg)) {
  let record = fn(name, url) {
    let entry = case url {
      "" -> [html.text(t(l, "publishers.pending"))]
      _ -> [a(url, last_segment(url))]
    }
    html.li([], [html.text(name <> ": "), ..entry])
  }
  [
    html.li([], [
      html.text("Zenodo: "),
      a("https://doi.org/" <> content.doi, "DOI " <> content.doi),
    ]),
    record("aiXiv", content.aixiv),
    record("arXiv", content.arxiv),
  ]
}

fn last_segment(url: String) -> String {
  case list.last(string.split(url, "/")) {
    Ok(id) -> id
    Error(Nil) -> url
  }
}

fn cite(l: String) -> Element(msg) {
  let release = case content.latest_release {
    "" -> []
    r -> [p(t(l, "cite.latest") <> " " <> r)]
  }
  section("cite", t(l, "cite.title"), [
    p(t(l, "cite.about")),
    html.ul([], publishers(l)),
    p(content.record_title),
    ..list.append(release, [
      html.ul([], list.map(content.people, person)),
    ])
  ])
}
