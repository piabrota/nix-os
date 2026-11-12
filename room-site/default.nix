# The room (piabrota/room): a 3D room in Vite and three.js, built once on the builder with
# `npm ci` and `vite build` from a pinned commit. The output is dist/ and nothing else:
# allowedReferences = [ ] fails the build if it names a store path, so node and the npm
# packages never reach the VPS closure. A new commit of piabrota/room shows on the site only
# after a PR here changes rev, hash and npmDepsHash: `.github/workflows/room-pin.yml` opens that PR
# by itself when room's main moves (`scripts/room-pin.sh`, `just room-pin`).
{ buildNpmPackage, fetchFromGitHub, nodejs_22 }:
buildNpmPackage {
  pname = "piabrota-room";
  version = "0-unstable-2026-11-12";
  src = fetchFromGitHub {
    owner = "piabrota";
    repo = "room";
    rev = "f1caedaa65108b2505437400ab12387f57cda2f5";
    hash = "sha256-U5v1jT3CJUdWuQAPxvFOgefXEw15Qq0Sef8+hLJsNNc=";
  };
  # The hash of package-lock.json's packages: `nix run nixpkgs#prefetch-npm-deps -- package-lock.json`.
  npmDepsHash = "sha256-/uqbxk0gN7bIosBtSKr8xF6XG4H3TaJf9LGADFd2muQ=";
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
