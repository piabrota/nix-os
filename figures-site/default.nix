# The figures as interactive pages, for /figures: archify (pinned below) turns each source in
# docs/archify/ (English) and docs/archify/pt/ (pt-BR) into one self-contained HTML page, on the
# builder. No HTML is committed. The output is those pages, an index with the PNG of each figure
# (docs/img/) and nothing else: allowedReferences = [ ] fails the build if the output names any
# store path, so node, jq and archify never reach the VPS closure.
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
  sources = "https://github.com/piabrota/nix-os/tree/main/docs/archify";
  # The foot's partnership line, as parts.foot writes it (site/src/piabrota_site/parts.gleam).
  inherit ((import ../mockups/data.nix).org) contact;

  # The org's mark, as parts.eye draws it (the same markup as the other pages of the site).
  eye = class: size: ''<svg xmlns="http://www.w3.org/2000/svg" aria-hidden="true" class="${class}" height="${size}" viewBox="0 0 100 100" width="${size}"><rect fill="#BC2318" height="100" rx="22" width="100"></rect><path d="M12 50 Q50 18 88 50 Q50 82 12 50Z" fill="#F7F3EA"></path><circle cx="50" cy="50" fill="#2E9E4F" r="14"></circle><circle cx="50" cy="50" fill="#0B0D12" r="6"></circle></svg>'';

  # The slim bar on top of every figure page. The tokens are the dark ones of site/DESIGN.md:
  # piabrota.css keeps these pages dark. piabrota.css hides everything but the drawing and fits the
  # drawing to the window with position: fixed, so the bar shows itself again and the drawing
  # moves down by the bar's height.
  barCss = ''
    .pz-bar{--pz-bg:#0B0D12;--pz-border:#2A303C;--pz-text:#EDEFF3;--pz-muted:#9AA3B2;--pz-accent:#FF6B5E;position:fixed;top:0;left:0;right:0;z-index:10;box-sizing:border-box;height:44px;display:flex;align-items:center;justify-content:space-between;gap:12px;padding:0 16px;background:var(--pz-bg);border-bottom:1px solid var(--pz-border);font:400 13px/1 Inter,system-ui,-apple-system,'Segoe UI',sans-serif}
    .pz-bar,.pz-bar *{visibility:visible!important}
    .pz-bar a{color:var(--pz-muted);text-decoration:none;white-space:nowrap}
    .pz-bar a:hover{color:var(--pz-text);text-decoration:underline;text-underline-offset:3px}
    .pz-bar a:focus-visible{outline:2px solid var(--pz-accent);outline-offset:3px;border-radius:6px}
    .pz-bar .pz-brand{display:inline-flex;align-items:center;gap:8px;color:var(--pz-text);font:400 1.1rem/1 'Fjalla One','Arial Narrow',sans-serif}
    .pz-bar .pz-brand svg{display:block;flex:none;width:22px;min-width:0;height:22px}
    .pz-bar .pz-links{display:inline-flex;align-items:center;gap:16px;min-width:0}
    .pz-bar .pz-back{color:var(--pz-accent)}
    .diagram-container svg{top:44px!important;height:calc(100vh - 44px)!important}
  '';
in
stdenvNoCC.mkDerivation {
  pname = "piabrota-figures-site";
  version = "1";
  src = lib.fileset.toSource {
    root = ../docs;
    fileset = lib.fileset.unions [
      ../docs/archify/piabrota.css
      (lib.fileset.fileFilter (file: file.hasExt "json") ../docs/archify)
      (lib.fileset.fileFilter (file: file.hasExt "png") ../docs/img)
    ];
  };
  nativeBuildInputs = [ nodejs jq ];

  buildPhase = ''
    runHook preBuild
    export ARCHIFY_UPDATE_CHECK_DISABLED=1

    # The page's look: piabrota.css, then the bar's.
    cat archify/piabrota.css > "$TMPDIR/look.css"
    cat > "$TMPDIR/bar.css" <<'EOF'
    ${barCss}
    EOF
    cat "$TMPDIR/bar.css" >> "$TMPDIR/look.css"

    # bar <en|pt-BR> <slug>: the bar's HTML. It holds the brand, the way back to the index and the
    # same figure in the other language. The links are relative: /figures/ is served under an alias.
    barmark='${eye "pz-eye" "22"}'
    bar() {
      local label back other lang
      # archify writes lang="en" on every page; the bar says which language it speaks.
      if [ "$1" = en ]; then
        lang=en
        label=Figures
        back='<a class="pz-back" href="../">← figures</a>'
        other="<a href=\"../pt-BR/$2/\" lang=\"pt-BR\" hreflang=\"pt-BR\">Português (pt-BR)</a>"
      else
        lang=pt-BR
        label=Figuras
        back='<a class="pz-back" href="../../">← figuras</a>'
        other="<a href=\"../../$2/\" lang=\"en\" hreflang=\"en\">English</a>"
      fi
      echo "<nav class=\"pz-bar\" lang=\"$lang\" aria-label=\"$label\"><a class=\"pz-brand\" href=\"/\">$barmark<span>piabrota</span></a><span class=\"pz-links\">$back $other</span></nav>"
    }

    # render <source> <output directory> <en|pt-BR> <slug>: validate, deliver and check with archify,
    # then put piabrota's look and the bar in. The page is self-contained; the look loads no font
    # here, because a visitor must not call Google Fonts from a figure: the system fonts stand in.
    render() {
      local src=$1 dest=$2 work=$TMPDIR/work/$2 log status html
      html=$(bar "$3" "$4")
      mkdir -p "$work" "$dest"
      set +e
      log=$(node ${archify}/archify/bin/archify.mjs finalize "$(jq -r .diagram_type "$src")" "$src" "$work/page.html" \
        --out-dir "$work/receipts" --quality "$(jq -r '.meta.quality_profile // "showcase"' "$src")" 2>&1)
      status=$?
      set -e
      echo "$log" >&2
      # Exit 2 means the browser check was skipped: there is no Chrome on the builder (just figure
      # ran it). The three other gates must pass.
      if [ "$status" != 0 ] && [ "$status" != 2 ]; then echo "archify failed on $src" >&2; exit 1; fi
      if ! grep -qF 'gates validate:pass deliver:pass check:pass' <<<"$log"; then
        echo "archify gates did not pass on $src" >&2; exit 1
      fi
      node -e '
        const fs = require("fs");
        const [page, css, bar, out] = process.argv.slice(1);
        const html = fs.readFileSync(page, "utf8");
        const at = html.indexOf("</head>");
        if (at < 0) throw new Error("no </head> in " + page);
        const body = /<body[^>]*>/.exec(html);
        if (!body) throw new Error("no <body> in " + page);
        const head = html.slice(0, at) + "<style>" + fs.readFileSync(css, "utf8") + "</style>";
        const rest = html.slice(at);
        const cut = body.index + body[0].length - at;
        fs.writeFileSync(out, head + rest.slice(0, cut) + bar + rest.slice(cut));
      ' "$work/page.html" "$TMPDIR/look.css" "$html" "$dest/index.html"
    }

    # esc <text>: the text as HTML.
    esc() { jq -rn --arg s "$1" '$s | @html'; }

    mkdir dist
    : > "$TMPDIR/cards.html"
    for src in archify/*.json; do
      slug=$(basename "$src" .json)
      render "$src" "dist/$slug" en "$slug"
      render "archify/pt/$slug.json" "dist/pt-BR/$slug" pt-BR "$slug"
      cp "img/$slug.png" "dist/$slug.png"
      # The PNG's size, from its header, so the browser keeps room for the image before it loads.
      dims=$(node -e 'const b = require("fs").readFileSync(process.argv[1]); console.log(b.readUInt32BE(16), b.readUInt32BE(20))' "img/$slug.png")
      size="width=\"''${dims% *}\" height=\"''${dims#* }\""
      # The title of a figure reads "Name: what it says". The card shows the two parts.
      title=$(jq -r .meta.title "$src")
      fname=''${title%%: *}
      take=''${title#*: }
      if [ "$fname" = "$title" ]; then take=""; fi
      {
        echo '<li class="figure-card">'
        echo "<a class=\"figure-preview\" href=\"$slug/\" tabindex=\"-1\" aria-hidden=\"true\"><img src=\"$slug.png\" $size alt=\"\" loading=\"lazy\"></a>"
        echo '<div class="figure-body">'
        echo "<h3><a href=\"$slug/\">$(esc "$fname")</a></h3>"
        if [ -n "$take" ]; then echo "<p class=\"blurb\">$(esc "$take")</p>"; fi
        echo '<div class="actions small">'
        echo "<a class=\"btn\" href=\"$slug/\">English</a>"
        echo "<a class=\"btn\" href=\"pt-BR/$slug/\" lang=\"pt-BR\" hreflang=\"pt-BR\">Português (pt-BR)</a>"
        echo "<a class=\"btn\" href=\"${repo}/$slug.json\">source</a>"
        echo '</div></div></li>'
      } >> "$TMPDIR/cards.html"
    done

    # The index wears the page frame of /hosts/ (site/src/piabrota_site/parts.gleam, page.gleam) and
    # the site's style.css. Like the site's other pages, and unlike the figure pages, it asks Google
    # Fonts for Fjalla One, Inter and JetBrains Mono (site/DESIGN.md, "Type"); the system fonts
    # stand in until they load.
    {
      cat <<'EOF'
    <!doctype html>
    <html lang="en"><head><meta charset="utf-8"><meta content="width=device-width, initial-scale=1" name="viewport"><title>piabrota · figures</title><meta content="How piabrota works, drawn with archify: one page for each figure, in English and in pt-BR." name="description"><meta content="#0B0D12" media="(prefers-color-scheme: dark)" name="theme-color"><meta content="#FFFFFF" media="(prefers-color-scheme: light)" name="theme-color"><link href="data:," rel="icon"><link href="https://fonts.googleapis.com" rel="preconnect"><link crossorigin href="https://fonts.gstatic.com" rel="preconnect"><link href="https://fonts.googleapis.com/css2?family=Fjalla+One&amp;family=Inter:wght@400;600&amp;family=JetBrains+Mono&amp;display=swap" rel="stylesheet"><link href="../style.css" rel="stylesheet"></head>
    <body class="figures"><div><header class="top"><div class="wrap bar"><a class="brand" href="/">
    EOF
      echo '${eye "eye" "30"}<span>piabrota</span></a>'
      cat <<'EOF'
    <nav aria-label="Languages" class="langs"><a aria-current="page" href="/" lang="en">English</a><a href="/pt-BR/" lang="pt-BR">Português</a><a href="/zh-CN/" lang="zh-CN">简体中文</a><a href="/ja-JP/" lang="ja-JP">日本語</a></nav><nav aria-label="Designs" class="designs"><a href="/"><b>A</b> fabric</a><a href="/index/"><b>B</b> index</a><a href="/paths/"><b>C</b> paths</a></nav></div>
    <div class="wrap hero"><div><p class="eyebrow">piabrota.art · figures</p><h1>figures <span>· drawn, not pasted</span></h1>
    <p class="lede">How piabrota works, drawn with archify. Each figure is a page that you can zoom. It has an English version and a pt-BR version.</p>
    <div class="actions"><a class="btn primary" href="#figures">The figures ↓</a><a class="btn" href="${sources}" rel="noopener">Sources ↗</a></div></div></div></header>
    <main><section class="wrap" id="figures"><div class="section-head"><h2>The figures</h2><span class="source">docs/archify/*.json</span></div>
    <ul class="figures-grid">
    EOF
      cat "$TMPDIR/cards.html"
      cat <<'EOF'
    </ul>
    <p class="meta">The pages are drawn by <a href="https://github.com/tt-a1i/archify">archify</a> (MIT) and embed JetBrains Mono (SIL Open Font License 1.1).</p>
    </section></main>
    <footer class="foot"><div class="wrap"><p>piabrota.art is served by <a href="/nixos">nix-os</a>, from /nix/store. Partnerships: ${contact}. <a href="/notes">Notes demo (Loco)</a>.</p><nav aria-label="Designs" class="designs"><a href="/"><b>A</b> fabric</a><a href="/index/"><b>B</b> index</a><a href="/paths/"><b>C</b> paths</a></nav></div></footer></div></body></html>
    EOF
    } > dist/index.html
    # render's stdout is inside the block above: a log line there lands in the index as page text.
    if grep -qE 'finalize|gates validate|/build/' dist/index.html; then
      echo "dist/index.html holds archify log text" >&2; exit 1
    fi
    # Only the index calls Google Fonts.
    if [ "$(grep -rl googleapis dist)" != dist/index.html ]; then
      echo "a figure page names Google Fonts, or the index does not" >&2; exit 1
    fi
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    cp -R dist $out
    runHook postInstall
  '';

  allowedReferences = [ ];
}
