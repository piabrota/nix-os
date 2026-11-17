# The website of h0ffmann/h0ffmann (the owner's profile): the static HTML that its www/build.py
# writes into www/dist, committed there, copied as it is at the commit below. No build step here:
# the site is HTML only, with no Gleam and no JavaScript (the owner, 2026-11-13).
{ stdenvNoCC
, fetchFromGitHub
}:
let
  rev = "2db650ebdb64ab685a29b13945754c6b7190977d";
in
stdenvNoCC.mkDerivation {
  pname = "h0ffmann-site";
  version = "0-unstable-${builtins.substring 0 7 rev}";
  src = fetchFromGitHub {
    owner = "h0ffmann";
    repo = "h0ffmann";
    inherit rev;
    hash = "sha256-sTMp8FukhAkXQcrazJVYiamB4YC/ZNwiAAyxBefPagk=";
  };
  dontConfigure = true;
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    grep -q '<html' www/dist/index.html
    if grep -rlq '<script' www/dist; then echo "hffmnn-site: www/dist has a <script>" >&2; exit 1; fi
    cp -R www/dist $out
    runHook postInstall
  '';
  dontFixup = true;
  allowedReferences = [ ];
}
