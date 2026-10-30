# The site, prerendered: Gleam and Lustre (src/) run once on the builder and write index.html; the
# output is that page and static/, nothing else. allowedReferences = [ ] fails the build if the
# output names any store path, so gleam, node and the hex packages never reach the VPS closure.
{ lib, stdenvNoCC, fetchurl, gleam, nodejs }:
let
  manifest = lib.importTOML ./manifest.toml;
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
  pname = "piabrota-site";
  inherit (lib.importTOML ./gleam.toml) version;
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [ ./gleam.toml ./manifest.toml ./src ./test ./static ];
  };
  nativeBuildInputs = [ gleam nodejs ];

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

  buildPhase = ''
    runHook preBuild
    gleam format --check src test
    gleam run -m piabrota_site/prerender --no-print-progress > index.html
    runHook postBuild
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    gleam test
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp index.html $out/
    cp -R static/. $out/
    runHook postInstall
  '';

  allowedReferences = [ ];
}
