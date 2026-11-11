import gleam/list
import gleam/string
import gleeunit
import ww3_gpu_content as c

pub fn main() -> Nil {
  gleeunit.main()
}

const adr =
  "# ADR-0007: Graphify is adopted as an offline locator

| | |
|---|---|
| **Status** | Accepted (2026-10-12, #97) |
| **Date** | 2026-10-11 |
"

pub fn heading_test() {
  assert c.heading(adr) == "ADR-0007: Graphify is adopted as an offline locator"
  assert c.heading("no heading here") == ""
  assert c.heading("# 12. Porting a kernel: `W3SNL1`")
    == "12. Porting a kernel: W3SNL1"
}

pub fn field_test() {
  assert c.field(adr, "Date") == "2026-10-11"
  assert c.field(adr, "Status") == "Accepted (2026-10-12, #97)"
  assert c.field(adr, "Missing") == ""
}

pub fn status_word_test() {
  assert c.status_word("Accepted (2026-10-12, #97)") == "Accepted"
  assert c.status_word("Draft.") == "Draft"
  assert c.status_word("") == ""
}

pub fn sections_test() {
  let doc =
    "# Architecture Decision Records\n\n| **Status** | not a record |\n\n<a id=\"adr-0001\"></a>\n\n## ADR-0001: First\n\n| **Status** | Accepted |\n\n### Context\n\n## ADR-0002: Second\n\n| **Date** | 2026-10-08 |\n"
  let parts = c.sections(doc, "ADR-")
  assert list.map(parts, c.heading) == ["ADR-0001: First", "ADR-0002: Second"]
  assert list.map(parts, fn(s) { c.field(s, "Status") }) == ["Accepted", ""]
  assert c.sections("no records", "ADR-") == []
}

pub fn split_id_test() {
  assert c.split_id("ADR-0007: the decision: with a colon")
    == #("ADR-0007", "the decision: with a colon")
  assert c.split_id("no id") == #("", "no id")
}

pub fn yaml_test() {
  let note = "---\nid: \"202610141200\"\ntitle: A note\ntype: permanent\n---\n"
  assert c.yaml(note, "id") == "202610141200"
  assert c.yaml(note, "title") == "A note"
  assert c.yaml(note, "status") == ""
}

pub fn latest_release_test() {
  assert c.latest_release(
      "# Releases\n\n## v0.1.4: what changed\n\n## v0.1.3\n",
    )
    == "v0.1.4: what changed"
  assert c.latest_release("") == ""
}

pub fn row_test() {
  assert c.link("# a comment\tx\ty\tz\tw") == Error(Nil)
  assert c.link(
      "author\tFabio Akita\thttps://github.com/akitaonrails\twhat\tsource",
    )
    == Ok(c.Link(
      "author",
      "Fabio Akita",
      "https://github.com/akitaonrails",
      "what",
      "source",
    ))
  assert c.person(
      "contributor\tGuimarães, P.V.\t0000-0002-1686-4722\tUFSC\tSupervisor",
    )
    == Ok(c.Person(
      "contributor",
      "Guimarães, P.V.",
      "0000-0002-1686-4722",
      "UFSC",
      "Supervisor",
    ))
}

pub fn lit_test() {
  assert c.lit("a \"quote\" and \\ back\nslash")
    == "\"a \\\"quote\\\" and \\\\ back\\nslash\""
}

pub fn empty_list_test() {
  let text =
    c.render(
      #("t", "s"),
      "d",
      "r",
      "",
      "x",
      [],
      [],
      [],
      [],
      [],
      [],
      [],
      [],
      [
        #("the book", "o livro"),
      ],
      [],
    )
  assert text |> contains("pub const notes: List(Note) = []")
  assert text |> contains("pub const events: List(Event) = []")
  assert text |> contains("#(\"the book\", \"o livro\")")
}

// One source and a table: a sentence is the English literal of `t(l, "…")`, in any layout the
// formatter gives the call, and never one in a comment.
pub fn sentences_test() {
  let code =
    "// t(l, \"in a comment\")
  html.text(t(l, \"the book\"))
  lede(t(
    l,
    \"a \\\"quoted\\\" word\",
  ))
  app.t(l, \"the PDF\")
  at(l, \"not a sentence\")"
  assert c.sentences(code) == ["the book", "a \"quoted\" word", "the PDF"]
}

pub fn a_whole_table_passes_test() {
  let table =
    "# source\tpt-BR\tstatus\tnote (optional)
the book\to livro\tdraft
the PDF\to PDF\treviewed\ta note"
  assert c.translation_errors(table, ["the book", "the PDF", "the book"]) == []
  assert c.translations(table)
    == [#("the book", "o livro"), #("the PDF", "o PDF")]
}

// The judge is judged: a table with one fault of each kind is refused for each.
pub fn a_bad_table_is_refused_test() {
  let table =
    "the book\to livro\tdraft
the book\to livro\tdraft
the PDF\t\tdraft
an old sentence\tuma frase velha\tdraft
the repository\to repositório\tdone
three cells\tonly"
  let errors =
    c.translation_errors(table, [
      "the book",
      "the PDF",
      "the repository",
      "a new sentence",
    ])
    |> string.join("\n")
  list.each(
    [
      "\"the book\" is there twice",
      "\"the PDF\" has no translation",
      "\"an old sentence\" is an orphan",
      "status is \"done\"",
      "a row has 2 cells",
      "the sentence \"a new sentence\" has no translation",
    ],
    fn(fault) {
      assert contains(errors, fault)
    },
  )
}

fn contains(haystack: String, needle: String) -> Bool {
  string.contains(haystack, needle)
}

const report =
  "# W3SNL1_KOKKOS

**Status:** L2 (inside WW3, on the CPU). Not run on a GPU inside WW3 yet.

<!-- bench:start -->
| step | date | what | backend | value | baseline | unit | source |
|---|---|---|---|---|---|---|---|
| 1 | 2026-09-15 | the shim | Serial | 25.88 | 25.88 | ms | bench/x.json |
| 2 | 2026-10-14 | ww3_shel | OpenMP | 217.9 | 152.7 | s | just full-ww3-gpu |
| 3 | too | few | cells |
<!-- bench:end -->

| 9 | outside | the | markers | 1 | 1 | s | x |
"

pub fn bold_line_test() {
  assert c.bold_line(report, "Status") == "L2 (inside WW3, on the CPU)"
  assert c.bold_line(report, "Missing") == ""
  assert c.bold_line("**Status:** L2, with `W3SNL1`.", "Status")
    == "L2, with W3SNL1"
}

pub fn benches_test() {
  let rows = c.benches("W3SNL1_KOKKOS", report)
  assert rows
    == [
      c.Bench(
        "W3SNL1_KOKKOS",
        "1",
        "2026-09-15",
        "the shim",
        "Serial",
        "25.88",
        "25.88",
        "ms",
        "bench/x.json",
      ),
      c.Bench(
        "W3SNL1_KOKKOS",
        "2",
        "2026-10-14",
        "ww3_shel",
        "OpenMP",
        "217.9",
        "152.7",
        "s",
        "just full-ww3-gpu",
      ),
    ]
  assert c.benches("x", "no table") == []
}

const ports =
  "# a comment
# ww3_rev\tabc
routine\tfile\tlines\tstatus\tevidence\tregtested\tkokkos
w3snl1md:w3snl1\tf:1-2\t2\tL2\te\tyes: L2\tkokkos/src/a.cpp
"

pub fn report_name_test() {
  assert c.report_name("w3snl1md:w3snl1") == "W3SNL1_KOKKOS"
  assert c.report_name("w3srce") == "W3SRCE_KOKKOS"
}

pub fn port_record_test() {
  assert c.port_record(ports, "W3SNL1_KOKKOS") == "yes: L2"
  assert c.port_record(ports, "W3SDS4_KOKKOS") == ""
}

const twin_ports =
  "routine\tfile\tlines\tstatus\tevidence\tregtested\tkokkos
w3src4md:tabu_stress\tf:1-2\t2\tported\te\tno: st4\tkokkos/src/a.cpp
w3src3md:tabu_stress\tf:3-4\t2\tported\te\tno: st3\tkokkos/src/b.hpp
"

pub fn port_record_qualified_test() {
  assert c.qualified_report_name("w3src3md:tabu_stress")
    == "W3SRC3MD_TABU_STRESS_KOKKOS"
  assert c.port_record(twin_ports, "W3SRC3MD_TABU_STRESS_KOKKOS") == "no: st3"
  assert c.port_record(twin_ports, "TABU_STRESS_KOKKOS") == "no: st4"
}

// The lineage: a date only as precise as its source, two statuses, two kinds, oldest first.
pub fn is_date_test() {
  assert c.is_date("2027")
  assert c.is_date("2027-02")
  assert c.is_date("2025-11-17")
  assert !c.is_date("Feb 2027")
  assert !c.is_date("2027-2")
  assert !c.is_date("")
}

pub fn lineage_test() {
  let table =
    "# a comment\ndate\tstatus\tkind\tline\tname\tlink\twhat\tsource\n"
    <> "2027-02\tplanned\tport\tthis work\tb\thttps://b\tlater\tthe owner\n"
    <> "1991-06\tdone\tmodel\twave\ta\thttps://a\tfirst\tCrossref\n"
  assert c.lineage_errors(table) == []
  assert list.map(c.lineage(table), fn(e) { e.name }) == ["a", "b"]
}

pub fn a_bad_lineage_row_is_refused_test() {
  let errors =
    c.lineage_errors(
      "Feb 2027\tsoon\tidea\tx\tn\thttps://n\tw\ts\n2027\tdone\tport\n",
    )
  assert list.length(errors) == 4
}
