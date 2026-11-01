# The facts of piabrota.art, read on 2026-11-01. The projects come from the org profile
# (piabrota/.github, profile/README.md) and dojo's REPOS.md, and their language, licence and last push
# from GitHub; the mockups draw them. The philosophy comes from the profile's "Why it is open" and
# piabrota/mu's DOGMA.md. The board, the partners and the forks below are dated where they are.
# `path` is a path on piabrota.art; `site` an address elsewhere; `state` is live, coming or none;
# `owner` when the repository is not the org's. site/data.nix writes the same facts as
# Gleam for the live site, so the mockups and the site cannot disagree.
rec {
  # Where a project meets the web, as the cards and rows print it.
  where = p:
    if p ? path then "piabrota.art${p.path}"
    else p.site or (if owner p == "piabrota" then "github.com/piabrota/${p.name}" else "${owner p}/${p.name}");

  # What its address links to: a live path here, its own site, or its repository. "" for none,
  # and for a path here that is not live yet, so the address is never a link to somewhere else.
  href = p:
    if p ? path then (if p.state == "live" then p.path else "")
    else if p ? site then "https://${p.site}"
    else "https://github.com/${owner p}/${p.name}";

  # Whose repository it is: the org's, or a personal one that dojo pins.
  owner = p: p.owner or "piabrota";
  repo = p: "https://github.com/${owner p}/${p.name}";
  origin = p: if owner p == "piabrota" then "own" else "personal";

  org = {
    name = "piabrota";
    kicker = "open software fabric · made in RJ";
    headline = "Open software, made in Rio de Janeiro.";
    lede = "Each project is its own repository, with its own README, licence and tests. The source is open, and so is the method.";
    contact = "mhoffmannfs [at] gmail.com";
    links = [ "structure" "dogma" "inventory" "board" "forks" ];
  };

  lanes = [
    { id = "company"; label = "the company"; }
    { id = "think"; label = "think and write"; }
    { id = "host"; label = "warn and host"; }
    { id = "play"; label = "play"; }
  ];

  # logo: the repository's own logo, at a pinned commit, never stored here. glyph: the text mark of a
  # repository that has no logo yet, as the org profile prints it.
  projects = [
    {
      name = "mu";
      logo = "https://raw.githubusercontent.com/piabrota/mu/d8762696790b97e874cbd9a580ceb957ecb23c6e/docs/drawings/mu.svg";
      lane = "company";
      blurb = "The company chart: the dogma, the standards, the journal and the index of the org's repositories.";
      lang = "Markdown, Bash";
      licence = "CC BY 4.0, AGPL-3.0, MPL-2.0";
      pushed = "2026-11-01";
      state = "none";
    }
    {
      name = "dojo";
      glyph = "道場";
      lane = "company";
      blurb = "The umbrella: every product as a submodule at a pinned commit, the routing table and its own tooling. It holds no product code.";
      lang = "Bash";
      licence = "MPL-2.0";
      pushed = "2026-11-01";
      state = "none";
    }
    {
      name = ".github";
      logo = "https://avatars.githubusercontent.com/piabrota?s=128";
      lane = "company";
      blurb = "The org's profile, with the project table, the fabric figure and the funding links.";
      lang = "Markdown";
      licence = "MPL-2.0";
      pushed = "2026-11-01";
      state = "none";
    }
    {
      name = "pirsig";
      logo = "https://raw.githubusercontent.com/piabrota/pirsig/b7dd1da2ac886845b14bb90e5d8d34976cfc95cb/docs/drawings/pirsig.svg";
      lane = "think";
      blurb = "A second brain: PARA and a Zettelkasten slip-box in one place. Desktop app, REST API and the psg CLI.";
      lang = "Rust";
      licence = "MPL-2.0";
      pushed = "2026-10-30";
      path = "/pirsig";
      state = "coming";
    }
    {
      name = "gramatico";
      logo = "https://raw.githubusercontent.com/piabrota/gramatico/d57371af30553ad66f63537e52c1f34112e2f86b/site/static/favicon.svg";
      lane = "think";
      blurb = "Rewrites technical text in Brazilian Portuguese so that it reads once. A Claude Code plugin.";
      lang = "Rust";
      licence = "MPL-2.0";
      pushed = "2026-10-30";
      site = "piabrota.github.io/gramatico";
      state = "live";
    }
    {
      name = "closed-source";
      logo = "https://raw.githubusercontent.com/h0ffmann/closed-source/6b3aae557f69ab89ec747364311978928dd0ca71/site/static/icons/favicon.svg";
      lane = "think";
      owner = "h0ffmann";
      blurb = "The god that failed: a book on why closed source failed as a protection, for science first.";
      lang = "Markdown, Gleam";
      licence = "CC BY 4.0, AGPL-3.0";
      pushed = "2026-10-27";
      site = "h0ffmann.github.io/closed-source";
      state = "live";
    }
    {
      name = "skills";
      logo = "https://raw.githubusercontent.com/h0ffmann/skills/bcccf4950e100ed0ae25291143f963ee09390a08/docs/drawings/waza.svg";
      lane = "think";
      owner = "h0ffmann";
      blurb = "A swiss army knife of agent skills.";
      lang = "Gleam";
      licence = "MPL-2.0";
      pushed = "2026-11-01";
      site = "h0ffmann.github.io/skills";
      state = "live";
    }
    {
      name = "alerts";
      logo = "https://raw.githubusercontent.com/piabrota/alerts/40d244f5e83bdb3700493de6612528982509f2a8/desktop/app/icons/icon.png";
      lane = "host";
      blurb = "Alerts from official sources only, to Discord and an Atom feed with CAP 1.2. First: floods in the south of Brazil.";
      lang = "Rust";
      licence = "MPL-2.0";
      pushed = "2026-11-01";
      path = "/alerts";
      state = "coming";
    }
    {
      name = "rax";
      logo = "https://raw.githubusercontent.com/piabrota/rax/b87c790db8d8cd1537bd79176fead0a0f8960bc9/docs/drawings/cosmos.svg";
      lane = "host";
      blurb = "Rustic Agentic Runtime: a pure-Rust port of AX, the declarative orchestrator for agentic tasks.";
      lang = "Rust";
      licence = "MPL-2.0";
      pushed = "2026-10-31";
      state = "none";
    }
    {
      name = "agents";
      glyph = "🤖";
      lane = "host";
      blurb = "Small agents that watch nix-os and its VPS, and report on GitHub as piabrota-ops. They open pull requests and never merge.";
      lang = "Bash";
      licence = "MPL-2.0";
      pushed = "2026-11-01";
      state = "none";
    }
    {
      name = "nix-os";
      logo = "https://raw.githubusercontent.com/piabrota/nix-os/8975d2c9354c09e9cae27819efce009741ffe22e/docs/drawings/mu.svg";
      lane = "host";
      blurb = "The NixOS configuration of the small VPS that serves piabrota.art. Judged by its closure.";
      lang = "Nix";
      licence = "MPL-2.0";
      pushed = "2026-10-31";
      path = "/nixos";
      state = "live";
    }
    {
      name = "astrbot_dw_ext_br_south_disaster";
      logo = "https://raw.githubusercontent.com/h0ffmann/astrbot_dw_ext_br_south_disaster/a6675479bebcacb92b1d18f4931a7065a1f70178/extension.png";
      lane = "host";
      owner = "h0ffmann";
      blurb = "South of Brazil (RS, SC, PR) disaster extension for AstrBot plugin astrbot_plugin_disaster_warning";
      lang = "Python";
      licence = "MPL-2.0";
      pushed = "2026-10-31";
      state = "none";
    }
    {
      name = "astrbot_dw_ext_br_south_waterq";
      logo = "https://raw.githubusercontent.com/h0ffmann/astrbot_dw_ext_br_south_waterq/12b71ac048ad29b83bfc6aaa0149e011c66886ce/extension.png";
      lane = "host";
      owner = "h0ffmann";
      blurb = "Bathing water quality alerts for the South of Brazil (RS, SC, PR). An extension for astrbot_plugin_disaster_warning.";
      lang = "Python";
      licence = "MPL-2.0";
      pushed = "2026-10-31";
      state = "none";
    }
    {
      name = "ihero";
      glyph = "🎶";
      lane = "play";
      blurb = "A FOSS music player and game, in Rust. Coming: the repository holds only its licence.";
      lang = "Rust, planned";
      licence = "MPL-2.0";
      pushed = "2026-11-01";
      state = "coming";
    }
  ];

  # The company's shape, as mu and dojo say it (2026-11-01).
  structure = [
    { name = "mu"; role = "the company chart"; text = "The dogma, the charter, the standards and the index of the repositories."; href = "https://github.com/piabrota/mu"; }
    { name = "dojo"; role = "the umbrella"; text = "Every product as a submodule at a pinned commit, and one routing table. No product code."; href = "https://github.com/piabrota/dojo"; }
    { name = "the products"; role = "each in its own repository"; text = "Each has its own README, licence and checks. A change to a product is made in that repository."; href = "#inventory"; }
    { name = "pirsig"; role = "the brain"; text = "Smart notes, PARA and a track record of the high-level decisions."; href = "https://github.com/piabrota/pirsig"; }
  ];

  # "Why it is open", word for word from the org profile.
  why = [
    { title = "Read it, use it, and build your own."; text = "You can have your own ideas by reading or using piabrota's repositories. They are live documentation, and proof of the human work behind the scenes, so that others can build their own."; }
    { title = "Built with Claude Code, on the way to FOSS."; text = "Claude Code builds piabrota's projects most of the time, but we keep a permanent effort to make the piabrota platform [F]OSS."; }
    { title = "A philosophy, not only a saving."; text = "Token optimization and open-source models, on Ollama and Ollaya, are how we build open-source software on open-source software, as agentic and as affordable as possible."; }
  ];

  # The ten invariants of piabrota/mu's DOGMA.md, shortened only where a list or a link would not fit.
  dogma = [
    { title = "Agents fix every error."; text = "An error a user or an owner reports is a goal. An agent takes it and closes it as a short-sized goal: one pull request."; }
    { title = "No tests, unless proven."; text = "Write a test only when it is a proven regression guardrail: it reproduces a failure that happened, it fails without the fix, and it passes with it."; }
    { title = "Judgement is decision-oriented."; text = "Agent output, evidence and a definition of done go to a decision model. It gives calibrated probabilities to a decision engine, with rules that humans define, and the final verdict is an agentic decision."; }
    { title = "Humans own the rules."; text = "Humans write the rules of the decision engine and approve direction. Agents decide inside those rules, and stop and ask outside them. Humans merge."; }
    { title = "The brain is the record."; text = "The company is managed in pirsig: smart notes, PARA, and a track record of every high-level decision with its outcome."; }
    { title = "Open and reproducible by default."; text = "Every project is FOSS, in its own repository, with its own licence. The source is open, and so is the method. Rust comes first. Every plot is drawn with archify and every mockup with OpenPencil, from a source anyone can run again."; }
    { title = "Credit what we take."; text = "Read before you borrow. Reuse work only as its licence allows, and keep its notices. A partner's name and logo stay theirs."; }
    { title = "Guardrails only get stronger."; text = "Never weaken an approval point, a sandbox, a policy or a ruleset. Never read, print or store a secret."; }
    { title = "Routines run anywhere."; text = "An agentic routine may run on a developer's personal computer, on local models (Ollama, Ollaya). Anthropic has first-class support (Claude Code, the Claude API), and so does Kimi."; }
    { title = "Prod may break, for now."; text = "Breaking prod is not a problem, as long as it can be fixed quickly. What counts is the time to fix, not the number of breaks."; }
  ];

  # The board: the people who build piabrota, from the Board of the org profile and the org's
  # members, who agree (2026-11-01). `site` is each one's own website, "" for none.
  people = [
    { login = "h0ffmann"; name = "Matheus Hoffmann"; about = "water animal"; place = "Florianópolis, Brazil"; site = "https://h0ffmann.github.io/h0ffmann/"; }
    { login = "aracyla"; name = ""; about = "General purpose developer currently focused on frontend development."; place = "Brazil"; site = "https://aracyla.xyz"; }
    { login = "robkler"; name = "Rôb Klér Soares da Silva Júnior"; about = "Senior Backend Engineer"; place = "Rio de Janeiro, Brazil"; site = ""; }
  ];

  # Partners, each with its logo as GitHub publishes it (the org's avatar); never stored here.
  partners = [
    { login = "marola-dev"; name = "marola.dev"; about = "BR water super app"; site = "https://marola.dev"; }
    { login = "ouroboric-dev"; name = "ouroboric"; about = "Open factories that improve themselves. Charter, standards, journal and brand."; site = "https://github.com/ouroboric-dev"; }
  ];

  # Every fork under piabrota, as GitHub listed them on 1 November 2026
  # (`gh repo list piabrota --fork`): 14, every one PUBLIC, because GitHub keeps a fork of a
  # public repository public. started: the year its parent was created on GitHub. forked: the day the
  # fork was made. licence: the parent's. sync: GitHub's compare of the default branches; no fork has
  # commits of its own. The description is the fork's own, which GitHub copies from its parent.
  forks = [
    { name = "archify"; parent = "tt-a1i/archify"; started = "2026"; forked = "2026-10-26"; lang = "JavaScript"; licence = "Apache-2.0"; sync = "14 behind upstream"; description = "Turn any idea, plan, or codebase into a beautiful interactive diagram. An agent skill for Claude Code, Codex, and more."; }
    { name = "asgard"; parent = "ouroboric-dev/asgard"; started = "2026"; forked = "2026-11-01"; lang = "Python"; licence = "AGPL-3.0"; sync = "even with upstream"; description = "Asgard: the company factory, running on Yggdrasil. (Design phase.)"; }
    { name = "axon"; parent = "danieltamas/axon"; started = "2026"; forked = "2026-10-30"; lang = "Rust"; licence = "MIT"; sync = "even with upstream"; description = "Axon reads the logs your AI coding-agent harnesses already write — Claude Code, Codex, OpenCode — and shows which harness, project, agent, and model is working, how fast, at what cost, and how much code it's producing."; }
    { name = "bton"; parent = "danieltamas/bton"; started = "2026"; forked = "2026-10-30"; lang = "Swift"; licence = "MIT"; sync = "11 behind upstream"; description = "Bton runs your team's review flow with coding agents, from the macOS menu bar."; }
    { name = "cloudroom"; parent = "davidondrej/cloudroom"; started = "2026"; forked = "2026-11-01"; lang = "TypeScript"; licence = "Apache-2.0"; sync = "2 behind upstream"; description = "cloudroom is the open-source platform to run 1,000+ agents productively"; }
    { name = "core"; parent = "home-assistant/core"; started = "2013"; forked = "2026-10-26"; lang = "Python"; licence = "Apache-2.0"; sync = "810 behind upstream"; description = "Open source home automation that puts local control and privacy first."; }
    { name = "graphify"; parent = "Graphify-Labs/graphify"; started = "2026"; forked = "2026-10-26"; lang = "Python"; licence = "Apache-2.0"; sync = "179 behind upstream"; description = "Turn any codebase, with its docs, SQL schemas, configs, and PDFs, into a queryable knowledge graph. A /graphify skill for Claude Code, Cursor, Codex, and Gemini CLI: local deterministic AST parsing, every edge explained, no vector store."; }
    { name = "lean_kernel_verify"; parent = "facebookresearch/lean_kernel_verify"; started = "2026"; forked = "2026-10-31"; lang = "Python"; licence = "MIT"; sync = "even with upstream"; description = "Compiler-based safety checker for GPU kernels. It lowers the real compiler's IR into a small kernel IR and decides specs in Lean 4 (bounds, hangs, exactly-once writes, barrier protocol, races) with no hand-written model. Specs and frontends plug in independently; today Triton/TLX and CuTe DSL on NVIDIA Blackwell."; }
    { name = "pgx"; parent = "pgrundev/pgx"; started = "2026"; forked = "2026-10-30"; lang = "Rust"; licence = "AGPL-3.0"; sync = "even with upstream"; description = "PGX — Lightweight Postgres for AI agents. Written in Rust. Thousands of isolated databases in one runtime. 🐘"; }
    { name = "relay"; parent = "ronaknnathani/relay"; started = "2026"; forked = "2026-10-31"; lang = "Go"; licence = "MIT"; sync = "even with upstream"; description = "Skills to orchestrate coding agents to do long horizon tasks with little to no steering"; }
    { name = "rust-cuda"; parent = "Rust-GPU/rust-cuda"; started = "2021"; forked = "2026-10-26"; lang = "Rust"; licence = "Apache-2.0"; sync = "even with upstream"; description = "Ecosystem of libraries and tools for writing and executing fast GPU code fully in Rust."; }
    { name = "skills"; parent = "davidondrej/skills"; started = "2026"; forked = "2026-11-01"; lang = "Shell"; licence = "MIT"; sync = "even with upstream"; description = "access to david ondrej's personal agent skills"; }
    { name = "TencentDB-Agent-Memory"; parent = "TencentCloud/TencentDB-Agent-Memory"; started = "2026"; forked = "2026-10-30"; lang = "TypeScript"; licence = "see upstream"; sync = "even with upstream"; description = "TencentDB Agent Memory is a team-level memory hub for AI Agents — turning conversations, docs, and code into four reusable memory assets (Chat Memory, Skill, LLM-Wiki, Code-Graph) that are governed, shared, and equipped across agents and frameworks."; }
    { name = "yggdrasil"; parent = "ouroboric-dev/yggdrasil"; started = "2026"; forked = "2026-11-01"; lang = "Python"; licence = "AGPL-3.0"; sync = "even with upstream"; description = "Yggdrasil: an open software factory. Agents build, humans steer. (Design phase.)"; }
  ];
}
