# The front page and the lineage page of the WW3 GPU Lab (h0ffmann/ww3-gpu), prerendered: the Gleam
# programs here (moved from ww3-gpu's site/) run once on the builder, on node, and write the pages.
# content/ reads the facts from ww3-gpu at the commit below (docs/ADRs.md, docs/WFIPs/, notes/,
# kokkos/ports.tsv, .zenodo.json, CITATION.cff, RELEASES.md, site/data/*.tsv) and writes the content
# module the page is built from; nothing in src/ is typed by hand. A new commit of ww3-gpu shows on
# the site only after a PR here changes rev and hash (`just ww3-pin`). allowedReferences = [ ] fails
# the build if the output names any store path, so gleam and node never reach the closure.
{ lib, stdenvNoCC, fetchFromGitHub, fetchurl, gleam, nodejs }:
let
  rev = "2ebd854ad503329c72784a9cba3c98743dd2c1d6";
  ww3gpu = fetchFromGitHub {
    owner = "h0ffmann";
    repo = "ww3-gpu";
    inherit rev;
    hash = "sha256-KTdmNOfVBfJQ3C0lkMS1HqbAgm36PEdLlpUeuNr1uEI=";
  };
  # Every hex package either manifest.toml locks, at its checksum, so the build runs offline.
  hex = dir: map
    (p: p // {
      tarball = fetchurl {
        url = "https://repo.hex.pm/tarballs/${p.name}-${p.version}.tar";
        sha256 = lib.toLower p.outer_checksum;
      };
    })
    (lib.importTOML (dir + "/manifest.toml")).packages;
  # What gleam deps download would write in <dir>/build/packages.
  unpack = dir: pkgs: ''
    mkdir -p ${dir}/build/packages
    echo '[packages]' > ${dir}/build/packages/packages.toml
    ${lib.concatMapStrings (p: ''
      mkdir -p ${dir}/build/packages/${p.name}
      tar -xOf ${p.tarball} contents.tar.gz | tar -xzf - -C ${dir}/build/packages/${p.name}
      echo '${p.name} = "${p.version}"' >> ${dir}/build/packages/packages.toml
    '') pkgs}
  '';
in
stdenvNoCC.mkDerivation {
  pname = "ww3-gpu-site";
  version = "0-unstable-${builtins.substring 0 7 rev}";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [ ./gleam.toml ./manifest.toml ./src ./test ./static ./content ./data ];
  };
  nativeBuildInputs = [ gleam nodejs ];

  # The programs read ../../ from site/content, so they run in site/ of a copy of ww3-gpu whose own
  # site code is replaced by this one; ww3-gpu's site/data/*.tsv stay, the translations are ours.
  configurePhase = ''
    runHook preConfigure
    export HOME=$TMPDIR
    tree=$TMPDIR/tree
    cp -R --no-preserve=mode ${ww3gpu} $tree
    rm -rf $tree/site/src $tree/site/test $tree/site/static $tree/site/content $tree/site/data/translations
    cp -R --no-preserve=mode . $tree/site/
    ${unpack "$tree/site" (hex ./.)}
    ${unpack "$tree/site/content" (hex ./content)}
    runHook postConfigure
  '';

  # scripts/build_site.sh --check of ww3-gpu, without the formatter checks (CI's job, not the deploy's).
  buildPhase = ''
    runHook preBuild
    export WW3_GPU_REV=${builtins.substring 0 7 rev}
    out_dir=$TMPDIR/out
    mkdir -p $out_dir/pt-BR $out_dir/lineage $out_dir/pt-BR/lineage
    (cd $tree/site/content && gleam test && gleam run --no-print-progress)
    cd $tree/site
    gleam format src/ww3_gpu_site/content.gleam
    gleam test
    gleam run -m ww3_gpu_site/prerender --no-print-progress > $out_dir/index.html
    gleam run -m ww3_gpu_site/prerender_pt_br --no-print-progress > $out_dir/pt-BR/index.html
    gleam run -m ww3_gpu_site/prerender_lineage --no-print-progress > $out_dir/lineage/index.html
    gleam run -m ww3_gpu_site/prerender_lineage_pt_br --no-print-progress > $out_dir/pt-BR/lineage/index.html
    cp -R static/. $out_dir/
    for page in index.html pt-BR/index.html; do
      for id in about decisions designs chaceon brain cite related; do
        grep -q "id=\"$id\"" "$out_dir/$page" || { echo "ww3-site: no #$id in $page" >&2; exit 1; }
      done
    done
    for page in lineage/index.html pt-BR/lineage/index.html; do
      grep -q 'id="lineage"' "$out_dir/$page" || { echo "ww3-site: no #lineage in $page" >&2; exit 1; }
    done
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    cp -R $TMPDIR/out $out
    runHook postInstall
  '';

  allowedReferences = [ ];
}
