# `piabrota`, every script of this repository as one Scala Native binary (scala/README.md). The
# dependencies come from scala/deps.lock.json (`just scala-lock`), each a fixed-output fetch laid
# out as a Coursier cache, so the build runs offline in the sandbox. The binary needs only glibc:
# no JVM reaches a box. The tests (`*.test.scala`) run in checkPhase against the built binary.
#
# A consumer wraps one command with its own PATH: `scripts.command { name = "specs"; }` gives
# `bin/specs` that runs `piabrota specs "$@"`.
{ lib
, stdenv
, callPackage
, clang
, which
, git
, util-linux
, fetchurl
, linkFarm
, makeWrapper
, runCommand
}:
let
  toolchain = callPackage ./toolchain.nix { };
  inherit (toolchain) jdk;

  central = "https://repo1.maven.org/maven2";
  # The same files; the first answers are kept by hash, so either serves the build.
  mirror = "https://maven-central.storage-download.googleapis.com/maven2";

  deps = linkFarm "piabrota-scala-deps" (map
    (d: {
      name = "https/repo1.maven.org/maven2/${d.path}";
      path = fetchurl {
        urls = [ "${central}/${d.path}" "${mirror}/${d.path}" ];
        inherit (d) hash;
        name = lib.strings.sanitizeDerivationName (baseNameOf d.path);
      };
    })
    (lib.importJSON ./deps.lock.json));

  # `scala-cli <subcommand>` with the options of an offline build.
  scalaCli = sub: "scala-cli --power ${sub} --offline --server=false --jvm system";

  piabrota = stdenv.mkDerivation {
    pname = "piabrota";
    version = "1";

    src = lib.fileset.toSource {
      root = ./.;
      fileset = lib.fileset.fileFilter (f: f.hasExt "scala") ./.;
    };

    nativeBuildInputs = [ toolchain.scalaCli clang jdk which ];

    # Coursier writes lock files next to what it reads, so it gets a copy it can write.
    configurePhase = ''
      runHook preConfigure
      export HOME=$TMPDIR JAVA_HOME=${jdk.home} COURSIER_CACHE=$TMPDIR/coursier
      cp -rL ${deps} $COURSIER_CACHE
      chmod -R u+w $COURSIER_CACHE
      runHook postConfigure
    '';

    buildPhase = ''
      runHook preBuild
      ${scalaCli "package"} . -o piabrota
      runHook postBuild
    '';

    doCheck = true;
    # Programs the tests use for real (a local git repository, setsid); stand-ins come from TestKit.fakes.
    nativeCheckInputs = [ git util-linux ];
    checkPhase = ''
      runHook preCheck
      PIABROTA=$PWD/piabrota ${scalaCli "test"} .
      runHook postCheck
    '';

    installPhase = ''
      runHook preInstall
      install -Dm0755 piabrota $out/bin/piabrota
      runHook postInstall
    '';

    passthru = {
      inherit deps toolchain;
      # One subcommand as a program of its own, with `runtimeInputs` on its PATH and `env` set.
      # `exclusivePath` replaces the PATH instead of prefixing it, for the rig toolkits.
      command =
        { name
        , subcommand ? name
        , runtimeInputs ? [ ]
        , env ? { }
        , exclusivePath ? false
        }:
        runCommand name { nativeBuildInputs = [ makeWrapper ]; meta.mainProgram = name; } ''
          makeWrapper ${piabrota}/bin/piabrota $out/bin/${name} \
            --add-flags ${lib.escapeShellArg subcommand} \
            ${if exclusivePath
              then "--set PATH ${lib.makeBinPath runtimeInputs}"
              else lib.optionalString (runtimeInputs != [ ]) "--prefix PATH : ${lib.makeBinPath runtimeInputs}"} \
            ${lib.concatStrings (lib.mapAttrsToList (k: v: "--set ${k} ${lib.escapeShellArg v} ") env)}
        '';
    };

    meta = {
      description = "The scripts of piabrota/nix-os, in Scala 3, as one native binary";
      license = lib.licenses.mpl20;
      mainProgram = "piabrota";
      platforms = lib.platforms.linux;
    };
  };
in
piabrota
