# The site, prerendered: Gleam and Lustre (src/) run once on the builder and write the three pages
# (A at index.html, B at index/, C at paths/, Hermes's configuration at hermes/, the two hosts at hosts/); the output is those pages, static/, the 无
# drawing and the link preview og.png (og/og.svg, drawn by resvg), nothing else. The facts come from ../mockups/data.nix, written as Gleam by data.nix. allowedReferences = [ ] fails the build if the
# output names any store path, so gleam, node and the hex packages never reach the VPS closure.
{ lib, stdenvNoCC, fetchurl, gleam, nodejs, resvg, inter, jetbrains-mono, measurementId ? "", hermes ? null }:
let
  manifest = lib.importTOML ./manifest.toml;
  dataGleam = import ./data.nix { inherit lib measurementId hermes; data = import ../mockups/data.nix; };
  # Every hex package manifest.toml locks, at its checksum, so the build runs offline.
  hex = map
    (p: p // {
      tarball = fetchurl {
        url = "https://repo.hex.pm/tarballs/${p.name}-${p.version}.tar";
        sha256 = lib.toLower p.outer_checksum;
      };
    })
    manifest.packages;
  # The link preview's display face; nixpkgs has no Fjalla One. Builder only, like the other two.
  fjalla = fetchurl {
    url = "https://fonts.gstatic.com/s/fjallaone/v16/Yq6R-LCAWCX3-6Ky7FAFnOY.ttf";
    hash = "sha256-7IhiZLRprAKZu/vwW2+DEMRGsTMbsmP3vC10eYdGkq0=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "piabrota-site";
  inherit (lib.importTOML ./gleam.toml) version;
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [ ./gleam.toml ./manifest.toml ./src ./test ./static ./og ];
  };
  nativeBuildInputs = [ gleam nodejs resvg ];
  inherit dataGleam;
  passAsFile = [ "dataGleam" ];

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
    cp $dataGleamPath src/piabrota_site/data.gleam
    gleam format src/piabrota_site/data.gleam
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    gleam format --check src test
    mkdir -p dist/index dist/paths dist/pt-BR dist/zh-CN dist/ja-JP dist/hermes dist/hosts
    gleam run -m piabrota_site/render/fabric --no-print-progress > dist/index.html
    gleam run -m piabrota_site/render/index --no-print-progress > dist/index/index.html
    gleam run -m piabrota_site/render/paths --no-print-progress > dist/paths/index.html
    gleam run -m piabrota_site/render/fabric_pt_br --no-print-progress > dist/pt-BR/index.html
    gleam run -m piabrota_site/render/fabric_zh_cn --no-print-progress > dist/zh-CN/index.html
    gleam run -m piabrota_site/render/fabric_ja_jp --no-print-progress > dist/ja-JP/index.html
    gleam run -m piabrota_site/render/hermes --no-print-progress > dist/hermes/index.html
    gleam run -m piabrota_site/render/hosts --no-print-progress > dist/hosts/index.html
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
    cp -R dist $out
    cp -R static/. $out/
    cp ${../docs/drawings/mu.svg} $out/mu.svg
    cp ${../docs/img/two-hosts.png} $out/hosts/two-hosts.png
    # og:image of every page: 1200x627, the size LinkedIn and X ask for (page.gleam's og_image).
    resvg --skip-system-fonts --use-font-file ${fjalla} \
      --use-font-file ${inter}/share/fonts/truetype/Inter.ttc \
      --use-fonts-dir ${jetbrains-mono}/share/fonts og/og.svg $out/og.png
    runHook postInstall
  '';

  allowedReferences = [ ];
}
