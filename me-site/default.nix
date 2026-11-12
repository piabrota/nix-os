# The website of h0ffmann/h0ffmann (the owner's profile), built on the builder at the commit below,
# as that repository's `just _site` builds it for GitHub Pages: its content generator
# (site/content, Gleam on node) writes site/src/h0ffmann_site/content.gleam from the README, me/
# and site/data/, then the site (Gleam and Lustre on node) is bundled with esbuild and prerendered.
# Nothing here is a copy of its code. The generator asks git for the revision and for the commits
# of README.md; the source has no .git, so a stub answers from the numbers below.
# allowedReferences = [ ] fails the build if the output names a store path.
{ lib
, stdenvNoCC
, fetchFromGitHub
, fetchurl
, writeShellScriptBin
, gleam
, erlang
, nodejs
, esbuild
, sourceOverride ? null # a local checkout, to build without fetching
}:
let
  # Move rev, hash and the README numbers together.
  rev = "2bb30b6bd8add017ec240d6965047aa28d777810";
  # `git log --follow --format=%as -- README.md` at rev: how many lines, and the last one.
  readmeCommits = 311;
  readmeFirst = "2025-06-25";
  profile =
    if sourceOverride != null then sourceOverride else
    fetchFromGitHub {
      owner = "h0ffmann";
      repo = "h0ffmann";
      inherit rev;
      hash = "sha256-1j5VXoOXuPRs7CAHlIUZzzvGjUMsRtmv1viu1QVTJao=";
    };
  git = writeShellScriptBin "git" ''
    case "$*" in
      "rev-parse --short HEAD") echo ${builtins.substring 0 7 rev} ;;
      "log --follow --format=%as -- ../../README.md")
        for _ in $(seq ${toString readmeCommits}); do echo ${readmeFirst}; done ;;
      *) echo "me-site: git $* is not available in the build" >&2; exit 1 ;;
    esac
  '';
  # Every hex package that <dir>/manifest.toml locks, at its checksum, so the build runs offline.
  hex = dir: map
    (p: p // {
      tarball = fetchurl {
        url = "https://repo.hex.pm/tarballs/${p.name}-${p.version}.tar";
        sha256 = lib.toLower p.outer_checksum;
      };
    })
    (lib.importTOML "${profile}/${dir}/manifest.toml").packages;
  # What gleam deps download would write in <dir>/build/packages.
  unpack = dir: ''
    mkdir -p ${dir}/build/packages
    echo '[packages]' > ${dir}/build/packages/packages.toml
    ${lib.concatMapStrings (p: ''
      mkdir -p ${dir}/build/packages/${p.name}
      tar -xOf ${p.tarball} contents.tar.gz | tar -xzf - -C ${dir}/build/packages/${p.name}
      echo '${p.name} = "${p.version}"' >> ${dir}/build/packages/packages.toml
    '') (hex dir)}
  '';
in
stdenvNoCC.mkDerivation {
  pname = "h0ffmann-site";
  version = "0-unstable-${builtins.substring 0 7 rev}";
  src = profile;
  nativeBuildInputs = [ gleam erlang nodejs esbuild git ];

  configurePhase = ''
    runHook preConfigure
    export HOME=$TMPDIR LANG=C.UTF-8
    chmod -R u+w .
    ${unpack "site/content"}
    ${unpack "site"}
    runHook postConfigure
  '';

  # The steps of h0ffmann/h0ffmann's `just _site`, without its check of the workflow files.
  buildPhase = ''
    runHook preBuild
    (cd site/content && gleam test && gleam run --no-print-progress)
    grep -q 'pub const revision = "${builtins.substring 0 7 rev}"' site/src/h0ffmann_site/content.gleam
    cd site
    gleam format src/h0ffmann_site/content.gleam
    gleam test
    mkdir dist
    gleam build
    esbuild entry.mjs --bundle --minify --format=esm --outfile=dist/app.js --log-level=warning
    gleam run -m h0ffmann_site/prerender --no-print-progress > dist/index.html
    cp -R static/. dist/
    cp -R ../media dist/
    grep -q 'https://me.piabrota.art/og.png' dist/index.html
    cd ..
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    cp -R site/dist $out
    runHook postInstall
  '';

  dontFixup = true;
  allowedReferences = [ ];
}
