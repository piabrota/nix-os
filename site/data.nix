# The facts of the site as Gleam (src/piabrota_site/data.gleam), written from mockups/data.nix,
# the same facts the mockups draw. default.nix writes the file on every build; `just site-data`
# writes it for local work. It is not committed.
{ lib, data, measurementId ? "" }:
let
  str = s: "\"" + builtins.replaceStrings [ "\\" "\"" ] [ "\\\\" "\\\"" ] s + "\"";
  state = { live = "Live"; coming = "Coming"; none = "NoSite"; };
  lane = l: "Lane(id: ${str l.id}, label: ${str l.label})";
  project = p: lib.concatStringsSep ", " [
    "Project(name: ${str p.name}"
    "lane: ${str p.lane}"
    "blurb: ${str p.blurb}"
    "lang: ${str p.lang}"
    "licence: ${str p.licence}"
    "where: ${str (data.where p)}"
    "href: ${str (data.href p)}"
    "state: ${state.${p.state}})"
  ];
  person = p: "Person(login: ${str p.login}, name: ${str p.name}, about: ${str p.about}, place: ${str p.place}, site: ${str p.site})";
  partner = p: "Partner(login: ${str p.login}, name: ${str p.name}, about: ${str p.about}, site: ${str p.site})";
  fork = f: "Fork(name: ${str f.name}, parent: ${str f.parent}, started: ${str f.started}, forked: ${str f.forked}, description: ${str f.description})";
  list = f: xs: "[\n" + lib.concatMapStrings (x: "  ${f x},\n") xs + "]";
in
''
  //// Written by site/data.nix from mockups/data.nix (the org profile). Do not edit: change
  //// mockups/data.nix and run `just site-data`.

  pub type State {
    Live
    Coming
    NoSite
  }

  pub type Lane {
    Lane(id: String, label: String)
  }

  pub type Project {
    Project(
      name: String,
      lane: String,
      blurb: String,
      lang: String,
      licence: String,
      where: String,
      href: String,
      state: State,
    )
  }

  pub type Person {
    Person(login: String, name: String, about: String, place: String, site: String)
  }

  pub type Partner {
    Partner(login: String, name: String, about: String, site: String)
  }

  pub type Fork {
    Fork(name: String, parent: String, started: String, forked: String, description: String)
  }

  /// The Google Analytics 4 measurement ID (piabrota.site.analytics.measurementId); "" for none.
  pub const analytics_id = ${str measurementId}

  pub const name = ${str data.org.name}

  pub const kicker = ${str data.org.kicker}

  pub const headline = ${str data.org.headline}

  pub const lede = ${str data.org.lede}

  pub const contact = ${str data.org.contact}

  pub const lanes = ${list lane data.lanes}

  pub const projects = ${list project data.projects}

  pub const people = ${list person data.people}

  pub const partners = ${list partner data.partners}

  pub const forks = ${list fork data.forks}
''
