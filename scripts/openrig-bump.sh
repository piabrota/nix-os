#!/bin/sh
# Bump the OpenRig pin of openrig/package.nix: `version`, `commit`, the source `hash` and
# `npmDepsHash`, and nothing else. The daily workflow (scripts/openrig-bump.workflow.yml) runs it.
# POSIX sh, jq, sed, curl or gh, and nix. It reads GitHub only and writes only the package file
# (and the files named by --output). The method is in docs/OPENRIG.md, "The daily version bump".
set -eu

REPO=mvschwarz/openrig
DEFAULT_API=https://api.github.com
API=${OPENRIG_BUMP_API:-$DEFAULT_API}
MIGRATIONS=packages/daemon/src/db/migrations

usage() {
  cat <<'EOF'
usage: scripts/openrig-bump.sh [options]

Move the pin of openrig/package.nix to a newer OpenRig: the HEAD of the upstream main branch
(default), or the latest release. Rewrites exactly four lines: version, commit, the source hash
(inside fetchFromGitHub) and npmDepsHash.

options:
  --check            print the pin and the newest candidate; change nothing.
                     Exit 0 when the pin is current, 10 when a newer one exists.
  --dry-run          do every step except the write to the package file
  --verify           only prove the method: recompute both hashes for the CURRENT pin and
                     compare them with the package file (exit 0 equal, 1 different)
  --channel main|release
                     main (default): the HEAD of the branch main. release: the latest release
                     that is neither a draft nor a prerelease, and never older than the pin
  --to REF           use this tag, branch or commit instead of the channel's choice.
                     A tag older than the pin, or a commit behind it, is refused
  --output FILE      write old, new, old_commit, commit, compare_url, ahead_by, committed_at,
                     migrations and changed as key=value lines to FILE (for $GITHUB_OUTPUT),
                     and the change notes (Markdown) to FILE.notes.md
  --package FILE     the package file (default: openrig/package.nix next to this script's
                     repository); flake.lock is read from the folder above its folder
  -h, --help         this text

exit codes: 0 done or current, 10 a newer pin exists (--check), 1 failure, 2 wrong usage.

environment:
  GH_TOKEN or GITHUB_TOKEN   used by gh or curl; without one the API allows 60 requests an hour
  OPENRIG_BUMP_API           API root, for tests (default https://api.github.com)
  OPENRIG_BUMP_RELEASE_JSON  a file used in place of the answer of releases/latest, for tests
EOF
}

say() { printf '%s\n' "$*"; }
warn() { printf 'openrig-bump: %s\n' "$*" >&2; }
die() {
  warn "error: $*"
  exit 1
}
bad_usage() {
  warn "$*"
  warn "try --help"
  exit 2
}

check=0
dry=0
verify=0
channel=main
to=
output=
pkg=
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

while [ $# -gt 0 ]; do
  case $1 in
    --check) check=1 ;;
    --dry-run) dry=1 ;;
    --verify) verify=1 ;;
    --channel)
      [ $# -ge 2 ] || bad_usage "--channel needs main or release"
      channel=$2
      shift
      ;;
    --to)
      [ $# -ge 2 ] || bad_usage "--to needs a tag or a commit"
      to=$2
      shift
      ;;
    --output)
      [ $# -ge 2 ] || bad_usage "--output needs a file name"
      output=$2
      shift
      ;;
    --package)
      [ $# -ge 2 ] || bad_usage "--package needs a file name"
      pkg=$2
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) bad_usage "unknown option: $1" ;;
  esac
  shift
done

case $channel in main | release) ;; *) bad_usage "--channel is main or release, not '$channel'" ;; esac
if [ -n "$to" ]; then
  printf '%s' "$to" | grep -Eq '^[A-Za-z0-9._/-]{1,100}$' || bad_usage "--to: '$to' is not a valid ref"
  case $to in -* | */ | /* | *..*) bad_usage "--to: '$to' is not a valid ref" ;; esac
fi
pkg=${pkg:-$root/openrig/package.nix}
lock=$(dirname -- "$pkg")/../flake.lock
[ -f "$pkg" ] || die "no package file: $pkg"

for tool in jq sed grep sort mktemp; do
  command -v "$tool" >/dev/null 2>&1 || die "needed tool not found: $tool"
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

token=${GH_TOKEN:-${GITHUB_TOKEN:-}}
if [ -z "$token" ]; then
  warn "no GH_TOKEN or GITHUB_TOKEN: the GitHub API allows 60 requests an hour without one"
fi

# --- GitHub ----------------------------------------------------------------------------------

# api PATH: the JSON answer on stdout. Return 4 for "not found"; any other failure ends the script.
api() {
  if [ -n "$token" ] && [ "$API" = "$DEFAULT_API" ] && command -v gh >/dev/null 2>&1; then
    if gh api "$1" >"$tmp/body" 2>"$tmp/err"; then
      cat "$tmp/body"
      return 0
    fi
    if grep -q 'HTTP 404' "$tmp/err"; then return 4; fi
    die "gh api $1 failed: $(tr '\n' ' ' <"$tmp/err" | cut -c1-200)"
  fi
  command -v curl >/dev/null 2>&1 || die "neither gh (with a token) nor curl is available"
  # The token goes to curl on stdin, so it never shows in the process list.
  rc=0
  {
    printf 'header = "Accept: application/vnd.github+json"\n'
    printf 'header = "X-GitHub-Api-Version: 2022-11-28"\n'
    if [ -n "$token" ]; then printf 'header = "Authorization: Bearer %s"\n' "$token"; fi
  } | curl -sS -K - -m 40 --connect-timeout 10 --retry 2 --retry-delay 1 \
    -o "$tmp/body" -w '%{http_code}' "$API/$1" >"$tmp/code" 2>"$tmp/err" || rc=$?
  [ "$rc" -eq 0 ] || die "cannot reach $API (curl exit $rc): $(tr '\n' ' ' <"$tmp/err" | cut -c1-200)"
  case $(cat "$tmp/code") in
    200 | 000)
      cat "$tmp/body"
      return 0
      ;;
    404 | 422) return 4 ;;
    403 | 429) die "GitHub refused $1 (rate limit or no access): set GH_TOKEN or GITHUB_TOKEN" ;;
    *) die "GitHub answered HTTP $(cat "$tmp/code") for $1" ;;
  esac
}

# --- the pin ---------------------------------------------------------------------------------

# pin_line REGEX: the one value captured by REGEX in a whole line of the package file.
pin_line() {
  found=$(sed -n "s|^$1\$|\\1|p" "$pkg")
  [ -n "$found" ] || die "$pkg: no line matches $1"
  [ "$(printf '%s\n' "$found" | wc -l)" -eq 1 ] || die "$pkg: more than one line matches $1"
  printf '%s\n' "$found"
}

RE_VERSION='  version = "\([^"]*\)";'
RE_COMMIT='  commit = "\([0-9a-f]\{40\}\)";'
RE_HASH='    hash = "\(sha256-[A-Za-z0-9+/]*=*\)";'
RE_NPM='  npmDepsHash = "\(sha256-[A-Za-z0-9+/]*=*\)";'

version=$(pin_line "$RE_VERSION")
old_commit=$(pin_line "$RE_COMMIT")
old_hash=$(pin_line "$RE_HASH")
old_npm=$(pin_line "$RE_NPM")
old_base=${version%%[-+]*}
short() { printf '%.7s' "$1"; }

# --- the hashes ------------------------------------------------------------------------------

nixq() {
  nix --extra-experimental-features 'nix-command flakes' "$@"
}

# prefetch COMMIT: sets src_hash (as fetchFromGitHub computes it) and src_path (the store path).
prefetch() {
  if [ -n "$token" ]; then
    NIX_CONFIG="${NIX_CONFIG:-}
access-tokens = github.com=$token"
    export NIX_CONFIG
  fi
  nixq flake prefetch "github:$REPO/$1" --json >"$tmp/prefetch.json" 2>"$tmp/prefetch.err" ||
    die "nix flake prefetch of $1 failed: $(tail -n 3 "$tmp/prefetch.err" | tr '\n' ' ')"
  src_hash=$(jq -r '.hash // empty' "$tmp/prefetch.json")
  src_path=$(jq -r '.storePath // empty' "$tmp/prefetch.json")
  case $src_hash in sha256-*) ;; *) die "no source hash from nix flake prefetch for $1" ;; esac
  [ -d "$src_path" ] || die "no source path from nix flake prefetch for $1"
}

# npm_hash LOCKFILE: sets npm_hash_value, with the prefetch-npm-deps of this flake's own nixpkgs, so
# its fetcher is the one buildNpmPackage uses (fetcher version 1, the default there).
npm_hash() {
  [ -f "$1" ] || die "no package-lock.json in the source: $1"
  [ -f "$lock" ] || die "no flake.lock at $lock"
  nixpkgs_rev=$(jq -r '.nodes.nixpkgs.locked.rev // empty' "$lock")
  [ -n "$nixpkgs_rev" ] || die "no nixpkgs rev in $lock"
  nixq shell "github:NixOS/nixpkgs/$nixpkgs_rev#prefetch-npm-deps" -c prefetch-npm-deps "$1" \
    >"$tmp/npm.out" 2>"$tmp/npm.err" ||
    die "prefetch-npm-deps failed: $(tail -n 3 "$tmp/npm.err" | tr '\n' ' ')"
  npm_hash_value=$(tail -n 1 "$tmp/npm.out")
  case $npm_hash_value in sha256-*) ;; *) die "prefetch-npm-deps gave no hash" ;; esac
}

# prove_method: recompute both hashes for the pinned commit. They must equal the package file, or
# the method (nix, nixpkgs' fetcher) is not the one that wrote it and a new hash cannot be trusted.
prove_method() {
  prefetch "$old_commit"
  old_src_path=$src_path
  npm_hash "$old_src_path/package-lock.json"
  say "proof for the pin $(short "$old_commit"):"
  say "  source hash  computed $src_hash"
  say "               in file   $old_hash"
  say "  npmDepsHash  computed $npm_hash_value"
  say "               in file   $old_npm"
  [ "$src_hash" = "$old_hash" ] || die "the source hash of the pin differs from the package file: the method is not trusted"
  [ "$npm_hash_value" = "$old_npm" ] || die "npmDepsHash of the pin differs from the package file: the method is not trusted"
  say "  both equal"
}

if [ "$verify" -eq 1 ]; then
  prove_method
  exit 0
fi

# --- the candidate ---------------------------------------------------------------------------

kind=main
tag=
if [ -n "$to" ]; then
  ref=$to
  if printf '%s' "$to" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
    kind=release
    tag=$to
  fi
elif [ "$channel" = release ]; then
  kind=release
  if [ -n "${OPENRIG_BUMP_RELEASE_JSON:-}" ]; then
    rel=$(cat "$OPENRIG_BUMP_RELEASE_JSON") || die "cannot read $OPENRIG_BUMP_RELEASE_JSON"
  else
    rel=$(api "repos/$REPO/releases/latest") || die "GitHub has no latest release of $REPO"
  fi
  printf '%s' "$rel" | jq -e . >/dev/null 2>&1 || die "the release answer is not JSON"
  tag=$(printf '%s' "$rel" | jq -r '.tag_name // empty')
  [ "$(printf '%s' "$rel" | jq -r '.draft // false')" = false ] || die "release $tag is a draft: refused"
  [ "$(printf '%s' "$rel" | jq -r '.prerelease // false')" = false ] || die "release $tag is a prerelease: refused"
  printf '%s' "$tag" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$' || die "release tag '$tag' is not vX.Y.Z: refused"
  ref=$tag
else
  ref=main
fi

rc=0
cand=$(api "repos/$REPO/commits/$ref") || rc=$?
[ "$rc" -ne 4 ] || die "ref not found in $REPO: $ref"
[ "$rc" -eq 0 ] || exit 1
new_commit=$(printf '%s' "$cand" | jq -r '.sha // empty')
committed_at=$(printf '%s' "$cand" | jq -r '.commit.committer.date // empty')
printf '%s' "$new_commit" | grep -Eq '^[0-9a-f]{40}$' || die "no commit sha for $ref in the GitHub answer"
printf '%s' "$committed_at" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$' || die "no commit date for $ref in the GitHub answer"

status=identical
ahead_by=0
behind_by=0
compare_url="https://github.com/$REPO/compare/$old_commit...$new_commit"
if [ "$new_commit" != "$old_commit" ]; then
  rc=0
  cmp_json=$(api "repos/$REPO/compare/$old_commit...$new_commit?per_page=1") || rc=$?
  [ "$rc" -ne 4 ] || die "GitHub cannot compare the pin $(short "$old_commit") with $(short "$new_commit")"
  [ "$rc" -eq 0 ] || exit 1
  status=$(printf '%s' "$cmp_json" | jq -r '.status // empty')
  ahead_by=$(printf '%s' "$cmp_json" | jq -r '.ahead_by // empty')
  behind_by=$(printf '%s' "$cmp_json" | jq -r '.behind_by // empty')
  case $ahead_by$behind_by in '' | *[!0-9]*) die "the compare answer has no ahead_by and behind_by" ;; esac
  url=$(printf '%s' "$cmp_json" | jq -r '.html_url // empty')
  case $url in "https://github.com/$REPO/compare/"*) compare_url=$url ;; esac
fi

# state: current (nothing newer), newer, or older (going back: refused).
state=newer
if [ "$new_commit" = "$old_commit" ]; then
  state=current
elif [ "$kind" = release ]; then
  # A release is cut from its own branch, so the compare of commits says "diverged" and cannot
  # tell the order. The versions do.
  new_base=${tag#v}
  if [ "$new_base" = "$old_base" ]; then
    state=current
  elif [ "$(printf '%s\n%s\n' "$old_base" "$new_base" | sort -V | tail -n 1)" = "$old_base" ]; then
    state=older
  fi
else
  if [ "$ahead_by" -eq 0 ]; then
    if [ "$behind_by" -gt 0 ]; then state=older; else state=current; fi
  fi
fi

say "pin:     $version  $(short "$old_commit")"
say "latest:  ${tag:-$ref}  $(short "$new_commit")  committed $committed_at  ahead $ahead_by behind $behind_by ($status)"
say "compare: $compare_url"

if [ "$state" = older ]; then
  if [ -z "$to" ] && [ "$kind" = release ]; then
    say "the pin ($version) is newer than the latest release (${tag}): nothing to do"
    state=current
  else
    die "$ref is older than the pin ($version): the script never goes back"
  fi
fi

write_output() { # write_output CHANGED NEW MIGRATIONS
  [ -n "$output" ] || return 0
  {
    printf 'changed=%s\n' "$1"
    printf 'old=%s\n' "$version"
    printf 'new=%s\n' "$2"
    printf 'old_commit=%s\n' "$old_commit"
    printf 'commit=%s\n' "$new_commit"
    printf 'compare_url=%s\n' "$compare_url"
    printf 'ahead_by=%s\n' "$ahead_by"
    printf 'committed_at=%s\n' "$committed_at"
    printf 'migrations=%s\n' "$3"
  } >"$output"
}

if [ "$state" = current ]; then
  say "state:   current"
  write_output false "$version" 0
  exit 0
fi
say "state:   newer"

if [ "$check" -eq 1 ]; then
  write_output true "" 0
  exit 10
fi

# --- the new hashes and version --------------------------------------------------------------

prove_method
old_src_path=$src_path
prefetch "$new_commit"
new_src_path=$src_path
new_src_hash=$src_hash
npm_hash "$new_src_path/package-lock.json"
new_npm=$npm_hash_value

if [ "$kind" = release ]; then
  new_version=${tag#v}
else
  # package.json of upstream main still says 0.7.1, below the pin: a daemon that reports it would
  # fail a bundle's min_daemon_version check (compareVersions in the daemon's routes/bundles.ts
  # ignores a prerelease tag). So the base is the highest of package.json, the newest heading of
  # CHANGELOG.md and the base of the current pin. The tag keeps the commit in the version.
  pj=$(jq -r '.version // empty' "$new_src_path/package.json")
  cl=$(sed -n 's/^## \[\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)\].*/\1/p' "$new_src_path/CHANGELOG.md" | sed -n 1p)
  base=$(printf '%s\n%s\n%s\n' "$pj" "$cl" "$old_base" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1)
  [ -n "$base" ] || die "no base version in package.json, CHANGELOG.md or the pin"
  new_version=$base-main.$(short "$new_commit")
fi
printf '%s' "$new_version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-main\.[0-9a-f]{7})?$' || die "unexpected version string: $new_version"
say "new:     $new_version  $new_commit"
say "         source hash $new_src_hash"
say "         npmDepsHash $new_npm"

# --- the notes -------------------------------------------------------------------------------

mig_added=$tmp/mig.added
mig_removed=$tmp/mig.removed
mig_modified=$tmp/mig.modified
: >"$mig_added"
: >"$mig_removed"
: >"$mig_modified"
if [ -d "$old_src_path/$MIGRATIONS" ] && [ -d "$new_src_path/$MIGRATIONS" ]; then
  (cd "$old_src_path/$MIGRATIONS" && find . -type f | sort) >"$tmp/mig.old"
  (cd "$new_src_path/$MIGRATIONS" && find . -type f | sort) >"$tmp/mig.new"
  comm -13 "$tmp/mig.old" "$tmp/mig.new" | sed 's|^\./||' >"$mig_added"
  comm -23 "$tmp/mig.old" "$tmp/mig.new" | sed 's|^\./||' >"$mig_removed"
  comm -12 "$tmp/mig.old" "$tmp/mig.new" | while IFS= read -r f; do
    cmp -s "$old_src_path/$MIGRATIONS/$f" "$new_src_path/$MIGRATIONS/$f" || printf '%s\n' "${f#./}"
  done >"$mig_modified"
else
  warn "no $MIGRATIONS in one of the two source trees: the migration list is empty"
fi
migrations=$(cat "$mig_added" "$mig_removed" "$mig_modified" | wc -l | tr -d ' ')

# The newest subjects, from the commit list of the new commit. Upstream text goes into a code
# fence, with backticks removed, so it can never ping a user or link an issue of this repository.
want=60
[ "$ahead_by" -ge "$want" ] || want=$ahead_by
subjects=$tmp/subjects
: >"$subjects"
if [ "$want" -gt 0 ]; then
  rc=0
  list=$(api "repos/$REPO/commits?sha=$new_commit&per_page=$want") || rc=$?
  if [ "$rc" -eq 0 ]; then
    printf '%s' "$list" | jq -r '.[] | "\(.sha[:7]) \((.commit.message | split("\n")[0])[:120] | gsub("`"; "\u0027"))"' >"$subjects" ||
      warn "the commit list is not readable: the notes have no subjects"
  else
    warn "no commit list for the notes"
  fi
fi

list_migrations() { # list_migrations WORD FILE
  while IFS= read -r f; do say "- $1: \`$f\`"; done <"$2"
}

notes() {
  say "<details><summary>Commits since the pin (newest first, $(wc -l <"$subjects" | tr -d ' ') of $ahead_by)</summary>"
  say
  say '```text'
  cat "$subjects"
  say '```'
  say
  say "</details>"
  say
  say "<details><summary>Database migrations changed ($migrations)</summary>"
  say
  if [ "$migrations" -eq 0 ]; then
    say "None under \`$MIGRATIONS\`."
  else
    list_migrations added "$mig_added"
    list_migrations modified "$mig_modified"
    list_migrations removed "$mig_removed"
  fi
  say
  say "</details>"
}

# --- the edit --------------------------------------------------------------------------------

if [ "$dry" -eq 1 ]; then
  say "dry run: $pkg is not changed"
else
  new_file=$(mktemp "$pkg.XXXXXX")
  trap 'rm -rf "$tmp" "$new_file"' EXIT HUP INT TERM
  cp -p "$pkg" "$new_file"
  sed -e "s|^  version = \"[^\"]*\";\$|  version = \"$new_version\";|" \
    -e "s|^  commit = \"[0-9a-f]\{40\}\";\$|  commit = \"$new_commit\";|" \
    -e "s|^    hash = \"sha256-[A-Za-z0-9+/]*=*\";\$|    hash = \"$new_src_hash\";|" \
    -e "s|^  npmDepsHash = \"sha256-[A-Za-z0-9+/]*=*\";\$|  npmDepsHash = \"$new_npm\";|" \
    "$pkg" >"$new_file"

  # Exactly the four lines, and the file must still parse. Only then it replaces the old one.
  diff "$pkg" "$new_file" | grep '^>' >"$tmp/changed" || true
  n=$(wc -l <"$tmp/changed" | tr -d ' ')
  [ "$n" -ge 1 ] && [ "$n" -le 4 ] || die "the edit changed $n lines, not one to four: $pkg is untouched"
  [ "$(diff "$pkg" "$new_file" | grep -c '^<')" -eq "$n" ] || die "the edit removed a different number of lines than it added: $pkg is untouched"
  if grep -Ev '^> (  version = "|  commit = "|    hash = "|  npmDepsHash = ")' "$tmp/changed" >"$tmp/stray"; then
    die "the edit changed a line it must not: $(sed -n 1p "$tmp/stray")"
  fi
  if command -v nix-instantiate >/dev/null 2>&1; then
    nix-instantiate --parse "$new_file" >/dev/null 2>"$tmp/parse.err" || die "the new package file does not parse: $(head -n 3 "$tmp/parse.err")"
  else
    warn "nix-instantiate not found: the new file was not parsed"
  fi
  mv -f "$new_file" "$pkg"
  say "wrote $pkg ($n lines changed):"
  sed 's/^>/ /' "$tmp/changed"
  if command -v git >/dev/null 2>&1 && git -C "$(dirname -- "$pkg")" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "$(dirname -- "$pkg")" diff --stat -- "$pkg" || true
  fi
fi

if [ -n "$output" ]; then
  write_output true "$new_version" "$migrations"
  notes >"$output.notes.md"
  say "wrote $output and $output.notes.md"
fi
