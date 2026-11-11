# /llms.txt (https://llmstxt.org): an index of piabrota for an AI agent, in Markdown, written from
# mockups/data.nix, the facts the site and the mockups print, so the three cannot disagree. Its shape
# follows xerj.org/llms.txt: one H1, a quote that says what this is, a note on how to read it, then
# sections of links with one line each. site.nix serves it; `just llms` prints it.
{ lib, data, base, hermes ? false, figures ? false, skills ? null }:
let
  inherit (lib) concatMapStrings filter optionalString;
  # A link of data.href is a path here, an address elsewhere, or "" (a path here that is not live yet).
  link = p:
    let h = data.href p; in
    if h == "" then data.repo p
    else if lib.hasPrefix "/" h then "${base}${h}"
    else h;
  # A blurb or a description with a full stop, when it ends on a letter or a digit.
  sentence = t: if builtins.match ".*[[:alnum:]]" t != null then "${t}." else t;
  state = { live = ""; coming = " Coming: not live yet."; none = ""; };
  source = p: optionalString (link p != data.repo p) " Source: ${data.repo p}.";
  project = p:
    "- [${p.name}](${link p}): ${sentence p.blurb} ${p.lang}; ${p.licence}.${source p}${state.${p.state}}\n";
  lane = l:
    let ps = filter (p: p.lane == l.id) data.projects; in
    optionalString (ps != [ ]) "\n### ${l.label}\n\n${concatMapStrings project ps}";
  service = s:
    "- [${s.label}](https://${s.host}/): ${s.blurb} ${if s.access == "public" then "Public." else "Behind a login: an agent gets a 401."}\n";
  page = path: text: "- [${base}${path}](${base}${path}): ${text}\n";
in
''
  # ${data.org.name}

  > ${data.org.headline} ${data.org.lede}

  This file is an index for you, the AI agent: find your topic here and follow its link. The detail
  lives behind the links, not here. Each project is its own repository; when this file and a
  repository disagree, the repository wins. The file is written at build time from
  `mockups/data.nix` of https://github.com/piabrota/nix-os, where every fact has its date, and it
  changes with each deploy.

  ## Start here

  ${page "/" "the homepage (design A, fabric): the projects, the structure, the dogma, the FOSS inventory, the board, the partners and the forks."}${page "/index/" "the same facts as an index (design B)."}${page "/paths/" "the same facts as paths (design C)."}${page "/pt-BR/" "the homepage in Brazilian Portuguese; also /zh-CN/ and /ja-JP/."}${page "/hosts/" "the two VPSs that serve piabrota.art and what each one runs."}${optionalString hermes (page "/hermes/" "the configuration of the Hermes Agent on the VPS, as plain YAML, with no secret.")}${optionalString figures (page "/figures/" "the figures of the README and the wiki, as interactive pages.")}- [${base}/nixos](https://github.com/piabrota/nix-os): the NixOS configuration of the VPSs; every address above is declared there.
  - [github.com/piabrota](https://github.com/piabrota): the organization, with every repository.
  - [all the work of h0ffmann](https://github.com/piabrota/nix-os/blob/main/llms.txt): the index of the work of the founder outside piabrota too (research, marola, the books).

  ## Services

  Each service is on its own name under piabrota.art.

  ${optionalString (skills != null) "- [skills](https://${skills}/): the skills website, from piabrota/skills at a pinned commit. Public.\n"}${concatMapStrings service data.services}
  ## Projects

  Each line is the project, its language and its licence.
  ${concatMapStrings lane data.lanes}
  ## How the company works

  ${concatMapStrings (s: "- [${s.name}](${if lib.hasPrefix "#" s.href then "${base}/${s.href}" else s.href}), ${s.role}: ${s.text}\n") data.structure}
  ## Why it is open

  ${concatMapStrings (w: "- **${w.title}** ${w.text}\n") data.why}
  ## The dogma

  The ten invariants of https://github.com/piabrota/mu (DOGMA.md), shortened.

  ${concatMapStrings (d: "- **${d.title}** ${d.text}\n") data.dogma}
  ## Partners

  ${concatMapStrings (p: "- [${p.name}](${p.site}): ${sentence p.about}\n") data.partners}
  ## Optional

  The forks under piabrota. None has commits of its own: each one follows its parent.

  ${concatMapStrings (f: "- [${f.name}](https://github.com/piabrota/${f.name}), a fork of [${f.parent}](https://github.com/${f.parent}) (${f.lang}, ${f.licence}): ${sentence f.description}\n") data.forks}''
