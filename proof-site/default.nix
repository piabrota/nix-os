# The pages of proof.piabrota.art, built on the builder: h0ffmann/proof's own browsable index
# (its site/default.nix, at the commit below) under /proof/, the HTML pages of piabrota/pirsig under
# /pirsig/, and an index at / that lists every page of both. No HTML is committed here.
#
# archify pages open dark, whatever the reader's setting (the owner, 2026-11-09): the index links
# them with ?theme=dark, and proof.nix sends any other request for one to that address. The build
# fails if an archify page is outside that location or no longer reads ?theme=.
#
# The output holds only files: allowedReferences = [ ] fails the build if it names a store path, so
# TeX Live, ffmpeg, node, jq and archify never reach the closure of piabrota2.
{ stdenvNoCC, callPackage, fetchFromGitHub, nodejs, jq }:
let
  # h0ffmann/proof's main. Move rev and hash together; its site needs no change here.
  proofRev = "895d6f9fece8a0827eca4a51e2b95dce0db2a3f9";
  proofSrc = fetchFromGitHub {
    owner = "h0ffmann";
    repo = "proof";
    rev = proofRev;
    hash = "sha256-lcU35HlJ7Y7HKL+KpELwt2lkT6uxQD6pfGPUzwQ7oqQ=";
  };
  proof = callPackage "${proofSrc}/site" { rev = proofRev; };

  # piabrota/pirsig's main: brain/Videos/index.html (one page, its images inline) and the figures of
  # docs/archify/, which archify draws here (pirsig's `just figure` draws only their PNGs).
  pirsigRev = "caa7bc7722f875bf617f59d0eaa6fffe9f201c27";
  pirsig = fetchFromGitHub {
    owner = "piabrota";
    repo = "pirsig";
    rev = pirsigRev;
    hash = "sha256-ig0hh2NwmA6gsLcTKwEU35b5IY31hYMDZ6chu7UBk8E=";
  };
  # The archify of pirsig's figures.lock and of figures-site/default.nix (vendor/archify).
  archify = fetchFromGitHub {
    owner = "tt-a1i";
    repo = "archify";
    rev = "208acba8d412335185b2056fedf54b3405df43fb";
    hash = "sha256-pejw78BgKDnttOAGcLvVtWa50azpCjTfESnmdYIjCoI=";
  };

  icons = import ../favicon/links.nix;
  eye = ''<svg xmlns="http://www.w3.org/2000/svg" aria-hidden="true" class="eye" height="28" viewBox="0 0 100 100" width="28"><rect fill="#BC2318" height="100" rx="22" width="100"></rect><path d="M12 50 Q50 18 88 50 Q50 82 12 50Z" fill="#F7F3EA"></path><circle cx="50" cy="50" fill="#2E9E4F" r="14"></circle><circle cx="50" cy="50" fill="#0B0D12" r="6"></circle></svg>'';
  # The dark tokens of site/DESIGN.md. The index is dark only, like the diagrams it lists.
  css = ''
    :root{color-scheme:dark;--bg:#0B0D12;--surface:#14171F;--border:#2A303C;--text:#EDEFF3;--muted:#9AA3B2;--accent-text:#FF6B5E}
    *{box-sizing:border-box}
    body{margin:0;background:var(--bg);color:var(--text);font:400 16px/1.6 Inter,system-ui,-apple-system,'Segoe UI',sans-serif}
    main{max-width:880px;margin:0 auto;padding:32px 16px 72px}
    header{display:flex;align-items:center;gap:12px;margin-bottom:8px}
    header a{display:inline-flex;align-items:center;gap:10px;color:var(--text);text-decoration:none;font:400 1.4rem/1 'Fjalla One','Arial Narrow',sans-serif}
    h1{font:400 2.2rem/1.15 'Fjalla One','Arial Narrow',sans-serif;margin:24px 0 8px}
    h2{font:400 1.5rem/1.2 'Fjalla One','Arial Narrow',sans-serif;margin:40px 0 4px}
    h3{font:600 .8rem/1.4 'JetBrains Mono',ui-monospace,monospace;color:var(--muted);text-transform:uppercase;letter-spacing:.06em;margin:24px 0 8px}
    p{color:var(--muted);margin:0 0 12px}
    a{color:var(--accent-text)}
    a:focus-visible{outline:2px solid var(--accent-text);outline-offset:3px;border-radius:4px}
    ul{list-style:none;margin:0;padding:0;display:grid;gap:8px}
    li{background:var(--surface);border:1px solid var(--border);border-radius:10px;padding:10px 14px;overflow-wrap:anywhere}
    li a{color:var(--text);text-decoration:none;font-weight:600}
    li a:hover{text-decoration:underline;text-underline-offset:3px}
    li code{display:block;color:var(--muted);font:400 .8rem/1.5 'JetBrains Mono',ui-monospace,monospace}
    footer{margin-top:48px;color:var(--muted);font-size:.85rem}
  '';
in
stdenvNoCC.mkDerivation {
  pname = "proof-pages";
  version = builtins.substring 0 7 proofRev;
  dontUnpack = true;
  nativeBuildInputs = [ nodejs jq ];

  buildPhase = ''
    runHook preBuild
    export ARCHIFY_UPDATE_CHECK_DISABLED=1
    mkdir -p dist/pirsig/videos dist/pirsig/figures

    cp -R ${proof} dist/proof
    chmod -R u+w dist/proof
    cp ${pirsig}/brain/Videos/index.html dist/pirsig/videos/index.html

    # The figures of pirsig: validate, deliver and check with archify, as figures-site does. Exit 2
    # means the browser check was skipped (no Chrome on the builder); the three other gates must pass.
    for src in ${pirsig}/docs/archify/*.json; do
      slug=$(basename "$src" .json)
      work=$TMPDIR/work/$slug
      mkdir -p "$work"
      set +e
      log=$(node ${archify}/archify/bin/archify.mjs finalize "$(jq -r .diagram_type "$src")" "$src" "$work/page.html" \
        --out-dir "$work/receipts" --quality "$(jq -r '.meta.quality_profile // "showcase"' "$src")" 2>&1)
      status=$?
      set -e
      echo "$log" >&2
      if [ "$status" != 0 ] && [ "$status" != 2 ]; then echo "archify failed on $src" >&2; exit 1; fi
      if ! grep -qF 'gates validate:pass deliver:pass check:pass' <<<"$log"; then
        echo "archify gates did not pass on $src" >&2; exit 1
      fi
      cp "$work/page.html" "dist/pirsig/figures/$slug.html"
    done

    # Dark, always: proof.nix sends an archify page asked for without ?theme=dark to that address,
    # and archify reads the address before localStorage and the system setting. Each archify page
    # must still read it, and must sit where proof.nix's location looks.
    while IFS= read -r page; do
      case "$page" in
        dist/proof/docs/diagrams/en/*.html | dist/proof/docs/diagrams/pt-BR/*.html | dist/pirsig/figures/*.html) ;;
        *) echo "$page: an archify page outside proof.nix's dark location" >&2; exit 1 ;;
      esac
      if ! grep -qF "URLSearchParams(window.location.search).get('theme')" "$page"; then
        echo "$page: archify no longer reads ?theme= from the address" >&2; exit 1
      fi
    done < <(grep -rlF --include='*.html' "archify-theme" dist)

    # esc <text>: the text as HTML. title <page>: the page's <title>, or its path.
    esc() { jq -rn --arg s "$1" '$s | @html'; }
    title() {
      local t
      t=$(node -e '
        const m = /<title>([^<]*)<\/title>/i.exec(require("fs").readFileSync(process.argv[1], "utf8"));
        console.log(m ? m[1].trim() : "");
      ' "$1")
      echo "''${t:-''${1#dist/}}"
    }
    # list <heading> <find arguments...>: one section of the index, a link per page, sorted by path.
    list() {
      local heading=$1 page href query
      shift
      echo "<h3>$(esc "$heading")</h3><ul>"
      while IFS= read -r page; do
        href=''${page#dist/}
        query=""
        if grep -qF "archify-theme" "$page"; then query="?theme=dark"; fi
        echo "<li><a href=\"$(esc "$href$query")\">$(esc "$(title "$page")")</a><code>/$(esc "$href")</code></li>"
      done < <(find "$@" -name '*.html' -print | LC_ALL=C sort)
      echo "</ul>"
    }

    {
      cat <<'EOF'
    <!doctype html>
    <html lang="en"><head><meta charset="utf-8"><meta content="width=device-width, initial-scale=1" name="viewport"><title>proof · piabrota</title><meta content="Every HTML page of h0ffmann/proof and piabrota/pirsig: specifications, Z3 reports, diagrams, figures and video notes." name="description"><meta content="#0B0D12" name="theme-color">
    EOF
      echo '${icons}'
      echo '<link href="https://fonts.googleapis.com" rel="preconnect"><link crossorigin href="https://fonts.gstatic.com" rel="preconnect"><link href="https://fonts.googleapis.com/css2?family=Fjalla+One&amp;family=Inter:wght@400;600&amp;family=JetBrains+Mono&amp;display=swap" rel="stylesheet">'
      cat <<'EOF'
    <style>
    ${css}
    </style></head>
    <body><main>
    EOF
      echo '<header><a href="https://www.piabrota.art/">${eye}<span>piabrota</span></a></header>'
      echo '<h1>proof</h1><p>Every HTML page of two repositories, built from a pinned commit. The diagrams open dark.</p>'
      echo "<h2 id=\"proof\">h0ffmann/proof</h2><p>Specifications checked by a prover, data experiments and papers. <a href=\"proof/\">Its own index</a> also lists the PDFs and the video preview. <a href=\"https://github.com/h0ffmann/proof/tree/${proofRev}\">Source at ${builtins.substring 0 7 proofRev}</a>.</p>"
      list "Pages" dist/proof -path dist/proof/docs/diagrams -prune -o -type f
      list "Diagrams, English" dist/proof/docs/diagrams/en -type f
      list "Diagrams, Português (BR)" dist/proof/docs/diagrams/pt-BR -type f
      list "Diagram index" dist/proof/docs/diagrams -maxdepth 1 -type f
      echo "<h2 id=\"pirsig\">piabrota/pirsig</h2><p>The brain: smart notes, PARA and the track record of decisions. <a href=\"https://github.com/piabrota/pirsig/tree/${pirsigRev}\">Source at ${builtins.substring 0 7 pirsigRev}</a>.</p>"
      list "Video notes" dist/pirsig/videos -type f
      list "Figures" dist/pirsig/figures -type f
      cat <<'EOF'
    <footer>Served by <a href="https://www.piabrota.art/nixos">nix-os</a> from /nix/store, on piabrota2. The diagrams and figures are drawn by <a href="https://github.com/tt-a1i/archify">archify</a>.</footer>
    </main></body></html>
    EOF
    } > dist/index.html
    # A log line of the loops above that landed in the page instead of stderr.
    if grep -qE 'finalize|gates validate|/build/' dist/index.html; then
      echo "dist/index.html holds build log text" >&2; exit 1
    fi
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    cp -R dist $out
    runHook postInstall
  '';

  dontFixup = true;
  allowedReferences = [ ];
}
