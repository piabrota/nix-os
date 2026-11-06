# The room (piabrota/room): a 3D room in Vite and three.js, built once on the builder with
# `npm ci` and `vite build` from a pinned commit. The output is dist/ and nothing else:
# allowedReferences = [ ] fails the build if it names a store path, so node and the npm
# packages never reach the VPS closure. A new commit of piabrota/room shows on the site only
# after a PR here changes rev, hash and npmDepsHash.
{ buildNpmPackage, fetchFromGitHub, nodejs_22 }:
buildNpmPackage {
  pname = "piabrota-room";
  version = "0-unstable-2026-11-05";
  src = fetchFromGitHub {
    owner = "piabrota";
    repo = "room";
    rev = "0da08f17e4d9d34b75e8667df608eecb4cb63f70";
    hash = "sha256-zB7wegWi3IpfPDmFUyx6TnaRYcGq55nOi1UqYm0utbg=";
  };
  # The hash of package-lock.json's packages: `nix run nixpkgs#prefetch-npm-deps -- package-lock.json`.
  npmDepsHash = "sha256-mj7bt+iuqhlv5XPN+GdaptrPhMw7OwkHi1ri4qXoDBE=";
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
