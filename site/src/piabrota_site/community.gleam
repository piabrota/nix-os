//// What every design ends with: the board (the people, each with a GitHub pill and a website),
//// the partners (each with its logo as GitHub publishes it), and the forks, a PUBLIC inventory in
//// the manner of h0ffmann/h0ffmann. Every fact is in mockups/data.nix.

import gleam/int
import gleam/list
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import piabrota_site/data.{type Fork, type Partner, type Person}
import piabrota_site/parts

pub fn sections() -> List(Element(msg)) {
  [board(), partners(), forks()]
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
              site_pill(p.site),
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
