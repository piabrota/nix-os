# `reel`, the toolkit of the Reels Fabric rig (docs/REELS.md): one screenplay.json a reel, scenes in
# SVG and ASS captions, procedural sound, assembly with ffmpeg. POSIX sh and jq; no Python, no network,
# no model. `bin/reel` runs with a PATH of its own tools only, and finds its data in
# share/reels (REELS_SHARE).
#
# Tools: ffmpeg-headless (it has libx264, libass and fontconfig, which the captions need; the full
# ffmpeg adds a display stack for nothing), resvg (one small Rust binary, no fontconfig of its own;
# ImageMagick would pull more), jq, GNU coreutils (timeout and nice for every ffmpeg) and `time` (the
# peak memory in render.json).
#
# Fonts: the owner's exception to "no fonts" (AGENTS.md), two files and no collection: Inter
# (variable, from nixpkgs) for text and Fjalla One for titles, the two faces of site/DESIGN.md. Both
# are copied into share/reels/fonts, so the scripts read that folder and never ask fontconfig for the
# system's fonts. About 1.1 MB in all.
#
# Tests: `nix build .#...reels.tests.run` (passthru.tests.run, test/run.sh) runs the real `reel` on the
# 15 s example: the approval gate, hostile text, slugs, the lint, a render twice for the same bytes, the
# QA against files that must fail, publish, a failing ffmpeg and the time limit. It takes minutes and
# about 600 MiB, so no check of the flake runs it.
{ lib
, stdenvNoCC
, makeWrapper
, fetchurl
, inter
, jq
, ffmpeg-headless
, resvg
, coreutils
, time
, runCommand
, dash
, shellcheck
, findutils
, diffutils
}:
let
  # google/fonts at the commit that nixpkgs' google-fonts pins. A single file: google-fonts itself
  # would fetch the whole repository.
  fjallaOne = fetchurl {
    url = "https://raw.githubusercontent.com/google/fonts/5174b3333331c966c38f4355d50b03ca1c1df2f9/ofl/fjallaone/FjallaOne-Regular.ttf";
    hash = "sha256-zjspliWr48dvis0jW1ez4HrG7i1VDhBqS05NYAla4ro=";
  };
  toolPath = lib.makeBinPath [ jq ffmpeg-headless resvg coreutils time ];
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "reels";
  version = "1";

  # The tests are not part of what runs: a change to them does not rebuild the toolkit.
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.difference ./. (lib.fileset.unions [ ./default.nix ./test ]);
  };

  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    share=$out/share/reels
    mkdir -p $out/bin $share/fonts
    cp -r profile.json lib styles examples $share/
    install -m 0755 reel $out/bin/reel
    install -m 0444 ${inter}/share/fonts/truetype/InterVariable.ttf $share/fonts/InterVariable.ttf
    install -m 0444 ${fjallaOne} $share/fonts/FjallaOne-Regular.ttf
    wrapProgram $out/bin/reel \
      --set REELS_SHARE $share \
      --set PATH ${toolPath}
    runHook postInstall
  '';

  passthru.tests.run = runCommand "reels-test"
    {
      nativeBuildInputs = [ jq ffmpeg-headless coreutils findutils diffutils dash shellcheck ];
    }
    ''
      pkg=${finalAttrs.finalPackage}
      cd ${./.}
      shellcheck -x -s sh reel test/run.sh
      for f in reel lib/*.sh test/run.sh; do dash -n "$f"; done
      export REEL=$pkg/bin/reel
      export REEL_DASH="${coreutils}/bin/env REELS_SHARE=$pkg/share/reels PATH=${toolPath} ${dash}/bin/dash $pkg/bin/.reel-wrapped"
      export REEL_SCRIPT=$pkg/bin/.reel-wrapped
      export REELS_SHARE=$pkg/share/reels
      export REELS_TOOLPATH=${toolPath}
      export REELS_FONTS=$pkg/share/reels/fonts
      export TMPDIR=$(mktemp -d)
      sh ${./test/run.sh} | tee $out
    '';

  meta = {
    description = "Screenplay-first toolkit that makes 15 s and 30 s vertical reels from code only";
    license = lib.licenses.mpl20;
    mainProgram = "reel";
    platforms = lib.platforms.linux;
  };
})
