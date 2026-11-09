import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import lustre/element
import piabrota_site/data
import piabrota_site/page

pub fn main() -> Nil {
  gleeunit.main()
}

fn pages() -> List(#(String, String)) {
  [
    #("fabric", page.fabric()),
    #("index", page.index()),
    #("paths", page.paths()),
  ]
}

pub fn documents_test() {
  list.each(pages(), fn(p) {
    let #(design, html) = p
    assert string.starts_with(string.lowercase(html), "<!doctype html>")
    assert string.contains(html, "<html lang=\"en\">")
    assert string.contains(html, "<body class=\"" <> design <> "\">")
    assert string.contains(html, "href=\"/style.css\"")
  })
}

// Every page of the site, in every language, names the org's icon (favicon/, favicon.nix).
pub fn icon_test() {
  let all =
    list.append(pages(), [
      #("hermes", page.hermes()),
      #("hosts", page.hosts()),
      #("pt-BR", page.fabric_in("pt-BR")),
      #("zh-CN", page.fabric_in("zh-CN")),
      #("ja-JP", page.fabric_in("ja-JP")),
    ])
  list.each(all, fn(p) {
    let #(_, html) = p
    assert string.contains(html, "href=\"/favicon.svg\"")
    assert string.contains(html, "href=\"/favicon.ico\"")
    assert string.contains(html, "href=\"/apple-touch-icon.png\"")
    assert !string.contains(html, "href=\"data:,\"")
  })
}

// Every page names every project of the org profile, and says what it is or where it meets the web.
pub fn every_project_test() {
  assert data.projects != []
  list.each(pages(), fn(p) {
    list.each(data.projects, fn(project) {
      assert string.contains(p.1, project.name)
      // Design C lists a path here without the domain: /nixos for piabrota.art/nixos.
      assert string.contains(p.1, project.blurb)
        || string.contains(p.1, project.where)
        || string.contains(
          p.1,
          string.replace(project.where, "piabrota.art", ""),
        )
    })
  })
}

// Every page links the other two, and marks itself as the current one.
pub fn switcher_test() {
  list.each(pages(), fn(p) {
    let #(design, html) = p
    assert string.contains(html, "href=\"/\"")
    assert string.contains(html, "href=\"/index/\"")
    assert string.contains(html, "href=\"/paths/\"")
    assert string.contains(html, "aria-current=\"page\"")
    assert string.contains(html, "</b> " <> design <> "</a>")
  })
}

// The README links piabrota.art/nixos; site.nix redirects it, and the pages link it.
pub fn nixos_link_test() {
  assert string.contains(page.fabric(), "href=\"/nixos\"")
  assert string.contains(page.paths(), "href=\"/nixos\"")
}

// A path here that is not live yet is no link at all: never a 404, never a link elsewhere.
pub fn no_dead_path_test() {
  list.each(pages(), fn(p) {
    assert !string.contains(p.1, "href=\"/pirsig\"")
    assert !string.contains(p.1, "href=\"/alerts\"")
  })
}

// Every page has its buttons: one primary, then GitHub and the sponsor link.
pub fn buttons_test() {
  list.each(pages(), fn(p) {
    assert string.contains(p.1, "class=\"btn primary\"")
    assert string.contains(p.1, "href=\"https://github.com/piabrota\"")
    assert string.contains(p.1, "href=\"https://opencollective.com/piabrota\"")
  })
}

// Every page lists the board with GitHub pills and websites, the partners with their logos, and
// every fork, said PUBLIC.
pub fn community_test() {
  list.each(pages(), fn(p) {
    list.each(data.people, fn(person) {
      assert string.contains(
        p.1,
        "href=\"https://github.com/" <> person.login <> "\"",
      )
      // A person without a website gets no pill.
      case person.site {
        "" -> Nil
        site -> {
          assert string.contains(p.1, "href=\"" <> site <> "\"")
        }
      }
    })
    list.each(data.partners, fn(partner) {
      assert string.contains(
        p.1,
        "src=\"https://avatars.githubusercontent.com/" <> partner.login,
      )
      assert string.contains(p.1, "href=\"" <> partner.site <> "\"")
    })
    assert data.forks != []
    list.each(data.forks, fn(f) {
      assert string.contains(
        p.1,
        "href=\"https://github.com/piabrota/" <> f.name <> "\"",
      )
      assert string.contains(
        p.1,
        "href=\"https://github.com/" <> f.parent <> "\"",
      )
    })
    assert string.contains(p.1, "PUBLIC")
  })
}

// No measurement ID, no tag; with one, Google's tag carries it twice (the script and the config).
pub fn analytics_test() {
  assert page.analytics("") == []
  let tag =
    page.analytics("G-TEST123")
    |> list.map(element.to_string)
    |> string.join("")
  assert string.contains(
    tag,
    "src=\"https://www.googletagmanager.com/gtag/js?id=G-TEST123\"",
  )
  assert string.contains(tag, "gtag('config', 'G-TEST123')")
}

// Design C keeps the drawing.
pub fn mu_test() {
  assert string.contains(page.paths(), "src=\"/mu.svg\"")
}

// Prerendered: no script, so every page works with JavaScript off; with a GA ID, only its tag.
pub fn no_script_test() {
  list.each(pages(), fn(p) {
    case data.analytics_id {
      "" -> {
        assert !string.contains(p.1, "<script")
      }
      id -> {
        // Only Google's two tags: the loader and its config.
        assert list.length(string.split(p.1, "<script")) == 3
        assert string.contains(p.1, "gtag/js?id=" <> id)
      }
    }
  })
}

// /hermes shows Hermes's configuration from hermes.nix, and design A's hermes card links to it.
pub fn hermes_page_test() {
  let html = page.hermes()
  assert string.starts_with(string.lowercase(html), "<!doctype html>")
  assert string.contains(html, "<body class=\"hermes\">")
  assert data.hermes_config != ""
  assert string.contains(html, "<pre class=\"yaml\">")
  assert string.contains(html, "model:")
  assert string.contains(html, "hermes-agent.service")
  // The release tag in the hero, in the YAML and in the link are the same string.
  let assert Ok(tag) = list.key_find(data.hermes_facts, "version")
  assert string.starts_with(tag, "v")
  assert string.contains(data.hermes_service, "  version: " <> tag <> "\n")
  assert data.hermes_release
    == "https://github.com/NousResearch/hermes-agent/releases/tag/" <> tag
  assert string.contains(html, "href=\"" <> data.hermes_release <> "\"")
  assert string.contains(page.fabric(), "href=\"/hermes\"")
}

// /hosts shows the figure and both hosts, and /hermes links to it.
pub fn hosts_page_test() {
  let html = page.hosts()
  assert string.contains(html, "<body class=\"hosts\">")
  assert string.contains(html, "src=\"/hosts/two-hosts.png\"")
  assert string.contains(html, "VPS 1 · KVM 1")
  assert string.contains(html, "VPS 2 · KVM 4")
  assert string.contains(page.hermes(), "href=\"/hosts\"")
}

// No secret reaches the page: not the env file, not a token's name. (A store path cannot: the
// build has allowedReferences = [ ].)
pub fn hermes_no_secret_test() {
  let text = data.hermes_config <> data.hermes_service
  list.each(["hermes.env", "TOKEN", "ALLOWED", "PRIVATE KEY"], fn(word) {
    assert !string.contains(text, word)
  })
}

// Design A links each service on its own name, with its drawn mark, and the hermes tile and
// /hermes show the hermes mark, not the ☤ glyph.
pub fn services_test() {
  assert list.length(data.services) == 4
  let html = page.fabric()
  list.each(data.services, fn(s) {
    assert string.contains(html, "href=\"https://" <> s.host <> "/\"")
    assert string.contains(html, "logo-mark logo-mark-" <> s.name)
  })
  assert string.contains(html, "logo-mark logo-mark-hermes")
  assert string.contains(page.hermes(), "logo-mark logo-mark-hermes")
  assert !string.contains(page.hermes(), "☤")
}

// The metrics page has no login, so design A says `public`; the OpenRig UI keeps its login.
pub fn metrics_public_test() {
  let assert Ok(metrics) =
    list.find(data.services, fn(s) { s.name == "metrics" })
  assert metrics.access == "public"
  let assert Ok(rig) = list.find(data.services, fn(s) { s.name == "openrig" })
  assert rig.access == "login"
}

// Only a project in the org's own repository, named like it, has commit counts: not hermes (a card
// for nix-os), not a personal repository, not a closed one.
pub fn commits_belong_to_own_repositories_test() {
  list.each(data.projects, fn(p) {
    let own =
      p.origin == "own" && p.repo == "https://github.com/piabrota/" <> p.name
    assert { p.commits != None } == own
  })
  assert data.commits_as_of != ""
}

// A card with counts shows both numbers, as data.nix has them; a project without shows none: the
// page has exactly one count line for each project that has counts, and no zero in its place.
pub fn commits_test() {
  let with =
    list.filter_map(data.projects, fn(p) {
      case p.commits {
        Some(c) -> Ok(#(p.name, c))
        None -> Error(Nil)
      }
    })
  assert list.length(with) == 11
  let fabric = page.fabric()
  let paths = page.paths()
  list.each(pages(), fn(p) {
    list.each(with, fn(entry) {
      let #(_, c) = entry
      assert string.contains(
        p.1,
        int.to_string(c.human)
          <> " human · "
          <> int.to_string(c.agent)
          <> " agent",
      )
    })
    // The inventory, on every design, has one fact for each project with counts.
    assert list.length(string.split(p.1, "<dt>commits</dt>"))
      == list.length(with) + 1
  })
  // Design A's tiles and design C's rows carry the line and the tooltip.
  list.each([fabric, paths], fn(html) {
    assert list.length(string.split(html, "class=\"commits\""))
      == list.length(with) + 1
    assert string.contains(
      html,
      "title=\"Commits on the default branch, as of "
        <> data.commits_as_of
        <> ".",
    )
  })
  assert !string.contains(page.index(), "class=\"commits\"")
}

// The labels come in every language; the numbers are the same in all four.
pub fn commits_languages_test() {
  assert string.contains(page.fabric_in("pt-BR"), " humano · ")
  assert string.contains(page.fabric_in("zh-CN"), " 人类 · ")
  assert string.contains(page.fabric_in("ja-JP"), " 人間 · ")
  assert string.contains(page.fabric_in("ja-JP"), "コミット")
}
