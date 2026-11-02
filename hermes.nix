# Hermes Agent (github.com/NousResearch/hermes-agent), Nous Research's agent, as the unit
# `hermes-agent`: its messaging gateway, which answers on the chat platforms whose tokens it has and
# runs its own cron jobs. Its NixOS module comes from the flake input `hermes-agent`; this file only
# chooses. State in /var/lib/hermes. See docs/HERMES.md.
{ lib, pkgs, hermes-agent, ... }:
let
  # Skills from the project's optional catalog (optional-skills/ at the pinned commit), as one
  # read-only directory in skills.external_dirs: they move with the flake input, never by hand.
  # Left out, because they need Node, Go or Homebrew on the box: pr-lens, qmd, llm-wiki,
  # blogwatcher, archify.
  optionalSkills = pkgs.linkFarm "hermes-optional-skills" (map
    (path: { name = baseNameOf path; path = "${hermes-agent}/optional-skills/${path}"; })
    [
      "devops/watchers" # poll RSS, JSON APIs and GitHub, with dedup: bulletins and alerts
      "research/rss-feeds" # read and discover feeds
      "research/duckduckgo-search" # web search with no key (the ddgs extra)
      "research/research-paper-writing" # papers, with the bundled arxiv and grounded-citations
      "software-development/ast-grep" # structural code search (pkgs.ast-grep below)
    ]);
in
{
  imports = [ hermes-agent.nixosModules.default ];

  services.hermes-agent = {
    enable = true;
    # The smallest build, plus the two extras this box uses: Anthropic's SDK and the chat
    # platforms (Telegram, Discord, Slack). The flake's default, `full`, adds about 700 MB more
    # (voice, Bedrock, Modal and the like).
    package = hermes-agent.packages.x86_64-linux.minimal;
    # mcp: the MCP client, without which mcpServers below do nothing. ddgs: DuckDuckGo search.
    extraDependencyGroups = [ "anthropic" "messaging" "mcp" "ddgs" ];
    # Claude through the owner's subscription: CLAUDE_CODE_OAUTH_TOKEN (`claude setup-token`) in the
    # env file below, as piabrota/agents does. Never a key here: settings land in the store.
    settings.model = {
      provider = "anthropic";
      default = "claude-sonnet-5-5";
    };
    settings.skills.external_dirs = [ "${optionalSkills}" ];
    # Remote MCP servers from the project's approved catalog (optional-mcps/), no key: nothing runs
    # on the box for them. DeepWiki answers about public repositories (piabrota, marola-dev,
    # nixpkgs), as in this repository's .mcp.json; Context7 gives current library docs.
    mcpServers = {
      deepwiki.url = "https://mcp.deepwiki.com/mcp";
      context7.url = "https://mcp.context7.com/mcp";
    };
    # gh for the bundled github skill (a read-only token as GITHUB_TOKEN in the env file),
    # ast-grep for the skill of that name.
    extraPackages = [ pkgs.gh pkgs.ast-grep ];
    # Written by hand on the box, root only: CLAUDE_CODE_OAUTH_TOKEN and a platform's token and
    # allowed users (docs/HERMES.md). Activation copies it into /var/lib/hermes/.hermes/.env;
    # without it Hermes warns and the gateway starts with no platform, so a deploy never waits on it.
    environmentFiles = [ "/var/lib/hermes-secrets/hermes.env" ];
    # `hermes` for the admins, on the service's state (HERMES_HOME), through the hermes group.
    addToSystemPackages = true;
  };

  systemd.tmpfiles.rules = [ "d /var/lib/hermes-secrets 0700 root root -" ];
  users.users.h0ffmann.extraGroups = [ "hermes" ];

  # The box has one vCPU and 4 GB: Hermes gets at most a quarter of the memory and yields the CPU
  # to sshd, nginx and the apps.
  systemd.services.hermes-agent.serviceConfig = {
    MemoryMax = lib.mkDefault "1G";
    CPUWeight = lib.mkDefault 50;
  };
}
