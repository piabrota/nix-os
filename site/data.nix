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
    "repo: ${str (data.repo p)}"
    "logo: ${str (p.logo or "")}"
    "glyph: ${str (p.glyph or "")}"
    "origin: ${str (data.origin p)}"
    "pushed: ${str p.pushed}"
    "state: ${state.${p.state}})"
  ];
  person = p: "Person(login: ${str p.login}, name: ${str p.name}, about: ${str p.about}, place: ${str p.place}, site: ${str p.site})";
  partner = p: "Partner(login: ${str p.login}, name: ${str p.name}, about: ${str p.about}, site: ${str p.site})";
  fork = f: "Fork(name: ${str f.name}, parent: ${str f.parent}, started: ${str f.started}, forked: ${str f.forked}, lang: ${str f.lang}, licence: ${str f.licence}, sync: ${str f.sync}, description: ${str f.description})";
  layer = l: "Layer(name: ${str l.name}, role: ${str l.role}, text: ${str l.text}, href: ${str l.href})";
  principle = x: "Principle(title: ${str x.title}, text: ${str x.text})";
  # The strings of every language, from locale/<lang>.json. en.json holds the page's words; each other
  # file holds the same keys, and the facts of mockups/data.nix in its own language. A key that one
  # language lacks stops the build.
  languages = [ "en" "pt-BR" "zh-CN" "ja-JP" ];
  locale = l: builtins.fromJSON (builtins.readFile (./locale + "/${l}.json"));
  keys = l: builtins.attrNames (locale l);
  checked = lib.all
    (l:
      lib.subtractLists (keys l) (keys "en") == [ ]
      && lib.subtractLists (keys l) (keys "pt-BR") == [ ]
      && lib.subtractLists (keys "pt-BR") (keys l) == [ ]
      || throw "site/locale/${l}.json has different keys")
    (lib.remove "en" languages);
  clause = l: k: "    ${str l}, ${str k} -> ${str (locale l).${k}}\n";
  clauses = lib.concatMapStrings (l: lib.concatMapStrings (clause l) (keys l)) languages;
  list = f: xs: "[\n" + lib.concatMapStrings (x: "  ${f x},\n") xs + "]";
in
assert checked;
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
      repo: String,
      logo: String,
      glyph: String,
      origin: String,
      pushed: String,
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
    Fork(name: String, parent: String, started: String, forked: String, lang: String, licence: String, sync: String, description: String)
  }

  pub type Layer {
    Layer(name: String, role: String, text: String, href: String)
  }

  pub type Principle {
    Principle(title: String, text: String)
  }

  /// The Google Analytics 4 measurement ID (piabrota.site.analytics.measurementId); "" for none.
  pub const analytics_id = ${str measurementId}

  pub const name = ${str data.org.name}

  pub const kicker = ${str data.org.kicker}

  pub const headline = ${str data.org.headline}

  pub const lede = ${str data.org.lede}

  pub const contact = ${str data.org.contact}

  pub const structure = ${list layer data.structure}

  pub const why = ${list principle data.why}

  pub const dogma = ${list principle data.dogma}

  pub const lanes = ${list lane data.lanes}

  pub const projects = ${list project data.projects}

  pub const people = ${list person data.people}

  pub const partners = ${list partner data.partners}

  pub const forks = ${list fork data.forks}

  /// One string of one language, "" when that language has no such key.
  pub fn locale(lang: String, key: String) -> String {
    case lang, key {
  ${clauses}    _, _ -> ""
    }
  }
''
