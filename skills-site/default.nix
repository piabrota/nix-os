# The skills website, prerendered: the Gleam program in src/ (moved here from piabrota/skills, www/)
# runs once on the builder and writes the pages for /skills; the output is those pages and waza.svg,
# nothing else. allowedReferences = [ ] fails the build if the output names any store path, so gleam,
# erlang and the hex packages never reach the VPS closure.
{ lib, stdenvNoCC, fetchFromGitHub, fetchurl, gleam, beamPackages }:
let
  manifest = lib.importTOML ./manifest.toml;
  # The skills, the docs and the agents the program reads. A new commit of piabrota/skills shows on
  # the site only after a PR here changes rev and hash.
  skills = fetchFromGitHub {
    owner = "piabrota";
    repo = "skills";
    rev = "e19bd4db29b699181dffb3886abc9843705e639f";
    hash = "sha256-w9HKrciBi3PRJhoGYRBw04/3+r9CVeUFxXOaci1LuD8=";
  };
  # Every hex package manifest.toml locks, at its checksum, so the build runs offline.
  hex = map
    (p: p // {
      tarball = fetchurl {
        url = "https://repo.hex.pm/tarballs/${p.name}-${p.version}.tar";
        sha256 = lib.toLower p.outer_checksum;
      };
    })
    manifest.packages;
in
stdenvNoCC.mkDerivation {
  pname = "piabrota-skills-site";
  inherit (lib.importTOML ./gleam.toml) version;
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [ ./gleam.toml ./manifest.toml ./src ];
  };
  nativeBuildInputs = [ gleam beamPackages.erlang ];

  # What gleam deps download would write: each package in build/packages, and the list of them.
  configurePhase = ''
    runHook preConfigure
    export HOME=$TMPDIR
    mkdir -p build/packages
    echo '[packages]' > build/packages/packages.toml
    ${lib.concatMapStrings (p: ''
      mkdir -p build/packages/${p.name}
      tar -xOf ${p.tarball} contents.tar.gz | tar -xzf - -C build/packages/${p.name}
      echo '${p.name} = "${p.version}"' >> build/packages/packages.toml
    '') hex}
    runHook postConfigure
  '';

  # The program reads ../skills, ../docs and ../agents and writes ../docs/site, so it runs in www/
  # of a tree that has the layout of piabrota/skills.
  buildPhase = ''
    runHook preBuild
    export HOME=$TMPDIR
    mkdir -p $TMPDIR/tree/www
    cp -R --no-preserve=mode ${skills}/skills ${skills}/docs ${skills}/agents $TMPDIR/tree/
    cp -R --no-preserve=mode . $TMPDIR/tree/www
    cp --no-preserve=mode ${skills}/www/tags.txt $TMPDIR/tree/www/
    (cd $TMPDIR/tree/www && gleam run --no-print-progress)
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    cp -R $TMPDIR/tree/docs/site $out
    test -f $out/index.html
    test -f $out/waza.svg
    runHook postInstall
  '';

  allowedReferences = [ ];
}
