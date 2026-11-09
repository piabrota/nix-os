# The pages of proof.piabrota.art, built on the builder: h0ffmann/proof's own browsable index
# (its site/default.nix, at the commit below) under /proof/, and an index at / that lists them.
# The pages of piabrota/pirsig are on their own name (pirsig.nix). No HTML is committed here.
#
# The index is made by the design kit (design/kit.mjs) from the list of pages, and the brand bar of
# the kit goes into every page of h0ffmann/proof (design/inject.mjs); common.nix has the steps.
#
# archify pages open dark, whatever the reader's setting (the owner, 2026-11-09): the index links
# them with ?theme=dark, and proof.nix sends any other request for one to that address. The build
# fails if an archify page is outside that location or no longer reads ?theme=.
#
# The output holds only files: allowedReferences = [ ] fails the build if it names a store path, so
# TeX Live and node never reach the closure of piabrota2.
{ lib, stdenvNoCC, callPackage, fetchFromGitHub, nodejs, writeText }:
let
  common = import ./common.nix { inherit lib writeText; };

  # h0ffmann/proof's main. Move rev and hash together; its site needs no change here.
  proofRev = "b863c15e56a22afaab2fa228fe5eb85847c1d6c4";
  proofSrc = fetchFromGitHub {
    owner = "h0ffmann";
    repo = "proof";
    rev = proofRev;
    hash = "sha256-1LdrGlHaIPZbO6ZL5JJnHN/XPzGpkYjRYQROfQ4RgQ4=";
  };
  proof = callPackage "${proofSrc}/site" { rev = proofRev; };
in
stdenvNoCC.mkDerivation {
  pname = "proof-pages";
  version = builtins.substring 0 7 proofRev;
  dontUnpack = true;
  nativeBuildInputs = [ nodejs ];

  buildPhase = ''
    runHook preBuild
    mkdir dist
    cp -R ${proof} dist/proof
    chmod -R u+w dist/proof

    ${common.darkGate "dist/proof/docs/diagrams/en/*.html | dist/proof/docs/diagrams/pt-BR/*.html"}
    ${common.indexSteps { current = "proof"; rev = proofRev; }}
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    cp -R dist $out
    runHook postInstall
  '';

  dontFixup = true;
  allowedReferences = [ ];
}
