# What proof-site/default.nix (proof.piabrota.art) and proof-site/pirsig.nix (pirsig.piabrota.art)
# share: the dark index page, its shell helpers and the gate for archify pages. Plain Nix, no
# derivation: each output is built in its own file, with its own `allowedReferences = [ ]`.
let
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
{
  # Shell: dark, always. proof.nix sends an archify page asked for without ?theme=dark to that
  # address, and archify reads the address before localStorage and the system setting. Each archify
  # page must still read it, and must sit where proof.nix's location looks. `allowed` is the `case`
  # pattern of the paths of that location.
  darkGate = allowed: ''
    while IFS= read -r page; do
      case "$page" in
        ${allowed}) ;;
        *) echo "$page: an archify page outside proof.nix's dark location" >&2; exit 1 ;;
      esac
      if ! grep -qF "URLSearchParams(window.location.search).get('theme')" "$page"; then
        echo "$page: archify no longer reads ?theme= from the address" >&2; exit 1
      fi
    done < <(grep -rlF --include='*.html' "archify-theme" dist)
  '';

  # Shell: esc <text>: the text as HTML. title <page>: the page's <title>, or its path.
  # list <heading> <find arguments...>: one section of the index, a link per page, sorted by path.
  indexFns = ''
    esc() { jq -rn --arg s "$1" '$s | @html'; }
    title() {
      local t
      t=$(node -e '
        const m = /<title>([^<]*)<\/title>/i.exec(require("fs").readFileSync(process.argv[1], "utf8"));
        console.log(m ? m[1].trim() : "");
      ' "$1")
      echo "''${t:-''${1#dist/}}"
    }
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
  '';

  # Shell: writes dist/index.html. `body` is shell that echoes the sections (it may call `list`);
  # `drawn` names what archify draws on the pages.
  writeIndex = { title, description, lead, body, drawn }: ''
    {
      cat <<'EOF'
    <!doctype html>
    <html lang="en"><head><meta charset="utf-8"><meta content="width=device-width, initial-scale=1" name="viewport"><title>${title} · piabrota</title><meta content="${description}" name="description"><meta content="#0B0D12" name="theme-color">
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
      echo '<h1>${title}</h1><p>${lead}</p>'
      ${body}
      cat <<'EOF'
    <footer>Served by <a href="https://www.piabrota.art/nixos">nix-os</a> from /nix/store, on piabrota2. The ${drawn} are drawn by <a href="https://github.com/tt-a1i/archify">archify</a>.</footer>
    </main></body></html>
    EOF
    } > dist/index.html
    # A log line of the loops above that landed in the page instead of stderr.
    if grep -qE 'finalize|gates validate|/build/' dist/index.html; then
      echo "dist/index.html holds build log text" >&2; exit 1
    fi
  '';
}
