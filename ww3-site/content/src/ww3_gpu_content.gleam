//// `gleam run` in site/content: reads the files of this repository and writes
//// ../src/ww3_gpu_site/content.gleam, the only place the site takes its facts from. Nothing in
//// site/src is typed by hand: a title, a status, a date or a DOI that the page shows is read here.
//// The pattern is h0ffmann/h0ffmann's `site/content`, itself from marola-research's `tools/content`.

import gleam/int
import gleam/io
import gleam/list
import gleam/string

/// The repository's root, seen from site/content.
const root = "../../"

/// An ADR or a WFIP: its number, the title its heading states, its status and its date.
pub type Record {
  Record(id: String, title: String, status: String, date: String, file: String)
}

pub type Note {
  Note(id: String, title: String, kind: String, status: String, file: String)
}

pub type Person {
  Person(
    role: String,
    name: String,
    orcid: String,
    affiliation: String,
    kind: String,
  )
}

pub type Link {
  Link(kind: String, name: String, url: String, what: String, source: String)
}

/// One dated event of site/data/lineage.tsv, the lineage page: a work this one descends from or
/// runs beside, or a release of this one, done or planned.
pub type Event {
  Event(
    date: String,
    status: String,
    kind: String,
    line: String,
    name: String,
    url: String,
    what: String,
    source: String,
  )
}

/// A port report of kokkos/port_report/: its name, its status line, its file, and the record of
/// kokkos/ports.tsv: was the Kokkos code regtested inside WW3. The port has no tests of its own;
/// WW3's regtests are its tests (ADR-0010).
pub type Report {
  Report(name: String, status: String, file: String, regtested: String)
}

/// One global number of the port, a row of site/data/port_score.tsv (scripts/port_score.py):
/// the share (the big number), the count behind it, and what it counts.
pub type Stat {
  Stat(name: String, share: String, count: String, what: String)
}

/// One tool of the reference toolchain, a row of VERSIONS.md's table: its name and its version.
pub type Tool {
  Tool(name: String, version: String)
}

/// One Archify drawing of docs/archify/dark.tsv whose PNG is committed, and the question it
/// answers (the Question column of docs/archify/README.md). `width` and `height` are the size it
/// was drawn at, in CSS pixels: half the PNG's, which is taken at twice the drawing's size.
pub type Figure {
  Figure(slug: String, question: String, width: String, height: String)
}

/// One repository of the side column, a row of site/data/orgs.tsv.
pub type Repo {
  Repo(org: String, name: String)
}

/// One row of a report's bench table. The speed-up is baseline / value, computed by the site.
pub type Bench {
  Bench(
    report: String,
    step: String,
    date: String,
    what: String,
    backend: String,
    value: String,
    baseline: String,
    unit: String,
    source: String,
  )
}

@external(javascript, "./ww3_gpu_content_ffi.mjs", "read")
fn read(path: String) -> String

@external(javascript, "./ww3_gpu_content_ffi.mjs", "write")
fn write(path: String, text: String) -> Nil

@external(javascript, "./ww3_gpu_content_ffi.mjs", "list")
fn list_dir(dir: String) -> List(String)

@external(javascript, "./ww3_gpu_content_ffi.mjs", "zenodo_people")
fn zenodo_people(path: String) -> String

@external(javascript, "./ww3_gpu_content_ffi.mjs", "zenodo_preprints")
fn zenodo_preprints(path: String) -> String

/// The first of `ids` on `host`, or "": an arXiv or aiXiv record is on the page only once
/// .zenodo.json lists it, so a record not yet submitted is never guessed.
pub fn on_host(ids: List(String), host: String) -> String {
  case list.find(ids, fn(id) { string.contains(id, "://" <> host <> "/") }) {
    Ok(id) -> id
    Error(Nil) -> ""
  }
}

@external(javascript, "./ww3_gpu_content_ffi.mjs", "revision")
fn revision() -> String

@external(javascript, "./ww3_gpu_content_ffi.mjs", "png_size")
fn png_size(path: String) -> String

@external(javascript, "./ww3_gpu_content_ffi.mjs", "locale")
fn locale(path: String) -> List(#(String, String))

@external(javascript, "./ww3_gpu_content_ffi.mjs", "commits")
fn commits() -> String

@external(javascript, "./ww3_gpu_content_ffi.mjs", "sentences")
pub fn sentences(code: String) -> List(String)

@external(javascript, "./ww3_gpu_content_ffi.mjs", "exit")
fn exit(code: Int) -> Nil

// ---- the locales -------------------------------------------------------------------------------
// One file for each language, site/locales/<lang>.json: a flat object from a key to the sentence
// in that language. en.json is the source. The page asks for a sentence with `t(l, "key")`.

/// The languages of the site, en first. Each has its file in site/locales/.
pub const languages = ["en", "pt-BR", "zh-CN", "ja-JP"]

/// What is wrong with the locale of `lang`, given its keys, the keys of en.json and the keys the
/// page asks for: a key the page asks for that en.json lacks, a key of en.json that this locale
/// lacks, and a key that en.json or the page no longer has (an orphan). The page is not built
/// while this is not empty.
pub fn locale_errors(
  lang: String,
  keys: List(String),
  en_keys: List(String),
  used: List(String),
) -> List(String) {
  let file = lang <> ".json"
  let unknown =
    used
    |> list.unique
    |> list.filter(fn(k) { !list.contains(en_keys, k) })
    |> list.map(fn(k) {
      "en.json: the page asks for " <> lit(k) <> ", and it has no such key"
    })
  let missing =
    en_keys
    |> list.filter(fn(k) { !list.contains(keys, k) })
    |> list.map(fn(k) { file <> ": the key " <> lit(k) <> " is missing" })
  let orphans =
    keys
    |> list.filter(fn(k) {
      !list.contains(en_keys, k) || !list.contains(used, k)
    })
    |> list.map(fn(k) {
      file
      <> ": the key "
      <> lit(k)
      <> " is an orphan: the page or en.json has no such key now"
    })
  case lang {
    "en" -> list.flatten([unknown, orphans])
    _ -> list.flatten([missing, orphans])
  }
}

// ---- parsing, pure and tested ------------------------------------------------------------------

/// The text of the first `# ` heading, or "".
pub fn heading(text: String) -> String {
  text
  |> string.split("\n")
  |> list.find(fn(line) { string.starts_with(line, "# ") })
  |> fn(found) {
    case found {
      Ok(line) ->
        line |> string.drop_start(2) |> string.replace("`", "") |> string.trim
      Error(_) -> ""
    }
  }
}

/// The value of a header-table row `| **Name** | value |`, or "".
pub fn field(text: String, name: String) -> String {
  let prefix = "| **" <> name <> "** |"
  text
  |> string.split("\n")
  |> list.find(fn(line) { string.starts_with(line, prefix) })
  |> fn(found) {
    case found {
      Ok(line) ->
        line
        |> string.drop_start(string.length(prefix))
        |> string.trim
        |> drop_suffix("|")
        |> string.trim
      Error(_) -> ""
    }
  }
}

/// The value of a `key: value` line (YAML front matter or a flat YAML file), unquoted, or "".
pub fn yaml(text: String, key: String) -> String {
  let prefix = key <> ":"
  text
  |> string.split("\n")
  |> list.find(fn(line) { string.starts_with(line, prefix) })
  |> fn(found) {
    case found {
      Ok(line) ->
        line
        |> string.drop_start(string.length(prefix))
        |> string.trim
        |> unquote
      Error(_) -> ""
    }
  }
}

/// The first word of a status cell: "Accepted" from "Accepted (2026-10-08, #97)".
pub fn status_word(cell: String) -> String {
  case string.split(string.trim(cell), " ") {
    [first, ..] -> drop_suffix(drop_suffix(first, "."), ",")
    [] -> ""
  }
}

/// The sections of a document that holds one record per `## <prefix>NNNN: …` heading, as docs/ADRs.md
/// holds every ADR (ADR-0022), each rewritten to open with `# <prefix>NNNN: …` so `heading` and
/// `field` read it as they read a file of its own. The text before the first such heading is dropped.
pub fn sections(text: String, prefix: String) -> List(String) {
  case string.split("\n" <> text, "\n## " <> prefix) {
    [_, ..rest] -> list.map(rest, fn(s) { "# " <> prefix <> s })
    [] -> []
  }
}

/// "ADR-0007" and the rest from "ADR-0007: the decision".
pub fn split_id(title: String) -> #(String, String) {
  case string.split_once(title, ": ") {
    Ok(#(id, rest)) -> #(id, rest)
    Error(_) -> #("", title)
  }
}

/// The text after a bold label at the start of a line, up to its first full stop:
/// "L2 (inside WW3, on the CPU)" from "**Status:** L2 (inside WW3, on the CPU). Not run …".
pub fn bold_line(text: String, label: String) -> String {
  let prefix = "**" <> label <> ":** "
  text
  |> string.split("\n")
  |> list.find(fn(line) { string.starts_with(line, prefix) })
  |> fn(found) {
    case found {
      Ok(line) -> {
        let rest =
          string.drop_start(line, string.length(prefix))
          |> string.replace("`", "")
        case string.split_once(rest, ". ") {
          Ok(#(first, _)) -> first
          Error(_) -> drop_suffix(string.trim(rest), ".")
        }
      }
      Error(_) -> ""
    }
  }
}

/// The rows of the table between `<!-- bench:start -->` and `<!-- bench:end -->`, as Bench
/// values: the header and the separator are not rows, and a row of another width is skipped.
pub fn benches(report: String, text: String) -> List(Bench) {
  case string.split_once(text, "<!-- bench:start -->") {
    Error(_) -> []
    Ok(#(_, rest)) -> {
      let block = case string.split_once(rest, "<!-- bench:end -->") {
        Ok(#(b, _)) -> b
        Error(_) -> ""
      }
      block
      |> string.split("\n")
      |> list.filter(fn(line) { string.starts_with(line, "| ") })
      |> list.filter_map(fn(line) {
        let cells =
          line
          |> string.trim
          |> drop_suffix("|")
          |> string.drop_start(1)
          |> string.split("|")
          |> list.map(string.trim)
        case cells {
          ["step", ..] -> Error(Nil)
          [step, date, what, backend, value, baseline, unit, source] ->
            Ok(Bench(
              report,
              step,
              date,
              what,
              backend,
              value,
              baseline,
              unit,
              source,
            ))
          _ -> Error(Nil)
        }
      })
    }
  }
}

/// The data rows of a TSV: no `#` line, no header, no empty line, split on tabs.
pub fn tsv_rows(text: String, header_first: String) -> List(List(String)) {
  text
  |> string.split("\n")
  |> list.filter(fn(line) {
    line != ""
    && !string.starts_with(line, "#")
    && !string.starts_with(line, header_first <> "\t")
  })
  |> list.map(fn(line) { string.split(line, "\t") })
}

/// "W3SNL1_KOKKOS" from "w3snl1md:w3snl1": the report a row of kokkos/ports.tsv has.
pub fn report_name(routine: String) -> String {
  let name = case string.split_once(routine, ":") {
    Ok(#(_, r)) -> r
    Error(_) -> routine
  }
  string.uppercase(name) <> "_KOKKOS"
}

/// "W3SRC3MD_TABU_STRESS_KOKKOS" from "w3src3md:tabu_stress": the report name of a routine whose
/// name another module also has (scripts/port_score.py, report_name).
pub fn qualified_report_name(routine: String) -> String {
  string.uppercase(string.replace(routine, ":", "_")) <> "_KOKKOS"
}

/// The regtested cell of kokkos/ports.tsv for a report, or "". A module-qualified report name
/// matches first, so W3SRC3MD_TABU_STRESS_KOKKOS is not taken for ST4's TABU_STRESS_KOKKOS.
pub fn port_record(ports_tsv: String, report: String) -> String {
  let rows = tsv_rows(ports_tsv, "routine")
  let by = fn(name: fn(String) -> String) {
    list.find(rows, fn(cells) {
      case cells {
        [routine, ..] -> name(routine) == report
        [] -> False
      }
    })
  }
  let found = case by(qualified_report_name) {
    Ok(cells) -> Ok(cells)
    Error(_) -> by(report_name)
  }
  case found {
    Ok([_, _, _, _, _, regtested, ..]) -> regtested
    _ -> ""
  }
}

/// The first `## ` heading of RELEASES.md, or "" when the file has none.
pub fn latest_release(text: String) -> String {
  text
  |> string.split("\n")
  |> list.find(fn(line) { string.starts_with(line, "## ") })
  |> fn(found) {
    case found {
      Ok(line) -> string.trim(string.drop_start(line, 3))
      Error(_) -> ""
    }
  }
}

pub fn person(line: String) -> Result(Person, Nil) {
  case string.split(line, "\t") {
    [role, name, orcid, affiliation, kind] ->
      Ok(Person(role, name, orcid, affiliation, kind))
    _ -> Error(Nil)
  }
}

/// A row of site/data/*.tsv; a line starting with `#` is a comment.
pub fn link(line: String) -> Result(Link, Nil) {
  case string.starts_with(line, "#"), string.split(line, "\t") {
    False, [kind, name, url, what, source] ->
      Ok(Link(kind, name, url, what, source))
    _, _ -> Error(Nil)
  }
}

// ---- the lineage -------------------------------------------------------------------------------

/// "2026", "2026-02" or "2026-02-17": a date as precise as its source, never more.
pub fn is_date(s: String) -> Bool {
  let digits = fn(part, n) { string.length(part) == n && is_number(part) }
  case string.split(s, "-") {
    [y] -> digits(y, 4)
    [y, m] -> digits(y, 4) && digits(m, 2)
    [y, m, d] -> digits(y, 4) && digits(m, 2) && digits(d, 2)
    _ -> False
  }
}

/// What is wrong with site/data/lineage.tsv: a row without its eight cells, a date that is not
/// YYYY[-MM[-DD]], a status other than done or planned, a kind other than model or port, or an
/// empty name, link or source. The page is not built while this is not empty.
pub fn lineage_errors(table: String) -> List(String) {
  tsv_rows(table, "date")
  |> list.flat_map(fn(cells) {
    case cells {
      [date, status, kind, _, name, url, _, source] -> {
        let where = "the row " <> lit(name)
        list.flatten([
          case is_date(date) {
            True -> []
            False -> [where <> ": date is " <> lit(date)]
          },
          case status {
            "done" | "planned" -> []
            _ -> [where <> ": status is " <> lit(status)]
          },
          case kind {
            "model" | "port" -> []
            _ -> [where <> ": kind is " <> lit(kind)]
          },
          case name == "" || url == "" || source == "" {
            True -> [where <> " needs a name, a link and a source"]
            False -> []
          },
        ])
      }
      _ -> [
        "a row has "
        <> int.to_string(list.length(cells))
        <> " cells, and it needs date, status, kind, line, name, link, what and source: "
        <> string.join(cells, " | "),
      ]
    }
  })
}

/// The events of a table that passed `lineage_errors`, oldest first.
pub fn lineage(table: String) -> List(Event) {
  tsv_rows(table, "date")
  |> list.filter_map(fn(cells) {
    case cells {
      [date, status, kind, line, name, url, what, source] ->
        Ok(Event(date, status, kind, line, name, url, what, source))
      _ -> Error(Nil)
    }
  })
  |> list.sort(fn(a, b) { string.compare(a.date, b.date) })
}

/// The repositories of site/data/orgs.tsv, in the order of the file.
pub fn repos(table: String) -> List(Repo) {
  tsv_rows(table, "org")
  |> list.filter_map(fn(row) {
    case row {
      [org, name, _, _] if org != "" && name != "" -> Ok(Repo(org, name))
      _ -> Error(Nil)
    }
  })
}

// ---- the tools and the figures -----------------------------------------------------------------

/// The cells of a Markdown table row, trimmed, with no backticks.
fn cells(line: String) -> List(String) {
  line
  |> string.trim
  |> drop_suffix("|")
  |> string.drop_start(1)
  |> string.split("|")
  |> list.map(fn(c) { c |> string.replace("`", "") |> string.trim })
}

/// The tools of the table under the `## ` heading that starts with `title` in VERSIONS.md: the
/// first two cells of each row, without the header and the separator.
pub fn tools(text: String, title: String) -> List(Tool) {
  case string.split_once(text, "\n## " <> title) {
    Error(_) -> []
    Ok(#(_, rest)) -> {
      let body = case string.split_once(rest, "\n## ") {
        Ok(#(b, _)) -> b
        Error(_) -> rest
      }
      body
      |> string.split("\n")
      |> list.filter(fn(line) { string.starts_with(line, "|") })
      |> list.drop(2)
      |> list.filter_map(fn(line) {
        case cells(line) {
          [name, version, ..] if name != "" -> Ok(Tool(name, version))
          _ -> Error(Nil)
        }
      })
    }
  }
}

/// The drawings of dark.tsv whose `<slug>.png` is in `files`, each with the Question cell of its
/// row in docs/archify/README.md (the row whose first cell names `<slug>.json`), or "".
pub fn figures(
  dark_tsv: String,
  readme: String,
  files: List(String),
  size: fn(String) -> #(String, String),
) -> List(Figure) {
  let rows =
    readme
    |> string.split("\n")
    |> list.filter(fn(line) { string.starts_with(line, "| [") })
  tsv_rows(dark_tsv, "slug")
  |> list.filter_map(fn(row) {
    case row {
      [slug, ..] ->
        case list.contains(files, slug <> ".png") {
          False -> Error(Nil)
          True -> {
            let question =
              list.find_map(rows, fn(line) {
                case cells(line) {
                  [source, _, _, question, ..] ->
                    case string.starts_with(source, "[" <> slug <> ".json]") {
                      True -> Ok(question)
                      False -> Error(Nil)
                    }
                  _ -> Error(Nil)
                }
              })
            let #(width, height) = size(slug)
            case question {
              Ok(q) -> Ok(Figure(slug, q, width, height))
              Error(_) -> Ok(Figure(slug, "", width, height))
            }
          }
        }
      [] -> Error(Nil)
    }
  })
}

fn drop_suffix(s: String, suffix: String) -> String {
  case string.ends_with(s, suffix) {
    True -> string.drop_end(s, string.length(suffix))
    False -> s
  }
}

fn unquote(s: String) -> String {
  case string.starts_with(s, "\""), string.ends_with(s, "\"") {
    True, True -> s |> string.drop_start(1) |> string.drop_end(1)
    _, _ -> s
  }
}

// ---- rendering ---------------------------------------------------------------------------------

/// A Gleam string literal.
pub fn lit(s: String) -> String {
  "\""
  <> s
  |> string.replace("\\", "\\\\")
  |> string.replace("\"", "\\\"")
  |> string.replace("\n", "\\n")
  <> "\""
}

fn call(name: String, args: List(String)) -> String {
  name <> "(" <> string.join(list.map(args, lit), ", ") <> ")"
}

fn items(name: String, type_: String, rows: List(String)) -> String {
  let body = case rows {
    [] -> "[]"
    _ -> "[\n  " <> string.join(rows, ",\n  ") <> ",\n]"
  }
  "pub const " <> name <> ": List(" <> type_ <> ") = " <> body <> "\n"
}

const types =
  "pub type Record {
  Record(id: String, title: String, status: String, date: String, file: String)
}

pub type Note {
  Note(id: String, title: String, kind: String, status: String, file: String)
}

pub type Person {
  Person(role: String, name: String, orcid: String, affiliation: String, kind: String)
}

pub type Link {
  Link(kind: String, name: String, url: String, what: String, source: String)
}

pub type Event {
  Event(date: String, status: String, kind: String, line: String, name: String, url: String, what: String, source: String)
}

pub type Report {
  Report(name: String, status: String, file: String, regtested: String)
}

pub type Stat {
  Stat(name: String, share: String, count: String, what: String)
}

pub type Bench {
  Bench(report: String, step: String, date: String, what: String, backend: String, value: String, baseline: String, unit: String, source: String)
}

pub type Tool {
  Tool(name: String, version: String)
}

pub type Figure {
  Figure(slug: String, question: String, width: String, height: String)
}

pub type Repo {
  Repo(org: String, name: String)
}
"

pub fn render(
  site: #(String, String),
  doi: String,
  preprints: #(String, String),
  record_title: String,
  release: String,
  rev: String,
  commit_count: String,
  adrs: List(Record),
  wfips: List(Record),
  notes: List(Note),
  people: List(Person),
  links: List(Link),
  reports: List(Report),
  bench_rows: List(Bench),
  stats: List(Stat),
  locales: List(#(String, List(#(String, String)))),
  events: List(Event),
  tool_rows: List(Tool),
  figure_rows: List(Figure),
  repo_rows: List(Repo),
) -> String {
  let record = fn(r: Record) {
    call("Record", [r.id, r.title, r.status, r.date, r.file])
  }
  string.join(
    [
      "//// Generated by site/content from the files of this repository (`just site`). Do not edit:\n//// change the file it was read from.\n",
      types,
      "pub const site_title = " <> lit(site.0) <> "\n",
      "pub const site_subtitle = " <> lit(site.1) <> "\n",
      "pub const doi = " <> lit(doi) <> "\n",
      "/// The aiXiv and arXiv records of the preprint (.zenodo.json), \"\" when it has none.\n",
      "pub const aixiv = " <> lit(preprints.0) <> "\n",
      "pub const arxiv = " <> lit(preprints.1) <> "\n",
      "pub const record_title = " <> lit(record_title) <> "\n",
      "pub const latest_release = " <> lit(release) <> "\n",
      "pub const revision = " <> lit(rev) <> "\n",
      "pub const commits = " <> lit(commit_count) <> "\n",
      items(
        "tools",
        "Tool",
        list.map(tool_rows, fn(t) { call("Tool", [t.name, t.version]) }),
      ),
      items(
        "repos",
        "Repo",
        list.map(repo_rows, fn(r) { call("Repo", [r.org, r.name]) }),
      ),
      items(
        "figures",
        "Figure",
        list.map(figure_rows, fn(f) {
          call("Figure", [f.slug, f.question, f.width, f.height])
        }),
      ),
      "/// Each language with its sentences, key and text (site/locales/<lang>.json).\n"
        <> items(
        "locales",
        "#(String, List(#(String, String)))",
        list.map(locales, fn(entry) {
          "#("
          <> lit(entry.0)
          <> ", ["
          <> string.join(
            list.map(entry.1, fn(p) {
              "#(" <> lit(p.0) <> ", " <> lit(p.1) <> ")"
            }),
            ", ",
          )
          <> "])"
        }),
      ),
      items("adrs", "Record", list.map(adrs, record)),
      items("wfips", "Record", list.map(wfips, record)),
      items(
        "notes",
        "Note",
        list.map(notes, fn(n) {
          call("Note", [n.id, n.title, n.kind, n.status, n.file])
        }),
      ),
      items(
        "people",
        "Person",
        list.map(people, fn(p) {
          call("Person", [p.role, p.name, p.orcid, p.affiliation, p.kind])
        }),
      ),
      items(
        "links",
        "Link",
        list.map(links, fn(l) {
          call("Link", [l.kind, l.name, l.url, l.what, l.source])
        }),
      ),
      items(
        "events",
        "Event",
        list.map(events, fn(e) {
          call("Event", [
            e.date,
            e.status,
            e.kind,
            e.line,
            e.name,
            e.url,
            e.what,
            e.source,
          ])
        }),
      ),
      items(
        "reports",
        "Report",
        list.map(reports, fn(r) {
          call("Report", [r.name, r.status, r.file, r.regtested])
        }),
      ),
      items(
        "stats",
        "Stat",
        list.map(stats, fn(s) {
          call("Stat", [s.name, s.share, s.count, s.what])
        }),
      ),
      items(
        "benches",
        "Bench",
        list.map(bench_rows, fn(b) {
          call("Bench", [
            b.report,
            b.step,
            b.date,
            b.what,
            b.backend,
            b.value,
            b.baseline,
            b.unit,
            b.source,
          ])
        }),
      ),
    ],
    "\n",
  )
}

// ---- reading the repository --------------------------------------------------------------------

fn matching(dir: String, prefix: String) -> List(String) {
  list_dir(root <> dir)
  |> list.filter(fn(name) {
    string.starts_with(name, prefix) && string.ends_with(name, ".md")
  })
}

fn records(dir: String, prefix: String, date_field: String) -> List(Record) {
  matching(dir, prefix)
  |> list.filter(fn(name) { !string.contains(name, ".tasks.") })
  |> list.map(fn(name) {
    let text = read(root <> dir <> name)
    let #(id, title) = split_id(heading(text))
    Record(
      id,
      title,
      status_word(field(text, "Status")),
      field(text, date_field),
      dir <> name,
    )
  })
}

fn sectioned_records(file: String, prefix: String) -> List(Record) {
  sections(read(root <> file), prefix)
  |> list.map(fn(text) {
    let #(id, title) = split_id(heading(text))
    Record(
      id,
      title,
      status_word(field(text, "Status")),
      field(text, "Date"),
      file <> "#" <> string.lowercase(id),
    )
  })
}

fn is_number(s: String) -> Bool {
  case int.parse(s) {
    Ok(_) -> True
    Error(_) -> False
  }
}

pub fn main() -> Nil {
  let site = "../src/ww3_gpu_site/"
  let page_sentences =
    list_dir(site)
    |> list.filter(fn(name) {
      string.ends_with(name, ".gleam") && name != "content.gleam"
    })
    |> list.flat_map(fn(name) { sentences(read(site <> name)) })
  let locales =
    list.map(languages, fn(lang) {
      #(lang, locale("../locales/" <> lang <> ".json"))
    })
  let keys_of = fn(entry: #(String, List(#(String, String)))) {
    list.map(entry.1, fn(p) { p.0 })
  }
  let en_keys = case locales {
    [en, ..] -> keys_of(en)
    [] -> []
  }
  case
    list.flat_map(locales, fn(entry) {
      locale_errors(entry.0, keys_of(entry), en_keys, page_sentences)
    })
  {
    [] -> Nil
    errors -> {
      list.each(errors, io.println_error)
      exit(1)
    }
  }
  let lineage_table = read("../data/lineage.tsv")
  case lineage_errors(lineage_table) {
    [] -> Nil
    errors -> {
      list.each(errors, fn(e) { io.println_error("lineage.tsv: " <> e) })
      exit(1)
    }
  }
  let notes =
    matching("notes/", "")
    |> list.filter(fn(name) { name != "index.md" && name != "README.md" })
    |> list.map(fn(name) {
      let text = read(root <> "notes/" <> name)
      Note(
        yaml(text, "id"),
        yaml(text, "title"),
        yaml(text, "type"),
        yaml(text, "status"),
        "notes/" <> name,
      )
    })
    |> list.filter(fn(n) { n.id != "" && n.title != "" })
    |> list.reverse
  let meta = read(root <> "pubs/site/meta.yaml")
  let cff = read(root <> "CITATION.cff")
  let people =
    zenodo_people(root <> ".zenodo.json")
    |> string.split("\n")
    |> list.filter_map(person)
  let preprints = zenodo_preprints(root <> ".zenodo.json") |> string.split("\n")
  let links =
    read("../data/related.tsv")
    |> string.split("\n")
    |> list.filter_map(link)
  let report_files =
    list_dir(root <> "kokkos/port_report")
    |> list.filter(fn(name) { string.ends_with(name, "_KOKKOS.md") })
  let ports_tsv = read(root <> "kokkos/ports.tsv")
  let reports =
    list.map(report_files, fn(name) {
      let text = read(root <> "kokkos/port_report/" <> name)
      Report(
        heading(text),
        bold_line(text, "Status"),
        "kokkos/port_report/" <> name,
        port_record(ports_tsv, heading(text)),
      )
    })
  let stats =
    tsv_rows(read("../data/port_score.tsv"), "name")
    |> list.filter_map(fn(cells) {
      case cells {
        [name, share, count, what] -> Ok(Stat(name, share, count, what))
        _ -> Error(Nil)
      }
    })
  let bench_rows =
    list.flat_map(report_files, fn(name) {
      let text = read(root <> "kokkos/port_report/" <> name)
      benches(heading(text), text)
    })
  let text =
    render(
      #(yaml(meta, "title"), yaml(meta, "subtitle")),
      yaml(cff, "doi"),
      #(on_host(preprints, "aixiv.online"), on_host(preprints, "arxiv.org")),
      yaml(cff, "title"),
      latest_release(read(root <> "RELEASES.md")),
      revision(),
      commits(),
      sectioned_records("docs/ADRs.md", "ADR-"),
      records("docs/WFIPs/", "WFIP-", "Created"),
      notes,
      people,
      links,
      reports,
      bench_rows,
      stats,
      locales,
      lineage(lineage_table),
      tools(read(root <> "VERSIONS.md"), "The reference toolchain"),
      figures(
        read(root <> "docs/archify/dark.tsv"),
        read(root <> "docs/archify/README.md"),
        list_dir(root <> "docs/archify"),
        fn(slug) {
          case
            string.split(
              png_size(root <> "docs/archify/" <> slug <> ".png"),
              " ",
            )
          {
            [w, h] -> #(w, h)
            _ -> #("", "")
          }
        },
      ),
      repos(read("../data/orgs.tsv")),
    )
  write("../src/ww3_gpu_site/content.gleam", text)
}
