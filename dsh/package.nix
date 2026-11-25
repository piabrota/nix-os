# DeepSeek Harness (dsh) 0.2.2-rc.5 from its npm tarball. The package is the
# same one numtide/llm-agents.nix builds (MIT), pinned by the tarball hash and
# the npm dependency hash of dsh/package-lock.json. Nixpkgs' own
# deepseek-harness is 0.2.1-alpha.3, whose headless profile lacks the
# --permission-mode/--approval-policy/--add-dir flags the runner uses.
#
# The npm tarball ships no lockfile; dsh/package-lock.json was generated from
# the package without devDependencies (the llm-agents.nix updater does the same),
# so the manifest drops them before buildNpmPackage reads it.
{ lib
, bashInteractive
, buildNpmPackage
, fetchurl
, jq
, makeWrapper
, nodejs_24
, runCommand
}:
let
  version = "0.2.2-rc.5";
  sourceHash = "sha256-Z9paPEWPRs0njg7satDjpE6Z/RMIfG8RobNiJokApSw=";
  npmDepsHash = "sha256-Z2lAvLWgoZKRRM/uBEUfPI2BwEP3wIBB3yhzPOhVVTY=";
  srcWithLock = runCommand "dsh-source" { nativeBuildInputs = [ jq ]; } ''
    mkdir -p $out
    tar -xzf ${
      fetchurl {
        url = "https://registry.npmjs.org/@deepseek-ai/dsh/-/dsh-${version}.tgz";
        hash = sourceHash;
      }
    } -C $out --strip-components=1
    jq 'del(.devDependencies)' $out/package.json > $out/package.json.tmp
    mv $out/package.json.tmp $out/package.json
    cp ${./package-lock.json} $out/package-lock.json
  '';
in
(buildNpmPackage.override { nodejs = nodejs_24; }) {
  pname = "dsh";
  inherit version;
  src = srcWithLock;

  npmDepsFetcherVersion = 2;
  inherit npmDepsHash;

  dontNpmBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    # /bin/bash does not exist on NixOS.
    substituteInPlace \
      $out/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-terminal-bash/lib/index.js \
      --replace-fail '"/bin/bash"' '"${lib.getExe bashInteractive}"'

    # The addon decodes V8 machine code, which nixpkgs' Node breaks.
    # --expose-internals makes plain require() work instead.
    for f in index.js worker/profile-resolution-bootstrap.js; do
      substituteInPlace \
        $out/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-app-boot/lib/$f \
        --replace-fail 'createRequire(import.meta.url)("node-addon-require-builtin")' \
        '{ requireBuiltin: createRequire(import.meta.url) }'
    done

    # The inspector worker does not inherit the wrapper's --expose-internals.
    substituteInPlace \
      $out/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-experimental-inspector/lib/index.js \
      --replace-fail 'execArgv: []' 'execArgv: ["--expose-internals"]'

    rm $out/bin/dsh
    makeWrapper ${lib.getExe nodejs_24} $out/bin/dsh \
      --argv0 dsh \
      --add-flags "--expose-internals" \
      --add-flags "$out/lib/node_modules/@deepseek-ai/dsh/lib/bin.js"
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    export HOME=$TMPDIR
    $out/bin/dsh --version
  '';

  meta = {
    description = "DeepSeek Harness, a plugin-composed coding agent";
    homepage = "https://github.com/deepseek-ai/deepseek-harness";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [
      binaryBytecode
      fromSource
    ];
    platforms = lib.platforms.linux;
    mainProgram = "dsh";
  };
}
