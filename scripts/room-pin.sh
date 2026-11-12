#!/bin/sh
# Moves the room pin (room-site/default.nix) to a commit of piabrota/room: rev, the source hash,
# npmDepsHash and version, then builds the room package with this flake's nixpkgs, so a pin that
# does not build never reaches a pull request.
#
#   sh scripts/room-pin.sh             (or: just room-pin)   the head of room's main
#   sh scripts/room-pin.sh <sha>       that commit
#
# It prints the old and the new commit as `old=<sha>` and `new=<sha>` on its last two lines, and
# `same=true` alone when the pin is already there (nothing is written). It needs `nix` with flakes
# and `git`; it reads piabrota/room anonymously, so it needs no token. It writes only
# room-site/default.nix and a `result-room` link. `.github/workflows/room-pin.yml` runs it.
set -eu

file=room-site/default.nix
repo=${ROOM_REPO:-piabrota/room}
nix="nix --extra-experimental-features nix-command --extra-experimental-features flakes"

old=$(sed -n 's/^ *rev = "\([0-9a-f]\{40\}\)";$/\1/p' "$file")
[ -n "$old" ] || { echo "no rev in $file" >&2; exit 1; }

new=${1:-$(git ls-remote "https://github.com/$repo.git" refs/heads/main | cut -f1)}
case $new in
  *[!0-9a-f]* | "") echo "not a commit: $new" >&2; exit 1 ;;
esac
if [ "${#new}" != 40 ]; then echo "give the whole sha, 40 characters: $new" >&2; exit 1; fi
if [ "$new" = "$old" ]; then
  echo "The room is pinned at $old already."
  echo "same=true"
  exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# The source: fetchFromGitHub's hash is the NAR hash of the unpacked tarball, as `flake prefetch`
# gives it. The flake's lastModified dates the version.
$nix flake prefetch --json "github:$repo/$new" >"$work/src.json"
src_hash=$(sed -n 's/.*"hash":"\(sha256-[^"]*\)".*/\1/p' "$work/src.json")
path=$(sed -n 's/.*"storePath":"\([^"]*\)".*/\1/p' "$work/src.json")
stamp=$(sed -n 's/.*"lastModified":\([0-9]*\).*/\1/p' "$work/src.json")
if [ -z "$src_hash" ] || [ ! -f "$path/package-lock.json" ]; then echo "prefetch failed" >&2; exit 1; fi
day=$(date -u -d "@$stamp" +%Y-%m-%d 2>/dev/null || date -u -r "$stamp" +%Y-%m-%d)

# The npm packages: the hash of package-lock.json's packages.
npm_hash=$($nix run nixpkgs#prefetch-npm-deps -- "$path/package-lock.json" | tail -n 1)
case $npm_hash in sha256-*) ;; *) echo "prefetch-npm-deps failed: $npm_hash" >&2; exit 1 ;; esac

sed -e "s|^\( *version = \"\)[^\"]*\";|\10-unstable-$day\";|" \
  -e "s|^\( *rev = \"\)$old\";|\1$new\";|" \
  -e "/^ *rev = /{n;s|^\( *hash = \"\)[^\"]*\";|\1$src_hash\";|;}" \
  -e "s|^\( *npmDepsHash = \"\)[^\"]*\";|\1$npm_hash\";|" \
  "$file" >"$work/default.nix"
if ! grep -q "rev = \"$new\"" "$work/default.nix" || ! grep -q "$src_hash" "$work/default.nix"; then
  echo "could not rewrite $file" >&2
  exit 1
fi
cp "$work/default.nix" "$file"

# The build, as room.nix calls it: npm ci, vite build, allowedReferences = [ ].
if [ "${PIN_BUILD:-1}" = 1 ]; then
  $nix build --impure -o result-room --print-build-logs --expr \
    "let f = builtins.getFlake (toString ./.); pkgs = import f.inputs.nixpkgs { system = builtins.currentSystem; }; in pkgs.callPackage ./room-site { }"
  test -f result-room/index.html
fi

echo "old=$old"
echo "new=$new"
