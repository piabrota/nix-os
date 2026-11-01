//// What the three pages share, in picasso's manner (site/DESIGN.md): the top band with the mark
//// and the design switcher, the hero's buttons and status pills, a project's state pill and
//// address, the section heads and the foot.

import gleam/int
import gleam/list
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/element/svg
import piabrota_site/data.{type Project, type State, Coming, Live, NoSite}
import piabrota_site/i18n

/// The three designs, each at its own path: A at the root, B and C below it.
pub const designs = [
  #("A", "fabric", "/"),
  #("B", "index", "/index/"),
  #("C", "paths", "/paths/"),
]

/// site.nix answers this path with a redirect to the repository.
pub const nixos = "/nixos"

pub const github = "https://github.com/piabrota"

pub const sponsor = "https://opencollective.com/piabrota"

/// The org's mark, as the profile shows it: an open green eye on red.
pub fn eye(size: Int) -> Element(msg) {
  let a = attribute.attribute
  html.svg(
    [
      a("viewBox", "0 0 100 100"),
      a("width", int.to_string(size)),
      a("height", int.to_string(size)),
      a("aria-hidden", "true"),
      attribute.class("eye"),
    ],
    [
      svg.rect([
        a("width", "100"),
        a("height", "100"),
        a("rx", "22"),
        a("fill", "#BC2318"),
      ]),
      svg.path([
        a("d", "M12 50 Q50 18 88 50 Q50 82 12 50Z"),
        a("fill", "#F7F3EA"),
      ]),
      svg.circle([
        a("cx", "50"),
        a("cy", "50"),
        a("r", "14"),
        a("fill", "#2E9E4F"),
      ]),
      svg.circle([
        a("cx", "50"),
        a("cy", "50"),
        a("r", "6"),
        a("fill", "#0B0D12"),
      ]),
    ],
  )
}

/// The top band: the mark and the name, the switcher, then the page's own hero.
pub fn top(
  current: String,
  lang: String,
  hero: List(Element(msg)),
) -> Element(msg) {
  html.header([attribute.class("top")], [
    html.div([attribute.class("wrap bar")], [
      html.a([attribute.class("brand"), attribute.href("/")], [
        eye(30),
        html.span([], [html.text(data.name)]),
      ]),
      languages(lang),
      switcher(current),
    ]),
    notice(lang),
    html.div([attribute.class("wrap hero")], hero),
  ])
}

/// The languages, the current one marked. Each links to design A in that language.
fn languages(lang: String) -> Element(msg) {
  html.nav(
    [
      attribute.class("langs"),
      attribute.aria_label(i18n.t(lang, "aria.languages")),
    ],
    {
      use #(code, name, href) <- list.map(i18n.languages)
      let here = case code == lang {
        True -> [attribute.aria_current("page")]
        False -> []
      }
      html.a([attribute.href(href), attribute.lang(code), ..here], [
        html.text(name),
      ])
    },
  )
}

/// Which text wins, and whether a native reader checked this one. English has no notice.
fn notice(lang: String) -> Element(msg) {
  case i18n.t(lang, "notice") {
    "" -> element.none()
    text -> html.p([attribute.class("wrap notice")], [html.text(text)])
  }
}

/// The switcher: the three designs as one segmented pill, the current one filled.
pub fn switcher(current: String) -> Element(msg) {
  html.nav([attribute.class("designs"), attribute.aria_label("Designs")], {
    use #(letter, name, href) <- list.map(designs)
    let here = case name == current {
      True -> [attribute.aria_current("page")]
      False -> []
    }
    html.a([attribute.href(href), ..here], [
      html.b([], [html.text(letter)]),
      html.text(" " <> name),
    ])
  })
}

/// The hero's eyebrow: the org's kicker, in the accent.
pub fn eyebrow(text: String) -> Element(msg) {
  html.p([attribute.class("eyebrow")], [html.text(text)])
}

/// A button: `primary` is the one filled pill of a row; the others are outlined.
pub fn button(href: String, label: String, primary: Bool) -> Element(msg) {
  let class = case primary {
    True -> "btn primary"
    False -> "btn"
  }
  html.a([attribute.class(class), attribute.href(href)], [html.text(label)])
}

/// The hero's buttons: where to go next.
pub fn buttons(first: #(String, String), lang: String) -> Element(msg) {
  html.div([attribute.class("actions")], [
    button(first.0, first.1, True),
    button(github, "GitHub ↗", False),
    button(sponsor, i18n.t(lang, "button.sponsor"), False),
  ])
}

/// The hero's status pills: how many projects are live, coming, without a site.
pub fn status(lang: String) -> Element(msg) {
  html.ul(
    [
      attribute.class("status"),
      attribute.aria_label(i18n.t(lang, "aria.status")),
    ],
    {
      use state <- list.map([Live, Coming, NoSite])
      let n = list.count(data.projects, fn(p) { p.state == state })
      html.li([attribute.class("is-" <> state_class(state))], [
        html.span([attribute.class("dot")], []),
        html.b([], [html.text(int.to_string(n))]),
        html.text(" " <> state_name(state, lang)),
      ])
    },
  )
}

pub fn state_name(state: State, lang: String) -> String {
  i18n.t(lang, "state." <> state_class(state))
}

pub fn state_class(state: State) -> String {
  case state {
    Live -> "live"
    Coming -> "coming"
    NoSite -> "none"
  }
}

/// The hero's numbers, closed-source's: each counted from the facts, never typed.
pub fn metrics(lang: String) -> Element(msg) {
  html.dl([attribute.class("metrics")], {
    use #(n, label) <- list.map([
      #(list.length(data.projects), "projects"),
      #(list.length(data.forks), "forks"),
      #(list.length(data.people), "people"),
      #(list.length(data.dogma), "invariants"),
    ])
    html.div([], [
      html.dt([], [html.text(i18n.t(lang, "metric." <> label))]),
      html.dd([], [html.text(int.to_string(n))]),
    ])
  })
}

/// A project's state, in words first and colour second.
pub fn pill(state: State, lang: String) -> Element(msg) {
  html.span([attribute.class("pill")], [html.text(state_name(state, lang))])
}

/// The project's address, a link when there is somewhere to go.
pub fn address(p: Project) -> Element(msg) {
  case p.href {
    "" -> html.span([attribute.class("where")], [html.text(p.where)])
    href ->
      html.a([attribute.class("where"), attribute.href(href)], [
        html.text(p.where),
      ])
  }
}

/// A section's head: its title, numbered by CSS (§ 01, § 02…), and a note on the right.
pub fn section_head(title: String, note: String) -> Element(msg) {
  html.div([attribute.class("section-head")], [
    html.h2([], [html.text(title)]),
    html.span([attribute.class("source")], [html.text(note)]),
  ])
}

/// The projects of one lane, in the profile's order.
pub fn in_lane(lane: String) -> List(Project) {
  list.filter(data.projects, fn(p) { p.lane == lane })
}

/// The foot: who serves the page, how to reach the org, and the switcher again.
pub fn foot(current: String, lang: String) -> Element(msg) {
  html.footer([attribute.class("foot")], [
    html.div([attribute.class("wrap")], [
      html.p([], [
        html.text(i18n.t(lang, "foot.a")),
        html.a([attribute.href(nixos)], [html.text("nix-os")]),
        html.text(i18n.t(lang, "foot.b") <> data.contact <> ". "),
        html.a([attribute.href("/notes")], [
          html.text(i18n.t(lang, "foot.notes")),
        ]),
        html.text("."),
      ]),
      switcher(current),
    ]),
  ])
}

/// A project's mark: its repository's logo, or the text mark of a repository that has none yet.
pub fn logo(p: Project) -> Element(msg) {
  case p.logo {
    "" ->
      html.span(
        [attribute.class("project-logo glyph"), attribute.aria_hidden(True)],
        [html.text(p.glyph)],
      )
    src ->
      html.img([
        attribute.src(src),
        attribute.alt(p.name <> " logo"),
        attribute.width(44),
        attribute.height(44),
        attribute.class("project-logo"),
        attribute.attribute("loading", "lazy"),
      ])
  }
}
