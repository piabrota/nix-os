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

@external(javascript, "./ww3_gpu_content_ffi.mjs", "revision")
fn revision() -> String

@external(javascript, "./ww3_gpu_content_ffi.mjs", "sentences")
pub fn sentences(code: String) -> List(String)

@external(javascript, "./ww3_gpu_content_ffi.mjs", "exit")
fn exit(code: Int) -> Nil

// ---- the translations --------------------------------------------------------------------------
// One source, the English sentences of site/src, and a table for each other language,
// site/data/translations/<lang>.tsv, keyed by the English sentence itself (h0ffmann/h0ffmann#86).

/// What is wrong with a translation table, given the sentences the page translates: a row that
/// is not `source, translation, status[, note]`, a status other than draft or reviewed, a source
/// twice, a row whose sentence the page no longer has (an orphan), and a sentence with no row.
/// The page is not built while this is not empty.
pub fn translation_errors(
  table: String,
  sentences: List(String),
) -> List(String) {
  let rows = tsv_rows(table, "source")
  let row_errors =
    list.flat_map(rows, fn(cells) {
      case cells {
        [source, target, status] | [source, target, status, _] -> {
          let where = "the row " <> lit(source)
          list.flatten([
            case string.trim(target) {
              "" -> [where <> " has no translation"]
              _ -> []
            },
            case status {
              "draft" | "reviewed" -> []
              _ -> [where <> ": status is " <> lit(status)]
            },
            case list.contains(sentences, source) {
              True -> []
              False -> [
                where
                <> " is an orphan: the page has no such sentence now. Translate the new sentence and delete this row",
              ]
            },
          ])
        }
        _ -> [
          "a row has "
          <> int.to_string(list.length(cells))
          <> " cells, and it needs source, translation, status and an optional note: "
          <> string.join(cells, " | "),
        ]
      }
    })
  let sources = list.filter_map(rows, list.first)
  let twice =
    sources
    |> list.unique
    |> list.filter(fn(s) { list.count(sources, fn(x) { x == s }) > 1 })
    |> list.map(fn(s) { "the row " <> lit(s) <> " is there twice" })
  let missing =
    sentences
    |> list.unique
    |> list.filter(fn(s) { !list.contains(sources, s) })
    |> list.map(fn(s) { "the sentence " <> lit(s) <> " has no translation" })
  list.flatten([row_errors, twice, missing])
}

/// The pairs `#(source, translation)` of a table that passed `translation_errors`.
pub fn translations(table: String) -> List(#(String, String)) {
  tsv_rows(table, "source")
  |> list.filter_map(fn(cells) {
    case cells {
      [source, target, ..] -> Ok(#(source, target))
      _ -> Error(Nil)
    }
  })
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
"

pub fn render(
  site: #(String, String),
  doi: String,
  record_title: String,
  release: String,
  rev: String,
  adrs: List(Record),
  wfips: List(Record),
  notes: List(Note),
  people: List(Person),
  links: List(Link),
  reports: List(Report),
  bench_rows: List(Bench),
  stats: List(Stat),
  pt_br: List(#(String, String)),
  events: List(Event),
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
      "pub const record_title = " <> lit(record_title) <> "\n",
      "pub const latest_release = " <> lit(release) <> "\n",
      "pub const revision = " <> lit(rev) <> "\n",
      "/// The page in Brazilian Portuguese: each English sentence with its translation\n/// (site/data/translations/pt-BR.tsv).\n"
        <> items(
        "pt_br",
        "#(String, String)",
        list.map(pt_br, fn(p) { "#(" <> lit(p.0) <> ", " <> lit(p.1) <> ")" }),
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
  let table = read("../data/translations/pt-BR.tsv")
  case translation_errors(table, page_sentences) {
    [] -> Nil
    errors -> {
      list.each(errors, fn(e) { io.println_error("pt-BR.tsv: " <> e) })
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
      yaml(cff, "title"),
      latest_release(read(root <> "RELEASES.md")),
      revision(),
      sectioned_records("docs/ADRs.md", "ADR-"),
      records("docs/WFIPs/", "WFIP-", "Created"),
      notes,
      people,
      links,
      reports,
      bench_rows,
      stats,
      translations(table),
      lineage(lineage_table),
    )
  write("../src/ww3_gpu_site/content.gleam", text)
}
