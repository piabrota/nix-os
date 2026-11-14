# `reel`, the toolkit of the Reels Fabric rig (docs/REELS.md): one screenplay.json a reel, scenes in
# SVG and ASS captions, procedural sound, assembly with ffmpeg. The command is `piabrota reel`
# (scala/reels/, Scala 3), the screenplay rules are jq programs (lib/*.jq); no Python, no network, no
# model. `bin/reel` runs with a PATH of its own tools only, and finds its data in share/reels
# (REELS_SHARE).
#
# Tools: ffmpeg-headless (it has libx264, libass and fontconfig, which the captions need; the full
# ffmpeg adds a display stack for nothing), resvg (one small Rust binary, no fontconfig of its own;
# ImageMagick would pull more), jq, GNU coreutils (timeout, nice, sha256sum, cp, chmod) and `time`
# (the peak memory in render.json). Blender is not here: it is optional, and the wrapper only passes
# on the `blender` that the caller has in its PATH (docs/REELS.md, "3D shots with Blender").
#
# Fonts: the owner's exception to "no fonts" (AGENTS.md), two files and no collection: Inter
# (variable, from nixpkgs) for text and Fjalla One for titles, the two faces of site/DESIGN.md. Both
# are copied into share/reels/fonts, so the toolkit reads that folder and never asks fontconfig for
# the system's fonts. About 1.1 MB in all.
#
# Tests: `nix build .#...reels.tests.run` (passthru.tests.run) builds piabrota again with the tools
# and this share folder, so its checkPhase runs scala/reels/Reel.test.scala against the real `reel`
# on the 15 s example: the approval gate, hostile text, slugs, the lint, a render twice for the same
# bytes, the QA against files that must fail, publish, a failing ffmpeg and the time limit. It takes
# minutes and about 600 MiB, so no check of the flake runs it.
{ lib
, stdenvNoCC
, callPackage
, makeWrapper
, fetchurl
, inter
, jq
, ffmpeg-headless
, resvg
, coreutils
, time
}:
let
  scripts = callPackage ../scala { };

  # google/fonts at the commit that nixpkgs' google-fonts pins. A single file: google-fonts itself
  # would fetch the whole repository.
  fjallaOne = fetchurl {
    url = "https://raw.githubusercontent.com/google/fonts/5174b3333331c966c38f4355d50b03ca1c1df2f9/ofl/fjallaone/FjallaOne-Regular.ttf";
    hash = "sha256-zjspliWr48dvis0jW1ez4HrG7i1VDhBqS05NYAla4ro=";
  };
  tools = [ jq ffmpeg-headless resvg coreutils time ];

  # `piabrota reel` with the toolkit's tools as its whole PATH.
  reel = scripts.command {
    name = "reel";
    runtimeInputs = tools;
    exclusivePath = true;
  };
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "reels";
  version = "1";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [ ./profile.json ./lib ./styles ./examples ];
  };

  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    share=$out/share/reels
    mkdir -p $out/bin $share/fonts
    cp -r profile.json lib styles examples $share/
    install -m 0444 ${inter}/share/fonts/truetype/InterVariable.ttf $share/fonts/InterVariable.ttf
    install -m 0444 ${fjallaOne} $share/fonts/FjallaOne-Regular.ttf
    # The inner wrapper replaces PATH with the toolkit's tools, so this one reads the caller's PATH
    # first: `reel blender` needs the caller's blender (piabrota.openrig.reels.blender.enable), and
    # its path goes in REELS_BLENDER, empty when there is none.
    makeWrapper ${reel}/bin/reel $out/bin/reel \
      --run 'REELS_BLENDER=$(command -v blender 2>/dev/null || :); export REELS_BLENDER' \
      --set REELS_SHARE $share
    runHook postInstall
  '';

  passthru.tests.run = scripts.overrideAttrs (old: {
    pname = "reels-test";
    nativeBuildInputs = old.nativeBuildInputs ++ tools;
    preCheck = ''
      export REELS_SHARE=${finalAttrs.finalPackage}/share/reels
      export REELS_SPECS=${../openrig/specs}
      export REELS_OPENRIG_NIX=${../openrig.nix}
    '';
  });

  meta = {
    description = "Screenplay-first toolkit that makes 15 s and 30 s vertical reels from code only";
    license = lib.licenses.mpl20;
    mainProgram = "reel";
    platforms = lib.platforms.linux;
  };
})
