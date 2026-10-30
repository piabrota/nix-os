# The facts of piabrota.art. The projects come from the org profile (piabrota/.github,
# profile/README.md, 2026-10-30): their lanes in the "How it fits" figure, where each meets the web;
# the mockups draw them. The board, the partners and the forks below are dated where they are.
# `path` is a path on piabrota.art; `site` an address elsewhere; `state` is live, coming or none;
# `repo = false` when the project has no repository yet. site/data.nix writes the same facts as
# Gleam for the live site, so the mockups and the site cannot disagree.
rec {
  # Where a project meets the web, as the cards and rows print it.
  where = p:
    if p ? path then "piabrota.art${p.path}"
    else p.site or (if p.repo or true then "github.com/piabrota/${p.name}" else "no repository yet");

  # What its address links to: a live path here, its own site, or its repository. "" for none,
  # and for a path here that is not live yet, so the address is never a link to somewhere else.
  href = p:
    if p ? path then (if p.state == "live" then p.path else "")
    else if p ? site then "https://${p.site}"
    else if p.repo or true then "https://github.com/piabrota/${p.name}"
    else "";

  org = {
    name = "piabrota";
    kicker = "open software fabric · made in RJ";
    headline = "Open software, made in Rio de Janeiro.";
    lede = "Each project is its own repository, with its own README, licence and tests. The source is open, and so is the method.";
    contact = "mhoffmannfs [at] gmail.com";
    links = [ "projects" "how it fits" "board" "partnerships" ];
  };

  lanes = [
    { id = "think"; label = "think and write"; }
    { id = "host"; label = "warn and host"; }
    { id = "play"; label = "play"; }
  ];

  projects = [
    {
      name = "pirsig";
      lane = "think";
      blurb = "A second brain: PARA and a Zettelkasten slip-box in one place. Desktop app, REST API and the psg CLI.";
      lang = "Rust";
      licence = "MPL-2.0";
      path = "/pirsig";
      state = "coming";
    }
    {
      name = "gramatico";
      lane = "think";
      blurb = "Rewrites technical text in Brazilian Portuguese so that it reads once. A Claude Code plugin.";
      lang = "Rust";
      licence = "MPL-2.0";
      site = "piabrota.github.io/gramatico";
      state = "live";
    }
    {
      name = "closed-source";
      lane = "think";
      blurb = "The god that failed: a book on why closed source failed as a protection, for science first.";
      lang = "Markdown";
      licence = "CC BY 4.0";
      site = "h0ffmann.github.io/closed-source";
      state = "live";
    }
    {
      name = "alerts";
      lane = "host";
      blurb = "Alerts from official sources only, to Discord and an Atom feed with CAP 1.2. First: floods in the south of Brazil.";
      lang = "Rust";
      licence = "MPL-2.0";
      path = "/alerts";
      state = "coming";
    }
    {
      name = "rax";
      lane = "host";
      blurb = "Rustic Agentic Runtime: a pure-Rust port of AX, the declarative orchestrator for agentic tasks.";
      lang = "Rust";
      licence = "MPL-2.0";
      state = "none";
    }
    {
      name = "nix-os";
      lane = "host";
      blurb = "The NixOS configuration of the small VPS that serves piabrota.art. Judged by its closure.";
      lang = "Nix";
      licence = "MPL-2.0";
      path = "/nixos";
      state = "live";
    }
    {
      name = "ihero";
      lane = "play";
      blurb = "A FOSS music player and game, in Rust. Coming.";
      repo = false;
      lang = "Rust";
      licence = "MPL-2.0";
      state = "coming";
    }
  ];

  # The board: the people who build piabrota, from their public GitHub profiles (2026-10-30).
  # `site` is each one's own website.
  people = [
    { login = "h0ffmann"; name = "Matheus Hoffmann"; about = "water animal, ai pilot"; place = "Florianópolis, Brazil"; site = "https://h0ffmann.github.io/h0ffmann/"; }
    { login = "aracyla"; name = ""; about = "General purpose developer currently focused on frontend development."; place = "Brazil"; site = "https://aracyla.xyz"; }
  ];

  # Partners, each with its logo as GitHub publishes it (the org's avatar); never stored here.
  partners = [
    { login = "marola-dev"; name = "marola.dev"; about = "BR water super app"; site = "https://marola.dev"; }
    { login = "ouroboric-dev"; name = "ouroboric"; about = "Open factories that improve themselves. Charter, standards, journal and brand."; site = "https://github.com/ouroboric-dev"; }
  ];

  # Every fork under piabrota, as GitHub listed them on 30 October 2026
  # (`gh repo list piabrota --fork`): 11, every one PUBLIC, because GitHub keeps a fork of a
  # public repository public. started: the year its parent was created on GitHub. forked: the day the
  # fork was made. The description is the fork's own, which GitHub copies from its parent.
  forks = [
    { name = "core"; parent = "home-assistant/core"; started = "2013"; forked = "2026-10-26"; description = "Open source home automation that puts local control and privacy first."; }
    { name = "rea"; parent = "morluto/rea"; started = "2026"; forked = "2026-10-26"; description = "Reverse engineer anything with agents, from app behavior down to native binaries."; }
    { name = "archify"; parent = "tt-a1i/archify"; started = "2026"; forked = "2026-10-26"; description = "Turn any idea, plan, or codebase into a beautiful interactive diagram. An agent skill for Claude Code, Codex, and more."; }
    { name = "prj-gd-engine"; parent = "mbracali/prj-gd-engine"; started = "2026"; forked = "2026-10-26"; description = "This repo contains re-implementations of guitar musical games"; }
    { name = "ouroboric"; parent = "ouroboric-dev/ouroboric"; started = "2026"; forked = "2026-10-26"; description = "Ouroboric: open factories that improve themselves. Charter, standards, journal and brand."; }
    { name = "edit"; parent = "fmhy/edit"; started = "2021"; forked = "2026-10-26"; description = "Make changes to FMHY"; }
    { name = "graphify"; parent = "Graphify-Labs/graphify"; started = "2026"; forked = "2026-10-26"; description = "Turn any codebase, with its docs, SQL schemas, configs, and PDFs, into a queryable knowledge graph. A /graphify skill for Claude Code, Cursor, Codex, and Gemini CLI: local deterministic AST parsing, every edge explained, no vector store."; }
    { name = "thc"; parent = "ekmett/thc"; started = "2015"; forked = "2026-10-26"; description = "The Turbo Haskell Compiler"; }
    { name = "rust-cuda"; parent = "Rust-GPU/rust-cuda"; started = "2021"; forked = "2026-10-26"; description = "Ecosystem of libraries and tools for writing and executing fast GPU code fully in Rust."; }
    { name = "naruto-unison"; parent = "naruto-unison/naruto-unison"; started = "2018"; forked = "2026-10-26"; description = "Naruto Unison"; }
    { name = "OpenVoice"; parent = "myshell-ai/OpenVoice"; started = "2023"; forked = "2026-10-26"; description = "Instant voice cloning by MIT and MyShell. Audio foundation model."; }
  ];
}
