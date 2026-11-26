# marola-site (marola-dev/marola-site) at a pinned commit, built by that repository's own
# nix/package.nix: the Haskell server (bin/marola-server) and the site it serves
# (share/marola/dist: the Elm map page and the static pages). The package is theirs; nothing here
# copies its code. To move the pin: change rev and hash together (`nix hash path` on
# `git archive <rev>`). passthru carries what the board build and the tiles unit read from the same commit: the
# app image it pins (marola-image), site/areas.json, the base map pin and its extract script.
{ lib, callPackage, fetchFromGitHub }:
let
  rev = "57c25dc779599d7995570ff1e581d6d1333d69a6";
  src = fetchFromGitHub {
    owner = "marola-dev";
    repo = "marola-site";
    inherit rev;
    hash = "sha256-lyRBWEPAPw+f1svqVHeHuc2VvH14enpAvh3jeG31DdY=";
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
