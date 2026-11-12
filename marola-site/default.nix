# marola-site (marola-dev/marola-site) at a pinned commit, built by that repository's own
# nix/package.nix: the Haskell server (bin/marola-server) and the site it serves
# (share/marola/dist: the Elm map page and the static pages). The package is theirs; nothing here
# copies its code. To move the pin: change rev and hash together (`nix hash path` on
# `git archive <rev>`).
{ callPackage, fetchFromGitHub }:
let
  rev = "f3c4f80a6371be83703ebcacbf2de584b5a35d97";
  src = fetchFromGitHub {
    owner = "marola-dev";
    repo = "marola-site";
    inherit rev;
    hash = "sha256-cRe5XJW/sV4lP7WFA7/7/oOdFLEAXJgl4d03kqg7OIA=";
  };
in
callPackage "${src}/nix/package.nix" { }
