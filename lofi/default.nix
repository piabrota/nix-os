# The lofi bot (lofi/src): one Rust binary, linked to libopus, which Discord's voice needs. The
# deck's tests run in the build.
{ lib, rustPlatform, pkg-config, libopus }:
rustPlatform.buildRustPackage {
  pname = "lofi";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [ ./Cargo.toml ./Cargo.lock ./src ];
  };
  cargoLock.lockFile = ./Cargo.lock;
  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ libopus ];
  # Symbols too, not only debug info: 24 MiB to a few.
  stripAllList = [ "bin" ];

  meta = {
    description = "A Discord bot that plays a folder of lofi tracks in one voice channel, without end";
    license = lib.licenses.mpl20;
    mainProgram = "lofi";
  };
}
