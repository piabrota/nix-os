# Hermes Agent (github.com/NousResearch/hermes-agent), Nous Research's agent, as the unit
# `hermes-agent`: its messaging gateway, which answers on the chat platforms whose tokens it has and
# runs its own cron jobs. Its NixOS module comes from the flake input `hermes-agent`; this file only
# chooses. State in /var/lib/hermes. See docs/HERMES.md.
{ lib, pkgs, hermes-agent, ... }:
let
  # Skills from the project's optional catalog (optional-skills/ at the pinned commit), as one
  # read-only directory in skills.external_dirs: they move with the flake input, never by hand.
  # Copied, not linked: a link into the input keeps its whole source (234 MiB) in the closure, and
  # allowedReferences fails the build if a copy still points at it.
  # Left out, because they need Node, Go or Homebrew on the box: pr-lens, qmd, llm-wiki,
  # blogwatcher, archify.
  skills = [
    "devops/watchers" # poll RSS, JSON APIs and GitHub, with dedup: bulletins and alerts
    "research/rss-feeds" # read and discover feeds
    "research/duckduckgo-search" # web search with no key (the ddgs extra)
    "research/research-paper-writing" # papers, with the bundled arxiv and grounded-citations
    "software-development/ast-grep" # structural code search (pkgs.ast-grep below)
  ];
  # Community add-ons, picked from github.com/0xNyk/awesome-hermes-agent and read before pinning
  # (docs/HERMES.md, "Community add-ons"). Pinned by commit; a new commit is a PR.
  # A pre_tool_call hook that blocks terminal commands matching hermes/dangerous-patterns.yaml.
  dangerousPatterns = pkgs.fetchFromGitHub {
    name = "custom-dangerous-patterns";
    owner = "scross01";
    repo = "hermes-custom-dangerous-patterns-plugin";
    rev = "6b9bda685fb6271d2be7f13b75cd59fafc30f263"; # v0.5.2, MIT
    hash = "sha256-/H2SPIvC+V7Pq/GybReP9yB2z9h04lcIANt85ObKwHA=";
  };
  # evidence-ledger-research: source, date, unit and table-cell discipline when extracting from
  # bulletins and PDFs (bathing water, alerts, papers). Markdown only.
  abvxSkills = pkgs.fetchFromGitHub {
    owner = "markoblogo";
    repo = "abvx-agent-skills";
    rev = "d4af8c3a5596ed055f5be5bbbd4c36b37d535530"; # MIT
    hash = "sha256-yjc2tz3WNQ3xvNs7CSvTSOGPt9RypFkB5cBNqkB2zKY=";
  };
  optionalSkills = pkgs.runCommand "hermes-optional-skills" { allowedReferences = [ ]; } (''
    mkdir $out
  '' + lib.concatMapStrings
    (path: ''
      cp -r ${hermes-agent}/optional-skills/${path} $out/${baseNameOf path}
    '')
    skills + ''
    cp -r ${abvxSkills}/skills/evidence-ledger-research $out/evidence-ledger-research
  '');
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
    # Sonnet and nothing else. Hermes's side tasks (compression, titles, the post-turn review) take
    # the main model by default, and subagents inherit it; pinned here so an upstream default cannot
    # move them. No fallback: if Anthropic fails, the turn fails rather than going to another model.
    settings.fallback_providers = [ ];
    settings.delegation = {
      provider = "anthropic";
      model = "claude-sonnet-5-5";
      fallback_providers = [ ];
      # Small and shallow fan-out, for one vCPU and the subscription's quota.
      max_concurrent_children = 2;
      max_iterations = 50;
      max_spawn_depth = 1;
    };
    settings.skills.external_dirs = [ "${optionalSkills}" ];
    # The deny list lives in the store, read-only: the agent cannot edit its own guardrails. (The
    # plugin then logs that it cannot write its integrity hash next to the file; that is expected.)
    extraPlugins = [ dangerousPatterns ];
    settings.plugins.enabled = [ "custom-dangerous-patterns" ];
    environment.HERMES_CUSTOM_PATTERNS_PATH = "${./hermes/dangerous-patterns.yaml}";
    # Limits from the list's operational playbooks, for one vCPU, 1 GB and a subscription's quota
    # (the fan-out limits are in settings.delegation above): fewer turns per run, a hard stop on
    # tool loops, and no update checks or shared metrics (Nix owns updates; nothing goes to Nous).
    settings.agent.max_turns = 60;
    settings.tool_loop_guardrails.hard_stop_enabled = true;
    settings.updates.check = false;
    settings.telemetry.shared_metrics.enabled = false;
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
    # Who it is and what it knows: its identity and rules (hermes/SOUL.md, from piabrota's dogma)
    # and a brief of the owner's projects, sources and jobs (hermes/AGENTS.md, which Hermes reads
    # from its working directory). Installed on every activation, so edit them here, not on the box.
    hermesHomeFiles."SOUL.md" = ./hermes/SOUL.md;
    documents."AGENTS.md" = ./hermes/AGENTS.md;
    # Where AGENTS.md goes and where the gateway runs; the module's default, stated as it asks.
    workingDirectory = "/var/lib/hermes/workspace";
    # Scheduled jobs and dates in the owner's time, not the server's UTC.
    settings.timezone = "America/Sao_Paulo";
    # `hermes` for the admins, on the service's state (HERMES_HOME), through the hermes group.
    addToSystemPackages = true;
  };

  systemd.tmpfiles.rules = [ "d /var/lib/hermes-secrets 0700 root root -" ];
  users.users.h0ffmann.extraGroups = [ "hermes" ];
  # Reads the system journal for its daily VPS check (hermes/AGENTS.md), as the observer account does.
  users.users.hermes.extraGroups = [ "systemd-journal" ];

  # The box has one vCPU and 4 GB: Hermes gets at most a quarter of the memory and yields the CPU
  # to sshd, nginx and the apps.
  systemd.services.hermes-agent.serviceConfig = {
    MemoryMax = lib.mkDefault "1G";
    CPUWeight = lib.mkDefault 50;
  };
}
