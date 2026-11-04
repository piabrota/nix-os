//// /hosts: what each of nix-os's two VPSs does. The figure is docs/img/two-hosts.png (`just
//// figure`, from docs/archify/two-hosts.json), copied in by default.nix. English only.

import gleam/list
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import piabrota_site/parts

pub const repo = "https://github.com/piabrota/nix-os/tree/main/hosts"

pub const migration =
  "https://github.com/piabrota/nix-os/blob/main/docs/MIGRATION-KVM4.md"

/// Each host and what it runs, as hosts/<name>/default.nix imports it.
pub const hosts = [
  #("VPS 1 · KVM 1", "piabrota (srv2108887) · 1 vCPU, 4 GB", [
    "www.piabrota.art: this site, prerendered from Gleam",
    "piabrota.art and /nixos: redirects",
    "/notes: a Loco app on SQLite",
  ]),
  #("VPS 2 · KVM 4", "kvm4 · 4 vCPU, 16 GB", [
    "hermes-agent: the full Hermes, its chats, cron jobs and omp",
    "hermes.piabrota.art: Hermes's dashboard, behind basic auth",
    "piabrota-hermes[bot]: pull requests on hermes/* branches",
    "PGX: a Postgres for data you can lose",
  ]),
]

pub fn view() -> Element(msg) {
  html.div([], [
    parts.top("hosts", "en", [
      html.div([], [
        parts.eyebrow("piabrota.art · nix-os"),
        html.h1([], [
          html.text("hosts "),
          html.span([], [html.text("· two VPSs")]),
        ]),
        html.p([attribute.class("lede")], [
          html.text(
            "One flake, two machines. KVM 1 serves the public web; KVM 4 runs Hermes. A merge to main builds both systems and deploys each one.",
          ),
        ]),
        html.div([attribute.class("actions")], [
          parts.button("#roles", "What each one runs ↓", True),
          parts.button(repo, "hosts/ ↗", False),
          parts.button(migration, "The migration ↗", False),
        ]),
      ]),
    ]),
    html.main([], [
      html.section([attribute.class("wrap")], [
        html.figure([attribute.class("hosts-figure")], [
          html.a([attribute.href("/hosts/two-hosts.png")], [
            html.img([
              attribute.src("/hosts/two-hosts.png"),
              attribute.alt(
                "Porkbun DNS sends www.piabrota.art to KVM 1 and hermes.piabrota.art to KVM 4; chats reach Hermes on KVM 4; deploy.yml deploys both.",
              ),
            ]),
          ]),
        ]),
      ]),
      html.section([attribute.class("wrap"), attribute.id("roles")], [
        parts.section_head("Who does what", "hosts/<name>/default.nix"),
        html.div([attribute.class("hosts-grid")], {
          use #(title, machine, roles) <- list.map(hosts)
          html.article([attribute.class("card")], [
            html.h3([], [html.text(title)]),
            html.p([attribute.class("sub")], [html.text(machine)]),
            html.ul([], list.map(roles, fn(r) { html.li([], [html.text(r)]) })),
          ])
        }),
      ]),
    ]),
    parts.foot("hosts", "en"),
  ])
}
