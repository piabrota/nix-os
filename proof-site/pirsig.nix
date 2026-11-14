# The pages of pirsig.piabrota.art, built on the builder: the HTML pages of piabrota/pirsig at the
# commit below (brain/Videos/index.html under /videos/, its archify figures under /figures/) and an
# index at / that lists them. No HTML is committed here. The pages of h0ffmann/proof are on their
# own name (default.nix); the steps and the dark gate are shared (common.nix). The index is made by
# the design kit (scala/design/), and the kit's brand bar goes into every other page. node runs
# archify only.
#
# archify pages open dark, whatever the reader's setting (the owner, 2026-11-09): the index links
# them with ?theme=dark, and proof.nix sends any other request for one to that address. The build
# fails if an archify page is outside that location or no longer reads ?theme=.
#
# The output holds only files: allowedReferences = [ ] fails the build if it names a store path, so
# ffmpeg, node, jq and archify never reach the closure of piabrota2.
{ lib, stdenvNoCC, callPackage, fetchFromGitHub, nodejs, jq, writeText }:
let
  common = import ./common.nix { inherit lib writeText callPackage; };

  # piabrota/pirsig's main: brain/Videos/index.html (one page, its images inline) and the figures of
  # docs/archify/, which archify draws here (pirsig's `just figure` draws only their PNGs).
  pirsigRev = "caa7bc7722f875bf617f59d0eaa6fffe9f201c27";
  pirsig = fetchFromGitHub {
    owner = "piabrota";
    repo = "pirsig";
    rev = pirsigRev;
    hash = "sha256-ig0hh2NwmA6gsLcTKwEU35b5IY31hYMDZ6chu7UBk8E=";
  };
  # The archify of pirsig's figures.lock and of figures-site/default.nix (vendor/archify).
  archify = fetchFromGitHub {
    owner = "tt-a1i";
    repo = "archify";
    rev = "208acba8d412335185b2056fedf54b3405df43fb";
    hash = "sha256-pejw78BgKDnttOAGcLvVtWa50azpCjTfESnmdYIjCoI=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "pirsig-pages";
  version = builtins.substring 0 7 pirsigRev;
  dontUnpack = true;
  nativeBuildInputs = [ nodejs jq ];

  buildPhase = ''
    runHook preBuild
    export ARCHIFY_UPDATE_CHECK_DISABLED=1
    mkdir -p dist/videos dist/figures

    # A copy from the store is read-only; the brand bar goes into it.
    cp ${pirsig}/brain/Videos/index.html dist/videos/index.html
    chmod u+w dist/videos/index.html

    # The figures of pirsig: validate, deliver and check with archify, as figures-site does. Exit 2
    # means the browser check was skipped (no Chrome on the builder); the three other gates must pass.
    for src in ${pirsig}/docs/archify/*.json; do
      slug=$(basename "$src" .json)
      work=$TMPDIR/work/$slug
      mkdir -p "$work"
      set +e
      log=$(node ${archify}/archify/bin/archify.mjs finalize "$(jq -r .diagram_type "$src")" "$src" "$work/page.html" \
        --out-dir "$work/receipts" --quality "$(jq -r '.meta.quality_profile // "showcase"' "$src")" 2>&1)
      status=$?
      set -e
      echo "$log" >&2
      if [ "$status" != 0 ] && [ "$status" != 2 ]; then echo "archify failed on $src" >&2; exit 1; fi
      if ! grep -qF 'gates validate:pass deliver:pass check:pass' <<<"$log"; then
        echo "archify gates did not pass on $src" >&2; exit 1
      fi
      cp "$work/page.html" "dist/figures/$slug.html"
    done

    ${common.darkGate [ "dist/figures/*.html" ]}
    ${common.indexSteps { current = "pirsig"; rev = pirsigRev; }}
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
