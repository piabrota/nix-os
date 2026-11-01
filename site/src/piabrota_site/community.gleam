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
import piabrota_site/i18n
import piabrota_site/parts

pub fn sections(lang: String) -> List(Element(msg)) {
  [
    anchors(lang),
    structure(lang),
    why(lang),
    dogma(lang),
    inventory(lang),
    board(lang),
    partners(lang),
    forks(lang),
  ]
}

/// A section's head, from its keys in site/locale.
fn head(lang: String, section: String) -> Element(msg) {
  parts.section_head(
    i18n.t(lang, "head." <> section),
    i18n.t(lang, "note." <> section),
  )
}

/// The bar of anchors, closed-source's: it stays at the top while the page scrolls.
fn anchors(lang: String) -> Element(msg) {
  html.nav(
    [
      attribute.class("anchors"),
      attribute.aria_label(i18n.t(lang, "aria.page")),
    ],
    [
      html.div([attribute.class("wrap")], {
        use id <- list.map([
          "structure", "why", "dogma", "inventory", "board", "partners", "forks",
        ])
        html.a([attribute.href("#" <> id)], [
          html.text(i18n.t(lang, "nav." <> id)),
        ])
      }),
    ],
  )
}

/// How the company is laid out: the chart, the umbrella, the products and the brain.
fn structure(lang: String) -> Element(msg) {
  html.section([attribute.class("wrap"), attribute.id("structure")], [
    head(lang, "structure"),
    html.figure([attribute.class("fabric-figure")], [
      html.img([
        attribute.src(i18n.t(lang, "structure.image")),
        attribute.alt(i18n.t(lang, "structure.alt")),
        attribute.width(1188),
        attribute.height(680),
        attribute.attribute("loading", "lazy"),
      ]),
    ]),
    html.ul(
      [attribute.class("layers")],
      list.map(data.structure, fn(l: Layer) {
        html.li([attribute.class("layer")], [
          html.span([attribute.class("role")], [
            html.text(i18n.fact(lang, "layer." <> l.name <> ".role", l.role)),
          ]),
          html.h3([], [
            html.a([attribute.href(l.href)], [
              html.text(i18n.fact(lang, "layer." <> l.name <> ".name", l.name)),
            ]),
          ]),
          html.p([], [
            html.text(i18n.fact(lang, "layer." <> l.name <> ".text", l.text)),
          ]),
        ])
      }),
    ),
  ])
}

fn why(lang: String) -> Element(msg) {
  html.section([attribute.class("wrap"), attribute.id("why")], [
    head(lang, "why"),
    html.ul(
      [attribute.class("reasons")],
      list.index_map(data.why, fn(p: Principle, i) {
        let key = "why." <> int.to_string(i + 1)
        html.li([], [
          html.h3([], [html.text(i18n.fact(lang, key <> ".title", p.title))]),
          html.p([], [html.text(i18n.fact(lang, key <> ".text", p.text))]),
        ])
      }),
    ),
  ])
}

/// The ten invariants. The list numbers them; the numbers are never typed.
fn dogma(lang: String) -> Element(msg) {
  html.section([attribute.class("wrap"), attribute.id("dogma")], [
    head(lang, "dogma"),
    html.p([attribute.class("sub")], [
      html.text(i18n.t(lang, "sub.dogma")),
    ]),
    html.ol(
      [attribute.class("dogma")],
      list.index_map(data.dogma, fn(p: Principle, i) {
        let key = "dogma." <> int.to_string(i + 1)
        html.li([], [
          html.strong([], [
            html.text(i18n.fact(lang, key <> ".title", p.title) <> " "),
          ]),
          html.text(i18n.fact(lang, key <> ".text", p.text)),
        ])
      }),
    ),
  ])
}

/// Every FOSS project, with each fact in words: closed-source's detail, one entry a project.
fn inventory(lang: String) -> Element(msg) {
  html.section([attribute.class("wrap"), attribute.id("inventory")], [
    head(lang, "inventory"),
    html.p([attribute.class("sub")], [
      html.text(
        int.to_string(list.length(data.projects))
        <> i18n.t(lang, "sub.inventory"),
      ),
    ]),
    html.ol(
      [attribute.class("inventory")],
      list.map(data.projects, entry(_, lang)),
    ),
  ])
}

fn entry(p: Project, lang: String) -> Element(msg) {
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
        html.div([attribute.class("card-name")], [
          parts.logo(p),
          html.h3([], [html.text(p.name)]),
        ]),
        parts.pill(p.state, lang),
      ]),
      html.p([attribute.class("blurb")], [
        html.text(i18n.fact(lang, "project." <> p.name, p.blurb)),
      ]),
      html.dl([], [
        fact(i18n.t(lang, "term.origin"), i18n.t(lang, "origin." <> p.origin)),
        fact(i18n.t(lang, "term.language"), p.lang),
        fact(i18n.t(lang, "term.licence"), p.licence),
        fact(i18n.t(lang, "term.push"), p.pushed),
      ]),
      html.div([attribute.class("links")], [
        html.a([attribute.href(p.repo), attribute.rel("noopener")], [
          html.text(i18n.t(lang, "link.repository")),
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

fn board(lang: String) -> Element(msg) {
  html.section([attribute.class("wrap"), attribute.id("board")], [
    head(lang, "board"),
    html.p([attribute.class("sub")], [
      html.text(i18n.t(lang, "sub.board")),
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

fn partners(lang: String) -> Element(msg) {
  html.section([attribute.class("wrap"), attribute.id("partners")], [
    head(lang, "partners"),
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
                html.text(i18n.fact(lang, "partner." <> p.login, p.about)),
              ]),
            ],
          ),
        ])
      }),
    ),
    html.aside([attribute.class("credit")], [
      html.p([], [
        html.strong([], [html.text(i18n.t(lang, "work.title"))]),
        html.text(i18n.t(lang, "work.text") <> data.contact <> "."),
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
fn forks(lang: String) -> Element(msg) {
  html.section([attribute.class("wrap"), attribute.id("forks")], [
    head(lang, "forks"),
    html.p([attribute.class("sub")], [
      html.text(
        i18n.t(lang, "sub.forks.a")
        <> int.to_string(list.length(data.forks))
        <> i18n.t(lang, "sub.forks.b"),
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
                html.text(i18n.t(lang, "fork.forked") <> f.forked),
              ]),
              html.span([attribute.class("mark")], [
                html.text(i18n.t(lang, "fork.started") <> f.started),
              ]),
              html.span([attribute.class("mark")], [html.text(f.licence)]),
              html.span([attribute.class("mark")], [html.text(f.sync)]),
              case f.lang {
                "" -> element.none()
                lang -> html.span([attribute.class("mark")], [html.text(lang)])
              },
              html.text(i18n.t(lang, "fork.from")),
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
