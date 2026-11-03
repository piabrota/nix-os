# Hermes Agent (github.com/NousResearch/hermes-agent), Nous Research's agent, as the unit
# `hermes-agent`: its messaging gateway, which answers on the chat platforms whose tokens it has and
# runs its own cron jobs. Its NixOS module comes from the flake input `hermes-agent`; this file only
# chooses. State in /var/lib/hermes. See docs/HERMES.md.
{ config, lib, pkgs, hermes-agent, ... }:
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
  # Three more from Nous's plugin catalog (plugin-catalog/ at the pinned hermes-agent commit:
  # maintainer-merged, scanned, pinned by commit), read at the catalog's commit before pinning.
  # tripwire: one JSON line per refused action (a hook block such as the deny list, or a denied
  # approval) in ~/.hermes/tripwire/events.jsonl. It stores no arguments or text and makes no calls.
  tripwire = pkgs.fetchFromGitHub {
    owner = "percyhendrux123-prog";
    repo = "hermes-tripwire";
    rev = "904a4f559808c57152ebb666cd0ab7d863220b49"; # v0.1.1, MIT
    hash = "sha256-Vxh+Nz0Qne7DfpfoXdXbg1/13HzVF++e6xCAC7LxtK4=";
  };
  # All four plugins of Nous Research's Labs (github.com/NousResearch/hermes-labs-plugins, MIT;
  # built by Nous, not supported), each at the commit its catalog entry pins:
  # inbox: `hermes inbox`, a read-only list of failed cron jobs, stalled subagents and work in
  # flight. A CLI command only.
  # telegram-business: drafts replies to a Telegram Business account's customers and sends one only
  # when the owner taps Send. Inert until a Business account (Telegram Premium) connects the bot.
  # workflow-record: `hermes record` records a browser workflow over CDP for /learn. Inert here:
  # the box runs no browser.
  # github-copilot: Copilot as a model provider. Inert: settings.model and the fallbacks name
  # Anthropic only, and it calls GitHub only for a profile that chose Copilot.
  labsPlugins = rev: hash: pkgs.fetchFromGitHub {
    owner = "NousResearch";
    repo = "hermes-labs-plugins";
    inherit rev hash;
  };
  labs = {
    inbox = labsPlugins "62dbc160fab57f893a9eaace79c16c00518c4eca"
      "sha256-tkkVfFbu+i483ypMQxszMpa7+M6OgZGugi4fQcZDLrk=";
    telegram-business = labsPlugins "0480b2e2947276b55b302d3288b30597d238ba51"
      "sha256-pXi9oon5r5akt+qpcqMrHvfT2DNYwN0qxxSsBjCzNB8=";
    workflow-record = labsPlugins "fde77be2bc939dbc71d425aab41731ad88173e67"
      "sha256-A7cmPg6PEihAR3tKG6SRtNtzA+KrSWWUDjUNuVKEX+E=";
    github-copilot = labsPlugins "346cfe972f72b6a966e84c1004cf8742554b193d"
      "sha256-Z+mJyWn0bFuuQuHB3doI3XqXs3hDcpL6g/gLkaaSNwA=";
  };
  # More from the catalog, each at its catalog commit, all MIT and pure Python: local ledgers and
  # small helpers that cost no model call.
  catalogPlugin = owner: repo: rev: hash: pkgs.fetchFromGitHub { inherit owner repo rev hash; };
  olric = catalogPlugin "olric3015" "hermes-plugins";
  refs = catalogPlugin "EloquentBrush0x" "hermes-context-refs";
  more = {
    # /errors: failed Anthropic calls (rate limits, overloads, timeouts) by cause and day.
    error-ledger = olric "dd646070c662ebf1978e5623bf30d2d1f55f7bef"
      "sha256-+f1ps0RuVn4AOEjg7huIIXJKdDYCNW6paNSP6HWX9ho=";
    # /aux: tokens and failures of the Haiku side tasks (titles, skills hub, goal judge).
    aux-ledger = olric "aee39a67b4ffb1ff786c417fb92f997a8c7663b7"
      "sha256-YtsrXUEzLC1wUarMijXNp2knC+2LA699u3Sd9rJiIFM=";
    # /approval-log: how often each deny-list rule asked, and the answers.
    approval-ledger = olric "4a2ef866a51f1c99ed1d77e423136450340d901b"
      "sha256-GPA252ZcSGizvro0Rxw/Q8rAhv4PUtqGusnUcd4RMOk=";
    # /stop-log: the turns stopped with /stop or /new while Hermes was working.
    stop-ledger = olric "604940a4bb6754c571b7562362fe2d1ceac1d741"
      "sha256-iw+wdpTSYokYCX1Q3yKYpTRBFLOUnZy65jII+/uxZLk=";
    # A progress bar's redraws reach the model as one line: tokens saved, nothing sent anywhere.
    progress-squash = catalogPlugin "pierrenode" "hermes-progress-squash"
      "044e6f1128037a58a76d5f6ff71df1607b4c1c63" "sha256-/5KHqlRkejtBEtePwbJBsK58yxFGBeFdljE4zg4uxS8=";
    # @gh:owner/repo#N attaches a public issue or PR (anonymous GET to api.github.com, no token).
    gh-ref = refs "bb0001012c5b213ce5a09b5905d859635c440c17"
      "sha256-z1We+CerQAZGM+TB+XkV+LoIUQf9CWiiQPUm8sQU8e8=";
    # @wiki:<title> attaches a Wikipedia lead section (GET to <lang>.wikipedia.org only).
    wiki-ref = refs "0154f6bfaafc837cc4af78742e6db7c087d5b5a7"
      "sha256-KHHeY/bqwpAZ8rsiw3oPVL6qNLudEsGdrljVl7fOfLM=";
  };
  # Brazilian holidays and workday maths for cron digests and deadlines, computed in code (GET to
  # date.nager.at with a country code and a year, no key). Its plugin.yaml is at the repo's root.
  publicHolidays = pkgs.fetchFromGitHub {
    name = "public-holidays";
    owner = "Akloenx123";
    repo = "hermes-public-holidays";
    rev = "d73f177b13c368c5c2445f6595f4008ed6c79a78"; # MIT
    hash = "sha256-NyQWrzgt361Hg7rTws7f5lgYbcNXf6VHOCH1gvznhtk=";
  };
  # The module wants a plugin's plugin.yaml at the package's root; these keep it in a subdirectory.
  subPlugin = name: src: pkgs.runCommand name { } "cp -r ${src}/${name} $out";
  # The owner's own plugins, in this repository (hermes/plugins/, docs/HERMES-PLUGINS.md): smart
  # notes and video readings, sent to piabrota/pirsig as pull requests on hermes/* branches. Each
  # is its directory plus the shared common/brain.py, so each stays one self-contained plugin.
  ownPlugins = [ "pirsig-notes" "pirsig-videos" ];
  ownPlugin = name: pkgs.runCommand name { } ''
    cp -r ${./hermes/plugins + "/${name}"} $out
    chmod u+w $out
    cp ${./hermes/plugins/common/brain.py} $out/brain.py
  '';
  # hermes-cron: a skill (markdown, no code in the agent) on cheap cron jobs: no_agent, the
  # wakeAgent pre-check and [SILENT], so a quiet tick makes no model call. Its read-only doctor
  # script needs python3, which is not on Hermes's PATH here; the rules work without it.
  hermesCron = pkgs.fetchFromGitHub {
    owner = "itpartypattaya";
    repo = "hermes-cron";
    rev = "2426b4b26a95e98112ac73415dedc8e0dd25c602"; # v1.5.2, MIT
    hash = "sha256-pA6FaHsOrsurjdLituyGg0dUcCoc/pVgJ3elURGF6Os=";
  };
  # evidence-ledger-research: source, date, unit and table-cell discipline when extracting from
  # bulletins and PDFs (bathing water, alerts, papers). Markdown only.
  abvxSkills = pkgs.fetchFromGitHub {
    owner = "markoblogo";
    repo = "abvx-agent-skills";
    rev = "d4af8c3a5596ed055f5be5bbbd4c36b37d535530"; # MIT
    hash = "sha256-yjc2tz3WNQ3xvNs7CSvTSOGPt9RypFkB5cBNqkB2zKY=";
  };
  # The owner's skills (github.com/h0ffmann/skills, MPL-2.0), pinned by commit; a new commit is a
  # PR. Not a git submodule: a flake reads its git tree without submodules unless the flake URL
  # says `?submodules=1`, so a submodule path is empty at build time. Each skill becomes a /name command, and on
  # Discord `/skill name`. Only the skills below are copied (docs/HERMES-SKILLS.md says why each
  # other one is left out). A skill needs nothing from the box beyond bash, git, gh and curl.
  ownerSkillsSrc = pkgs.fetchFromGitHub {
    owner = "h0ffmann";
    repo = "skills";
    rev = "78c5cac9d2f057414440bbf9931b1b1eeb0f7301";
    hash = "sha256-4sZmWpg+YnmPG0Tsdr/nnateGqagAceITa+sCkBSZdE=";
  };
  ownerSkillPaths = [
    "writing/ste100"
    "writing/ptbr"
    "writing/cientifico"
    "writing/ptbr-humanizer"
    "writing/easy-translate"
    "writing/essay"
    "research/paper"
    "research/cite-release"
    "research/open-text"
    "research/eli5"
    "dev-flow/triage"
    "dev-flow/mip"
    "dev-flow/easy-issues"
    "dev-flow/skill-validator"
    "code/lean-code"
    "code/loco"
    "nix/nix-debug"
    "nix/nixos-vps"
    "nix/systemd-hardening"
    "nix/nix-lab"
    "figures/svg-diagram"
    "figures/ddraw"
    "ouroboric/ponytail-review"
    "ouroboric/sharingan"
    "ouroboric/retro"
    "ouroboric/writing-styles"
    "web/citizen-science"
    "web/news-post"
    "web/web-ui"
  ];
  ownerSkills = pkgs.runCommand "hermes-owner-skills" { allowedReferences = [ ]; } (''
    mkdir $out
  '' + lib.concatMapStrings
    (path: ''
      cp -r ${ownerSkillsSrc}/skills/${path} $out/${baseNameOf path}
    '')
    ownerSkillPaths);
  optionalSkills = pkgs.runCommand "hermes-optional-skills" { allowedReferences = [ ]; } (''
    mkdir $out
  '' + lib.concatMapStrings
    (path: ''
      cp -r ${hermes-agent}/optional-skills/${path} $out/${baseNameOf path}
    '')
    skills + ''
    cp -r ${abvxSkills}/skills/evidence-ledger-research $out/evidence-ledger-research
    cp -r ${hermesCron}/skills/hermes-cron $out/hermes-cron
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
    # Two Claude models, both on the subscription: Sonnet for judgment, Haiku for mechanical work.
    # Sonnet is the main model: it plans, writes, reviews and decides. Haiku takes the subagents
    # (delegate_task: read-only fan-out; SOUL.md keeps single greps on Sonnet, since a subagent's
    # fresh context costs more than the grep) and three cheap side tasks (session titles, skill
    # matching, the /goal judge). Compression, the dangerous-command approval and the
    # post-turn review stay on Sonnet, because a wrong answer there costs more than the saving.
    # Hermes has no per-call router: Sonnet chooses to delegate, so SOUL.md tells it when to.
    # No fallback: if Anthropic fails, the turn fails rather than going to another provider.
    settings.fallback_providers = [ ];
    settings.auxiliary = {
      title_generation = {
        provider = "anthropic";
        model = "claude-haiku-4-5";
      };
      skills_hub = {
        provider = "anthropic";
        model = "claude-haiku-4-5";
      };
      # The judge of /goal (Hermes's Ralph loop): one short verdict after each turn.
      goal_judge = {
        provider = "anthropic";
        model = "claude-haiku-4-5";
      };
    };
    # /goal continues a task on its own until the judge says done. The default budget is 20 turns,
    # each up to agent.max_turns (60) model calls; 6 keeps one goal within the subscription's quota.
    # `/goal resume` continues for 6 more.
    settings.goals.max_turns = 6;
    settings.delegation = {
      provider = "anthropic";
      model = "claude-haiku-4-5";
      fallback_providers = [ ];
      # Small and shallow fan-out, for one vCPU and the subscription's quota.
      max_concurrent_children = 2;
      max_iterations = 50;
      max_spawn_depth = 1;
    };
    settings.skills.external_dirs = [ "${optionalSkills}" "${ownerSkills}" ];
    # The deny list lives in the store, read-only: the agent cannot edit its own guardrails. (The
    # plugin then logs that it cannot write its integrity hash next to the file; that is expected.)
    extraPlugins = [
      dangerousPatterns
      (subPlugin "tripwire" tripwire)
      publicHolidays
    ] ++ lib.mapAttrsToList subPlugin (labs // more) ++ map ownPlugin ownPlugins;
    settings.plugins.enabled = [ "custom-dangerous-patterns" "tripwire" "public-holidays" ]
      ++ builtins.attrNames (labs // more) ++ ownPlugins;
    environment.HERMES_CUSTOM_PATTERNS_PATH = "${./hermes/dangerous-patterns.yaml}";
    # Limits from the list's operational playbooks, for one vCPU, 1 GB and a subscription's quota
    # (the fan-out limits are in settings.delegation above): fewer turns per run, a hard stop on
    # tool loops, and no update checks or shared metrics (Nix owns updates; nothing goes to Nous).
    settings.agent.max_turns = 60;
    # How long a reload (reloadTriggers, below) waits for work in flight before it stops the
    # gateway anyway. The default, 30 min, keeps Hermes deaf to new messages for too long after a
    # deploy; a run of 60 turns took about 3 min on 2026-11-03.
    settings.agent.restart_after_turn_timeout = 600;
    settings.tool_loop_guardrails.hard_stop_enabled = true;
    settings.updates.check = false;
    settings.telemetry.shared_metrics.enabled = false;
    # From the survey in docs/AWESOME-HERMES.md, each key checked at the pinned commit.
    # Tokens: the prompt cache lives 1 h for chat (people pause) and 5 min for cron and subagents;
    # MCP servers do not reload (and drop the cache) on a config change, which only a deploy makes.
    settings.prompt_caching.cache_ttl = "auto";
    settings.mcp.auto_reload_on_config_change = false;
    # Memory, for 1 vCPU and 1 GB: fewer cached agents, one cron job at a time, one code kernel,
    # and media read into RAM capped at 20 MiB.
    settings.agent.agent_cache.max_size = 16;
    settings.cron.max_parallel_jobs = 1;
    settings.code_execution.max_session_kernels = 1;
    settings.gateway.max_inbound_media_bytes = 20 * 1024 * 1024;
    # Disk: prune sessions older than 45 days, then vacuum state.db.
    settings.sessions = {
      auto_prune = true;
      retention_days = 45;
      vacuum_after_prune = true;
    };
    # Nix owns the dependencies and the models: no pip installs at run time, no model catalog
    # fetched from Nous every 20 minutes, no DNS-over-HTTPS lookups of Telegram through Google
    # and Cloudflare.
    settings.security.allow_lazy_installs = false;
    settings.model_catalog.enabled = false;
    environment.HERMES_TELEGRAM_DISABLE_FALLBACK_IPS = "true";
    # Discord (the token and the allowed user ID are in the env file): attachments are held in RAM
    # while they download, so the same 20 MiB cap as Telegram's media, not Discord's 32 MiB.
    environment.DISCORD_MAX_ATTACHMENT_BYTES = toString (20 * 1024 * 1024);
    # Telegram: 👀 and ✅ reactions instead of "still working" messages (no tokens), and cron
    # results without the header and footer.
    settings.telegram.reactions = true;
    settings.cron.wrap_response = false;
    # Remote MCP servers from the project's approved catalog (optional-mcps/), no key: nothing runs
    # on the box for them. DeepWiki answers about public repositories (piabrota, marola-dev,
    # nixpkgs), as in this repository's .mcp.json; Context7 gives current library docs.
    mcpServers = {
      deepwiki.url = "https://mcp.deepwiki.com/mcp";
      context7.url = "https://mcp.context7.com/mcp";
    };
    # gh for the bundled github skill (a read-only token as GITHUB_TOKEN in the env file),
    # ast-grep for the skill of that name, yt-dlp for pirsig-videos (captions only: the light
    # build has no ffmpeg, and the plugin never downloads a video or its audio).
    extraPackages = [ pkgs.gh pkgs.ast-grep pkgs.yt-dlp-light ];
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
  # Activation rewrites config.yaml, .env, SOUL.md, AGENTS.md and the plugin links, but the unit
  # itself does not change, so a deploy left the old process running with the old config
  # (2026-11-03). Reload it when any of them changes. A reload sends SIGUSR1: the gateway takes no
  # new work, lets the turns, cron jobs and subagents in flight finish, and exits 75; Restart=always
  # (the module's default) starts it with the new config. A SIGTERM restart cut the turn in flight,
  # also when a merge of Hermes's own PR deployed it. A new Hermes package changes ExecStart, and
  # that still restarts the unit at once.
  systemd.services.hermes-agent.reloadTriggers = with config.services.hermes-agent; [
    (builtins.toJSON settings)
    (builtins.toJSON environment)
    (builtins.toJSON mcpServers)
    optionalSkills
    ownerSkills
    (builtins.toJSON extraPlugins)
    (builtins.toJSON hermesHomeFiles)
    (builtins.toJSON documents)
  ];

  # The gateway's exit 75 after a reload failed the first deploy that reloaded it (#76,
  # 2026-11-03): switch-to-configuration counts a service in auto-restart whose ExecMainStatus is
  # not 0 as failed, so deploy-rs rolled the box back. SuccessExitStatus does not change
  # ExecMainStatus. This wrapper is the main process instead: it passes SIGUSR1 and SIGTERM on to
  # the gateway and turns its 75 into 0, so a reload restarts it without a failed unit. The
  # package is the module's own (moduleCommon.nix, effectivePackage).
  systemd.services.hermes-agent.serviceConfig = {
    ExecStart = lib.mkForce (
      let
        cfg = config.services.hermes-agent;
        package =
          if cfg.extraPythonPackages == [ ] && cfg.extraDependencyGroups == [ ] then
            cfg.package
          else
            cfg.package.override (prev: {
              extraPythonPackages = (prev.extraPythonPackages or [ ]) ++ cfg.extraPythonPackages;
              extraDependencyGroups = (prev.extraDependencyGroups or [ ]) ++ cfg.extraDependencyGroups;
            });
      in
      pkgs.writeShellScript "hermes-gateway" ''
        ${package}/bin/hermes gateway ${lib.escapeShellArgs cfg.extraArgs} &
        child=$!
        trap 'kill -USR1 "$child" 2>/dev/null' USR1
        trap 'kill -TERM "$child" 2>/dev/null' TERM INT
        # A trapped signal ends `wait` early; wait again until the gateway has exited.
        while kill -0 "$child" 2>/dev/null; do wait "$child"; done
        wait "$child"
        status=$?
        if [ "$status" -eq 75 ]; then exit 0; fi
        exit "$status"
      ''
    );
    ExecReload = "${pkgs.coreutils}/bin/kill -USR1 $MAINPID";
    MemoryMax = lib.mkDefault "1G";
    CPUWeight = lib.mkDefault 50;
  };
}
