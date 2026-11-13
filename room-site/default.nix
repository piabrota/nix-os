# The room (piabrota/room): a 3D room in Vite and three.js, built once on the builder with
# `npm ci` and `vite build` from a pinned commit. The output is dist/ and nothing else:
# allowedReferences = [ ] fails the build if it names a store path, so node and the npm
# packages never reach the VPS closure. A new commit of piabrota/room shows on the site only
# after a PR here changes rev, hash and npmDepsHash: `.github/workflows/room-pin.yml` opens that PR
# by itself when room's main moves (`scripts/pins.py one room`, `just room-pin`).
{ buildNpmPackage, fetchFromGitHub, nodejs_22 }:
buildNpmPackage {
  pname = "piabrota-room";
  version = "0-unstable-2026-11-13";
  src = fetchFromGitHub {
    owner = "piabrota";
    repo = "room";
    rev = "80db3568bd0344dcbb1851f524d34151580ed046";
    hash = "sha256-2vh3YvDK4+CofiacQOh782sqFFAr/awl1Yeuf6MSSRM=";
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
