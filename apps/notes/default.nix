# The notes demo, a Loco app (loco new 1.2, then a hand-written controller): CRUD for notes on
# SQLite, under /notes on www.piabrota.art, behind one password read from the box's environment
# file. Built here so it ships with the loco.nix change that mounts it; a real app lives in its
# own repository (docs/LOCO.md). The output is what loco.nix runs: bin/notes-cli, and
# share/notes/ with config/ and assets/ (the Tera views are read from there at run time).
{ lib, rustPlatform }:
rustPlatform.buildRustPackage {
  pname = "notes";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./Cargo.toml
      ./Cargo.lock
      ./src
      ./migration
      ./config
      ./assets
    ];
  };
  cargoLock.lockFile = ./Cargo.lock;

  # Only the binary: the generated playground and tool are not needed on the box.
  cargoBuildFlags = [ "--bin" "notes-cli" ];
  # The unit tests of the controller (the password check, the form limits). The generated
  # request tests need a database and a test config, so they run with `cargo test` locally.
  cargoTestFlags = [ "--lib" ];
  checkFlags = [ "controllers::web::" ];

  postInstall = ''
    mkdir -p $out/share/notes
    cp -r config assets $out/share/notes/
  '';

  meta = {
    description = "Notes, a Loco demo for piabrota.art";
    license = lib.licenses.mpl20;
    mainProgram = "notes-cli";
  };
}
