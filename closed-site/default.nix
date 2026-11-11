# The website of h0ffmann/closed-source, built on the builder at the commit below, as that
# repository's `just site-build` builds it for GitHub Pages: its content generator (tools/fabric,
# Gleam on Erlang) writes site/src/closed_source_site/content.gleam from the paper, then the site
# (Gleam and Lustre on node) is bundled with esbuild and prerendered. Nothing here is a copy of its
# code. The three PDFs are the release assets of the tag at that commit, not built again: the
# paper's build needs XeLaTeX and the logos fetched from the network. The generator asks Zenodo for
# the version DOIs; the sandbox has no network, so it reads zenodo.json instead, that reply cut to
# the fields it reads (fetched 2026-11-11; fetch it again when the pin moves past a release).
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
, poppler-utils
, src ? null
}:
let
  # Move rev, commits, hash and the release with its three PDF hashes together.
  rev = "6b3aae557f69ab89ec747364311978928dd0ca71";
  # The number of commits up to rev (`git rev-list --count`), which the page shows; the source
  # has no .git.
  commits = 219;
  release = "v0.3.4";
  closedSource =
    if src != null then src else
    fetchFromGitHub {
      owner = "h0ffmann";
      repo = "closed-source";
      inherit rev;
      hash = "sha256-j+HPOh7bVCcfMhPf2WdAJ4998qx3P9TmtJVmlCanROs=";
    };
  pdf = name: hash: fetchurl {
    url = "https://github.com/h0ffmann/closed-source/releases/download/${release}/${name}.pdf";
    inherit hash;
  };
  pdfs = {
    closed-source = pdf "closed-source" "sha256-eYpgC5U4GH+Rn7OCZspXlenTxOMG3uWweBvEj2TWIw8=";
    closed-source-ste = pdf "closed-source-ste" "sha256-tqPi/3DI0TLgKv3T5tGzIkZaLixuQ/u2tx8OJTGLiQg=";
    closed-source-pt-BR = pdf "closed-source-pt-BR" "sha256-JWDVlKjxxpm5HPbjnKb5G2G5+fc/ivImdObfR7HMOGA=";
  };
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
  nativeBuildInputs = [ gleam erlang nodejs esbuild pandoc poppler-utils git ];

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
    mkdir -p pdf
    ${lib.concatStrings (lib.mapAttrsToList (n: p: "cp ${p} pdf/${n}.pdf\n") pdfs)}
    runHook postConfigure
  '';

  # The steps of closed-source's `just site-build` and site/justfile, without the paper's build.
  buildPhase = ''
    runHook preBuild
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
