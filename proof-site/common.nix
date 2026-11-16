# What proof-site/default.nix (proof.piabrota.art) and proof-site/pirsig.nix (pirsig.piabrota.art) share:
# the gate for archify pages, and the steps that put the brand bar into every page and make the index
# with the design kit (scala/design/, docs/DESIGN-KIT.md). Plain Nix, no derivation: each output is
# built in its own file, with its own `allowedReferences = [ ]`.
{ lib, writeText, callPackage }:
let
  icons = import ../favicon/links.nix;
  # The list of sites, for the brand bar and the nav: one source, design/sites.nix.
  sitesJson = writeText "piabrota-sites.json" (builtins.toJSON (import ../design/sites.nix).sites);

  # The steps are commands of the scripts' binary (scala/design/); the two that write HTML read the
  # kit's CSS from DESIGN_CSS. A change to any script of scala/ builds the pages again.
  scripts = callPackage ../scala { };
  kit = name: scripts.command { inherit name; env.DESIGN_CSS = "${../design/css}"; };
  bin = {
    inject = "${kit "design-inject"}/bin/design-inject";
    index = "${kit "proof-index"}/bin/proof-index";
    manifest = "${scripts.command { name = "proof-manifest"; }}/bin/proof-manifest";
    loc = "${scripts.command { name = "proof-loc"; }}/bin/proof-loc";
    darkGate = "${scripts.command { name = "proof-dark-gate"; }}/bin/proof-dark-gate";
  };
in
{
  # Shell: dark, always. proof.nix sends an archify page asked for without ?theme=dark to that
  # address, and archify reads the address before localStorage and the system setting. Each archify
  # page must still read it, and must sit where proof.nix's location looks. `allowed` is the list of
  # `case` patterns of the paths of that location.
  darkGate = allowed: "${bin.darkGate} dist ${lib.escapeShellArgs allowed}";

  # Shell: the brand bar into every page of `dist`; the list of pages as JSON; the index, made by the
  # kit from that list; then the check that every page but the index has the bar. `current` is the
  # site's id in design/sites.nix, `rev` the commit of the pages' repository. `loc`, when given, is
  # that repository's source: proof-loc counts its lines of code for the index.
  indexSteps = { current, rev, loc ? null }: ''
    ${bin.inject} inject dist --current ${current} --sites ${sitesJson} --index /
    ${bin.manifest} dist ${current} > "$TMPDIR/manifest.json"
    ${lib.optionalString (loc != null) ''${bin.loc} ${loc} > "$TMPDIR/loc.json"''}
    ${bin.index} ${current} "$TMPDIR/manifest.json" --rev ${rev} --sites ${sitesJson} --icons '${icons}'${lib.optionalString (loc != null) " --loc \"$TMPDIR/loc.json\""} > dist/index.html
    ${bin.inject} check dist --except index.html
  '';
}
