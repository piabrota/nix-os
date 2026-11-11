#!/bin/sh
# Moves the ww3-gpu pin (ww3-site/default.nix) to a commit of h0ffmann/ww3-gpu: rev and the source
# hash, then builds the site with this flake's nixpkgs, so a pin that does not build never reaches a
# pull request.
#
#   sh scripts/ww3-pin.sh             (or: just ww3-pin)   the head of ww3-gpu's main
#   sh scripts/ww3-pin.sh <sha>       that commit
#
# It prints `old=<sha>` and `new=<sha>` on its last two lines, and `same=true` alone when the pin is
# already there (nothing is written). It needs `nix` with flakes and `git`; it reads h0ffmann/ww3-gpu
# anonymously, so it needs no token. It writes only ww3-site/default.nix and a `result-ww3-site`
# link. `.github/workflows/ww3-pin.yml` runs it.
set -eu

file=ww3-site/default.nix
repo=${WW3_REPO:-h0ffmann/ww3-gpu}
nix="nix --extra-experimental-features nix-command --extra-experimental-features flakes"

old=$(sed -n 's/^ *rev = "\([0-9a-f]\{40\}\)";$/\1/p' "$file")
[ -n "$old" ] || { echo "no rev in $file" >&2; exit 1; }

new=${1:-$(git ls-remote "https://github.com/$repo.git" refs/heads/main | cut -f1)}
case $new in
  *[!0-9a-f]* | "") echo "not a commit: $new" >&2; exit 1 ;;
esac
if [ "${#new}" != 40 ]; then echo "give the whole sha, 40 characters: $new" >&2; exit 1; fi
if [ "$new" = "$old" ]; then
  echo "ww3-gpu is pinned at $old already."
  echo "same=true"
  exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# fetchFromGitHub's hash is the NAR hash of the unpacked tarball, as `flake prefetch` gives it.
$nix flake prefetch --json "github:$repo/$new" >"$work/src.json"
src_hash=$(sed -n 's/.*"hash":"\(sha256-[^"]*\)".*/\1/p' "$work/src.json")
path=$(sed -n 's/.*"storePath":"\([^"]*\)".*/\1/p' "$work/src.json")
if [ -z "$src_hash" ] || [ ! -f "$path/docs/ADRs.md" ]; then echo "prefetch failed" >&2; exit 1; fi

sed -e "s|^\( *rev = \"\)$old\";|\1$new\";|" \
  -e "/^ *hash = \"sha256-/s|^\( *hash = \"\)[^\"]*\";|\1$src_hash\";|" \
  "$file" >"$work/default.nix"
if ! grep -q "rev = \"$new\"" "$work/default.nix" || ! grep -q "$src_hash" "$work/default.nix"; then
  echo "could not rewrite $file" >&2
  exit 1
fi
cp "$work/default.nix" "$file"

# The build, as ww3.nix calls it: the content generator, the tests, the four pages.
$nix build --impure -o result-ww3-site --print-build-logs --expr \
  "let f = builtins.getFlake (toString ./.); pkgs = import f.inputs.nixpkgs { system = builtins.currentSystem; }; in pkgs.callPackage ./ww3-site { }"
test -f result-ww3-site/index.html

echo "old=$old"
echo "new=$new"
