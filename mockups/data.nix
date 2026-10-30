# What the homepage mockups show, from the org profile (piabrota/.github, profile/README.md,
# 2026-10-30): the projects, their lanes in the "How it fits" figure, where each meets the web.
# `path` is a path on piabrota.art; `site` an address elsewhere; `state` is live, coming or none;
# `repo = false` when the project has no repository yet.
{
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
}
