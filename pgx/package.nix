# PGX (github.com/pgrundev/pgx), a Postgres-compatible engine in Rust, from its release, not from
# source: the build needs Rust 1.96, RE2 and a PostgreSQL 18 initdb, and the release ships the
# base cluster that initdb made. The tarball holds the CLI (`pgx`), the engine (`postgres`) and
# `share/` (timezones, contrib scripts, the base cluster); both binaries link only glibc and
# libstdc++, which autoPatchelfHook points at the store. nixpkgs (nixos-26.05) has no pgx; bump
# `version` and both hashes together (the release's .sha256 files list them in hex).
{ lib, stdenv, fetchurl, autoPatchelfHook }:
let
  arch = {
    x86_64-linux = { name = "amd64"; hash = "sha256-baCgwotUcUv/EJ1K1itsOPz1QzCv/vJJFiiANcAUapk="; };
    aarch64-linux = { name = "arm64"; hash = "sha256-FKF3MKVJs7qbFjI8zkdTC4aZ61w2jzqqNIFOkzhdHtg="; };
  }.${stdenv.hostPlatform.system} or (throw "pgx: no release for ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation (finalAttrs: {
  pname = "pgx";
  version = "0.1.2";

  src = fetchurl {
    url = "https://github.com/pgrundev/pgx/releases/download/v${finalAttrs.version}/pgx-${finalAttrs.version}-linux-${arch.name}.tar.gz";
    inherit (arch) hash;
  };

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib ];
  dontConfigure = true;
  dontBuild = true;

  # `pgx` finds the engine and share/ relative to its own path, so the layout stays as shipped.
  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r bin share $out/
    runHook postInstall
  '';

  meta = {
    description = "Lightweight Postgres-compatible database runtime (PostgreSQL 18 wire protocol and SQL)";
    homepage = "https://pgx.dev";
    license = lib.licenses.agpl3Only;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    mainProgram = "pgx";
  };
})
