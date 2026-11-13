# The website of h0ffmann/closed-source, built on the builder at the commit below, as that
# repository's `just site-build` builds it for GitHub Pages: its content generator (tools/fabric,
# Gleam on Erlang) writes site/src/closed_source_site/content.gleam from the paper, then the site
# (Gleam and Lustre on node) is bundled with esbuild and prerendered. Nothing here is a copy of its
# code. The three PDFs are built too, as its `just build` does (pandoc with pandoc-crossref and
# citeproc, XeLaTeX twice, with the TeX set of picasso's paper lab), from the same commit, so the
# page and the paper never disagree. The title-page logo is fetched by the hashes in the
# paper's metadata.md and converted with rsvg-convert, as `tools/fabric logos` does; it stays a
# trademark of its project and is not a file of this repository. The generator asks Zenodo for
# the version DOIs; the sandbox has no network, so it reads zenodo.json instead, that reply cut to
# the fields it reads (fetched 2026-11-11, still current on 2026-11-12 at 23:59; fetch it again when
# closed-source makes a release).
# allowedReferences = [ ] fails the build if the output names a store path, so gleam, erlang and
# node never reach the closure.
{ lib
, stdenvNoCC
, fetchFromGitHub
, fetchurl
, writeShellScriptBin
, gleam
, erlang
, nodejs
, esbuild
, pandoc
, haskellPackages
, texliveMedium
, librsvg
, poppler-utils
, sourceOverride ? null # a local checkout, to build without fetching
}:
let
  # Move rev, commits and hash together; the logos only when metadata.md changes them.
  rev = "03dee6bc64e7d30cd48a3d794801b84949df1cad";
  # The number of commits up to rev (`git rev-list --count`), which the page shows; the source
  # has no .git.
  commits = 269;
  closedSource =
    if sourceOverride != null then sourceOverride else
    fetchFromGitHub {
      owner = "h0ffmann";
      repo = "closed-source";
      inherit rev;
      hash = "sha256-CyVoxdXwFykN8H4EpWM13feX8vBjK6pvzWXCiDr0mUw=";
    };
  # The `logos:` of papers/closed-source/metadata.md: file, svg and sha256.
  logos = {
    marola = fetchurl {
      url = "https://raw.githubusercontent.com/marola-dev/marola/d0d576ea014335acbc190a09ce9fcbe0f89a391d/docs/assets/logo.svg";
      sha256 = "71567f8c69a5c5e18b8b712a280cae1dac402e6a2e7ceb331408a4e713159cf9";
    };
  };
  # picasso's labs/paper texFor, and babel-portuges for the pt-BR text (`babel: brazilian`).
  tex = texliveMedium.withPackages (ps: with ps; [
    xetex
    fontspec
    unicode-math
    lm
    lm-math
    babel-english
    babel-portuges
    csquotes
    enumitem
    etoolbox
    fancyhdr
    footnotehyper
    titling
    xurl
    booktabs
    microtype
    xcolor
    upquote
    bookmark
    parskip
  ]);
  # The content generator asks git for the revision and the commit count, and nothing else.
  git = writeShellScriptBin "git" ''
    case "$*" in
      "rev-parse --short HEAD") echo ${builtins.substring 0 7 rev} ;;
      "rev-list --count HEAD") echo ${toString commits} ;;
      *) echo "closed-site: git $* is not available in the build" >&2; exit 1 ;;
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
    (lib.importTOML "${closedSource}/${dir}/manifest.toml").packages;
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
  pname = "closed-source-site";
  version = "0-unstable-${builtins.substring 0 7 rev}";
  src = closedSource;
  nativeBuildInputs = [ gleam erlang nodejs esbuild pandoc haskellPackages.pandoc-crossref tex librsvg poppler-utils git ];

  postPatch = ''
    substituteInPlace tools/src/fabric/content.gleam --replace-fail \
      '    "" -> Error("no Zenodo concept DOI")' \
      '    _ if True -> result.try(sys.read("${./zenodo.json}"), json.decode)
        "" -> Error("no Zenodo concept DOI")'
  '';

  configurePhase = ''
    runHook preConfigure
    export HOME=$TMPDIR LANG=C.UTF-8
    chmod -R u+w .
    ${unpack "tools"}
    ${unpack "site"}
    mkdir -p pdf build/tex build/logos
    ${lib.concatStrings (lib.mapAttrsToList (n: svg: "rsvg-convert -f pdf -o build/logos/${n}.pdf ${svg}\n") logos)}
    runHook postConfigure
  '';

  # The steps of closed-source's `just build`, `just site-build` and site/justfile.
  buildPhase = ''
    runHook preBuild
    export TEXMFVAR=$TMPDIR/texmf-var SOURCE_DATE_EPOCH=0
    printf '%s+%s' ${builtins.substring 0 7 rev} ${toString commits} > build/.current-revision
    paper=papers/closed-source
    for dir in prose prose-ste prose-pt-BR; do
      name=closed-source''${dir#prose}
      pandoc --from markdown+fancy_lists+raw_tex -F pandoc-crossref --citeproc \
        --metadata link-citations=true --number-sections --top-level-division=section \
        --fail-if-warnings -s --template format/tex/template.tex -t latex \
        --metadata-file format/crossref.yaml --bibliography $paper/refs.bib \
        -o build/tex/$name.tex $paper/metadata.md $paper/$dir/*.md
      (cd build && for _ in 1 2; do
        xelatex -interaction=nonstopmode -halt-on-error tex/$name.tex > /dev/null \
          || { tail -n 30 $name.log >&2; exit 1; }
      done)
      cp build/$name.pdf pdf/$name.pdf
    done
    patchShebangs tools/fabric
    tools/fabric content --self-test
    tools/fabric content
    grep -q '10.5281/zenodo.23679470' site/src/closed_source_site/content.gleam
    grep -q 'pub const revision = "${builtins.substring 0 7 rev}"' site/src/closed_source_site/content.gleam
    cd site
    gleam test
    mkdir dist
    gleam build
    esbuild entry.mjs --bundle --minify --format=esm --outfile=dist/app.js --log-level=warning
    gleam run -m closed_source_site/prerender --no-print-progress > dist/index.html
    cp -R static/. dist/
    cp ../pdf/*.pdf dist/
    cp dist/closed-source.pdf dist/paper.pdf
    grep -q '<main' dist/index.html
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
