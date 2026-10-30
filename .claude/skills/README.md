# Vendored agent skills

Community skills for agentic Nix work and for the static site in `site/` (Gleam, prerendered), copied so Claude Code (and any tool that reads
`.claude/skills/*/SKILL.md`) uses them here. They are the ones
[picasso](https://github.com/h0ffmann/picasso/tree/main/.claude/skills) already vets that fit a
single small VPS. Each `SKILL.md` is the upstream file with one added note under its front matter:
where it came from, and what differs in this repo. AGENTS.md wins wherever a skill disagrees with it.

| Skill | Upstream | Commit | Licence | Use it for |
|---|---|---|---|---|
| `nix-config-update` | [ryan4yin/nix-config](https://github.com/ryan4yin/nix-config) | `497fabbf9206` | MIT | a `flake.lock` bump, treated as a supply-chain event: what changed, validated before the merge deploys it |
| `nix-config-debug` | [ryan4yin/nix-config](https://github.com/ryan4yin/nix-config) | `497fabbf9206` | MIT | a failed eval, build, CI run or deploy-rs rollback |
| `systemd-hardening` | [daracci/nix-config](https://github.com/daracci/nix-config) | `6e5c465f66b2` | MIT | sandboxing a service written in Nix (`loco.nix`) |
| `ultimate-nixos` | [kaynetik/skills](https://github.com/kaynetik/skills) | `3ecbe1424cd5` | MIT | NixOS modules, flakes and a hardening review of `configuration.nix` |
| `frontend-design` | [anthropics/skills](https://github.com/anthropics/skills) | `ca45fc496a34` | Apache-2.0 | a deliberate visual direction for `site/`: palette, type, layout, copy |
| `web-design-guidelines` | [vercel-labs/agent-skills](https://github.com/vercel-labs/agent-skills), rules from [vercel-labs/web-interface-guidelines](https://github.com/vercel-labs/web-interface-guidelines) | `1a2c79d4e6c4`, `434b7f913646` | MIT | an accessibility and UX review of `site/`; the rules are vendored in `references/command.md` instead of fetched |
| `figure` | [piabrota/pirsig](https://github.com/piabrota/pirsig) | `main`, 2026-10-30 | MPL-2.0 | a figure in README.md or the wiki: an archify source, `just figure`, a reading card, in English and pt-BR |
| `archify` | [tt-a1i/archify](https://github.com/tt-a1i/archify), a link into the submodule `vendor/archify` | `208acba8d412` | Apache-2.0 | the archify CLI and its schemas, which `just figure` runs |
| `open-pencil` | [open-pencil/open-pencil](https://github.com/open-pencil/open-pencil) | `24461adec707` | MIT | drafting or inspecting a design in OpenPencil, through its CLI or the `open-pencil` MCP server |

`.mcp.json` adds [mcp-nixos](https://github.com/utensils/mcp-nixos) (`nix run nixpkgs#mcp-nixos`)
for package and option lookups; prefer it over guessing an option name. It runs where the agent
runs, never on the VPS. It also adds OpenPencil's MCP server (`@open-pencil/mcp@0.16.0`, started with `npx`; node from
`nix develop .#site`), which drives the [OpenPencil](https://openpencil.dev) desktop app; the app
must be open with a document loaded. `OPENPENCIL_MCP_ROOT` limits it to `site/design/`. It is
local design tooling for `site/`, nothing the VPS runs.

Hostinger's MCP server and agent skills are not here on purpose: a Hostinger API token has every
right of the account (no scopes), so an agent holding one could reinstall or delete the VPS.

Licence texts are in `LICENSES/`. To refresh one, copy the upstream file at a newer commit, keep
the note, and update the commit here.
