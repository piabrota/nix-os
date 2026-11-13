# Hermes Agent (github.com/NousResearch/hermes-agent), Nous Research's agent, as the unit
# `hermes-agent`: its messaging gateway, which answers on the chat platforms whose tokens it has and
# runs its own cron jobs. Its NixOS module comes from the flake input `hermes-agent`; this file only
# chooses. State in /var/lib/hermes. See docs/HERMES.md.
# Every host gets this file. It sets what does not depend on the machine and leaves the rest at
# upstream's defaults: the full Hermes. A small host would cut it in its own file (git history has
# KVM 1's, hosts/piabrota/hermes.nix, removed when Hermes moved to piabrota2).
{ config, lib, pkgs, utils, hermes-agent, ... }:
let
  # The release tag of the pinned hermes-agent input (flake.nix, flake.lock): v0.23.1 is 3b42157.
  hermesVersion = "0.23.1";
  # Skills from the project's optional catalog (optional-skills/ at the pinned commit), as one
  # read-only directory in skills.external_dirs: they move with the flake input, never by hand.
  # Copied, not linked: a link into the input keeps its whole source (234 MiB) in the closure, and
  # allowedReferences fails the build if a copy still points at it.
  # Left out, because they need Node, Go or Homebrew on the box: pr-lens, qmd, llm-wiki,
  # blogwatcher, archify.
  skills = [
    "devops/watchers" # poll RSS, JSON APIs and GitHub, with dedup: bulletins and alerts
    "research/rss-feeds" # read and discover feeds
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
  # Wave 1 of issue #88 (plugins for a long-living instance), each at its catalog commit, MIT.
  # memory-rewind v1.3.2: a version history of memories/, SOUL.md and skills/ in a bare git
  # repository in plugin-data/memory-rewind, written by a background thread; local git, no
  # network. `/memory-history` in chat; `hermes memory-rewind restore` on the box only.
  memoryRewind = pkgs.fetchFromGitHub {
    owner = "AhmetArif0";
    repo = "hermes-memory-rewind";
    rev = "354927184de03cdc4a9e9e48ddb2865c36368b1f";
    hash = "sha256-Rf5LEIrGLcS9q12TeYrEKt/jnyjP0VNE12tJtftxaD8=";
  };
  # hermes-guide v0.8.12: `/hermes-doctor` and `hermes guide`, ten read-only checks. Each run
  # makes one `git ls-remote` of its own repository for a release notice (none with --fast);
  # `proactive`, the checks at every session start and end, stays off.
  hermesGuide = pkgs.fetchFromGitHub {
    name = "hermes-guide";
    owner = "iap";
    repo = "hermes-guide";
    rev = "ca10574b22c703215fb5321dd32568d4203ba472";
    hash = "sha256-Gwe55b9xlp3X/tIV08opM4rA9ogXq7dDDPHi284TsW8=";
  };
  # hermes-plugin-guard v0.2.1: `hermes plugin-guard scan <dir>`, a static scan of a candidate
  # plugin that never imports or runs it, and one read-only tool. The plugin is the repository's
  # src/, which leaves out the scanner's deliberately unsafe test fixtures.
  pluginGuard = pkgs.runCommand "hermes-plugin-guard" { } "cp -r ${pkgs.fetchFromGitHub {
    owner = "mauricemohr88-debug";
    repo = "hermes-plugin-guard";
    rev = "857d881be77249c192c5fefa8254db186a7abbca";
    hash = "sha256-XQGm8nJanbCQzrfvpfABdwRy8NwzGlH9HvGiPU/V5cE=";
  }}/src $out";
  # superpowers v7.0.2 (obra/superpowers, MIT): 15 skills, and a `pre_llm_call` hook that adds a
  # bootstrap text (about 5 KB) to the first turn of a session, not to a subagent. The visual
  # companion of the brainstorming skill (skills/brainstorming/scripts/server.cjs) needs node.
  # This box has no node, so it stays inert. The plugin code makes no network call. Read at
  # v7.0.2, hash pinned; a new commit is a PR. The plugin keeps plugin.yaml and __init__.py in
  # .hermes-plugin/; the flat layout (both files next to skills/) is one it supports.
  superpowers = pkgs.runCommand "superpowers" { } ''
    src=${pkgs.fetchFromGitHub {
      owner = "obra";
      repo = "superpowers";
      rev = "22f0b463e7a5e579904dd6211a520321035526f7";
      hash = "sha256-rP5YsyGuPd9YSW/Fj3aukrq1bLuV+nwwQMK4JaZQgkI=";
    }}
    mkdir -p "$out"
    cp "$src/.hermes-plugin/plugin.yaml" "$src/.hermes-plugin/__init__.py" "$out/"
    cp -r "$src/skills" "$out/skills"
  '';
  # Manim Community, for the hermes-manim skill (hermes/skills/hermes-manim). It renders on the CPU
  # only. It adds about 2.4 GiB to the closure of piabrota2, the only host that imports this file.
  # Two tests of nixpkgs fail at this pin: test_ImageMobject and test_ImageInterpolation. The
  # Pillow of this pin refuses `Image.fromarray(..., mode="RGBA")` on a float array, in
  # `Camera.display_image_mobject`. So a scene with an ImageMobject fails; text, MathTex and
  # shapes work. Hydra has no cached build, so the host that builds runs the tests itself.
  # Remove this override when nixpkgs fixes the build.
  manim = pkgs.manim.overridePythonAttrs (old: {
    disabledTests = (old.disabledTests or [ ]) ++ [ "test_ImageMobject" "test_ImageInterpolation" ];
  });
  # The kvm4-health skill's script as a command (hermes/skills/kvm4-health), with the tools it
  # reads with on its PATH, for chat and for the watchdog cron job below.
  kvm4Health = pkgs.writeShellApplication {
    name = "kvm4-health";
    runtimeInputs = with pkgs; [ coreutils gawk gnugrep gnused config.systemd.package ];
    text = ''exec ${pkgs.runtimeShell} ${./hermes/skills/kvm4-health/scripts/kvm4-health.sh} "$@"'';
  };
  # The hermes-omp skill's stream filter as a command (hermes/skills/hermes-omp/scripts): it turns
  # the JSON lines of `omp -p --mode json` into plain lines, for the heartbeat of a background run.
  ompStream = pkgs.writeShellApplication {
    name = "omp-stream";
    runtimeInputs = [ pkgs.jq ];
    text = ''exec ${pkgs.runtimeShell} ${./hermes/skills/hermes-omp/scripts/omp-stream.sh} "$@"'';
  };
  # The hermes-omp skill's runner (hermes/skills/hermes-omp/scripts/omp-run.sh): one background omp
  # run through omp-stream, and `omp-run --stop <name>`. It ends with a code, never by a signal, so
  # the `bash -lic` of a background task prints no tcsetattr error and a stop is not a failure.
  ompRun = pkgs.writeShellApplication {
    name = "omp-run";
    runtimeInputs = [ pkgs.coreutils ompWrapped ompStream ];
    text = ''exec ${pkgs.runtimeShell} ${./hermes/skills/hermes-omp/scripts/omp-run.sh} "$@"'';
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
  # synalinks: Apache-2.0, read at that commit; a new commit is a PR. It teaches the Synalinks
  # framework (a Keras-shaped neuro-symbolic LM framework in Python). The skill is markdown,
  # references and example scripts. None of them runs by itself. The box has no Python for Hermes
  # and no `synalinks` package, so the scripts are for reading only.
  synalinksSkills = pkgs.fetchFromGitHub {
    owner = "SynaLinks";
    repo = "synalinks-skills";
    rev = "092970a578e53590f3b87597887952a4cfa98a4e";
    hash = "sha256-BhvPkdux6/8Z1JG1SHZ7cebm+o7ZVZ0QV/Re2gpGhpo=";
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
  # The category folder is kept on purpose: Hermes reads the category of a skill from its folder.
  # A flat copy shows every skill as "general".
  ownerSkills = pkgs.runCommand "hermes-owner-skills" { allowedReferences = [ ]; } (''
    mkdir $out
  '' + lib.concatMapStrings
    (path: ''
      mkdir -p $out/${dirOf path}
      cp -r ${ownerSkillsSrc}/skills/${path} $out/${path}
    '')
    ownerSkillPaths);
  # The `omp` wrapper (omp/wrapper.nix): the only omp on Hermes's PATH.
  ompWrapped = pkgs.callPackage ./omp/wrapper.nix { };
  optionalSkills = pkgs.runCommand "hermes-optional-skills" { allowedReferences = [ ]; } (''
    mkdir $out
  '' + lib.concatMapStrings
    (path: ''
      mkdir -p $out/${dirOf path}
      cp -r ${hermes-agent}/optional-skills/${path} $out/${path}
    '')
    skills + ''
    mkdir -p $out/research $out/devops $out/software-development
    cp -r ${abvxSkills}/skills/evidence-ledger-research $out/research/evidence-ledger-research
    cp -r ${hermesCron}/skills/hermes-cron $out/devops/hermes-cron
    cp -r ${synalinksSkills}/skills/synalinks $out/software-development/synalinks
  '');
in
{
  imports = [ hermes-agent.nixosModules.default ];

  services.hermes-agent = {
    enable = true;
    # The flake's default, `full`: every portable extra (voice, Bedrock, Modal and the like).
    # A small host can take `minimal` instead.
    # The flake builds it with version "0.0.0" (its stamp, install-stamp.json, takes the version
    # from this argument). At 0.0.0 the dashboard and `hermes --version` show v0.0.0, and Hermes
    # refuses every plugin whose requires_hermes is higher, among them the deny list and tripwire.
    # hermesVersion is the release that the input `hermes-agent` pins in flake.lock: change it in
    # the same pull request as the pin (and the badge in README.md).
    package = lib.mkDefault (hermes-agent.packages.x86_64-linux.default.override {
      version = hermesVersion;
    });
    # The extras every host uses, added to the package's own: Anthropic's SDK and the chat platforms
    # (Telegram, Discord, Slack), already in `full`; mcp, the MCP client, without which mcpServers
    # below do nothing; ddgs, DuckDuckGo search with no key (since v0.23.0 a web search provider
    # that Hermes picks when no other web key is set, no longer an optional skill).
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
        model = "claude-haiku-5-5";
      };
      skills_hub = {
        provider = "anthropic";
        model = "claude-haiku-5-5";
      };
      # The judge of /goal (Hermes's Ralph loop): one short verdict after each turn.
      goal_judge = {
        provider = "anthropic";
        model = "claude-haiku-5-5";
      };
    };
    # Compress the conversation at 40 % of the context window, not 50 %. Sonnet has 1,000,000
    # tokens, so this is about 400,000 tokens. Hermes floors the ratio at 0.75 only for windows
    # under 512K, so 0.40 holds here. Trade-off: each compression rewrites the cached prompt prefix
    # once, and every later turn is cheaper because the context is smaller. Compression stays on
    # Sonnet (see above).
    settings.compression.threshold = 0.40;
    # /goal continues a task on its own until the judge says done. The default budget is 20 turns,
    # each up to agent.max_turns (60) model calls; 6 keeps one goal within the subscription's quota.
    # `/goal resume` continues for 6 more.
    settings.goals.max_turns = 6;
    settings.delegation = {
      provider = "anthropic";
      model = "claude-haiku-5-5";
      fallback_providers = [ ];
      # Shallow fan-out, for the subscription's quota. How many children run at once depends on
      # the machine: upstream's 10 on piabrota2.
      max_iterations = 50;
      max_spawn_depth = 1;
    };
    # The third directory holds this repository's own skills (hermes/skills/): hermes-omp, kvm4-health, site-pins.
    settings.skills.external_dirs = [ "${optionalSkills}" "${ownerSkills}" "${./hermes/skills}" ];
    # The deny list lives in the store, read-only: the agent cannot edit its own guardrails. (The
    # plugin then logs that it cannot write its integrity hash next to the file; that is expected.)
    extraPlugins = [
      dangerousPatterns
      (subPlugin "tripwire" tripwire)
      publicHolidays
      (subPlugin "memory-rewind" memoryRewind)
      hermesGuide
      pluginGuard
      superpowers
    ] ++ lib.mapAttrsToList subPlugin (labs // more) ++ map ownPlugin ownPlugins;
    settings.plugins.enabled = [
      "custom-dangerous-patterns"
      "tripwire"
      "public-holidays"
      "memory-rewind"
      "hermes-guide"
      "hermes-plugin-guard"
      "superpowers"
    ] ++ builtins.attrNames (labs // more) ++ ownPlugins;
    environment.HERMES_CUSTOM_PATTERNS_PATH = "${./hermes/dangerous-patterns.yaml}";
    # Limits from the list's operational playbooks, for a subscription's quota (the fan-out limits
    # are in settings.delegation above): fewer turns per run, a hard stop on tool loops, and no
    # update checks or shared metrics (Nix owns updates; nothing goes to Nous). The machine's
    # limits (memory, CPU, parallel work) are per host.
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
    # omp is the wrapper above, for the hermes-omp skill.
    # kvm4-health is the skill of that name (hermes/skills/kvm4-health).
    # omp-stream filters omp's JSON output for the hermes-omp skill (hermes/skills/hermes-omp/scripts),
    # and omp-run runs and stops a background omp through it.
    # rig (OpenRig's CLI, for the hermes-rig skill) is added by openrig.nix.
    # manim renders animations for the hermes-manim skill (hermes/skills/hermes-manim).
    extraPackages = [ pkgs.gh pkgs.jq pkgs.ast-grep pkgs.yt-dlp-light manim ompWrapped kvm4Health ompStream ompRun ];
    # Written by hand on the box, root only: CLAUDE_CODE_OAUTH_TOKEN and a platform's token and
    # allowed users (docs/HERMES.md). Activation copies it into /var/lib/hermes/.hermes/.env;
    # without it Hermes warns and the gateway starts with no platform, so a deploy never waits on it.
    environmentFiles = [ "/var/lib/hermes-secrets/hermes.env" ];
    # Who it is and what it knows: its identity and rules (hermes/SOUL.md, from piabrota's dogma)
    # and a brief of the owner's projects, sources and jobs (hermes/AGENTS.md, which Hermes reads
    # from its working directory). Installed on every activation, so edit them here, not on the box.
    hermesHomeFiles."SOUL.md" = ./hermes/SOUL.md;
    # The look of the dashboard and of the TUI (the Chat tab embeds it): the theme is read from
    # HERMES_HOME/dashboard-themes/<file>.yaml by its `name`, the skin from skins/<name>.yaml.
    # Both are the dark tokens of site/DESIGN.md; see docs/HERMES.md, "The web dashboard".
    hermesHomeFiles."dashboard-themes/piabrota.yaml" = ./hermes/dashboard-themes/piabrota.yaml;
    hermesHomeFiles."skins/piabrota.yaml" = ./hermes/skins/piabrota.yaml;
    settings.dashboard.theme = "piabrota";
    settings.display.skin = "piabrota";
    # The script of the kvm4-health watchdog, a no_agent cron job: a cron script must be a file in
    # HERMES_HOME/scripts. It prints nothing while the box is healthy, so a tick posts nothing.
    hermesHomeFiles."scripts/kvm4-health-alert.sh" = ''
      #!/bin/sh
      exec ${kvm4Health}/bin/kvm4-health --alert --record
    '';
    # The personal feed (docs/FEEDS.md): the script of a no_agent cron job and its sources. The
    # outputs go to HERMES_HOME/feeds/out/ and the state to HERMES_HOME/feeds/state.json; the
    # tmpfiles rule below gives feeds/ to hermes.
    hermesHomeFiles."scripts/feed-build.py" = ./hermes/feeds/build_feed.py;
    hermesHomeFiles."feeds/feeds.toml" = ./hermes/feeds/feeds.toml;
    # The skills-export no_agent cron job (daily 01:45) runs this: it copies Hermes's skills into a
    # pull request on piabrota/skills. Cron gives it the unit's PATH, so the script adds the system profile.
    hermesHomeFiles."scripts/export-skills.sh" = ./hermes/scripts/export-skills.sh;
    # The grid-refresh no_agent cron job (daily 02:30) runs this: it refreshes the data of the ▲ grid
    # in a pull request on piabrota/room. It runs the room's dev shell with nix develop; the script adds the system profile to the PATH.
    hermesHomeFiles."scripts/refresh-grid.sh" = ./hermes/scripts/refresh-grid.sh;
    documents."AGENTS.md" = ./hermes/AGENTS.md;
    # Where AGENTS.md goes and where the gateway runs; the module's default, stated as it asks.
    workingDirectory = "/var/lib/hermes/workspace";
    # Scheduled jobs and dates in the owner's time, not the server's UTC.
    settings.timezone = "America/Sao_Paulo";
    # `hermes` for the admins, on the service's state (HERMES_HOME), run as `sudo -u hermes hermes ...`.
    addToSystemPackages = true;
  };

  # The metrics page counts the skills that ship inside Hermes apart from the ones chosen here
  # (metrics.nix, "inventory"): the skills/ folder of its source, which its package ships.
  piabrota.metrics.inventory.bundledSkillDirs = [ "${hermes-agent}/skills" ];

  # omp-tasks: the task files of the hermes-omp skill. feeds: activation's `install -D` of
  # feeds/feeds.toml makes the directory as root, 2755, and feeds is not a state directory of the
  # module, so the feed script could not write out/ or state.json. `d` also fixes the owner and the
  # mode of a directory that exists.
  systemd.tmpfiles.rules = [
    "d /var/lib/hermes-secrets 0700 root root -"
    "d /var/lib/hermes/workspace/omp-tasks 0770 hermes hermes -"
    "d /var/lib/hermes/.hermes/feeds 2770 hermes hermes -"
  ];
  # h0ffmann is NOT in the `hermes` group, on purpose. Upstream refuses the gateway control socket
  # when the group of a group-writable home has another member, and then the dashboard Chat tab
  # cannot attach. h0ffmann reaches the state with `sudo -u hermes`.
  # Reads the system journal for its daily VPS check (hermes/AGENTS.md), as the observer account does.
  users.users.hermes.extraGroups = [ "systemd-journal" ];

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
  # ExecMainStatus. hermes/scripts/gateway-wrapper.sh is the main process instead: it passes
  # SIGUSR1 and SIGTERM on to the gateway, and on a 75 it starts the gateway again itself, with no
  # pause, so a reload never leaves "active" and never fails the unit. The package is the module's
  # own (moduleCommon.nix, effectivePackage).
  # The gap of Restart=always (RestartSec 5 s) let the dashboard's Chat tab start a second,
  # unmanaged gateway, and the unit then looped on "already serves" (2026-11-05). The wrapper
  # also waits for such a gateway to exit and does not loop. See docs/HERMES.md.
  # The wrapper also hides systemd from the gateway: the gateway is a child of a shell, not of
  # systemd. Without --external-supervisor, Hermes v0.22.7 treated a reload as a graceful restart
  # and started a detached gateway, and the unit then looped (2026-11-04). The flag makes the
  # gateway exit back to this wrapper instead. v0.23.1 still reads it (gateway/restart.py) and
  # exits 75 on a reload and when another gateway serves the host.
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
        wrapper = pkgs.writeShellScript "hermes-gateway" (builtins.readFile ./hermes/scripts/gateway-wrapper.sh);
      in
      utils.escapeSystemdExecArgs (
        [ wrapper "${package}/bin/hermes" "gateway" "run" "--external-supervisor" ] ++ cfg.extraArgs
      )
    );
    ExecReload = "${pkgs.coreutils}/bin/kill -USR1 $MAINPID";
  };
}
