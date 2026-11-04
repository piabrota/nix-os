# OpenRig (github.com/mvschwarz/openrig, Apache-2.0), built from source at a release tag. The
# source is an npm workspace (daemon, UI, TUI, CLI). This file repeats the steps of
# scripts/build-package.sh, which needs git and the network: it builds the daemon, the TUI and the
# CLI with tsc, writes the build stamp, makes the context packs, and puts the daemon and the TUI in
# the CLI package. The result has the layout of the npm package @openrig/cli, so `rig` finds its
# daemon in its own `daemon/` folder. The UI is not built: it is in maintenance mode, the daemon
# serves no web page without it, and a build needs vite and its prebuilt esbuild. better-sqlite3
# 13 ships prebuilt .node files in its tarball: they are removed here and the addon is compiled
# from the bundled SQLite source. Bump `version`, `commit` and both hashes together.
{ lib, buildNpmPackage, fetchFromGitHub, makeWrapper, nodejs_24 }:
let
  version = "0.7.7";
  # The commit of the tag v${version}.
  commit = "f3d8bac42e1f874aa0f784e412909fab27dded1b";
in
(buildNpmPackage.override { nodejs = nodejs_24; }) {
  pname = "openrig";
  inherit version;

  src = fetchFromGitHub {
    owner = "mvschwarz";
    repo = "openrig";
    rev = commit;
    hash = "sha256-Hzog+WHFjkLOqE9/DaMsJRjhdjtUl/+yLSulp2PVrvw=";
  };
  npmDepsHash = "sha256-fg0TrtDGQggrHo2RPMMQ97tmzIMlwxFWNwVA3OybL4g=";

  nativeBuildInputs = [ makeWrapper ];

  # No install script runs: esbuild (UI build only) downloads or checks a binary, and the CLI's
  # postinstall opens a database before the addon is built.
  npmRebuildFlags = [ "--ignore-scripts" ];

  # The context packs ship scripts: `rig context get` serves them as they are, so no shebang changes.
  dontPatchShebangs = true;

  buildPhase = ''
    runHook preBuild
    export NODE_OPTIONS=--max-old-space-size=2048
    tsc=$PWD/node_modules/.bin/tsc

    # The addon: the prebuilt files go away, so the loader finds build/Release.
    (
      cd node_modules/better-sqlite3
      rm -rf prebuilds
      node ${nodejs_24}/lib/node_modules/npm/node_modules/node-gyp/bin/node-gyp.js rebuild \
        --release --force_build=1 --nodedir=$npm_config_nodedir --jobs=$NIX_BUILD_CORES
    )

    # The daemon first: the TUI and the CLI read its types.
    (cd packages/daemon && $tsc && node scripts/copy-workflow-specs.mjs)
    (cd packages/tui && $tsc && node ../../scripts/prepare-workspace-build.mjs tui)
    (cd packages/cli && $tsc && node ../../scripts/prepare-workspace-build.mjs cli)

    # The build stamp of scripts/build-package.sh. SOURCE_DATE_EPOCH keeps the time fixed.
    for dist in packages/daemon/dist packages/cli/dist; do
      cat > $dist/build-info.js <<EOF
    export const BUILD_INFO = {
      semver: "${version}",
      commit: "${commit}",
      dirty: false,
      builtAt: "$(date -u -d @$SOURCE_DATE_EPOCH +%Y-%m-%dT%H:%M:%SZ)",
    };
    export function stampFields(info = BUILD_INFO) {
      if (!info.commit) return {};
      return { semver: info.semver, commit: info.commit, dirty: info.dirty, builtAt: info.builtAt };
    }
    EOF
    done

    node scripts/generate-context-packs.mjs --version=${version}

    # The assembly of build-package.sh, step 6, then its rewrite of the daemon imports.
    cli=packages/cli
    mkdir -p $cli/daemon/docs $cli/tui
    cp -r packages/daemon/dist packages/daemon/assets packages/daemon/specs \
      packages/daemon/context-packs packages/daemon/policies $cli/daemon/
    cp -r docs/reference $cli/daemon/docs/reference
    cp -r packages/tui/dist $cli/tui/dist
    node scripts/rewrite-daemon-imports.mjs
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    lib=$out/lib/node_modules
    cli=$lib/@openrig/cli
    mkdir -p $out/bin $lib

    # Only what the CLI, the daemon and the TUI need at run time. The lock tells which package
    # asks for which; the UI and the dev tools are not in that set. Same lookup as node: a
    # package's own node_modules first, then each parent's.
    cp -r node_modules/. $lib
    chmod -R u+w $lib
    node - <<'EOF'
    const fs = require("fs");
    const lock = JSON.parse(fs.readFileSync("package-lock.json", "utf8")).packages;
    const keep = new Set();
    const find = (from, name) => {
      for (let base = from; ; ) {
        const key = (base ? base + "/" : "") + "node_modules/" + name;
        if (lock[key]) return key;
        if (!base) return null;
        const up = base.replace(/\/?node_modules\/(@[^/]+\/)?[^/]+$/, "");
        base = up === base ? "" : up;
      }
    };
    const visit = (key) => {
      const pkg = lock[key];
      for (const field of ["dependencies", "optionalDependencies", "peerDependencies"]) {
        for (const name of Object.keys(pkg[field] || {})) {
          const found = find(key, name);
          if (found && !keep.has(found)) { keep.add(found); visit(found); }
        }
      }
    };
    for (const root of ["packages/cli", "packages/daemon", "packages/tui"]) visit(root);
    for (const key of Object.keys(lock)) {
      if (key.startsWith("node_modules/") && !keep.has(key))
        fs.rmSync(process.env.out + "/lib/" + key, { recursive: true, force: true });
    }
    EOF
    rm -rf $lib/.bin $lib/.package-lock.json $lib/@openrig

    # The addon alone: no SQLite source, no object files.
    sqlite=$lib/better-sqlite3
    find $sqlite -mindepth 1 -maxdepth 1 ! -name lib ! -name package.json ! -name LICENSE -exec rm -rf {} +
    install -D node_modules/better-sqlite3/build/Release/better_sqlite3.node \
      $sqlite/build/Release/better_sqlite3.node
    strip $sqlite/build/Release/better_sqlite3.node
    mkdir -p $cli
    cp -r packages/cli/dist packages/cli/daemon packages/cli/tui packages/cli/package.json \
      packages/cli/LICENSE $cli/

    makeWrapper ${lib.getExe nodejs_24} $out/bin/rig --add-flags $cli/dist/bin-wrapper.js
    makeWrapper ${lib.getExe nodejs_24} $out/bin/openrig-tui --add-flags $cli/tui/dist/main.js
    runHook postInstall
  '';

  passthru = {
    nodejs = nodejs_24;
    # The daemon's folder. The unit runs `node <daemon>/dist/index.js` in the foreground.
    daemon = "lib/node_modules/@openrig/cli/daemon";
  };

  meta = {
    description = "OpenRig, a control plane for teams of AI coding agents";
    homepage = "https://github.com/mvschwarz/openrig";
    license = lib.licenses.asl20;
    platforms = [ "x86_64-linux" ];
    mainProgram = "rig";
  };
}
