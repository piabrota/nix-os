# marola-site (marola-dev/marola-site) at a pinned commit, built by that repository's own
# nix/package.nix: the Haskell server (bin/marola-server) and the site it serves
# (share/marola/dist: the Elm map page and the static pages). The package is theirs; nothing here
# copies its code. To move the pin: change rev and hash together (`nix hash path` on
# `git archive <rev>`). passthru carries what the board build and the tiles unit read from the same commit: the
# app image it pins (marola-image), site/areas.json, the base map pin and its extract script.
{ lib, callPackage, fetchFromGitHub }:
let
  rev = "605cac52556e646bd09c951bef2a5681b3af9f5e";
  src = fetchFromGitHub {
    owner = "marola-dev";
    repo = "marola-site";
    inherit rev;
    hash = "sha256-O8fwT7118zh0u34HTzFeIPtx0fWy9QMV+zEekms48LI=";
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
