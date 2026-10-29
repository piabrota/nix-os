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
    nix run nixpkgs#nixpkgs-fmt -- --check flake.nix deploy.nix tools.nix
    nix run nixpkgs#shellcheck -- scripts/*.sh

# deploy by hand, as CI does (needs SSH to the box as `user`; magic rollback included)
deploy user="deploy":
    nix run .#deploy-rs -- .#piabrota --hostname {{host}} --ssh-user {{user}} --skip-checks

# write the README drawing (docs/drawings/mu.svg and its Desmos state) from drawings/
drawing:
    cargo run -q --manifest-path drawings/Cargo.toml > docs/drawings/mu.svg
    cargo run -q --manifest-path drawings/Cargo.toml -- desmos > docs/drawings/mu.desmos.json

# print the specs of this machine
specs:
    sh scripts/specs.sh

# print the specs of the VPS over SSH
remote-specs user="h0ffmann":
    ssh {{user}}@{{host}} sh -s < scripts/specs.sh
