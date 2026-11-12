#!/bin/sh
# Moves every website pin to the head of its source's main, in one go: rev, the source hash and
# the numbers each site reads from its commit, then builds each site with this flake's nixpkgs, so
# a pin that does not build never reaches a pull request. ww3 and room go through their own
# scripts (scripts/ww3-pin.sh, scripts/room-pin.sh); the others are moved here.
#
#   sh scripts/site-pins.sh                 (or: just site-pins)   every site
#   sh scripts/site-pins.sh closed proof    those sites only
#   sh scripts/site-pins.sh --list          each site, its pin and the head of its main; writes nothing
#   PIN_BUILD=0 sh scripts/site-pins.sh     move the pins and build nothing (CI's flake check builds them)
#
# One line per site: `<site> same <sha>`, `<site> moved <old> <new>` or `<site> FAILED <step>`. A
# site that fails is put back as it was and the others go on; the exit status is 1 if one failed.
# It needs `nix` with flakes and `git`; it reads the sources anonymously, so it needs no token. It
# writes only the pinned files below and `result-<site>` links. The site-pins skill
# (hermes/skills/site-pins) says how to open the pull request.
set -eu

# site | repository | file | name of the rev binding | what else moves | file the build must have
sites='ww3|h0ffmann/ww3-gpu|ww3-site/default.nix|rev|script|index.html
closed|h0ffmann/closed-source|closed-site/default.nix|rev|commits|index.html
hffmnn|h0ffmann/h0ffmann|hffmnn-site/default.nix|rev|readme|index.html
marola-site|marola-dev/marola-site|marola-site/default.nix|rev|-|bin/marola-server
skills|piabrota/skills|skills-site/default.nix|rev|-|index.html
proof|h0ffmann/proof|proof-site/default.nix|proofRev|-|index.html
pirsig|piabrota/pirsig|proof-site/pirsig.nix|pirsigRev|-|index.html
room|piabrota/room|room-site/default.nix|rev|script|index.html'

nix="nix --extra-experimental-features nix-command --extra-experimental-features flakes"
build=${PIN_BUILD:-1}
list=0
if [ "${1:-}" = "--list" ]; then list=1; shift; fi
wanted=" $* "

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

head_of() { git ls-remote "https://github.com/$1.git" refs/heads/main | cut -f1; }

# The 40-character sha bound to <name> in <file>: `<name> = "<sha>";`.
rev_of() { sed -n "s/^ *$2 = \"\([0-9a-f]\{40\}\)\";.*/\1/p" "$1" | head -n 1; }

# The first `hash = "sha256-…";` after the line `repo = "<repo>";`: the hash of that source.
hash_of() {
  awk -v repo="repo = \"$2\";" '
    index($0, repo) { found = 1; next }
    found && /hash = "sha256-/ { sub(/.*hash = "/, ""); sub(/".*/, ""); print; exit }
  ' "$1"
}

build_site() { # site file path-the-output-must-have
  [ "$build" = 1 ] || return 0
  $nix build --impure -o "result-$1" --print-build-logs --expr \
    "let f = builtins.getFlake (toString ./.); pkgs = import f.inputs.nixpkgs { system = builtins.currentSystem; }; in pkgs.callPackage ./$2 { }" &&
    test -e "result-$1/$3"
}

move() { # site repo file revname extra must
  site=$1 repo=$2 file=$3 revname=$4 extra=$5 must=$6
  old=$(rev_of "$file" "$revname")
  [ -n "$old" ] || { echo "$site FAILED no $revname in $file"; return 1; }
  new=$(head_of "$repo")
  case $new in
    *[!0-9a-f]* | "") echo "$site FAILED the head of $repo's main"; return 1 ;;
  esac
  if [ "$list" = 1 ]; then
    if [ "$new" = "$old" ]; then echo "$site same $old"; else echo "$site behind $old $new"; fi
    return 0
  fi
  if [ "$new" = "$old" ]; then echo "$site same $old"; return 0; fi

  if [ "$extra" = script ]; then
    if PIN_BUILD=$build sh "scripts/$site-pin.sh" "$new" >"$work/$site.log" 2>&1; then
      echo "$site moved $old $new"
      return 0
    fi
    tail -n 20 "$work/$site.log" >&2
    git checkout -- "$file" 2>/dev/null || true
    echo "$site FAILED scripts/$site-pin.sh"
    return 1
  fi

  cp "$file" "$work/$site.orig"
  fail() { cp "$work/$site.orig" "$file"; echo "$site FAILED $1"; return 1; }

  # fetchFromGitHub's hash is the NAR hash of the unpacked tarball, as `flake prefetch` gives it.
  # Where the tarball cannot be had, the same tree over git gives the same hash (a source with
  # export-ignore in .gitattributes would differ; the build then fails on the hash).
  if ! $nix flake prefetch --json "github:$repo/$new" >"$work/$site.json"; then
    $nix flake prefetch --json "git+https://github.com/$repo?rev=$new&shallow=1" >"$work/$site.json" ||
      { fail prefetch; return 1; }
  fi
  src_hash=$(sed -n 's/.*"hash":"\(sha256-[^"]*\)".*/\1/p' "$work/$site.json")
  old_hash=$(hash_of "$file" "${repo#*/}")
  if [ -z "$src_hash" ] || [ -z "$old_hash" ]; then fail "the source hash"; return 1; fi

  set -- -e "s|^\( *$revname = \"\)$old\";|\1$new\";|" -e "s|\"$old_hash\";|\"$src_hash\";|"
  case $extra in
    commits | readme)
      # A clone with no blobs is enough for a count, and stays small.
      rm -rf "$work/$site.git"
      git clone --quiet --bare --filter=blob:none "https://github.com/$repo.git" "$work/$site.git" ||
        { fail clone; return 1; }
      ;;
  esac
  case $extra in
    commits)
      commits=$(git -C "$work/$site.git" rev-list --count "$new")
      case $commits in "" | *[!0-9]*) fail "the commit count"; return 1 ;; esac
      set -- "$@" -e "s|^\( *commits = \)[0-9]*;|\1$commits;|"
      ;;
    readme)
      # What the profile's generator asks git: `git log --follow --format=%as -- README.md`.
      git -C "$work/$site.git" log --follow --format=%as "$new" -- README.md >"$work/$site.readme"
      count=$(wc -l <"$work/$site.readme" | tr -d ' ')
      first=$(tail -n 1 "$work/$site.readme")
      case $count in "" | 0 | *[!0-9]*) fail "the README commits"; return 1 ;; esac
      set -- "$@" -e "s|^\( *readmeCommits = \)[0-9]*;|\1$count;|" \
        -e "s|^\( *readmeFirst = \"\)[0-9-]*\";|\1$first\";|"
      ;;
  esac

  sed "$@" "$work/$site.orig" >"$file"
  if ! grep -q "$revname = \"$new\"" "$file" || ! grep -q "\"$src_hash\"" "$file"; then
    fail "the rewrite of $file"
    return 1
  fi
  build_site "$site" "$file" "$must" || { fail build; return 1; }
  echo "$site moved $old $new"
}

status=0
echo "$sites" >"$work/sites"
while IFS='|' read -r site repo file revname extra must; do
  case $wanted in "  " | *" $site "*) ;; *) continue ;; esac
  move "$site" "$repo" "$file" "$revname" "$extra" "$must" </dev/null || status=1
done <"$work/sites"
exit $status
