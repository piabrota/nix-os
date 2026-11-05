#!/usr/bin/env bash
# Export the skills that Hermes loads to piabrota/skills and open or update a PR.
# Cron runs it once a day. It prints nothing when there is nothing to do.
#
# Environment (all optional):
#   SKILLS_DIR   the skills of Hermes          ($HOME/.hermes/skills)
#   HERMES_HOME  the home of Hermes            ($HOME/.hermes)
#   REPO_DIR     a clone of piabrota/skills    (/var/lib/hermes/workspace/skills-src)
#   TOKEN_FILE   the GitHub token file         (/run/hermes-github/piabrota)
#   REPO         the GitHub repository         (piabrota/skills)
#   DRY_RUN      1 = no git push and no gh call; print what would happen
#   OUT_PATCH    a file path: write the commit there as a patch

# -E: the ERR trap also fires inside functions.
set -eEuo pipefail

# Cron runs this script with the PATH of the hermes-agent unit. It has no awk and no perl.
# The system profile has them, so add it at the end: the unit's own tools keep their order.
export PATH="$PATH:/run/current-system/sw/bin"

# A missing tool must stop the run now, not half way through the copy.
for tool in awk perl git gh jq grep sed find sort diff mktemp date cat cut head tail cp rm mkdir chmod; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "skills export failed: $tool is not on the PATH"
    exit 1
  fi
done

STEP="start"
BODY=""
NAMES=()
DIRS=()
ORIGINS=()
LICENSES=()
AUTHORS=()
DUPS=()
OWNED=()
declare -A SEEN=()
NAME_RE='^[A-Za-z0-9][A-Za-z0-9._-]*$'
BRANCH=""
PR_URL=""
CHECK_EDITED=0

# Any failed command ends here with one line on stdout.
trap 'echo "skills export failed: $STEP"; exit 1' ERR
trap '[ -z "$BODY" ] || rm -f "$BODY"' EXIT

SKILLS_DIR=${SKILLS_DIR:-$HOME/.hermes/skills}
SKILLS_DIR=${SKILLS_DIR%/}
REPO_DIR=${REPO_DIR:-/var/lib/hermes/workspace/skills-src}
TOKEN_FILE=${TOKEN_FILE:-/run/hermes-github/piabrota}
REPO=${REPO:-piabrota/skills}
DRY_RUN=${DRY_RUN:-}
HERMES_HOME=${HERMES_HOME:-$HOME/.hermes}
OUT_PATCH=${OUT_PATCH:-}

fail() {
  echo "skills export failed: $1"
  exit 1
}

is_dry() {
  [ "$DRY_RUN" = 1 ]
}

# ---------------------------------------------------------------- Step 1
read_token() {
  STEP="read the token"
  if [ ! -r "$TOKEN_FILE" ]; then
    echo "skills export waiting: the piabrota-hermes App has no installation on piabrota/skills (no token file)"
    exit 0
  fi
  GH_TOKEN=$(cat "$TOKEN_FILE")
  export GH_TOKEN
}

# ---------------------------------------------------------------- Step 2
# Fill NAMES, DIRS and ORIGINS with every skill that Hermes loads: source A (the skills
# directory), B (the skills of plugins) and C (the external directories of nix-os).
# A second skill with a name that we have already is kept in DUPS.
add_skill() {
  local name=$1 dir=$2 origin=$3
  # Only skills that the owner wrote or changed for Hermes: those made on this box, those of the
  # pirsig plugins and those of nix-os's own skills directory. Bundled, hub, catalog and other
  # plugin skills are written by others: they stay out.
  case $origin in
    "Made by Hermes on this box" | "Plugin pirsig-"* | "Added by nix-os (skills)") ;;
    *) return 0 ;;
  esac
  # The name builds a path that we remove later: keep it plain.
  [[ $name =~ $NAME_RE ]] || fail "bad skill name: $name"
  if [ -n "${SEEN[$name]+x}" ]; then
    DUPS+=("$name")
    return 0
  fi
  SEEN[$name]=1
  NAMES+=("$name")
  DIRS+=("$dir")
  ORIGINS+=("$origin")
}

find_skills() {
  STEP="find the skills of Hermes"
  [ -d "$SKILLS_DIR" ] || fail "no skills directory"

  local bundled="" hub="" lock="$SKILLS_DIR/.hub/lock.json"
  local f rel dir name origin plugins="$HERMES_HOME/plugins"
  local cfg="$HERMES_HOME/config.yaml" d base
  local ext=()

  # The origin of a source A skill. Bundled skills: lines "name:hash".
  if [ -f "$SKILLS_DIR/.bundled_manifest" ]; then
    bundled=$(cut -d: -f1 "$SKILLS_DIR/.bundled_manifest")
  fi
  # Hub skills: the keys of .installed, or the top-level keys. Ignore an odd shape.
  if [ -f "$lock" ]; then
    hub=$(jq -r 'if (.installed | type) == "object" then .installed | keys[]
                 elif type == "object" then keys[]
                 else empty end' "$lock" 2>/dev/null || true)
  fi

  # Source A.
  while IFS= read -r -d '' f; do
    rel=${f#"$SKILLS_DIR"/}
    # Ignore a path with a component that starts with a dot.
    case "/$rel" in */.*) continue ;; esac
    dir=${f%/SKILL.md}
    [ "$dir" != "$SKILLS_DIR" ] || continue
    name=${dir##*/}
    if grep -qxF -- "$name" <<<"$bundled"; then
      origin="Bundled with Hermes Agent"
    elif grep -qxF -- "$name" <<<"$hub"; then
      origin="Installed from a skills hub"
    else
      origin="Made by Hermes on this box"
    fi
    add_skill "$name" "$dir" "$origin"
  done < <(find "$SKILLS_DIR" -type f -name SKILL.md -print0 | sort -z)

  # Source B: <plugins>/<plugin>/skills/<name>/SKILL.md. The plugins are symlinks.
  if [ -d "$plugins" ]; then
    while IFS= read -r -d '' f; do
      rel=${f#"$plugins"/}
      [[ $rel =~ ^[^/]+/skills/[^/]+/SKILL\.md$ ]] || continue
      base=${rel%%/*}
      dir=${f%/SKILL.md}
      add_skill "${dir##*/}" "$dir" "Plugin ${base#nix-managed-}"
    done < <(find -L "$plugins" -mindepth 4 -maxdepth 4 -type f -name SKILL.md -print0 | sort -z)
  fi

  # Source C: <external dir>/<name>/SKILL.md. The awk keeps the lines of the external_dirs
  # block; the grep takes the store paths from a list or from an inline [a, b].
  if [ -f "$cfg" ]; then
    mapfile -t ext < <(awk '/external_dirs:/{f=1} f&&/^[^ -]/{f=0} f' "$cfg" \
      | grep -o '/nix/store/[^ ,"]*' | awk '!seen[$0]++' || true)
  fi
  for d in ${ext[@]+"${ext[@]}"}; do
    d=${d%]}
    d=${d%/}
    [ -d "$d" ] || continue
    # The name of the directory without the store hash.
    base=${d##*/}
    if [[ $base =~ ^[a-z0-9]{32}-(.+)$ ]]; then
      base=${BASH_REMATCH[1]}
    fi
    while IFS= read -r -d '' f; do
      dir=${f%/SKILL.md}
      add_skill "${dir##*/}" "$dir" "Added by nix-os ($base)"
    done < <(find -L "$d" -mindepth 2 -maxdepth 3 -type f -name SKILL.md -print0 | sort -z)
  done

  if [ "${#NAMES[@]}" -eq 0 ]; then
    exit 0
  fi
}

# ---------------------------------------------------------------- Step 3
remote_branch_exists() {
  local rc=0
  git ls-remote --exit-code --heads origin "$1" >/dev/null || rc=$?
  case $rc in
    0) return 0 ;;
    2) return 1 ;;
    *) fail "$STEP" ;;
  esac
}

prepare_repo() {
  STEP="update the clone of $REPO"
  cd "$REPO_DIR"
  git fetch -q --depth 1 origin main
  git checkout -q -f --detach FETCH_HEAD
  git clean -fdq

  if is_dry; then
    BRANCH="hermes/skills-export-dry"
    git checkout -q -B "$BRANCH" FETCH_HEAD
    return 0
  fi

  STEP="look for an open PR"
  local pr
  pr=$(gh pr list -R "$REPO" --state open --json number,headRefName,url \
    --jq '[.[]|select(.headRefName|startswith("hermes/skills-export"))][0]')
  BRANCH=$(jq -r '.headRefName // empty' <<<"$pr")

  if [ -n "$BRANCH" ]; then
    # Reuse the open PR: work on its branch.
    PR_URL=$(jq -r '.url' <<<"$pr")
    STEP="check out the branch of the open PR"
    git fetch -q --depth 1 origin "$BRANCH"
    git checkout -q -B "$BRANCH" FETCH_HEAD
    return 0
  fi

  STEP="choose a branch name"
  local base="hermes/skills-export-$(date +%Y%m%d)" n=2
  BRANCH=$base
  while remote_branch_exists "$BRANCH"; do
    BRANCH="$base-$n"
    n=$((n + 1))
  done
  git checkout -q -B "$BRANCH" FETCH_HEAD
}

# Skip each skill that has the name of a skill in another category of the repository.
skip_owned() {
  STEP="skip the skills that the repository has"
  local i name p cat owned
  local names=() dirs=() origins=()
  for i in "${!NAMES[@]}"; do
    name=${NAMES[$i]}
    owned=0
    for p in "$REPO_DIR"/skills/*/"$name"; do
      [ -d "$p" ] || continue
      cat=${p%/*}
      [ "${cat##*/}" != hermes ] || continue
      owned=1
      break
    done
    if [ "$owned" = 1 ]; then
      OWNED+=("$name")
    else
      names+=("$name")
      dirs+=("${DIRS[$i]}")
      origins+=("${ORIGINS[$i]}")
    fi
  done
  NAMES=(${names[@]+"${names[@]}"})
  DIRS=(${dirs[@]+"${dirs[@]}"})
  ORIGINS=(${origins[@]+"${origins[@]}"})
  if [ "${#NAMES[@]}" -eq 0 ]; then
    exit 0
  fi
}

# ---------------------------------------------------------------- Step 4
# Keep only the keys of the Agent Skills format in the front matter. Set name to the name of the
# directory and add disable-model-invocation. The body stays byte for byte.
normalize_skill() {
  local file=$1 name=$2 rc=0
  perl -e '
    my ($f, $name) = @ARGV;
    my %keep = map { $_ => 1 } qw(name description license compatibility allowed-tools);
    open(my $in, "<:raw", $f) or die "open: $!";
    my $s = do { local $/; <$in> };
    close($in);
    # Front matter: the first two lines that are exactly "---", the first on line 1.
    $s =~ /\A---\n((?:.*?\n)??)(---(?:\n|\z))/s or exit 3;
    my ($fm, $close, $rest) = ($1, $2, substr($s, $+[0]));
    # A key line starts a block; its continuation lines follow it.
    my @blocks;
    for my $l (split /^/, $fm) {
      push @blocks, [$1, ""] if $l =~ /^([A-Za-z][A-Za-z0-9_-]*):/;
      $blocks[-1][1] .= $l if @blocks;
    }
    my ($has_name, $has_desc, $out) = (0, 0, "");
    for my $b (@blocks) {
      my ($k, $t) = @$b;
      next unless $keep{$k};
      if ($k eq "name") {
        next if $has_name++;
        $t = "name: $name\n";
      } elsif ($k eq "description") {
        next if $has_desc++;
        $t .= "disable-model-invocation: true\n";
      }
      $out .= $t;
    }
    exit 4 unless $has_desc;
    $out = "name: $name\n" . $out unless $has_name;
    open(my $o, ">:raw", $f) or die "write: $!";
    print $o "---\n", $out, $close, $rest;
    close($o) or die "close: $!";
  ' "$file" "$name" || rc=$?
  case $rc in
    0) ;;
    3) fail "$name has no front matter" ;;
    4) fail "$name has no description" ;;
    *) fail "normalize the front matter of $name" ;;
  esac
}

# Print the value of a key in the front matter of a file, or "not stated".
fm_field() {
  local file=$1 key=$2 v
  v=$(perl -e '
    my ($f, $k) = @ARGV;
    open(my $in, "<:raw", $f) or die "open: $!";
    my $s = do { local $/; <$in> };
    close($in);
    $s =~ /\A---\n((?:.*?\n)??)(---(?:\n|\z))/s or exit 0;
    my $fm = $1;
    my ($v, $on) = ("", 0);
    for my $l (split /^/, $fm) {
      if ($l =~ /^([A-Za-z][A-Za-z0-9_-]*):[ \t]*(.*?)\s*$/) {
        last if $on;
        ($on, $v) = (1, $2) if $1 eq $k;
      } elsif ($on && $l =~ /^[ \t]+(\S.*?)\s*$/) {
        $v .= " $1";
      }
    }
    $v =~ s/\A[>|][+-]?\s*//;
    $v =~ s/^(["\x27])(.*)\1$/$2/;
    $v =~ s/[|\r\n]//g;
    $v =~ s/^\s+|\s+$//g;
    print $v;
  ' "$file" "$key")
  [ -n "$v" ] || v="not stated"
  printf '%s' "$v"
}

# A table cell has no "|" and no newline.
cell() {
  local v=${1//|/}
  v=${v//$'\n'/ }
  printf '%s' "${v//$'\r'/}"
}

# Write skills/hermes/README.md in full. It is generated.
write_readme() {
  STEP="write skills/hermes/README.md"
  local i rows=""
  for i in "${!NAMES[@]}"; do
    rows+=$(printf '%s\t| `%s` | %s | %s | %s |' "${NAMES[$i]}" "${NAMES[$i]}" \
      "$(cell "${ORIGINS[$i]}")" "$(cell "${LICENSES[$i]}")" "$(cell "${AUTHORS[$i]}")")$'\n'
  done
  {
    cat <<'EOF'
# hermes

The skills that the owner wrote or changed for Hermes. Hermes copies them here once a day. Do not edit them by hand.
Each skill has the tag `hermes-skill` in `www/tags.txt`.
These skills are copied as is, with the files next to each `SKILL.md`.
The `license` column is the value in the front matter of the skill. `not stated` means that the skill has no value.
Check the licence of the source before you reuse a skill.

| Skill | Origin | Licence | Author |
|---|---|---|---|
EOF
    printf '%s' "$rows" | LC_ALL=C sort -t $'\t' -k1,1 | cut -f2-
  } >"$REPO_DIR/skills/hermes/README.md"
}

copy_skills() {
  STEP="copy the skills"
  local i name target
  # The directory is generated: start empty, so a skill that left the list leaves the repository.
  rm -rf -- "${REPO_DIR:?}/skills/hermes"
  perl -i -ne 'next if /^\S+: hermes-skill\s*$/; s/ hermes-skill(?=\s)//g; print' "$REPO_DIR/www/tags.txt"
  mkdir -p "$REPO_DIR/skills/hermes"
  for i in "${!NAMES[@]}"; do
    name=${NAMES[$i]}
    target="${REPO_DIR:?}/skills/hermes/${name:?}"
    LICENSES[$i]=$(fm_field "${DIRS[$i]}/SKILL.md" license)
    AUTHORS[$i]=$(fm_field "${DIRS[$i]}/SKILL.md" author)
    rm -rf -- "$target"
    # The whole directory: these skills are the owner's and small, and their references matter.
    cp -rL -- "${DIRS[$i]}" "$target"
    # A copy from the Nix store is read only.
    chmod -R u+w -- "$target"
    STEP="normalize the front matter of $name"
    normalize_skill "$target/SKILL.md" "$name"
    STEP="copy the skills"
  done
  write_readme
}

# ---------------------------------------------------------------- Step 5
# Make sure each exported skill has the tag hermes-skill in www/tags.txt.
tag_skills() {
  STEP="tag the skills in www/tags.txt"
  perl -e '
    my ($file, @names) = @ARGV;
    open(my $in, "<", $file) or die "open: $!";
    my @lines = <$in>;
    close($in);
    for my $n (@names) {
      my $found = 0;
      for my $l (@lines) {
        next if index($l, "$n:") != 0;
        $found = 1;
        my ($tags) = $l =~ /^[^:]*:(.*)$/;
        next if grep { $_ eq "hermes-skill" } split(" ", $tags);
        $l =~ s/\s+\z//;
        $l .= " hermes-skill\n";
      }
      next if $found;
      $lines[-1] .= "\n" if @lines && $lines[-1] !~ /\n\z/;
      push @lines, "$n: hermes-skill\n";
    }
    open(my $out, ">", $file) or die "write: $!";
    print $out @lines;
    close($out) or die "close: $!";
  ' "$REPO_DIR/www/tags.txt" "${NAMES[@]}"
}

# ---------------------------------------------------------------- Step 6
# Skills of Hermes are copied as is: exempt them in scripts/check.py.
exempt_check() {
  STEP="edit scripts/check.py"
  local comment="        # skills/hermes/ holds the skills of Hermes, copied as is on the owner's word."
  local line='        as_is = rel in AS_IS or rel.startswith("skills/hermes/")'
  if ! grep -q 'skills/hermes/' scripts/check.py; then
    perl -i -pe 'BEGIN { ($c, $l) = splice(@ARGV, 0, 2) }
                 $_ = "$c\n$l\n" if /^        as_is = rel in AS_IS\s*$/;' \
      "$comment" "$line" scripts/check.py
    grep -qxF -- "$line" scripts/check.py || fail "scripts/check.py has no as_is line to edit"
    CHECK_EDITED=1
  fi
}

# ---------------------------------------------------------------- Step 7
# Print only the place of a finding, never the text.
scan_secrets() {
  STEP="scan for secrets"
  local patterns=(
    'gh[pousr]_(?![xX]+(?![A-Za-z0-9]))[A-Za-z0-9]{20,}'
    'github_pat_[A-Za-z0-9_]{20,}'
    'sk-ant-[A-Za-z0-9_-]{10,}'
    'sk-[A-Za-z0-9]{32,}'
    '-----BEGIN [A-Z ]*PRIVATE KEY-----'
    'AKIA[0-9A-Z]{16}'
    'xox[abprs]-[A-Za-z0-9-]{10,}'
    '(TOKEN|SECRET|PASSWORD|API_KEY|PRIVATE_KEY)[A-Z_]*[=:] *["'\'']?[A-Za-z0-9_+/=-]{20,}'
    'eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}'
  )
  local i hit
  for i in "${!patterns[@]}"; do
    # A match that is plainly a placeholder (xxxx, ..., your-..., example) is not a secret.
    hit=$(grep -rIPno -e "${patterns[$i]}" skills/hermes | grep -viE ':[^:]*(x{4,}|\.\.\.|your-|example|changeme|placeholder|<)' | cut -d: -f1,2 | head -n 1 || true)
    if [ -n "$hit" ]; then
      fail "possible secret in $hit ($((i + 1)))"
    fi
  done
}

# ---------------------------------------------------------------- Step 9
run_check() {
  local label=$1 out rc=0
  shift
  # The trap is off in the substitution so that it cannot write into $out.
  out=$(trap - ERR; "$@" 2>&1) || rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "skills export failed: the checks of the repository fail ($label)"
    printf '%s\n' "$out" | tail -n 5
    exit 1
  fi
}

run_checks() {
  STEP="find a Python for the checks"
  local hermes_bin PY
  hermes_bin=$(command -v hermes || true)
  PY=""
  if [ -n "$hermes_bin" ]; then
    PY=$(grep -ao '/nix/store/[a-z0-9]*-hermes-agent-env/bin/python3[.0-9]*' "$hermes_bin" | head -1 || true)
  fi
  if [ -z "$PY" ]; then
    echo "skills export: no python for the checks"
    exit 1
  fi

  STEP="run the checks"
  # The checks must not leave bytecode in the tree that we commit.
  export PYTHONDONTWRITEBYTECODE=1
  run_check "scripts/check.py" "$PY" scripts/check.py
  run_check "agentskills_check.py" "$PY" skills/dev-flow/agentskills-checker/scripts/agentskills_check.py skills
}

# ---------------------------------------------------------------- Step 10
write_body() {
  cat <<'EOF'
## Summary

Hermes exports the skills that the owner wrote or changed for it. Skills that other authors wrote stay out.
This PR adds or updates them under `skills/hermes/`.
Each skill has the tag `hermes-skill` in `www/tags.txt`.

## Tested

- `scripts/check.py` passes.
- `agentskills_check.py skills` passes.
- A scan found no secret in the exported files.

## What changed

EOF
  printf -- '- Skills: %s.\n' "$1"
  if [ "$CHECK_EDITED" = 1 ]; then
    printf '%s\n' '- `scripts/check.py`: a skill under `skills/hermes/` counts as copied as is. It gets warnings, not failures. These skills are not written in ASD-STE100 and they have links. Decide if you accept this.'
  fi
  cat <<'EOF'

## Notes

- The skills are public in this repository. Read them before you merge.
- The front matter keeps only the keys of the Agent Skills format. The export adds `disable-model-invocation: true`.
EOF
  if [ "${#OWNED[@]}" -gt 0 ]; then
    printf -- '- Skipped, because the repository already has them: %s.\n' "$(join_names "${OWNED[@]}")"
  fi
  if [ "${#DUPS[@]}" -gt 0 ]; then
    printf -- '- Skipped, same name as another Hermes skill: %s.\n' "$(join_names "${DUPS[@]}")"
  fi
}

# The names, sorted and without a repeat, in one line.
join_names() {
  local out
  out=$(printf '%s\n' "$@" | LC_ALL=C sort -u)
  printf '%s' "${out//$'\n'/, }"
}

# The first 20 names, then "and <K> more".
names_list() {
  local n=${#NAMES[@]} max=20 list
  list=$(printf '%s, ' "${NAMES[@]:0:max}")
  list=${list%, }
  if [ "$n" -gt "$max" ]; then
    list+=" and $((n - max)) more"
  fi
  printf '%s' "$list"
}

commit_and_publish() {
  local list ident=() counts
  list=$(names_list)
  counts="${#NAMES[@]} skills, $((${#OWNED[@]} + ${#DUPS[@]})) skipped"

  STEP="commit"
  git add -A skills www scripts
  if [ -z "$(git config user.name || true)" ]; then
    ident=(-c user.name=piabrota-hermes -c user.email=piabrota-hermes@users.noreply.github.com)
  fi
  git ${ident[@]+"${ident[@]}"} commit -q \
    -m "feat(skills): export the skills of Hermes" \
    -m "Skills: $list." \
    -m "Tested: scripts/check.py and agentskills_check.py pass"

  if [ -n "$OUT_PATCH" ]; then
    STEP="write the patch"
    git format-patch -1 --stdout >"$OUT_PATCH"
    echo "patch: $OUT_PATCH"
  fi

  if is_dry; then
    echo "dry run: would push $BRANCH"
    git --no-pager diff --stat HEAD~1
    exit 0
  fi

  STEP="push the branch"
  git push origin "$BRANCH" >/dev/null 2>&1

  if [ -n "$PR_URL" ]; then
    # Keep the description true: the list of skills changes between runs.
    BODY=$(mktemp "${TMPDIR:-/tmp}/skills-export-XXXXXX.md")
    write_body "$list" >"$BODY"
    gh pr edit "$PR_URL" --body-file "$BODY" >/dev/null
    echo "skills export: updated $PR_URL ($counts)"
    exit 0
  fi

  STEP="open the pull request"
  BODY=$(mktemp "${TMPDIR:-/tmp}/skills-export-XXXXXX.md")
  write_body "$list" >"$BODY"
  PR_URL=$(gh pr create -R "$REPO" --base main --head "$BRANCH" \
    --title "feat(skills): export the skills of Hermes" --body-file "$BODY")
  echo "skills export: opened $PR_URL ($counts)"
}

# ---------------------------------------------------------------- Main
if ! is_dry; then
  read_token
fi
find_skills
prepare_repo
skip_owned
copy_skills
tag_skills
exempt_check
scan_secrets

STEP="look for changes"
if [ -z "$(git status --porcelain)" ]; then
  exit 0
fi

run_checks
commit_and_publish
