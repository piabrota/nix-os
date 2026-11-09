# The pages of proof.piabrota.art, built on the builder: h0ffmann/proof's own browsable index
# (its site/default.nix, at the commit below) under /proof/, and an index at / that lists them.
# The pages of piabrota/pirsig are on their own name (pirsig.nix). No HTML is committed here.
#
# archify pages open dark, whatever the reader's setting (the owner, 2026-11-09): the index links
# them with ?theme=dark, and proof.nix sends any other request for one to that address. The build
# fails if an archify page is outside that location or no longer reads ?theme=.
#
# The output holds only files: allowedReferences = [ ] fails the build if it names a store path, so
# TeX Live, node and jq never reach the closure of piabrota2.
{ stdenvNoCC, callPackage, fetchFromGitHub, nodejs, jq }:
let
  common = import ./common.nix;

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
  nativeBuildInputs = [ nodejs jq ];

  buildPhase = ''
    runHook preBuild
    mkdir dist
    cp -R ${proof} dist/proof
    chmod -R u+w dist/proof

    ${common.darkGate "dist/proof/docs/diagrams/en/*.html | dist/proof/docs/diagrams/pt-BR/*.html"}
    ${common.indexFns}
    ${common.writeIndex {
      title = "proof";
      description = "Every HTML page of h0ffmann/proof: specifications, Z3 reports and diagrams.";
      lead = "Every HTML page of h0ffmann/proof, built from a pinned commit. The diagrams open dark.";
      drawn = "diagrams";
      body = ''
        echo "<h2 id=\"proof\">h0ffmann/proof</h2><p>Specifications checked by a prover, data experiments and papers. <a href=\"proof/\">Its own index</a> also lists the PDFs and the video preview. <a href=\"https://github.com/h0ffmann/proof/tree/${proofRev}\">Source at ${builtins.substring 0 7 proofRev}</a>.</p>"
        list "Pages" dist/proof -path dist/proof/docs/diagrams -prune -o -type f
        list "Diagrams, English" dist/proof/docs/diagrams/en -type f
        list "Diagrams, Português (BR)" dist/proof/docs/diagrams/pt-BR -type f
        list "Diagram index" dist/proof/docs/diagrams -maxdepth 1 -type f
      '';
    }}
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
