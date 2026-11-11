//// The page. Every fact it shows comes from `content`, which site/content writes from the files of
//// this repository; the sentences that tell the story are written here, in lower case
//// (DESIGN.md). The page is prerendered and needs no JavaScript.
////
//// It is written once, in English, and built twice: at / in English and at /pt-BR/ in Brazilian
//// Portuguese. Each sentence goes through `t(l, "…")`, which looks it up by its English in
//// site/data/translations/pt-BR.tsv; site/content fails the build when a sentence has no row, or a
//// row no sentence. The pattern is h0ffmann/h0ffmann#86.

import gleam/float
import gleam/int
import gleam/list
import gleam/string
import lustre/attribute.{type Attribute}
import lustre/element.{type Element}
import lustre/element/html
import ww3_gpu_site/content.{
  type Bench, type Link, type Note, type Person, type Record, type Report,
  type Stat,
}

pub const repo = "https://github.com/h0ffmann/ww3-gpu"

const blob = "https://github.com/h0ffmann/ww3-gpu/blob/main/"

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

/// The way from the page to the root of the site: the style and the pages built by
/// scripts/build_html.sh sit next to the English page, one level up from /pt-BR/.
pub fn up(l: String) -> String {
  case l {
    "pt-BR" -> "../"
    _ -> ""
  }
}

pub fn view(l: String) -> Element(msg) {
  html.main([], [
    cover(l),
    about(l),
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
    port(l),
    rust_port(l),
    brain(l),
    cite(l),
    related(l),
    footer(l),
  ])
}

// ---- the port, measured ----------------------------------------------------------------------
// Each bench row of kokkos/port_report/*_KOKKOS.md is one step: a bar as long as the log of its
// speed-up (baseline / value), in a deeper shade of the proof light the larger the speed-up
// (DESIGN.md); a step slower than its baseline is grey and says "slower".

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

/// The shade of a step: g1 (under 2x) to g4 (100x and more); "slower" under 1x.
pub fn shade(x: Float) -> String {
  case x <. 1.0, x <. 2.0, x <. 10.0, x <. 100.0 {
    True, _, _, _ -> "slower"
    _, True, _, _ -> "g1"
    _, _, True, _ -> "g2"
    _, _, _, True -> "g3"
    _, _, _, _ -> "g4"
  }
}

fn log10(x: Float) -> Float {
  case float.logarithm(x), float.logarithm(10.0) {
    Ok(a), Ok(b) -> a /. b
    _, _ -> 0.0
  }
}

fn bar_width(x: Float, top: Float) -> String {
  let w = case x <=. 1.0 || top <=. 1.0 {
    True -> 4.0
    False -> 4.0 +. 96.0 *. log10(x) /. log10(top)
  }
  float.to_string(float.to_precision(w, 1)) <> "%"
}

fn step(l: String, b: Bench, top: Float) -> Element(msg) {
  let x = speedup(b)
  html.li([attribute.class("step")], [
    html.span([attribute.class("num")], [html.text(b.step)]),
    html.span([attribute.class("name")], [
      html.text(b.what <> " · " <> b.backend),
    ]),
    html.span([attribute.class("date")], [html.text(b.date)]),
    html.span([attribute.class("bar")], [
      html.span(
        [
          attribute.class("fill " <> shade(x)),
          attribute.style("width", bar_width(x, top)),
        ],
        [],
      ),
    ]),
    html.span([attribute.class("speed " <> shade(x))], [
      html.text(case x <. 1.0 {
        True -> times(x) <> " · " <> t(l, "slower")
        False -> times(x)
      }),
    ]),
    html.span([attribute.class("aff")], [
      html.text(
        b.value
        <> " "
        <> b.unit
        <> " "
        <> t(l, "against")
        <> " "
        <> b.baseline
        <> " "
        <> b.unit
        <> " · "
        <> b.source,
      ),
    ]),
  ])
}

/// A record of kokkos/ports.tsv ("yes: …" or "no: …"): proof when yes, warn when no or missing.
fn record_line(l: String, label: String, value: String) -> Element(msg) {
  let class = case string.starts_with(value, "yes") {
    True -> "chip proof"
    False -> "chip warn"
  }
  let shown = case value {
    "" -> t(l, "no record")
    v -> v
  }
  html.p([attribute.class("record")], [
    html.span([attribute.class(class)], [html.text(label)]),
    html.text(" "),
    html.span([attribute.class("aff")], [html.text(shown)]),
  ])
}

fn stat(s: Stat) -> Element(msg) {
  html.li([], [
    html.span([attribute.class("value")], [html.text(s.share)]),
    html.span([attribute.class("name")], [html.text(s.name)]),
    html.span([attribute.class("count")], [html.text(s.count)]),
    html.span([attribute.class("aff")], [html.text(s.what)]),
  ])
}

fn report(l: String, r: Report) -> Element(msg) {
  let rows = list.filter(content.benches, fn(b) { b.report == r.name })
  let top = list.fold(rows, 1.0, fn(acc, b) { float.max(acc, speedup(b)) })
  html.div([attribute.class("report")], [
    html.h3([], [
      a(blob <> r.file, r.name),
      html.text(" "),
      html.span([attribute.class("chip code")], [html.text(r.status)]),
    ]),
    record_line(l, t(l, "regtested"), r.regtested),
    case rows {
      [] ->
        html.p([attribute.class("empty")], [
          html.text(t(l, "no benchmark: the report says why.")),
        ])
      _ ->
        html.ol(
          [attribute.class("steps")],
          list.map(rows, fn(b) { step(l, b, top) }),
        )
    },
  ])
}

fn port(l: String) -> Element(msg) {
  section("port", t(l, "the port, measured"), [
    lede(t(
      l,
      "how much of WW3 runs on Kokkos, then every number of every port report, step by step. a bar is the speed-up over its own baseline, on a log scale; the deeper the green, the larger it is. a step slower than its baseline is grey, and says so.",
    )),
    html.ul([attribute.class("stats")], list.map(content.stats, stat)),
    ..list.map(content.reports, report(l, _))
  ])
}

fn a(href: String, text: String) -> Element(msg) {
  html.a([attribute.href(href)], [html.text(text)])
}

fn section(id: String, title: String, children: List(Element(msg))) {
  html.section([attribute.id(id), attribute.class("wrap")], [
    html.h2([], [html.text(title)]),
    ..children
  ])
}

fn lede(text: String) -> Element(msg) {
  html.p([attribute.class("lede")], [html.text(text)])
}

fn light(name: String) -> Attribute(msg) {
  attribute.class("light " <> name)
}

fn cover(l: String) -> Element(msg) {
  html.header([attribute.class("cover wrap")], [
    html.p([attribute.class("kicker")], [
      html.text("h0ffmann / ww3-gpu"),
    ]),
    html.h1([], [html.text("ww3-gpu")]),
    html.p([attribute.class("epithet")], [
      html.text(string.lowercase(content.site_title)),
    ]),
    html.p([attribute.class("lede")], [
      html.text(t(
        l,
        "making WAVEWATCH III run faster with Kokkos and CUDA, without changing the Fortran's arithmetic: every ported routine gives the Fortran's bits.",
      )),
    ]),
    html.p([attribute.class("actions")], [
      html.a([attribute.class("button"), attribute.href(repo)], [
        html.text(t(l, "the repository")),
      ]),
      html.a([attribute.class("button quiet"), attribute.href(chaceon().url)], [
        html.text(t(l, "the port in rust: chaceon")),
      ]),
    ]),
    html.nav([attribute.class("jump")], [
      a("#about", t(l, "about")),
      a("#decisions", t(l, "decisions")),
      a("#designs", t(l, "designs")),
      a("#chaceon", t(l, "rust port")),
      a("#brain", t(l, "second brain")),
      a("#cite", t(l, "cite")),
      a("#related", t(l, "related")),
      a("lineage/", t(l, "lineage")),
      other_language(l),
    ]),
  ])
}

/// The link to the page in the other language, named in that language.
fn other_language(l: String) -> Element(msg) {
  let #(href, lang, name) = case l {
    "pt-BR" -> #("../", "en", "english")
    _ -> #("pt-BR/", "pt-BR", "português")
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

fn about(l: String) -> Element(msg) {
  section("about", t(l, "the repository"), [
    html.p([attribute.class("title")], [html.text(content.site_title)]),
    lede(content.site_subtitle),
    html.p([], [
      html.text(t(
        l,
        "the code, the plans, the decisions and the measurements sit side by side. every claim carries",
      )),
      html.text(" "),
      html.span([light("proof")], [html.text("(v)")]),
      html.text(" " <> t(l, "when it was checked and") <> " "),
      html.span([light("warn")], [html.text("⚠")]),
      html.text(
        " " <> t(l, "when it was not, and every number comes with its command."),
      ),
    ]),
    html.p([attribute.class("links")], [
      a(up(l) <> "andamento/", t(l, "progress (pt-BR)")),
      html.text(" · "),
      a(up(l) <> "adrs/", t(l, "decision records (pt-BR)")),
    ]),
  ])
}

fn status_class(status: String) -> String {
  case string.lowercase(status) {
    "accepted" | "implemented" -> "proof"
    "proposed" | "draft" -> "code"
    "rejected" | "superseded" -> "muted"
    _ -> "wave"
  }
}

fn records(
  id: String,
  title: String,
  about: String,
  rows: List(Record),
) -> Element(msg) {
  section(id, title, [
    lede(about),
    html.ul(
      [attribute.class("records")],
      list.map(rows, fn(r) {
        html.li([], [
          html.a([attribute.href(blob <> r.file)], [
            html.span([attribute.class("num")], [html.text(r.id)]),
            html.text(r.title),
          ]),
          html.span([attribute.class("chip " <> status_class(r.status))], [
            html.text(string.lowercase(r.status)),
          ]),
          html.span([attribute.class("date")], [html.text(r.date)]),
        ])
      }),
    ),
  ])
}

fn brain(l: String) -> Element(msg) {
  let notes = case content.notes {
    [] -> [
      html.p([attribute.class("empty")], [html.text(t(l, "no note yet."))]),
    ]
    notes -> [
      html.ul([attribute.class("records")], list.map(notes, note)),
    ]
  }
  section("brain", t(l, "the second brain"), [
    lede(t(
      l,
      "one idea in one note, with a permanent id, links between notes, and a status that stays unverified until a source is cited. the preprint and the proposal are written from them.",
    )),
    ..notes
  ])
}

fn note(n: Note) -> Element(msg) {
  html.li([], [
    html.a([attribute.href(blob <> n.file)], [
      html.span([attribute.class("num")], [html.text(n.id)]),
      html.text(n.title),
    ]),
    html.span([attribute.class("chip " <> note_class(n.status))], [
      html.text(n.status),
    ]),
    html.span([attribute.class("date")], [html.text(n.kind)]),
  ])
}

fn note_class(status: String) -> String {
  case status {
    "verified" | "approved" -> "proof"
    "unverified" | "open-question" -> "warn"
    _ -> "code"
  }
}

fn orcid(p: Person) -> List(Element(msg)) {
  case p.orcid {
    "" -> []
    id -> [
      html.text(" · "),
      html.a([attribute.href("https://orcid.org/" <> id)], [
        html.text("ORCID " <> id),
      ]),
    ]
  }
}

fn person(p: Person) -> Element(msg) {
  let role = case p.kind {
    "" -> p.role
    kind -> p.role <> ", " <> string.lowercase(kind)
  }
  html.li([], [
    html.span([attribute.class("name")], [html.text(p.name)]),
    html.span([attribute.class("date")], [html.text(role)]),
    html.span([attribute.class("aff")], [html.text(p.affiliation), ..orcid(p)]),
  ])
}

fn cite(l: String) -> Element(msg) {
  let release = case content.latest_release {
    "" -> []
    r -> [html.p([], [html.text(t(l, "latest release:") <> " " <> r)])]
  }
  section("cite", t(l, "how to cite"), [
    lede(t(
      l,
      "cite the concept DOI for the work as a whole: it always resolves to the latest edition. to pin the exact code you ran, cite that release's own DOI.",
    )),
    html.p([attribute.class("doi")], [
      html.a([attribute.href("https://doi.org/" <> content.doi)], [
        html.text(content.doi),
      ]),
    ]),
    html.p([], [html.text(content.record_title)]),
    ..list.append(release, [
      html.ul([attribute.class("people")], list.map(content.people, person)),
    ])
  ])
}

fn link_item(l: Link) -> Element(msg) {
  html.li([], [
    html.a([attribute.href(l.url)], [html.text(l.name)]),
    html.span([attribute.class("aff")], [html.text(l.what)]),
  ])
}

fn related(l: String) -> Element(msg) {
  let authors =
    content.people
    |> list.filter(fn(p) { p.role == "contributor" })
    |> list.map(fn(p) {
      html.li([], [
        html.span([attribute.class("name")], [html.text(p.name)]),
        html.span([attribute.class("aff")], [
          html.text(
            string.lowercase(p.kind)
            <> " "
            <> t(l, "of this work")
            <> " · "
            <> p.affiliation,
          ),
          ..orcid(p)
        ]),
      ])
    })
  let kind = fn(k) { list.filter(content.links, fn(l: Link) { l.kind == k }) }
  section("related", t(l, "related authors and works"), [
    html.h3([], [html.text(t(l, "authors"))]),
    html.ul(
      [attribute.class("people")],
      list.append(authors, list.map(kind("author"), link_item)),
    ),
    html.h3([], [html.text(t(l, "sister works, by the same author"))]),
    html.ul([attribute.class("people")], list.map(kind("work"), link_item)),
  ])
}

// ---- the sister port in Rust ------------------------------------------------------------------
// chaceon and its facts are rows of site/data/related.tsv (kind port and chaceon), each linked to
// the file of chaceon that states it; nothing about it is typed here (DESIGN.md, "Facts").

fn chaceon() -> Link {
  case list.find(content.links, fn(l: Link) { l.kind == "port" }) {
    Ok(link) -> link
    Error(_) -> content.Link("port", "chaceon", "", "", "")
  }
}

fn rust_port(l: String) -> Element(msg) {
  let port = chaceon()
  let facts = list.filter(content.links, fn(l: Link) { l.kind == "chaceon" })
  section("chaceon", t(l, "the same rule, in rust"), [
    lede(t(
      l,
      "ww3-gpu keeps WW3 and lets its Fortran call C++ written with Kokkos, one flag per routine. its sister project replaces WW3 with Rust, with no Fortran in its process. both ports must give the Fortran's bits, and a tolerance is a diagnostic, never the verdict.",
    )),
    html.p([attribute.class("title")], [html.text(port.name)]),
    html.p([], [html.text(port.what)]),
    html.ul([attribute.class("people")], list.map(facts, link_item)),
    html.p([attribute.class("actions")], [
      html.a([attribute.class("button quiet"), attribute.href(port.url)], [
        html.text(t(l, "go to the rust repository")),
      ]),
    ]),
  ])
}

fn footer(l: String) -> Element(msg) {
  html.footer([attribute.class("wrap foot")], [
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
  ])
}
