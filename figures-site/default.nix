# The figures as interactive pages, for /figures: archify (pinned below) turns each source in
# docs/archify/ (English) and docs/archify/pt/ (pt-BR) into one self-contained HTML page, on the
# builder. No HTML is committed. The output is those pages and an index, nothing else:
# allowedReferences = [ ] fails the build if the output names any store path, so node, jq and
# archify never reach the VPS closure.
{ lib, stdenvNoCC, fetchFromGitHub, nodejs, jq }:
let
  # The commit of the submodule vendor/archify (git ls-files -s vendor/archify). Move both together:
  # docs/SITE.md, "The figures".
  archify = fetchFromGitHub {
    owner = "tt-a1i";
    repo = "archify";
    rev = "208acba8d412335185b2056fedf54b3405df43fb";
    hash = "sha256-pejw78BgKDnttOAGcLvVtWa50azpCjTfESnmdYIjCoI=";
  };
  repo = "https://github.com/piabrota/nix-os/blob/main/docs/archify";
in
stdenvNoCC.mkDerivation {
  pname = "piabrota-figures-site";
  version = "1";
  src = lib.fileset.toSource {
    root = ../docs/archify;
    fileset = lib.fileset.unions [
      ../docs/archify/piabrota.css
      (lib.fileset.fileFilter (file: file.hasExt "json") ../docs/archify)
    ];
  };
  nativeBuildInputs = [ nodejs jq ];

  buildPhase = ''
    runHook preBuild
    export ARCHIFY_UPDATE_CHECK_DISABLED=1

    # render <source> <output directory>: validate, deliver and check with archify, then put
    # piabrota's look in. The page is self-contained; the look loads no font here, because a visitor
    # must not call Google Fonts: the system fonts stand in, as on the rest of the site.
    render() {
      local src=$1 dest=$2 work=$TMPDIR/work/$2 log status
      mkdir -p "$work" "$dest"
      set +e
      log=$(node ${archify}/archify/bin/archify.mjs finalize "$(jq -r .diagram_type "$src")" "$src" "$work/page.html" \
        --out-dir "$work/receipts" --quality "$(jq -r '.meta.quality_profile // "showcase"' "$src")" 2>&1)
      status=$?
      set -e
      echo "$log"
      # Exit 2 means the browser check was skipped: there is no Chrome on the builder (just figure
      # ran it). The three other gates must pass.
      if [ "$status" != 0 ] && [ "$status" != 2 ]; then echo "archify failed on $src" >&2; exit 1; fi
      if ! grep -qF 'gates validate:pass deliver:pass check:pass' <<<"$log"; then
        echo "archify gates did not pass on $src" >&2; exit 1
      fi
      node -e '
        const fs = require("fs");
        const [page, css, out] = process.argv.slice(1);
        const html = fs.readFileSync(page, "utf8");
        const at = html.indexOf("</head>");
        if (at < 0) throw new Error("no </head> in " + page);
        fs.writeFileSync(out, html.slice(0, at) + "<style>" + fs.readFileSync(css, "utf8") + "</style>" + html.slice(at));
      ' "$work/page.html" piabrota.css "$dest/index.html"
    }

    mkdir dist
    {
      echo '<!doctype html>'
      echo '<html lang="en"><head><meta charset="utf-8">'
      echo '<meta name="viewport" content="width=device-width, initial-scale=1">'
      echo '<title>Figures · piabrota</title><link rel="stylesheet" href="../style.css"></head>'
      echo '<body><main class="wrap"><h1>Figures</h1>'
      echo '<p class="lede">How piabrota works, drawn with archify. Each page zooms, and follows your light or dark setting. Each figure has an English page and a pt-BR page.</p>'
      echo '<ul>'
      for src in *.json; do
        slug=$(basename "$src" .json)
        render "$src" "dist/$slug"
        render "pt/$slug.json" "dist/pt-BR/$slug"
        echo "<li><strong>$(jq -r '.meta.title | @html' "$src")</strong><br>"
        echo "<a href=\"$slug/\">English</a> · <a href=\"pt-BR/$slug/\" lang=\"pt-BR\" hreflang=\"pt-BR\">Português (pt-BR)</a> ·"
        echo "<a href=\"${repo}/$slug.json\">source</a></li>"
      done
      echo '</ul>'
      echo '<p class="meta">The pages are drawn by <a href="https://github.com/tt-a1i/archify">archify</a> (MIT) and embed JetBrains Mono (SIL Open Font License 1.1).</p>'
      echo '</main></body></html>'
    } > dist/index.html
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    cp -R dist $out
    runHook postInstall
  '';

  allowedReferences = [ ];
}
