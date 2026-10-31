# Recipes for the piabrota VPS. Must parse with just 1.21 (Ubuntu 24.04's apt package):
# no [group], no [positional-arguments] attribute. CI checks it with that version.

host := env_var_or_default("DEPLOY_HOST", "piabrota.art")

# list the recipes
default:
    @just --list

# build the system closure here, without deploying it
build:
    nix build .#nixosConfigurations.piabrota.config.system.build.toplevel --print-build-logs

# what CI runs on a pull request
check:
    nix flake check --no-update-lock-file --print-build-logs
    nix run nixpkgs#nixpkgs-fmt -- --check flake.nix deploy.nix tools.nix loco.nix site.nix kubesolo.nix kubesolo/package.nix pgx.nix pgx/package.nix pgx/test.nix site/default.nix site/data.nix apps.nix apps/notes/default.nix drawings/*.nix mockups/*.nix
    nix run nixpkgs#statix -- check .
    nix run nixpkgs#deadnix -- --fail .
    nix run nixpkgs#shellcheck -- scripts/*.sh kubesolo/k8s.bash
    nix run nixpkgs#jq -- -r -f scripts/deepwiki-check.jq .devin/wiki.json

# CVE report of the system closure (vulnix against the NVD; a report, many matches are false)
cves: build
    nix run --inputs-from . nixpkgs#vulnix -- --closure ./result || [ $? -eq 2 ]

# deploy by hand, as CI does (needs SSH to the box as `user`; magic rollback included)
deploy user="deploy":
    nix run .#deploy-rs -- .#piabrota --hostname {{host}} --ssh-user {{user}} --skip-checks

# write the README drawing (docs/drawings/mu.svg and its Desmos state) from drawings/*.nix
drawing:
    art=$(nix build .#mu-art --no-link --print-out-paths) && \
    cat "$art/mu.svg" > docs/drawings/mu.svg && \
    cat "$art/mu.desmos.json" > docs/drawings/mu.desmos.json

# build the site (site/, Gleam prerendered by Nix) into ./result-site, as the VPS gets it
site:
    nix build .#site --out-link result-site --print-build-logs

# write site/src/piabrota_site/data.gleam from mockups/data.nix (not committed; the build writes its own)
site-data:
    cat "$(nix build .#site-data --no-link --print-out-paths)" > site/src/piabrota_site/data.gleam

# format and test the site's Gleam code, in the site dev shell (gleam and node; never on the VPS)
site-test: site-data
    nix develop .#site --command sh -c 'cd site && gleam format src test && gleam test'

# write the homepage mockups (docs/mockups/*.svg, and the wiki's copy in wiki/mockups/) from mockups/*.nix
mockups:
    art=$(nix build .#mockups --no-link --print-out-paths) && \
    for f in "$art"/*.svg; do cat "$f" > "docs/mockups/$(basename "$f")"; cat "$f" > "wiki/mockups/$(basename "$f")"; done

# check out the pinned Archify (vendor/archify, sparse to archify/), once per clone
figure-init:
    git submodule update --init --depth 1 vendor/archify
    git -C vendor/archify sparse-checkout set --no-cone /archify/
    @echo "figure-init: $(git -C vendor/archify rev-parse --short HEAD)"

# Archify validates and checks each source (finalize), piabrota's look (docs/archify/piabrota.css) goes
# over it, headless Chrome takes the picture, and the wiki gets a copy. English sources are
# docs/archify/*.json, their pt-BR mirrors docs/archify/pt/*.json. Needs node, jq, perl, Chrome
# (CHROME names another) and the Google Fonts; writes docs/archify/figures.lock.
# draw every docs/archify/<slug>.json to docs/img/<slug>.png (pt/ to docs/img/pt/), and copy to wiki/img
figure: figure-init
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p build/figure docs/img/pt wiki/img/pt
    for src in docs/archify/*.json docs/archify/pt/*.json; do
        rel="${src#docs/archify/}"; slug="${rel%.json}"; out="build/figure/$slug"
        rm -rf "$out"; mkdir -p "$out"
        ARCHIFY_UPDATE_CHECK_DISABLED=1 node vendor/archify/archify/bin/archify.mjs finalize "$(jq -r .diagram_type "$src")" "$src" "$out/page.html" --out-dir "$out/receipts" --quality "$(jq -r '.meta.quality_profile // "showcase"' "$src")"
        read -r w h < <(grep -o '<svg viewBox="[^"]*"' "$out/page.html" | head -1 | sed -E 's/.*0 0 ([0-9.]+) ([0-9.]+)"/\1 \2/')
        crop="$(awk -F'\t' -v s="$slug" '$1==s {print $2}' docs/archify/crop.tsv)"; h="${crop:-$h}"
        FONTS='<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Fjalla+One&family=Inter:wght@400;600&display=block">' CSS="$(cat docs/archify/piabrota.css)" W="$w" H="$h" \
            perl -0pe 's|</head>|$ENV{FONTS}<style>$ENV{CSS}</style></head>|; s|<svg viewBox="0 0 [0-9.]+ [0-9.]+"|<svg viewBox="0 0 $ENV{W} $ENV{H}"|' "$out/page.html" > "$out/frame.html"
        "${CHROME:-google-chrome}" --headless --disable-gpu --hide-scrollbars --force-dark-mode --force-device-scale-factor=2 --user-data-dir="$PWD/$out/profile" --window-size="$w,$h" --virtual-time-budget=3000 --screenshot="$PWD/docs/img/$slug.png" "file://$PWD/$out/frame.html" 2>/dev/null
        cp "docs/img/$slug.png" "wiki/img/$slug.png"
        echo "figure: docs/img/$slug.png"
    done
    just _figure-lock > docs/archify/figures.lock

# the inputs of each figure (its source, the look, the crop, the Archify pin), one line per slug
_figure-lock:
    #!/usr/bin/env bash
    set -euo pipefail
    pin="$(git ls-files -s vendor/archify | cut -d' ' -f2)"
    for src in docs/archify/*.json docs/archify/pt/*.json; do
        rel="${src#docs/archify/}"
        printf '%s\t%s\n' "${rel%.json}" "$(cat "$src" docs/archify/piabrota.css docs/archify/crop.tsv | sha256sum | cut -c1-16)-${pin:0:7}"
    done

# cheap and offline: every source has its PNG, shown in README.md (pt/ in the wiki), the wiki has the same PNG, all match the last `just figure`
figure-check:
    #!/usr/bin/env bash
    set -euo pipefail
    for src in docs/archify/*.json docs/archify/pt/*.json; do
        rel="${src#docs/archify/}"; s="${rel%.json}"
        test -s "docs/img/$s.png" || { echo "figure-check: no PNG for $src; run just figure" >&2; exit 1; }
        cmp -s "docs/img/$s.png" "wiki/img/$s.png" || { echo "figure-check: wiki/img/$s.png is not docs/img/$s.png; run just figure" >&2; exit 1; }
        case "$s" in
            pt/*) grep -rqF "](img/$s.png)" wiki/ || { echo "figure-check: no wiki page shows img/$s.png" >&2; exit 1; } ;;
            *) grep -qF "](docs/img/$s.png)" README.md || { echo "figure-check: README.md does not show docs/img/$s.png" >&2; exit 1; } ;;
        esac
    done
    just _figure-lock | cmp -s - docs/archify/figures.lock || { echo "figure-check: a source, the look or the Archify pin changed since the PNG; run just figure" >&2; exit 1; }
    echo "figure-check: ok"

# print the specs of this machine
specs:
    sh scripts/specs.sh

# list every package of the running system with its size, like pip freeze (--by-size to sort by size)
freeze *args:
    sh scripts/freeze.sh {{args}}

# the same, of the VPS, over SSH
remote-freeze user="h0ffmann":
    ssh {{user}}@{{host}} sh -s < scripts/freeze.sh

# print the specs of the VPS over SSH
remote-specs user="h0ffmann":
    ssh {{user}}@{{host}} sh -s < scripts/specs.sh
