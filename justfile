# Recipes for the piabrota VPSs (hosts/: piabrota, piabrota2). Must parse with just 1.21 (Ubuntu 24.04's apt package):
# no [group], no [positional-arguments] attribute. CI checks it with that version.

host := env_var_or_default("DEPLOY_HOST", "piabrota.art")
# piabrota2 (KVM 4), for the recipes that act on both boxes
kvm4 := env_var_or_default("DEPLOY_HOST_KVM4", "srv2125808.hstgr.cloud")

# list the recipes
default:
    @just --list

# the HTTPS certificate of every live name in scripts/domains.txt, from here, as a browser sees it (read-only; curl, openssl); `just certs www.piabrota.art` checks one
certs *names:
    sh scripts/cert-check.sh {{names}}

# build a host's system closure here, without deploying it (piabrota or piabrota2)
build node="piabrota":
    nix build .#nixosConfigurations.{{node}}.config.system.build.toplevel --print-build-logs

# what CI runs on a pull request
check:
    nix flake check --no-update-lock-file --print-build-logs
    nix run nixpkgs#nixpkgs-fmt -- --check flake.nix acme-retry.nix deploy.nix tools.nix loco.nix site.nix pgx.nix hermes.nix hermes-github.nix hosts/*/*.nix kubesolo-purge.nix observer.nix pgx/package.nix pgx/test.nix site/default.nix skills-site/default.nix ww3.nix ww3-site/default.nix paperclip.nix paperclip/package.nix site/data.nix site/hermes.nix apps.nix apps/notes/default.nix drawings/*.nix mockups/*.nix favicon.nix favicon/*.nix
    nix run nixpkgs#statix -- check .
    nix run nixpkgs#deadnix -- --fail .
    nix run nixpkgs#shellcheck -- scripts/*.sh hermes/skills/*/scripts/*.sh metrics/*.sh metrics/test/*.sh favicon/*.sh
    nix run nixpkgs#jq -- -r -f scripts/deepwiki-check.jq .devin/wiki.json

# unit tests of the owner's Hermes plugins (hermes/plugins/), with the local python3 and git
hermes-plugins-test:
    cd hermes/plugins/tests && python3 -m unittest -v test_plugins

# tests of the design kit (design/) and of the proof and pirsig indexes (proof-site/): node only, offline
design-test:
    node --test design/test.mjs proof-site/test.mjs

# tests of hermes/skills/kvm4-health/scripts/kvm4-health.sh with a stub journalctl and systemctl (offline)
health-test:
    sh hermes/skills/kvm4-health/scripts/kvm4-health.test.sh

# tests of hermes/scripts/refresh-grid.sh with a bare origin and a stub gh (offline; needs bash, git, jq)
grid-refresh-test:
    bash hermes/scripts/refresh-grid.test.sh

# tests of scripts/restart-services.sh with stub systemctl, tmux and a fixture /proc (offline)
restart-test:
    sh scripts/restart-services.test.sh

# tests of scripts/cert-renew.sh with a fixture /var/lib/acme and a stub systemctl (offline; needs openssl)
cert-renew-test:
    sh scripts/cert-renew.test.sh

# the human and agent commit counts of each own repository, as lines to paste into mockups/data.nix (read-only, needs gh)
commit-counts:
    sh scripts/commit-counts.sh

# tests of scripts/commit-counts.sh with a stub gh (offline)
commit-counts-test:
    sh scripts/commit-counts.test.sh

# unit tests of the personal feed (hermes/feeds/), offline, with the local python3
feeds-test:
    cd hermes/feeds/tests && python3 -m unittest -v test_build_feed

# tests of the Paperclip helpers (paperclip/*.test.sh): the pi_local shim and paperclip-hermes-key; needs bash and openssl
paperclip-test:
    bash paperclip/pi-to-omp.test.sh
    sh paperclip/hermes-key.test.sh

# tests of the hermes-omp commands (hermes/skills/hermes-omp/scripts): omp-stream and omp-run; needs bash, jq and setsid
omp-test:
    sh hermes/skills/hermes-omp/scripts/test-omp-stream.sh
    bash hermes/skills/hermes-omp/scripts/test-omp-run.sh

# build the personal feed from the real sources into a temporary folder; writes no state (needs network)
feeds-build:
    python3 hermes/feeds/build_feed.py --config hermes/feeds/feeds.toml --out "$(mktemp -d)" --dry-run

# CVE report of the system closure (vulnix against the NVD; a report, many matches are false)
cves: build
    nix run --inputs-from . nixpkgs#vulnix -- --closure ./result || [ $? -eq 2 ]

# deploy one host by hand, as CI does (needs SSH to the box as `user`; magic rollback included)
deploy user="deploy" node="piabrota":
    nix run .#deploy-rs -- .#{{node}} --hostname {{host}} --ssh-user {{user}} --skip-checks

# move the room pin (room-site/default.nix) to room's main, or to <rev>, with both hashes, and build it
room-pin rev="":
    sh scripts/room-pin.sh {{rev}}

# write the README drawing (docs/drawings/mu.svg and its Desmos state) from drawings/*.nix
drawing:
    art=$(nix build .#mu-art --no-link --print-out-paths) && \
    cat "$art/mu.svg" > docs/drawings/mu.svg && \
    cat "$art/mu.desmos.json" > docs/drawings/mu.desmos.json

# build the site (site/, Gleam prerendered by Nix) into ./result-site, as the VPS gets it
site:
    nix build .#site --out-link result-site --print-build-logs

# build the ww3-gpu website (ww3-site/, Gleam prerendered by Nix) into ./result-ww3-site, as the VPS gets it
ww3-site:
    nix build .#ww3-site --out-link result-ww3-site --print-build-logs

# move the ww3-gpu pin (ww3-site/default.nix) to ww3-gpu's main, or to <rev>, and build the site
ww3-pin rev="":
    sh scripts/ww3-pin.sh {{rev}}

# build the skills website (skills-site/, Gleam prerendered by Nix) into ./result-skills-site, as the VPS gets it
skills-site:
    nix build .#skills-site --out-link result-skills-site --print-build-logs

# the security review of security.yml, here: gitleaks on the whole history (fails on a finding not in .gitleaksignore) and zizmor on the workflows (a report)
security:
    nix run --inputs-from . nixpkgs#gitleaks -- git --no-banner --redact .
    -nix run --inputs-from . nixpkgs#zizmor -- --offline --min-severity medium .github/workflows

# print /llms.txt, the index for AI agents that site/llms.nix writes from mockups/data.nix
llms:
    nix eval --raw .#nixosConfigurations.piabrota.config.piabrota.site.llms

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

# check that the files Hermes loads into its context stay under its 32000-character cut
context-size:
    sh scripts/context-size.sh

# list every package of the running system with its size, like pip freeze (--by-size to sort by size)
freeze *args:
    sh scripts/freeze.sh {{args}}

# the same, of the VPS, over SSH
remote-freeze user="h0ffmann":
    ssh {{user}}@{{host}} sh -s < scripts/freeze.sh

# print the specs of the VPS over SSH
remote-specs user="h0ffmann":
    ssh {{user}}@{{host}} sh -s < scripts/specs.sh

# check on the VPS that Hermes's plugins, skills, omp and yt-dlp of the last deploy are live (read-only)
remote-hermes-check user="h0ffmann":
    ssh {{user}}@{{host}} sh -s < scripts/hermes-check.sh

# the health of a VPS and its units: memory, MemoryPeak against MemoryMax, disk, CPU (read-only); `just remote-health h0ffmann srv2125808.hstgr.cloud` asks the other box; exit 1 means a WARN or CRIT line
remote-health user="h0ffmann" target=host:
    ssh {{user}}@{{target}} sh -s < hermes/skills/kvm4-health/scripts/kvm4-health.sh || { s=$?; [ "$s" -ne 1 ] || echo "remote-health: {{target}} has a WARN or CRIT line, see above" >&2; exit "$s"; }

# restart the services the VPS has, over SSH, through sudo; a human only, never an agent (docs/DEPLOY.md, "Restarting the services by hand"). Groups: metrics web pgx room loco rig hermes, `list` (the plan only), default all. It asks `Proceed? [y/N]` on your terminal; flags go inside the quoted first argument: `just remote-restart "hermes --dry-run"`, `just remote-restart "all --yes"`; KVM 4: `just remote-restart all h0ffmann <address>`
remote-restart what="all" user="h0ffmann" target=host:
    case '{{what}}' in *[!a-z\ -]*) echo "remote-restart: the first argument takes letters, spaces and - only" >&2; exit 2 ;; esac
    b64=$(base64 < scripts/restart-services.sh | tr -d '\n') && ssh -t {{user}}@{{target}} "sudo sh -c \"\$(echo $b64 | base64 -d)\" restart-services {{what}}"

# order again, over SSH through sudo, the certificates of a VPS that a browser refuses (self-signed or ending within 14 days); a human only, never an agent (docs/SITE.md, "Certificates"). `just remote-cert-renew skills.piabrota.art`, `just remote-cert-renew "all --dry-run"`; KVM 4: `just remote-cert-renew all h0ffmann {{kvm4}}`
remote-cert-renew what="all" user="h0ffmann" target=host:
    case '{{what}}' in *[!a-z0-9.\ -]*) echo "remote-cert-renew: the first argument takes names, spaces and - only" >&2; exit 2 ;; esac
    b64=$(base64 < scripts/cert-renew.sh | tr -d '\n') && ssh {{user}}@{{target}} "sudo sh -c \"\$(echo $b64 | base64 -d)\" cert-renew {{what}}"

# fix every refused certificate on both VPSs (remote-cert-renew all on each), then check every name from here; a human only
certs-fix user="h0ffmann":
    a=0; b=0; {{just_executable()}} remote-cert-renew all {{user}} {{host}} || a=$?; {{just_executable()}} remote-cert-renew all {{user}} {{kvm4}} || b=$?; {{just_executable()}} certs && [ "$a" = 0 ] && [ "$b" = 0 ]

# smoke check of the render path: a 30 s dummy video from ffmpeg alone, into video-lab/out/dummy (see docs/VIDEO-PIPELINE.md)
video-dummy:
    sh video-lab/dummy/run.sh

# tests of the metrics collector (fixture /proc) and page; needs jq, and python3 and curl for the page's HTTP check
metrics-test:
    sh metrics/test/run.sh
    sh metrics/test/page.sh

# open the metrics page on fixtures (healthy, stale, missing or hostile) at http://127.0.0.1:<port>/; needs python3 and jq
metrics-preview case="healthy" port="8080":
    sh metrics/test/preview.sh {{case}} {{port}}
