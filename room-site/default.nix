# The room (piabrota/room): a 3D room in Vite and three.js, built once on the builder with
# `npm ci` and `vite build` from a pinned commit. The output is dist/ and nothing else:
# allowedReferences = [ ] fails the build if it names a store path, so node and the npm
# packages never reach the VPS closure. A new commit of piabrota/room shows on the site only
# after a PR here changes rev, hash and npmDepsHash.
{ buildNpmPackage, fetchFromGitHub, nodejs_22 }:
buildNpmPackage {
  pname = "piabrota-room";
  version = "0-unstable-2026-11-09";
  src = fetchFromGitHub {
    owner = "piabrota";
    repo = "room";
    rev = "034d58a617e77d0e6c844621c0a292d3979a290c";
    hash = "sha256-iUfoT+TrYWYAJPrsvEUECHgZtz0BXFtYQ/8/EnJRFB4=";
  };
  # The hash of package-lock.json's packages: `nix run nixpkgs#prefetch-npm-deps -- package-lock.json`.
  npmDepsHash = "sha256-jDpvclK84fuO9jmN5/ehHmWjLID/bgsGHW3nGBfVifk=";
  # The room's flake gives Node 22 to its developers; build with the same.
  nodejs = nodejs_22;

  # `npm run build` is `vite build`, into dist/. The room is served at the root of its own name,
  # so Vite's default base (/) holds.
  installPhase = ''
    runHook preInstall
    cp -R dist $out
    test -f $out/index.html
    runHook postInstall
  '';

  allowedReferences = [ ];
}
