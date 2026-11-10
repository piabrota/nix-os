# What proof-site/default.nix (proof.piabrota.art) and proof-site/pirsig.nix (pirsig.piabrota.art) share:
# the gate for archify pages, and the steps that put the brand bar into every page and make the index
# with the design kit (design/, docs/DESIGN-KIT.md). Plain Nix, no derivation: each output is built in
# its own file, with its own `allowedReferences = [ ]`.
{ lib, writeText }:
let
  icons = import ../favicon/links.nix;
  # The list of sites, for the brand bar and the nav: one source, design/sites.nix.
  sitesJson = writeText "piabrota-sites.json" (builtins.toJSON (import ../design/sites.nix).sites);
  # Only what the build runs: the kit's CSS and modules and the two scripts of this folder. A change
  # to a test does not rebuild the pages.
  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [ ../design/css ../design/kit.mjs ../design/inject.mjs ./manifest.mjs ./index.mjs ];
  };
in
{
  # Shell: dark, always. proof.nix sends an archify page asked for without ?theme=dark to that
  # address, and archify reads the address before localStorage and the system setting. Each archify
  # page must still read it, and must sit where proof.nix's location looks. `allowed` is the `case`
  # pattern of the paths of that location.
  darkGate = allowed: ''
    while IFS= read -r page; do
      case "$page" in
        ${allowed}) ;;
        *) echo "$page: an archify page outside proof.nix's dark location" >&2; exit 1 ;;
      esac
      if ! grep -qF "URLSearchParams(window.location.search).get('theme')" "$page"; then
        echo "$page: archify no longer reads ?theme= from the address" >&2; exit 1
      fi
    done < <(grep -rlF --include='*.html' "archify-theme" dist)
  '';

  # Shell: the brand bar into every page of `dist`; the list of pages as JSON; the index, made by the
  # kit from that list; then the check that every page but the index has the bar. `current` is the
  # site's id in design/sites.nix, `rev` the commit of the pages' repository.
  indexSteps = { current, rev }: ''
    node ${src}/design/inject.mjs inject dist --current ${current} --sites ${sitesJson} --index /
    node ${src}/proof-site/manifest.mjs dist ${current} > "$TMPDIR/manifest.json"
    node ${src}/proof-site/index.mjs ${current} "$TMPDIR/manifest.json" --rev ${rev} --sites ${sitesJson} --icons '${icons}' > dist/index.html
    node ${src}/design/inject.mjs check dist --except index.html
  '';
}
