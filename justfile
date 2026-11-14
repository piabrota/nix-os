# Recipes for the piabrota VPSs (hosts/: piabrota, piabrota2). Must parse with just 1.21 (Ubuntu 24.04's apt package):
# no [group], no [positional-arguments] attribute. CI checks it with that version.

host := env_var_or_default("DEPLOY_HOST", "piabrota.art")
# piabrota2 (KVM 4), for the recipes that act on both boxes
kvm4 := env_var_or_default("DEPLOY_HOST_KVM4", "srv2125808.hstgr.cloud")
# the scripts (scala/), built by Nix on first use; on a box they are `piabrota` on the PATH
piabrota := "nix run .#piabrota --"

# list the recipes
default:
    @just --list

# Short names for the daily recipes (`just b`, `just h`); `just --list` shows each beside its recipe.
alias b := build
alias c := check
alias h := remote-health
alias s := remote-specs
alias t := scala-test
alias p := site-pins

# the morning look, read only: the health of both boxes, their failed units, then every certificate from here
daily user="h0ffmann":
    a=0; b=0; c=0; \
    {{just_executable()}} remote-health {{user}} {{host}} || a=$?; \
    {{just_executable()}} remote-health {{user}} {{kvm4}} || b=$?; \
    for t in {{host}} {{kvm4}}; do echo "== failed units on $t"; ssh {{user}}@$t systemctl --failed --no-pager --legend=no; done; \
    {{just_executable()}} certs || c=$?; \
    [ "$a" = 0 ] && [ "$b" = 0 ] && [ "$c" = 0 ]

# open a shell on piabrota (box) or on piabrota2 (box2)
box user="h0ffmann":
    ssh {{user}}@{{host}}

box2 user="h0ffmann":
    ssh {{user}}@{{kvm4}}

# the last 100 lines of a unit's journal on a box, read only; `just logs hermes-agent h0ffmann {{kvm4}}`
logs unit user="h0ffmann" target=host:
    case '{{unit}}' in *[!a-zA-Z0-9@._-]*) echo "logs: not a unit name: {{unit}}" >&2; exit 2 ;; esac
    ssh {{user}}@{{target}} journalctl -u '{{unit}}' -n 100 --no-pager

# the open pull requests of this repository (needs gh)
prs:
    gh pr list --repo piabrota/nix-os

# the HTTPS certificate of every live name in scripts/domains.txt, from here, as a browser sees it (read-only; openssl); `just certs www.piabrota.art` checks one
certs *names:
    {{piabrota}} cert-check {{names}}

# build a host's system closure here, without deploying it (piabrota or piabrota2)
build node="piabrota":
    nix build .#nixosConfigurations.{{node}}.config.system.build.toplevel --print-build-logs

# what CI runs on a pull request
check:
    nix flake check --no-update-lock-file --print-build-logs
    nix run nixpkgs#nixpkgs-fmt -- --check flake.nix acme-retry.nix deploy.nix tools.nix loco.nix site.nix pgx.nix hermes.nix hermes-github.nix lofi.nix lofi/default.nix hosts/*/*.nix kubesolo-purge.nix observer.nix pgx/package.nix pgx/test.nix site/default.nix skills-site/default.nix ww3.nix ww3-site/default.nix closed.nix closed-site/default.nix hffmnn.nix hffmnn-site/default.nix site/data.nix site/hermes.nix apps.nix apps/notes/default.nix drawings/*.nix mockups/*.nix favicon.nix favicon/*.nix
    nix run nixpkgs#statix -- check .
    nix run nixpkgs#deadnix -- --fail .
    {{piabrota}} deepwiki-check








# the human and agent commit counts of each own repository, as lines to paste into mockups/data.nix (read-only, needs gh)
commit-counts:
    {{piabrota}} commit-counts




# build the personal feed from the real sources into a temporary folder; writes no state (needs network)
feeds-build:
    {{piabrota}} feed-build --config hermes/feeds/feeds.toml --out "$(mktemp -d)" --dry-run

# CVE report of the system closure (vulnix against the NVD; a report, many matches are false)
cves: build
    nix run --inputs-from . nixpkgs#vulnix -- --closure ./result || [ $? -eq 2 ]

# deploy one host by hand, as CI does (needs SSH to the box as `user`; magic rollback included)
deploy user="deploy" node="piabrota":
    nix run .#deploy-rs -- .#{{node}} --hostname {{host}} --ssh-user {{user}} --skip-checks

# move the marola-site pin (marola-site/default.nix) to marola-site's main, or to <rev>, and build it
marola-site-pin rev="":
    {{piabrota}} pins one marola-site {{rev}}

# move the room pin (room-site/default.nix) to room's main, or to <rev>, with both hashes, and build it
room-pin rev="":
    {{piabrota}} pins one room {{rev}}

# merge open PRs, in this order, onto origin/main in git's object store only, and name each that conflicts (the pr-stack skill); `just pr-stack-plan 221 222 223`
pr-stack-plan +prs:
    {{piabrota}} pr-stack plan {{prs}}

# a stack branch is ready for one merge commit: it contains origin/main and every PR head (the pr-stack skill); `just pr-stack-check claude/nix-os-pr-stack 221 222 223`
pr-stack-check branch +prs:
    {{piabrota}} pr-stack check {{branch}} {{prs}}

# write the README drawing (docs/drawings/mu.svg and its Desmos state) from drawings/*.nix
drawing:
    art=$(nix build .#mu-art --no-link --print-out-paths) && \
    cat "$art/mu.svg" > docs/drawings/mu.svg && \
    cat "$art/mu.desmos.json" > docs/drawings/mu.desmos.json

# build the site (site/, Gleam prerendered by Nix) into ./result-site, as the VPS gets it
site:
    nix build .#site --out-link result-site --print-build-logs

# build the closed-source website (closed-site/, at a pinned commit) into ./result-closed-site, as the VPS gets it
closed-site:
    nix build .#closed-site --out-link result-closed-site --print-build-logs

# build the profile website (hffmnn-site/, h0ffmann/h0ffmann at a pinned commit) into ./result-hffmnn-site, as the VPS gets it
hffmnn-site:
    nix build .#hffmnn-site --out-link result-hffmnn-site --print-build-logs

# build the ww3-gpu website (ww3-site/, Gleam prerendered by Nix) into ./result-ww3-site, as the VPS gets it
ww3-site:
    nix build .#ww3-site --out-link result-ww3-site --print-build-logs

# move the ww3-gpu pin (ww3-site/default.nix) to ww3-gpu's main, or to <rev>, and build the site
ww3-pin rev="":
    {{piabrota}} pins one ww3 {{rev}}

# move every website pin to the head of its source's main and build each site (piabrota pins); `just site-pins --list` only reads, `just site-pins closed proof` moves those
site-pins *args:
    {{piabrota}} pins all {{args}}

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
    {{piabrota}} figure-lock > docs/archify/figures.lock

# cheap and offline: every source has its PNG, shown in docs/FIGURES.md (pt/ in the wiki), the wiki has the same PNG, all match the last `just figure`
figure-check:
    {{piabrota}} figure-check

# print the specs of this machine
specs:
    {{piabrota}} specs

# check that the files Hermes loads into its context stay under its 32000-character cut
context-size:
    {{piabrota}} context-size

# list every package of the running system with its size, like pip freeze (--by-size to sort by size)
freeze *args:
    {{piabrota}} freeze {{args}}

# the same, of the VPS, over SSH
remote-freeze user="h0ffmann":
    ssh {{user}}@{{host}} piabrota freeze

# print the specs of the VPS over SSH
remote-specs user="h0ffmann":
    ssh {{user}}@{{host}} piabrota specs

# check on the VPS that Hermes's plugins, MCP servers, skills, omp and yt-dlp of the last deploy are live (read-only)
remote-hermes-check user="h0ffmann":
    ssh {{user}}@{{host}} piabrota hermes-check

# the health of a VPS and its units: memory, MemoryPeak against MemoryMax, disk, CPU (read-only); `just remote-health h0ffmann srv2125808.hstgr.cloud` asks the other box; exit 1 means a WARN or CRIT line
remote-health user="h0ffmann" target=host:
    ssh {{user}}@{{target}} piabrota kvm4-health || { s=$?; [ "$s" -ne 1 ] || echo "remote-health: {{target}} has a WARN or CRIT line, see above" >&2; exit "$s"; }

# restart the services the VPS has, over SSH, through sudo; a human only, never an agent (docs/DEPLOY.md, "Restarting the services by hand"). Groups: metrics web pgx room loco rig hermes, `list` (the plan only), default all. It asks `Proceed? [y/N]` on your terminal; flags go inside the quoted first argument: `just remote-restart "hermes --dry-run"`, `just remote-restart "all --yes"`; KVM 4: `just remote-restart all h0ffmann <address>`
remote-restart what="all" user="h0ffmann" target=host:
    case '{{what}}' in *[!a-z\ -]*) echo "remote-restart: the first argument takes letters, spaces and - only" >&2; exit 2 ;; esac
    ssh -t {{user}}@{{target}} "sudo /run/current-system/sw/bin/piabrota restart-services {{what}}"

# order again, over SSH through sudo, the certificates of a VPS that a browser refuses (self-signed or ending within 14 days); a human only, never an agent (docs/SITE.md, "Certificates"). `just remote-cert-renew skills.piabrota.art`, `just remote-cert-renew "all --dry-run"`; KVM 4: `just remote-cert-renew all h0ffmann {{kvm4}}`
remote-cert-renew what="all" user="h0ffmann" target=host:
    case '{{what}}' in *[!a-z0-9.\ -]*) echo "remote-cert-renew: the first argument takes names, spaces and - only" >&2; exit 2 ;; esac
    ssh {{user}}@{{target}} "sudo /run/current-system/sw/bin/piabrota cert-renew {{what}}"

# fix every refused certificate on both VPSs (remote-cert-renew all on each), then check every name from here; a human only
certs-fix user="h0ffmann":
    a=0; b=0; {{just_executable()}} remote-cert-renew all {{user}} {{host}} || a=$?; {{just_executable()}} remote-cert-renew all {{user}} {{kvm4}} || b=$?; {{just_executable()}} certs && [ "$a" = 0 ] && [ "$b" = 0 ]

# smoke check of the render path: a 30 s dummy video from ffmpeg alone, into video-lab/out/dummy (see docs/VIDEO-PIPELINE.md)
video-dummy:
    {{piabrota}} video-dummy

# the page's rules (pure Nix) and its HTTP fetch on the healthy fixture; the collector, probe and export are tested in `just scala-build`
metrics-test:
    nix build --no-link --print-build-logs .#checks.x86_64-linux.metrics-page
    {{piabrota}} metrics-preview --check

# open the metrics page on fixtures (healthy, stale, missing or hostile) at http://127.0.0.1:<port>/
metrics-preview case="healthy" port="8080":
    {{piabrota}} metrics-preview {{case}} {{port}}

# build the scripts' binary (scala/) into ./result with Nix, as CI and the boxes get it, tests included
scala-build:
    nix build .#piabrota --print-build-logs

# compile scala/ and run its tests in the dev shell, with the network (faster than scala-build while you edit)
scala-test:
    nix develop .#scala -c sh -c 'cd scala && scala-cli --power package --server=false --jvm system . -o ../.scala-piabrota --force && PIABROTA=$PWD/../.scala-piabrota scala-cli --power test --server=false --jvm system .'

# write scala/deps.lock.json again after a version changes in scala/project.scala (needs the network)
scala-lock:
    nix develop .#scala -c sh -c 'set -e; c=$(mktemp -d); cd scala; COURSIER_CACHE=$c scala-cli --power package --server=false --jvm system . -o "$c/piabrota" --force; COURSIER_CACHE=$c PIABROTA=$c/piabrota scala-cli --power test --server=false --jvm system .; scala-cli run --server=false --jvm system lock/Lock.scala -- "$c" deps.lock.json; rm -rf "$c"'
