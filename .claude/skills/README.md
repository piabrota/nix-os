# Vendored agent skills

Community skills for agentic Nix work, copied so Claude Code (and any tool that reads
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

`.mcp.json` adds [mcp-nixos](https://github.com/utensils/mcp-nixos) (`nix run nixpkgs#mcp-nixos`)
for package and option lookups; prefer it over guessing an option name. It runs where the agent
runs, never on the VPS.

Hostinger's MCP server and agent skills are not here on purpose: a Hostinger API token has every
right of the account (no scopes), so an agent holding one could reinstall or delete the VPS.

Licence texts are in `LICENSES/`. To refresh one, copy the upstream file at a newer commit, keep
the note, and update the commit here.
