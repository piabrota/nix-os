# marola-site (marola-dev/marola-site) at a pinned commit, built by that repository's own
# nix/package.nix: the Haskell server (bin/marola-server) and the site it serves
# (share/marola/dist: the Elm map page and the static pages). The package is theirs; nothing here
# copies its code. To move the pin: change rev and hash together (`nix hash path` on
# `git archive <rev>`). passthru carries what the board build reads from the same commit: the app
# image it pins (marola-image) and site/areas.json.
{ lib, callPackage, fetchFromGitHub }:
let
  rev = "b5db03e238cdabb7e5e5c32d6724606746727632";
  src = fetchFromGitHub {
    owner = "marola-dev";
    repo = "marola-site";
    inherit rev;
    hash = "sha256-5iwsKZT81VLXxzlHxA2Mar7K37iEnWSn99L8FGZWflM=";
  };
in
(callPackage "${src}/nix/package.nix" { }).overrideAttrs (old: {
  passthru = (old.passthru or { }) // {
    marolaImage = lib.fileContents "${src}/marola-image";
    areas = "${src}/site/areas.json";
  };
})
