# oh-my-pi (omp) from its release binary, not from source. Built from the flake, omp is a Rust and
# Bun build with its own nixpkgs, rust-overlay toolchain and crane: no binary cache has it, so the
# first deploy after each bump compiled it on the runner. The release is the same tag's `bun build
# --compile` output; its JavaScript lives in the ELF section `.bun`, so patchelf can set the
# interpreter, and strip must not run.
{ lib, stdenvNoCC, fetchurl, autoPatchelfHook }:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "omp";
  version = "18.16.0";
  src = fetchurl {
    url = "https://github.com/can1357/oh-my-pi/releases/download/v${finalAttrs.version}/omp-linux-x64";
    hash = "sha256-ZJjteFurANKSbgOH4OwCNi1tRfHD0NG1fBYYt/lckmQ=";
  };
  dontUnpack = true;
  dontStrip = true;
  nativeBuildInputs = [ autoPatchelfHook ];
  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/omp
    runHook postInstall
  '';
  meta = {
    description = "oh-my-pi, a terminal coding agent (release binary)";
    homepage = "https://github.com/can1357/oh-my-pi";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "omp";
  };
})
