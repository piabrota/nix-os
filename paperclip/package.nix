# Paperclip (github.com/paperclipai/paperclip, MIT) from its npm release, not from source: the
# source is a pnpm workspace whose image build also compiles a Rust runner and installs four agent
# CLIs. The npm tarball has no lock file, so package.json here is the release's own with its
# optional dependencies replaced by the two that Linux needs (sharp's x64 build and its libvips),
# and package-lock.json is made from it (docs/PAPERCLIP.md, "Updating"). The optional ones are
# embedded PostgreSQL and agent CLI binaries for every platform (3.9 GiB to fetch, 2.3 GiB
# installed; without them 113 MiB and 564 MiB, measured 2026-11-04); this box uses the
# NixOS PostgreSQL and talks to Hermes over HTTP. Bump `version`, both hashes and the two files
# together.
{ lib, buildNpmPackage, fetchNpmDeps, fetchurl, runCommand, jq, nodejs_24 }:
let
  # The lock without the download address of a package that only an optional dependency pulls in
  # (the other platforms' binaries): the fetch skips them, and `--omit=optional` installs none.
  lock = runCommand "paperclipai-package-lock.json" { nativeBuildInputs = [ jq ]; } ''
    jq '(.packages[] | select(.optional == true)) |= del(.resolved, .integrity)' ${./package-lock.json} > $out
  '';
in
(buildNpmPackage.override { nodejs = nodejs_24; }) (finalAttrs: {
  pname = "paperclipai";
  version = "2026.1023.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/paperclipai/-/paperclipai-${finalAttrs.version}.tgz";
    hash = "sha256-wF6KKFpdDmpthbYKuFClUaAqfInynGaJXULoHNus8AI=";
  };
  sourceRoot = "package";
  postPatch = ''
    cp ${./package.json} package.json
    cp ${lock} package-lock.json
  '';
  npmDeps = fetchNpmDeps {
    name = "paperclipai-${finalAttrs.version}-npm-deps";
    src = runCommand "paperclipai-lock" { } "mkdir $out; cp ${lock} $out/package-lock.json";
    hash = "sha256-AyRMlUWZwFSXuJrmhKkPe6Jq46UUqBVkM7TEjlI6LKE=";
  };

  # The release is built: dist/ is the bundled CLI and @paperclipai/server ships its own dist/.
  dontNpmBuild = true;
  npmInstallFlags = [ "--omit=optional" ];
  # No install script runs: they download binaries (opencode-ai) or compile optional native
  # helpers (ssh2, cpu-features) that the server loads only when they are there.
  npmRebuildFlags = [ "--ignore-scripts" ];

  # No autoPatchelfHook: patchelf on sharp's prebuilt libvips makes it segfault on load. Unpatched,
  # it loads, because the nixpkgs node has already loaded the libstdc++ and libgcc_s it asks for,
  # and libvips sits next to the addon ($ORIGIN). The other prebuilt binaries are not run here.

  passthru = {
    nodejs = nodejs_24;
    # The server's entry point (the Docker image runs its own bundle of the same server).
    server = "lib/node_modules/paperclipai/node_modules/@paperclipai/server/dist/index.js";
    # Paperclip's skills for its agents, shipped with the server.
    skills = "lib/node_modules/paperclipai/node_modules/@paperclipai/server/skills";
  };

  meta = {
    description = "Paperclip, a control plane for teams of AI agents (npm release)";
    homepage = "https://github.com/paperclipai/paperclip";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "paperclipai";
  };
})
