# marola-site (marola-dev/marola-site) at a pinned commit, built by that repository's own
# nix/package.nix: the Haskell server (bin/marola-server) and the site it serves
# (share/marola/dist: the Elm map page and the static pages). The package is theirs; nothing here
# copies its code. To move the pin: change rev and hash together (`nix hash path` on
# `git archive <rev>`). passthru carries what the board build and the tiles unit read from the same commit: the
# app image it pins (marola-image), site/areas.json, the base map pin and its extract script.
{ lib, callPackage, fetchFromGitHub }:
let
  rev = "ecc34e339841248c740a43e2554e202c611c3482";
  src = fetchFromGitHub {
    owner = "marola-dev";
    repo = "marola-site";
    inherit rev;
    hash = "sha256-RZ9z0U4jUcP2zHcO+cEDiP/D8YZ5iYinO6ejhVMJz9M=";
  };
in
(callPackage "${src}/nix/package.nix" { }).overrideAttrs (old: {
  passthru = (old.passthru or { }) // {
    marolaImage = lib.fileContents "${src}/marola-image";
    areas = "${src}/site/areas.json";
    basemapVersion = "${src}/site/basemap.version";
    basemapExtract = "${src}/scripts/basemap_extract.sh";
  };
})
