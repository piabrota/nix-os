//// What every design shares: the anchor bar, the structure, why it is open, the dogma, the FOSS
//// inventory, the board (the people, each with a GitHub pill and their website), the partners (each
//// with its logo as GitHub publishes it), and the forks, a PUBLIC inventory in the manner of
//// h0ffmann/h0ffmann. Every fact is in mockups/data.nix.

import gleam/int
import gleam/list
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import piabrota_site/data.{
  type Fork, type Layer, type Partner, type Person, type Principle, type Project,
}
import piabrota_site/parts

pub fn sections() -> List(Element(msg)) {
  [
    anchors(),
    structure(),
    why(),
    dogma(),
    inventory(),
    board(),
    partners(),
    forks(),
  ]
}

/// The bar of anchors, closed-source's: it stays at the top while the page scrolls.
fn anchors() -> Element(msg) {
  html.nav([attribute.class("anchors"), attribute.aria_label("On this page")], [
    html.div([attribute.class("wrap")], {
      use #(id, label) <- list.map([
        #("structure", "Structure"),
        #("why", "Why it is open"),
        #("dogma", "Dogma"),
        #("inventory", "Inventory"),
        #("board", "Board"),
        #("partners", "Partners"),
        #("forks", "Forks"),
      ])
      html.a([attribute.href("#" <> id)], [html.text(label)])
    }),
  ])
}

/// How the company is laid out: the chart, the umbrella, the products and the brain.
fn structure() -> Element(msg) {
  html.section([attribute.class("wrap"), attribute.id("structure")], [
    parts.section_head("Structure", "from piabrota/mu and piabrota/dojo"),
    html.ul(
      [attribute.class("layers")],
      list.map(data.structure, fn(l: Layer) {
        html.li([attribute.class("layer")], [
          html.span([attribute.class("role")], [html.text(l.role)]),
          html.h3([], [
            html.a([attribute.href(l.href)], [html.text(l.name)]),
          ]),
          html.p([], [html.text(l.text)]),
        ])
      }),
    ),
  ])
}

fn why() -> Element(msg) {
  html.section([attribute.class("wrap"), attribute.id("why")], [
    parts.section_head("Why it is open", "from piabrota/.github"),
    html.ul(
      [attribute.class("reasons")],
      list.map(data.why, fn(p: Principle) {
        html.li([], [
          html.h3([], [html.text(p.title)]),
          html.p([], [html.text(p.text)]),
        ])
      }),
    ),
  ])
}

/// The ten invariants. The list numbers them; the numbers are never typed.
fn dogma() -> Element(msg) {
  html.section([attribute.class("wrap"), attribute.id("dogma")], [
    parts.section_head("Dogma", "from piabrota/mu, DOGMA.md"),
    html.p([attribute.class("sub")], [
      html.text(
        "The ten invariants. They bind every repo, every person and every agent in the company.",
      ),
    ]),
    html.ol(
      [attribute.class("dogma")],
      list.map(data.dogma, fn(p: Principle) {
        html.li([], [
          html.strong([], [html.text(p.title <> " ")]),
          html.text(p.text),
        ])
      }),
    ),
  ])
}

/// Every FOSS project, with each fact in words: closed-source's detail, one entry a project.
fn inventory() -> Element(msg) {
  html.section([attribute.class("wrap"), attribute.id("inventory")], [
    parts.section_head("FOSS inventory", "gh repo view, 2026-11-01"),
    html.p([attribute.class("sub")], [
      html.text(
        int.to_string(list.length(data.projects))
        <> " projects. Own means the org's repository; personal means a repository that dojo pins and a person keeps.",
      ),
    ]),
    html.ol([attribute.class("inventory")], list.map(data.projects, entry)),
  ])
}

fn entry(p: Project) -> Element(msg) {
  let fact = fn(term, value) {
    html.div([], [
      html.dt([], [html.text(term)]),
      html.dd([], [html.text(value)]),
    ])
  }
  html.li(
    [
      attribute.class("entry"),
      attribute.data("state", parts.state_class(p.state)),
    ],
    [
      html.div([attribute.class("card-head")], [
        html.h3([], [html.text(p.name)]),
        parts.pill(p.state),
      ]),
      html.p([attribute.class("blurb")], [html.text(p.blurb)]),
      html.dl([], [
        fact("origin", p.origin),
        fact("language", p.lang),
        fact("licence", p.licence),
        fact("last push", p.pushed),
      ]),
      html.div([attribute.class("links")], [
        html.a([attribute.href(p.repo), attribute.rel("noopener")], [
          html.text("repository ↗"),
        ]),
        parts.address(p),
      ]),
    ],
  )
}

/// The avatar GitHub publishes for a login, at twice the drawn size for sharp screens.
fn avatar(login: String, size: Int, class: String) -> Element(msg) {
  html.img([
    attribute.src(
      "https://avatars.githubusercontent.com/"
      <> login
      <> "?s="
      <> int.to_string(size * 2),
    ),
    attribute.alt(""),
    attribute.width(size),
    attribute.height(size),
    attribute.class(class),
    attribute.attribute("loading", "lazy"),
  ])
}

/// A GitHub pill: the avatar and the @login, linked to the profile.
pub fn github_pill(login: String) -> Element(msg) {
  html.a(
    [
      attribute.class("gh"),
      attribute.href("https://github.com/" <> login),
      attribute.rel("noopener"),
    ],
    [avatar(login, 22, "face"), html.text("@" <> login)],
  )
}

/// A website pill: the host, without its scheme.
fn site_pill(url: String) -> Element(msg) {
  let host = case url {
    "https://" <> rest -> rest
    "http://" <> rest -> rest
    other -> other
  }
  let host = case string.ends_with(host, "/") {
    True -> string.drop_end(host, 1)
    False -> host
  }
  html.a(
    [attribute.class("gh site"), attribute.href(url), attribute.rel("noopener")],
    [html.text(host <> " ↗")],
  )
}

fn board() -> Element(msg) {
  html.section([attribute.class("wrap"), attribute.id("board")], [
    parts.section_head("Board", "from their public GitHub profiles"),
    html.p([attribute.class("sub")], [
      html.text("The people who build piabrota."),
    ]),
    html.ul(
      [attribute.class("people")],
      list.map(data.people, fn(p: Person) {
        html.li([attribute.class("person")], [
          avatar(p.login, 56, "portrait"),
          html.div([], [
            html.h4([], [
              html.text(case p.name {
                "" -> "@" <> p.login
                name -> name
              }),
            ]),
            html.p([attribute.class("about")], [
              html.text(p.about <> " · " <> p.place),
            ]),
            html.div([attribute.class("pills")], [
              github_pill(p.login),
              case p.site {
                "" -> element.none()
                site -> site_pill(site)
              },
            ]),
          ]),
        ])
      }),
    ),
  ])
}

fn partners() -> Element(msg) {
  html.section([attribute.class("wrap"), attribute.id("partners")], [
    parts.section_head("Partners", "logos as GitHub publishes them"),
    html.ul(
      [attribute.class("partners")],
      list.map(data.partners, fn(p: Partner) {
        html.li([], [
          html.a(
            [
              attribute.class("partner"),
              attribute.href(p.site),
              attribute.rel("noopener"),
            ],
            [
              html.img([
                attribute.src(
                  "https://avatars.githubusercontent.com/"
                  <> p.login
                  <> "?s=128",
                ),
                attribute.alt(p.name <> " logo"),
                attribute.width(56),
                attribute.height(56),
                attribute.class("logo"),
                attribute.attribute("loading", "lazy"),
              ]),
              html.span([], [
                html.b([], [html.text(p.name)]),
                html.text(p.about),
              ]),
            ],
          ),
        ])
      }),
    ),
    html.aside([attribute.class("credit")], [
      html.p([], [
        html.strong([], [html.text("Work with us. ")]),
        html.text(
          "Partnership or white label requests: " <> data.contact <> ".",
        ),
      ]),
      html.div([attribute.class("actions")], [
        parts.button(parts.sponsor, "Open Collective", True),
        parts.button(
          "https://github.com/sponsors/h0ffmann",
          "GitHub Sponsors",
          False,
        ),
      ]),
    ]),
  ])
}

/// Every fork under piabrota. "PUBLIC" stays in capitals, as on h0ffmann/h0ffmann: GitHub keeps
/// a fork of a public repository public.
fn forks() -> Element(msg) {
  html.section([attribute.class("wrap"), attribute.id("forks")], [
    parts.section_head(
      "Forks, a PUBLIC inventory",
      "gh repo list piabrota --fork",
    ),
    html.p([attribute.class("sub")], [
      html.text(
        "Every fork under piabrota: "
        <> int.to_string(list.length(data.forks))
        <> ". Each one is PUBLIC, because GitHub keeps a fork of a public repository public. A fork is a copy of somebody else's work, kept to read it, to study it, or to send something back.",
      ),
    ]),
    html.ul(
      [attribute.class("forks")],
      list.map(data.forks, fn(f: Fork) {
        html.li([], [
          html.span([attribute.class("year")], [
            html.text(string.slice(f.forked, 0, 4)),
          ]),
          html.div([], [
            html.a(
              [
                attribute.class("fork-name"),
                attribute.href("https://github.com/piabrota/" <> f.name),
                attribute.rel("noopener"),
              ],
              [
                html.span([attribute.class("owner")], [html.text("piabrota/")]),
                html.text(f.name),
              ],
            ),
            html.p([attribute.class("says")], [
              html.span([attribute.class("mark")], [
                html.text("forked " <> f.forked),
              ]),
              html.span([attribute.class("mark")], [
                html.text("started " <> f.started),
              ]),
              html.span([attribute.class("mark")], [html.text(f.licence)]),
              html.span([attribute.class("mark")], [html.text(f.sync)]),
              case f.lang {
                "" -> element.none()
                lang -> html.span([attribute.class("mark")], [html.text(lang)])
              },
              html.text("from "),
              html.a(
                [
                  attribute.href("https://github.com/" <> f.parent),
                  attribute.rel("noopener"),
                ],
                [html.text(f.parent)],
              ),
              case f.description {
                "" -> element.none()
                d -> html.text(". " <> d)
              },
            ]),
          ]),
        ])
      }),
    ),
  ])
}
