//// The page. Every fact it shows comes from `content`, which site/content writes from the files of
//// ww3-gpu at the pinned commit; the sentences around the facts are written here, in lower case.
//// The page is plain: the research, its numbers, its tools, its figures and its records, with no
//// colour of its own. The Archify figures are the PNGs committed in ww3-gpu, shown as they are.
//// The look follows reasonablypolymorphic.com (Sandy Maguire, github.com/isovector): a text column
//// and a dark side column. It is prerendered and needs no JavaScript.
////
//// It is written once, in English, and built twice: at / in English and at /pt-BR/ in Brazilian
//// Portuguese. Each sentence goes through `t(l, "…")`, which looks it up by its English in
//// site/data/translations/pt-BR.tsv; site/content fails the build when a sentence has no row, or a
//// row no sentence. The pattern is h0ffmann/h0ffmann#86.

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

pub const template_author = "https://github.com/isovector"

/// A sentence of the page in language `l`, "en" or "pt-BR". The key is the English sentence
/// itself; a sentence with no row is shown in English, and the build has already failed for it.
pub fn t(l: String, source: String) -> String {
  case l {
    "pt-BR" ->
      case list.key_find(content.pt_br, source) {
        Ok(target) -> target
        Error(_) -> source
      }
    _ -> source
  }
}

/// The way from the page to the root of the site: the style and the figures sit next to the
/// English page, one level up from /pt-BR/.
pub fn up(l: String) -> String {
  case l {
    "pt-BR" -> "../"
    _ -> ""
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
        t(l, "the decisions"),
        t(
          l,
          "each one a choice the lab made, the context that forced it and what follows. an accepted record is never edited; a new one supersedes it.",
        ),
        content.adrs,
      ),
      records(
        "designs",
        t(l, "the designs"),
        t(
          l,
          "a change is designed before it is built, tied to a deliverable of the project proposal, with its definition of done.",
        ),
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
  html.div([attribute.class("page")], [
    html.div([attribute.class("main")], [html.article([], children)]),
    side(l, home),
  ])
}

fn side(l: String, home: String) -> Element(msg) {
  let item = fn(href, text) { html.li([], [a(href, text)]) }
  html.nav([], [
    html.p([attribute.class("brand")], [
      html.a([attribute.href(home <> "./")], [
        html.text("ww3"),
        html.br([]),
        html.text("gpu"),
      ]),
    ]),
    html.p([], [
      html.text(t(
        l,
        "the research of Matheus Hoffmann: WAVEWATCH III on GPUs, bit for bit with the Fortran.",
      )),
    ]),
    html.h2([], [html.text(t(l, "links"))]),
    html.ul([], [
      item(repo, t(l, "the repository")),
      item("https://doi.org/" <> content.doi, "DOI " <> content.doi),
      item(home <> "lineage/", t(l, "lineage")),
      html.li([], [other_language(l, home)]),
    ]),
    html.h2([], [html.text(t(l, "on this page"))]),
    html.ul([], [
      item(home <> "#research", t(l, "the research")),
      item(home <> "#numbers", t(l, "in numbers")),
      item(home <> "#tools", t(l, "tools used")),
      item(home <> "#figures", t(l, "figures")),
      item(home <> "#port", t(l, "the port, measured")),
      item(home <> "#decisions", t(l, "the decisions")),
      item(home <> "#designs", t(l, "the designs")),
      item(home <> "#cite", t(l, "how to cite")),
    ]),
  ])
}

/// The link to the same page in the other language, named in that language. `home` is "" on
/// the front page and "../" on the lineage.
fn other_language(l: String, home: String) -> Element(msg) {
  let #(href, lang, name) = case l, home {
    "pt-BR", "" -> #("../", "en", "english")
    "pt-BR", _ -> #("../../lineage/", "en", "english")
    _, "" -> #("pt-BR/", "pt-BR", "português")
    _, _ -> #("../pt-BR/lineage/", "pt-BR", "português")
  }
  html.a(
    [
      attribute.href(href),
      attribute.attribute("hreflang", lang),
      attribute.attribute("lang", lang),
    ],
    [html.text(name)],
  )
}

/// The line under the title: the commits and the commit the page was read at.
fn meta(l: String) -> Element(msg) {
  let count = case content.commits {
    "" -> []
    n -> [html.text(n <> " " <> t(l, "commits") <> " · ")]
  }
  html.p([attribute.class("meta")], [
    html.text(string.lowercase(content.site_title) <> " · "),
    ..list.append(count, [
      html.text(t(l, "read at") <> " "),
      html.a([attribute.href(repo <> "/commit/" <> content.revision)], [
        html.text(content.revision),
      ]),
    ])
  ])
}

fn footer(l: String) -> Element(msg) {
  html.footer([attribute.class("foot")], [
    html.p([], [
      html.text(
        t(l, "every fact on this page was read from the repository at") <> " ",
      ),
      html.a([attribute.href(repo <> "/commit/" <> content.revision)], [
        html.text(content.revision),
      ]),
      html.text(
        ". "
        <> t(
          l,
          "WAVEWATCH III is a registered trademark of NOAA's National Weather Service; this project is independent and not endorsed by NOAA.",
        ),
      ),
    ]),
    credit(l),
  ])
}

/// The credit of the look, in the foot of every page.
pub fn credit(l: String) -> Element(msg) {
  html.p([], [
    html.text(t(l, "the look of this page follows") <> " "),
    a(template, "reasonablypolymorphic.com"),
    html.text(", " <> t(l, "by Sandy Maguire") <> " ("),
    a(template_author, "@isovector"),
    html.text(
      "), "
      <> t(l, "the man who made me go back to math in 2026 and probably 2027."),
    ),
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
  section("research", t(l, "the research"), [
    p(t(
      l,
      "making WAVEWATCH III run faster with Kokkos and CUDA, without changing the Fortran's arithmetic: every ported routine gives the Fortran's bits.",
    )),
    p(t(
      l,
      "the code, the plans, the decisions and the measurements sit side by side. every claim carries (v) when it was checked and ⚠ when it was not, and every number comes with its command.",
    )),
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
    n -> [html.li([], [html.text(n <> " " <> t(l, "commits"))])]
  }
  section("numbers", t(l, "in numbers"), [
    html.ul(
      [],
      list.append(commits, [
        count_item(list.length(content.adrs), t(l, "decision records")),
        count_item(list.length(content.wfips), t(l, "design documents")),
        count_item(list.length(content.notes), t(l, "notes")),
        count_item(list.length(content.figures), t(l, "figures")),
        count_item(list.length(content.reports), t(l, "port reports")),
      ]),
    ),
    p(t(
      l,
      "how much of WW3 runs on Kokkos, read from site/data/port_score.tsv:",
    )),
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
  section("tools", t(l, "tools used"), [
    p(t(
      l,
      "the reference toolchain: every verdict and every timing comes from it. read from VERSIONS.md.",
    )),
    html.table([], [
      html.thead([], [
        html.tr([], [
          html.th([], [html.text(t(l, "tool"))]),
          html.th([], [html.text(t(l, "version"))]),
        ]),
      ]),
      html.tbody([], list.map(content.tools, tool_row)),
    ]),
  ])
}

/// One Archify figure: the PNG as it is, at its own size up to the width of the column, linked to
/// itself, and under it the question it answers and its PDF.
fn figure(l: String, f: Figure) -> Element(msg) {
  let png = up(l) <> "archify/" <> f.slug <> ".png"
  let caption = case f.question {
    "" -> f.slug
    q -> q
  }
  html.figure([attribute.id(f.slug)], [
    html.a([attribute.href(png)], [
      html.img([
        attribute.src(png),
        attribute.alt(caption),
        attribute.attribute("loading", "lazy"),
      ]),
    ]),
    html.figcaption([], [
      html.text(caption <> " "),
      a(blob <> "docs/archify/" <> f.slug <> ".pdf", "pdf"),
    ]),
  ])
}

fn figures(l: String) -> Element(msg) {
  section("figures", t(l, "figures"), [
    p(t(
      l,
      "drawn with Archify. each picture is the PNG committed in the repository, shown as it is.",
    )),
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
      True -> times(x) <> " " <> t(l, "slower")
      False -> times(x)
    }),
    td(
      b.value
      <> " "
      <> b.unit
      <> " "
      <> t(l, "against")
      <> " "
      <> b.baseline
      <> " "
      <> b.unit,
    ),
  ])
}

fn report(l: String, r: Report, rows: List(Bench)) -> Element(msg) {
  let regtested = case r.regtested {
    "" -> t(l, "no record")
    v -> v
  }
  html.div([attribute.class("report")], [
    html.h3([], [a(blob <> r.file, r.name)]),
    p(r.status <> ". " <> t(l, "regtested") <> ": " <> regtested),
    html.table([], [
      html.thead([], [
        html.tr(
          [],
          list.map(
            [
              t(l, "step"),
              t(l, "date"),
              t(l, "what"),
              t(l, "speed-up"),
              t(l, "measured"),
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
  section("port", t(l, "the port, measured"), [
    p(t(
      l,
      "every number of every port report, step by step. the speed-up is over the step's own baseline.",
    )),
    ..list.append(list.map(measured, fn(pair) { report(l, pair.0, pair.1) }), [
      html.h3([], [
        html.text(
          int.to_string(list.length(others))
          <> " "
          <> t(l, "reports with no benchmark yet"),
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

fn cite(l: String) -> Element(msg) {
  let release = case content.latest_release {
    "" -> []
    r -> [p(t(l, "latest release:") <> " " <> r)]
  }
  section("cite", t(l, "how to cite"), [
    p(t(
      l,
      "cite the concept DOI for the work as a whole: it always resolves to the latest edition. to pin the exact code you ran, cite that release's own DOI.",
    )),
    html.p([], [a("https://doi.org/" <> content.doi, content.doi)]),
    p(content.record_title),
    ..list.append(release, [
      html.ul([], list.map(content.people, person)),
    ])
  ])
}
